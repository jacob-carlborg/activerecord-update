require 'pry'

require 'activerecord-update'

SpecRoot = ActiveRecord::Update.root.join('spec')
Dir[SpecRoot.join('support/**/*.rb')].each { |file| require file }

RSpec.configure do |config|
  config.order = :random

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end
end
