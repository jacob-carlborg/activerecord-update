require 'pry'
require 'ruby-prof'
require 'simplecov'

SimpleCov.start do
  add_filter '/spec/'
  minimum_coverage 100
end

require 'activerecord-update'

SpecRoot = ActiveRecord::Update.root.join('spec')
Dir[SpecRoot.join('support/**/*.rb')].each { |file| require file }

RSpec.configure do |config|
  config.order = :random

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end
end
