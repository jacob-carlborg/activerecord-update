module ActiveRecord
  class Base
    UPDATE_RECORDS_SQL_TEMPLATE = <<-SQL.strip_heredoc.strip.freeze
      UPDATE %{table} SET
        %{set_columns}
      FROM (
        VALUES %{values}
      )
      AS %{alias}(%{columns})
      WHERE %{table}.%{primary_key} = %{alias}.%{primary_key}
      RETURNING %{table}.%{primary_key}
    SQL

    private_constant :UPDATE_RECORDS_SQL_TEMPLATE

    class << self
      private

      # Returns the given records that are not new records and have changed.
      #
      # @param records [<ActiveRecord::Base>] the records to filter
      # @return that records that are not new records and have changed
      def changed_records(records)
        records.reject(&:new_record?).select(&:changed?)
      end

      # Builds the SQL query used by the {#update_records} method.
      #
      # @example
      #   class Model
      #     include ActiveModel::Model
      #     include ActiveModel::Dirty
      #
      #     attr_accessor :id, :foo, :bar
      #     define_attribute_methods :id, :foo, :bar
      #
      #     def slice(*keys)
      #       attributes = { id: id, foo: foo, bar: bar }
      #       hash = ActiveSupport::HashWithIndifferentAccess.new(attributes)
      #       hash.slice(*keys)
      #     end
      #
      #     def id=(value)
      #       id_will_change! unless value == @id
      #       @id = value
      #     end
      #
      #     def foo=(value)
      #       foo_will_change! unless value == @foo
      #       @foo = value
      #     end
      #
      #     def bar=(value)
      #       bar_will_change! unless value == @bar
      #       @bar = value
      #     end
      #   end
      #
      #   record1 = Model.new(id: 1, foo: 4, bar: 5)
      #   record2 = Model.new(id: 2, foo: 2, bar: 3)
      #   records = [record1, record2]
      #
      #   ActiveRecord::Base.send(:sql_for_update_records, records)
      #   # =>
      #   # UPDATE "foos" SET
      #   # "id" = "foos_2"."id", "foo" = "foos_2"."foo", "bar" = "foos_2"."bar
      #   # FROM (
      #   #   VALUES (1, 4, 5), (2, 2, 3)
      #   # )
      #   # AS foos_2("id", "foo", "bar")
      #   # WHERE "foos"."id" = foos_2."id"
      #   # RETURNING "foos"."id";
      #
      # @param records [<ActiveRecord::Base>] the records that have changed
      # @return the SQL query for the #{update_records} method
      # @see #update_records
      # rubocop:disable Metrics/MethodLength
      def sql_for_update_records(records)
        changed_attrs = changed_attributes(records)
        quoted_changed_attributes = changed_attributes_for_sql(
          changed_attrs, quoted_table_alias
        )

        quoted_values = values_for_sql(records, changed_attrs, primary_key)
        quoted_column_names = column_names_for_sql(
          primary_key, changed_attrs
        )

        format(
          UPDATE_RECORDS_SQL_TEMPLATE,
          table: quoted_table_name,
          set_columns: quoted_changed_attributes,
          values: quoted_values,
          alias: quoted_table_alias,
          columns: quoted_column_names,
          primary_key: quoted_primary_key
        )
      end
      # rubocop:enable Metrics/MethodLength

      # @return [String] the table alias quoted.
      def quoted_table_alias
        @quoted_table_alias ||=
          connection.quote_table_name(arel_table.alias.name)
      end

      # Quotes/escapes the given column value to prevent SQL injection attacks.
      #
      # This is an PostgreSQL specific method which properly handles quoting of
      # `true` and `false`. The built-in ActiveRecord quote method will convert
      # these values to `"'t'"` and `"'f'"`, which will not work for
      # {.update_records}. This method will convert these values to `"TRUE"` and
      # `"FALSE"` instead. All other values are delegated to
      # `ActiveRecord::ConnectionAdapters::Quoting#quote`.
      #
      # @param value [Object] the value to escape
      # @return [String] the quoted value
      def quote(value)
        case value
        when true, false
          value ? 'TRUE' : 'FALSE'
        else
          connection.quote(value)
        end
      end

      # Returns the changed attribute names of the given records.
      #
      # @param records [<ActiveModel::Dirty>] the records to return the changed
      #   attributes for
      #
      # @return [Set<String>] a list of the names of the attributes that have
      #   changed
      def changed_attributes(records)
        Set.new(records.flat_map(&:changed))
      end

      # Returns the given changed attributes formatted for SQL.
      #
      # @param changed_attributes [Set<String>] the attributes that have changed
      # @param table_alias [String] an alias for the table name
      #
      # @return [String] the changed attributes formatted for SQL
      # @raise [ArgumentError] if the given list is `nil` or empty
      def changed_attributes_for_sql(changed_attributes, table_alias)
        if changed_attributes.blank?
          raise ArgumentError, 'No changed attributes given'
        end

        changed_attributes
          .map { |e| connection.quote_column_name(e) }
          .map { |e| "#{e} = #{table_alias}.#{e}" }.join(', ')
      end

      # Returns the values of the given records that have changed, formatted for
      # SQL.
      #
      # @example
      #   class Model
      #     include ActiveModel::Model
      #
      #     attr_accessor :id, :foo, :bar
      #
      #     def slice(*keys)
      #       attributes = { id: id, foo: foo, bar: bar }
      #       hash = ActiveSupport::HashWithIndifferentAccess.new(attributes)
      #       hash.slice(*keys)
      #     end
      #   end
      #
      #   record1 = Model.new(id: 1, foo: 3)
      #   record2 = Model.new(id: 2, bar: 4)
      #   records = [record1, record2]
      #
      #   ActiveRecord::Base.send(:values_for_sql, records, 'id')
      #   # => "(1, 3, NULL), (2, NULL, 4)"
      #
      # @param records [<ActiveRecord::Base>] the records that have changed
      # @param changed_attributes [Set<String>] the attributes that have changed
      # @param primary_key [String] the primary key of the table
      #
      # @return [String] the values formatted for SQL
      #
      # @raise [ArgumentError]
      #   * if the given list of records or changed attributes is `nil` or empty
      #   * If the given primary key is `nil` or empty
      #
      # rubocop:disable Metrics/AbcSize
      def values_for_sql(records, changed_attributes, primary_key)
        raise ArgumentError, 'No changed records given' if records.blank?
        raise ArgumentError, 'No primary key given' if primary_key.blank?

        if changed_attributes.blank?
          raise ArgumentError, 'No changed attributes given'
        end

        # We're using `slice` instead of `changed_attributes` because we need to
        # include all the changed attributes from all the changed records and
        # not just the changed attributes for a given record.
        records
          .map! { |e| e.slice(primary_key, *changed_attributes).values }
          .map! { |e| '(' + e.map! { |b| quote(b) }.join(', ') + ')' }
          .join(', ')
      end
      # rubocop:enable Metrics/AbcSize

      # Returns the given column names formatted for SQL.
      #
      # @example
      #   ActiveRecord::Base.send(:column_names_for_sql, 'id', %w(foo bar))
      #   # => '"id", "foo", "bar"'
      #
      # @param primary_key [String] the primary key of the table
      # @param column_names [<String>] the name of the columns
      #
      # @return [String] the column names formatted for SQL
      #
      # @raise [ArgumentError]
      #   * If the given primary key is `nil` or empty
      #   * If the given list of column names is `nil` or empty
      def column_names_for_sql(primary_key, column_names)
        raise ArgumentError, 'No primary key given' if primary_key.blank?
        raise ArgumentError, 'No column names given' if column_names.blank?

        sql_columns = (Set.new([primary_key]) + column_names).to_a
        sql_columns.map! { |e| connection.quote_column_name(e) }.join(', ')
      end
    end
  end
end
