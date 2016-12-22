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
    end
  end
end
