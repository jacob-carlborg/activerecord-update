class Record < ActiveRecord::Base
  validates :bar, numericality: { greater_than: 1 }
end
