require 'bundler/gem_tasks'
require 'rspec/core/rake_task'

RSpec::Core::RakeTask.new(:spec)

task default: :spec

require 'activerecord-update'
require ActiveRecord::Update.root.join('spec/support/database')

namespace :db do
  desc 'Creates the database from spec/db/database.yml'
  task :create do
    name = ActiveRecord::Update.database.name
    sh "psql -c 'create database #{name};' -U postgres"
  end

  desc 'Drops the database from spec/db/database.yml'
  task :drop do
    name = ActiveRecord::Update.database.name
    sh "psql -c 'drop database #{name};' -U postgres"
  end

  desc 'Migrate the database'
  task :migrate do
    ActiveRecord::Update.database.migrate
  end
end
