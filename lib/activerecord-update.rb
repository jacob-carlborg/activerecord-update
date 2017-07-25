# rubocop:disable Style/FileName

begin
  require 'active_support/core_ext/string/strip'
rescue LoadError
  require 'activerecord-update/core_ext/string/strip'
end

begin
  require 'active_support/core_ext/hash/slice'
rescue LoadError
  require 'activerecord-update/core_ext/hash/slice'
end

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
