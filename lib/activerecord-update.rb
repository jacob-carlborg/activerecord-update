# rubocop:disable Style/FileName

require 'active_support/core_ext/string/strip'
require 'active_record'

require 'activerecord-update/version'
require 'activerecord-update/active_record/base'
require 'activerecord-update/active_record/update/result'

module ActiveRecord
  module Update
    def self.root
      @root ||= Pathname.new(File.dirname(__FILE__)).join('..')
    end
  end
end
