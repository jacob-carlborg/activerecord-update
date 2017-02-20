module ActiveRecord
  class Base
    UPDATE_RECORDS_SQL_TEMPLATE = <<-SQL.strip_heredoc.strip.freeze
      UPDATE %{table} SET
        %{set_columns}
      FROM (
        VALUES
          %{type_casts},
          %{values}
      )
      AS %{alias}(%{columns})
      WHERE %{table}.%{primary_key} = %{alias}.%{primary_key}
    SQL

    private_constant :UPDATE_RECORDS_SQL_TEMPLATE

    UPDATE_RECORDS_SQL_LOCKING_CONDITION = <<-SQL.strip_heredoc.strip.freeze
      AND %{table}.%{locking_column} = %{alias}.%{prev_locking_column}
    SQL

    private_constant :UPDATE_RECORDS_SQL_LOCKING_CONDITION

    UPDATE_RECORDS_SQL_FOOTER = <<-SQL.strip_heredoc.strip.freeze
      RETURNING %{table}.%{primary_key}
    SQL

    private_constant :UPDATE_RECORDS_SQL_FOOTER

    class << self
      # Updates a list of records in a single batch.
      #
      # This is more efficient than calling `ActiveRecord::Base#save` multiple
      # times.
      #
      # * Only records that have changed will be updated
      # * All new records will be ignored
      # * Validations will be performed for all the records
      # * Only the records for which the validations pass will be updated
      #
      # * The union of the changed attributes for all the records will be
      #   updated
      #
      # * The `updated_at` attribute will be updated for all the records that
      #   where updated
      #
      # * All the given records should be of the same type and the same type
      #   as the class this method is called on
      #
      # * If the model is using optimistic locking, that is honored
      #
      # @example
      #   Model.update_records(array_of_models)
      #
      # @param records [<ActiveRecord::Base>] the records to be updated
      #
      # @return [ActiveRecord::Update::Result] the ID's of the records that
      #   were updated and the records that failed to validate
      #
      # @see ActiveRecord::Update::Result
      # @see .update_records!
      def update_records(records)
        _update_records(
          records,
          raise_on_validation_failure: false,
          raise_on_stale_objects: false
        )
      end

      # (see .update_records)
      #
      # The difference compared to {.update_records} is that this method will
      # raise on validation failures. It will pick the first failing record and
      # raise the error based that record's failing validations.
      #
      # If an `ActiveRecord::RecordInvalid` error is raised none of the records
      # will be updated, including the valid records.
      #
      # If an `ActiveRecord::StaleObjectError` error is raised, some of the
      # records might have been updated and is reflected in the
      # {ActiveRecord::Update::Result#ids} and
      # {ActiveRecord::Update::Result#stale_objects} attributes on the return
      # value.
      #
      # @raise [ActiveRecord::RecordInvalid] if any records failed to validate
      #
      # @raise [ActiveRecord::StaleObjectError] if optimistic locking is enabled
      #   and there were stale objects
      #
      # @see .update_records
      def update_records!(records)
        _update_records(
          records,
          raise_on_validation_failure: true,
          raise_on_stale_objects: true
        )
      end

      private

      # rubocop:disable Metrics/MethodLength
      # rubocop:disable Metrics/AbcSize

      # (see .update_records)
      #
      # @param raise_on_validation_failure [Boolean] if `true`, an error will be
      #   raised for any validation failures
      #
      # @param raise_on_stale_objects [Boolean] if `true`, an error will be
      #   raised if optimistic locking is used and there are stale objects
      #
      # @see .update_records
      def _update_records(
        records,
        raise_on_validation_failure:,
        raise_on_stale_objects:
      )

        changed = changed_records(records)
        valid, failed = validate_records(changed, raise_on_validation_failure)
        return build_result(valid, failed, []) if valid.empty?

        timestamp = current_time
        previous_lock_values = {}

        begin
          query = sql_for_update_records(valid, timestamp, previous_lock_values)
          ids = perform_update_records_query(query, primary_key)
          result = build_result(valid, failed, ids)
          restore_lock(result.stale_objects, previous_lock_values)
          validate_result(result, raise_on_stale_objects)

          update_timestamp(valid, timestamp)
          mark_changes_applied(valid)
          result
        # rubocop:disable Lint/RescueException
        rescue Exception
          # rubocop:enable Lint/RescueException
          restore_lock(records, previous_lock_values)
          raise
        end
      end
      # rubocop:enable Metrics/AbcSize
      # rubocop:enable Metrics/MethodLength

      # Returns the given records that are not new records and have changed.
      #
      # @param records [<ActiveRecord::Base>] the records to filter
      # @return that records that are not new records and have changed
      def changed_records(records)
        records.reject(&:new_record?).select(&:changed?)
      end

      # Validates the given records.
      #
      # @param records [<ActiveModel::Validations>] the records to validate
      # @param raise_on_validation_failure [Boolean] if `true`, an error will be
      #   raised for any validation failures
      #
      # @return [(<ActiveModel::Validations>, <ActiveModel::Validations>)]
      #   a tuple where the first element is an array of records that are valid.
      #   The second element is an array of the invalid records
      #
      # @raise [ActiveRecord::RecordInvalid] if `raise_on_validation_failure`
      #   is `true` and there are validation failures
      def validate_records(records, raise_on_validation_failure)
        valid, invalid = records.partition(&:valid?)

        if raise_on_validation_failure && invalid.any?
          raise RecordInvalid, invalid.first
        end

        [valid, invalid]
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
      # @param timestamp [Time] the timestamp used for the `updated_at` column
      #
      # @param previous_lock_values [{ Integer => Integer }] on return, this
      #   hash will contain the record ID's mapping to the previous lock
      #   versions. In an error occurs this hash can be used to restore the lock
      #   attribute to its previous value.
      #
      # @return the SQL query for the #{update_records} method
      #
      # @see #update_records
      # rubocop:disable Metrics/MethodLength
      # rubocop:disable Metrics/AbcSize
      def sql_for_update_records(records, timestamp, previous_lock_values)
        attributes = changed_attributes(records)
        quoted_changed_attributes = changed_attributes_for_sql(
          attributes, quoted_table_alias
        )

        attributes = all_attributes(attributes)
        casts = type_casts(attributes)
        values = changed_values(
          records,
          attributes,
          timestamp,
          previous_lock_values
        )
        quoted_values = values_for_sql(values)
        quoted_column_names = column_names_for_sql(attributes)
        template = build_sql_template

        options = build_format_options(
          table: quoted_table_name,
          set_columns: quoted_changed_attributes,
          type_casts: casts,
          values: quoted_values,
          alias: quoted_table_alias,
          columns: quoted_column_names,
          primary_key: quoted_primary_key
        )

        format(template, options)
      end
      # rubocop:enable Metrics/AbcSize
      # rubocop:enable Metrics/MethodLength

      # @return [Time] the current time in the ActiveRecord timezone.
      def current_time
        default_timezone == :utc ? Time.now.getutc : Time.now
      end

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
      # When locking is enabled the locking column will be inserted as well in
      # the return value.
      #
      # @param records [<ActiveModel::Dirty>] the records to return the changed
      #   attributes for
      #
      # @return [Set<String>] a list of the names of the attributes that have
      #   changed
      def changed_attributes(records)
        changed = records.flat_map(&:changed)
        return changed if changed.empty?

        attrs = changed.dup << 'updated_at'
        attrs << locking_column if locking_enabled?
        attrs.tap(&:uniq!)
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

      # @return [<String>] all attributes, that is, the given attributes plus
      #   some extra, like the primary key.
      def all_attributes(attributes)
        [primary_key] + attributes
      end

      # Returns a row used for typecasting the values that will be updated.
      #
      # This is needed because many types don't have a specific literal syntax
      # and are instead using the string literal syntax. This will cause type
      # mismatches because there's not context, which is otherwise present for
      # regular inserts, for the values to infer the types from.
      #
      # When locking is enabled a virtual prev locking column is inserted,
      # called `'prev_' + locking_column`, at the second position, after the
      # primary key. This column is used in the where condition to implement
      # the optimistic locking feature.
      #
      # @example
      #   ActiveRecord::Base.send(:type_casts, %w(id foo bar))
      #   # => (NULL::integer, NULL::character varying(255), NULL::boolean)
      #
      # @param column_names [Set<String>] the name of the columns
      #
      # @raise [ArgumentError]
      #   * If the given list of column names is `nil` or empty
      def type_casts(column_names)
        raise ArgumentError, 'No column names given' if column_names.blank?

        type_casts = column_names.dup

        # This is the virtual prev locking column. We're using the same name as
        # the locking column since the column is virtual it does not exist in
        # `columns_hash` hash. That works fine since we're only interested in
        # the SQL type, which will always be the same for the locking and prev
        # locking columns.
        type_casts.insert(1, locking_column) if locking_enabled?
        type_casts.map! { |n| 'NULL::' + columns_hash[n].sql_type }

        '(' + type_casts.join(', ') + ')'
      end

      # rubocop:disable Metrics/MethodLength
      # rubocop:disable Metrics/AbcSize

      # Returns the values of the given records that have changed.
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
      #   changed_attributes = Set.new(%w(id foo bar))
      #   ActiveRecord::Base.send(
      #     :changed_values, records, changed_attributes, Time.at(0)
      #   )
      #   # => [
      #   #   [1, 3, nil, 1970-01-01 01:00:00 +0100],
      #   #   [2, nil, 4, 1970-01-01 01:00:00 +0100]
      #   # ]
      #
      # @param records [<ActiveRecord::Base>] the records that have changed
      #
      # @param changed_attributes [Set<String>] the attributes that have
      #   changed, including the primary key, and the locking column, if locking
      #   is enabled
      #
      # @param updated_at [Time] the value of the updated_at column
      #
      # @param previous_lock_values [{ Integer => Integer }] on return, this
      #   hash will contain the record ID's mapping to the previous lock
      #   versions. In an error occurs this hash can be used to restore the lock
      #   attribute to its previous value.
      #
      # @return [<<Object>>] the changed values
      #
      # @raise [ArgumentError]
      #   * if the given list of records or changed attributes is `nil` or empty
      def changed_values(records, changed_attributes, updated_at,
        previous_lock_values)

        raise ArgumentError, 'No changed records given' if records.blank?

        if changed_attributes.blank?
          raise ArgumentError, 'No changed attributes given'
        end

        extract_changed_values = lambda do |record|
          previous_lock_value = increment_lock(record)

          if locking_enabled?
            previous_lock_values[record.id] = previous_lock_value
          end

          # We're using `slice` instead of `changed_attributes` because we need
          # to include all the changed attributes from all the changed records
          # and not just the changed attributes for a given record.
          values = record
            .slice(*changed_attributes)
            .merge('updated_at' => updated_at)
            .values

          locking_enabled? ? values.insert(1, previous_lock_value) : values
        end

        records.map(&extract_changed_values)
      end
      # rubocop:enable Metrics/AbcSize
      # rubocop:enable Metrics/MethodLength

      # Increments the lock column of the given record if locking is enabled.
      #
      # @param record [ActiveRecord::Base] the record to update the lock column
      #   for
      #
      # @param operation [:decrement, :increment] the operation to perform,
      #   increment or decrement
      #
      # @return [void]
      def increment_lock(record)
        return unless locking_enabled?

        lock_col = locking_column
        previous_lock_value = record.send(lock_col).to_i
        record.send(lock_col + '=', previous_lock_value + 1)
        previous_lock_value
      end

      # Restores the lock column of the given records to given values,
      #   if locking is enabled.
      #
      # @param records [<ActiveRecord::Base>] the records to restore the lock
      #   column on
      #
      # @param lock_values [{ Integer => Integer }] this hash contains the
      #   record ID's mapping to the lock values that should be restored.
      #
      # @return [void]
      def restore_lock(records, lock_values)
        return if !locking_enabled? || records.empty?
        method_name = locking_column + '='

        records.each do |record|
          lock_value = lock_values[record.id]
          next unless lock_value
          record.send(method_name, lock_value)
        end
      end

      # Returns the values of the given records that have changed, formatted for
      # SQL.
      #
      # @example
      #   changed_values = [
      #     [1, 3, 4, 1970-01-01 01:00:00 +0100],
      #     [2, 5, 6, 1970-01-01 01:00:00 +0100]
      #   ]
      #   ActiveRecord::Base.send(:values_for_sql, records)
      #   # => "(1, 3, NULL), (2, NULL, 4)"
      #
      # @param changed_values [<<Object>>] the values that have changed
      # @return [String] the values formatted for SQL
      #
      # @raise [ArgumentError] if the given list of changed values is `nil` or
      #   empty
      def values_for_sql(changed_values)
        raise ArgumentError, 'No changed values given' if changed_values.blank?

        changed_values
          .map { |e| '(' + e.map { |b| quote(b) }.join(', ') + ')' }
          .join(', ')
      end

      # Returns the name of the previous locking column.
      #
      # This column is used when locking is enabled. It's used in the where
      # condition when looking for matching rows to update.
      #
      # @return [String] the name of the previous locking column
      def prev_locking_column
        @prev_locking_column ||= 'prev_' + locking_column
      end

      # Returns the given column names formatted for SQL.
      #
      # @example
      #   ActiveRecord::Base.send(:column_names_for_sql, %w(id foo bar))
      #   # => '"id", "foo", "bar"'
      #
      # @param column_names [<String>] the name of the columns
      #
      # @return [String] the column names formatted for SQL
      #
      # @raise [ArgumentError]
      #   * If the given list of column names is `nil` or empty
      def column_names_for_sql(column_names)
        raise ArgumentError, 'No column names given' if column_names.blank?

        names = column_names.dup
        names.insert(1, prev_locking_column) if locking_enabled?
        names.map! { |e| connection.quote_column_name(e) }.join(', ')
      end

      # Builds the SQL template for the query.
      #
      # This method will choose the correct template depending on if locking is
      # enabled or not.
      #
      # @return [String] the SQL template
      def build_sql_template
        template =
          if locking_enabled?
            UPDATE_RECORDS_SQL_TEMPLATE + "\n" +
              UPDATE_RECORDS_SQL_LOCKING_CONDITION
          else
            UPDATE_RECORDS_SQL_TEMPLATE
          end

        template + "\n" + UPDATE_RECORDS_SQL_FOOTER
      end

      # Build the option hash used for the call to `format` in
      # {Base#sql_for_update_records}.
      #
      # This method will add the format options to the given hash of options as
      # necessary if locking is enabled.
      #
      # @param options [{ Symbol => String }] the format options
      #
      # @return [{ Symbol => String }] the format options
      def build_format_options(options)
        if locking_enabled?
          prev_col_name = connection.quote_column_name(prev_locking_column)
          col_name = connection.quote_column_name(locking_column)

          options.merge(
            locking_column: col_name,
            prev_locking_column: prev_col_name
          )
        else
          options
        end
      end

      # Performs the given query and returns the result of the query.
      #
      # @param query [String] the query to perform
      # @param primary_key [String] the primary key
      #
      # @return the result of the query, the primary keys of the records what
      #   were updated
      def perform_update_records_query(query, primary_key)
        primary_key_column = columns_hash[primary_key]
        values = connection.execute(query).values.flatten
        values.map! { |e| primary_key_column.type_cast(e) }
      end

      # Raises an exception if the given result contain any stale objects.
      #
      # @param result [ActiveRecord::Update::Result] the result to check if it
      #   contains stale objects
      #
      # @return [void]
      def validate_result(result, raise_on_stale_objects)
        return unless result.stale_objects?
        record = result.stale_objects.first
        return unless raise_on_stale_objects
        raise ActiveRecord::StaleObjectError.new(record, 'update')
      end

      # Builds the result, returned from {#update_records}, based on the given
      # arguments.
      #
      # @param valid [<ActiveRecord::Base>] the list of records which was
      #   successfully validate
      #
      # @param failed [<ActiveRecord::Base>] the list of records which failed to
      #   validate
      #
      # @param primary_keys [<Integer>] the list of primary keys that were
      #   update
      def build_result(valid, failed, primary_keys)
        stale_objects = extract_stale_objects(valid, primary_keys)
        ActiveRecord::Update::Result.new(primary_keys, failed, stale_objects)
      end

      # Extracts the stale objects from the given list of records.
      #
      # Will always return an empty list if locking is not enabled for this
      # class.
      #
      # @param records [<ActiveRecord::Base>] the list of records to extract
      #   the stale objects from
      #
      # @param primary_keys [<Integer>] the list of primary keys that were
      #   updated
      #
      # @return [<ActiveRecord::Base>] the stale objects
      def extract_stale_objects(records, primary_keys)
        return [] unless locking_enabled?
        primary_key_set = primary_keys.to_set
        records.reject { |e| primary_key_set.include?(e.send(primary_key)) }
      end

      # Updates the `updated_at` attribute for the given records.
      #
      # This will only updated the actual Ruby objects, the database should
      # already have been updated by this point.
      #
      # @param records [<ActiveRecord::Base>] the records that should have their
      #   timestamp updated
      #
      # @return [void]
      def update_timestamp(records, timestamp)
        records.each { |e| e.updated_at = timestamp }
      end

      # Mark changes applied for the given records.
      #
      # @param records [<ActiveModel::Dirty>] the records to mark changes
      #   applied for
      #
      # @return [void]
      def mark_changes_applied(records)
        records.each { |e| e.send(:changes_applied) }
      end
    end
  end
end
