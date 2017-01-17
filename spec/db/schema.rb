ActiveRecord::Schema.define do
  create_table :schema_migrations, force: :cascade do |t|
    t.integer :version, unique: true
  end

  SchemaMigration.create(version: SchemaMigration::VERSION)

  create_table :records do |t|
    t.integer :foo
    t.integer :bar
    t.integer :lock_version

    t.timestamps
  end
end
