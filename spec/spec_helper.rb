require 'pry'

require 'activerecord-update'

RSpec.configure do |config|
  config.order = :random

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end
end
