require_relative '../db/schema_migration'

module ActiveRecord
  module Update
    def self.database
      @database ||= Database.new
    end
  end

  class Database
    DEFAULT_ENV = 'test'.freeze

    private_constant :DEFAULT_ENV

    def root
      @root ||= ActiveRecord::Update.root.join('spec/db')
    end

    def config
      @config ||= begin
        config = YAML.load_file(root.join('database.yml'))[DEFAULT_ENV]
        ActiveRecord::Base.configurations[DEFAULT_ENV] = config
      end
    end

    def name
      config['database']
    end

    def connect
      config
      ActiveRecord::Base.default_timezone = :utc
      ActiveRecord::Base.establish_connection(DEFAULT_ENV.to_sym)
      yield if block_given?
    ensure
      disconnect if block_given?
    end

    def disconnect
      ActiveRecord::Base.remove_connection
    end

    def migrate
      connect { require root.join('schema') unless migrated? }
    end

    def migrated?
      schema_migration_exists? && migration_up_to_date?
    end

    private

    def schema_migration_exists?
      ActiveRecord::Base.connection.table_exists?(SchemaMigration.table_name)
    end

    def migration_up_to_date?
      SchemaMigration.where(version: SchemaMigration::VERSION).exists?
    end
  end
end
