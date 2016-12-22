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
    end
  end
end
