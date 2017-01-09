require 'timecop'

require 'spec_helper'

# Load models
Dir[SpecRoot.join('models/**/*.rb')].each { |file| require file }

RSpec.configure do |config|
  config.before :suite do
    ActiveRecord::Update.database.connect
  end

  config.after :suite do
    ActiveRecord::Update.database.disconnect
  end
end
