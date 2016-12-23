module ActiveRecord
  class Base
    class << self
      private

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
    end
  end
end
