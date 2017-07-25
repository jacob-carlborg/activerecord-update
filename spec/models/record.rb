class Record < ActiveRecord::Base
  # Use `validates_numericality_of` to support both ActiveRecord 2.3 and 4.1.
  validates_numericality_of :bar, greater_than: 1

  unless method_defined?(:slice)
    def slice(*methods)
      Hash[methods.map! { |method| [method, public_send(method)] }]
        .with_indifferent_access
    end
  end
end
