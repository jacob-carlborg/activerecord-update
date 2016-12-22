# rubocop:disable Style/FileName
require 'spec_helper'

describe ActiveRecord::Update do
  it 'has a version number' do
    expect(ActiveRecord::Update::VERSION).not_to be nil
  end
end
