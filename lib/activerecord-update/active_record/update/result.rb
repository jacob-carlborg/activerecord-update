module ActiveRecord
  module Update
    # This class represents the result return by the {Base#update_records}
    # method. It contains the ID's of the records that were updated and the
    # records that failed to validate and
    #
    # @see Base#update_records
    class Result
      # @return [<Integer>] the ID's of the records that were updated.
      attr_reader :ids

      # @return [<ActiveRecord::Base>] the records that failed to validate.
      attr_reader :failed_records

      # Initialize the receiver.
      #
      # @param ids [<Integer>] the ID's of the records that were updated.
      #
      # @param failed_records [<ActiveRecord::Base>] the records that failed to
      #   validate
      def initialize(ids, failed_records)
        @ids = ids
        @failed_records = failed_records
      end

      # @return [Boolean] `true` if there were no failed records.
      def success?
        !failed_records?
      end

      # @return [Boolean] `true` if there were records that failed to validate.
      def failed_records?
        failed_records.any?
      end

      # @return [Boolean] `true` if there were any updated records.
      def updates?
        ids.any?
      end
    end
  end
end
