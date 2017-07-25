require 'spec_helper'

describe ActiveRecord::Base do
  subject { ActiveRecord::Base }

  module Dirty
    def update
    end

    def reload
    end

    def self.included(mod)
      mod.module_eval do
        if defined?(ActiveModel::Dirty)
          include ActiveModel::Dirty
        else
          include ActiveRecord::Dirty
        end
      end
    end
  end

  # rubocop:disable Style/ClassAndModuleChildren
  class self::Model
    COLUMNS = %w(id foo bar).freeze

    def save
    end

    def save!
    end

    if defined?(ActiveModel::Model)
      include ActiveModel::Model
    else
      include ActiveRecord::Validations
      include ActiveRecord::AttributeMethods
    end

    COLUMNS.each do |name|
      attr_accessor name.to_sym
    end

    def initialize(params = {})
      if params
        params.each do |attr, value|
          public_send("#{attr}=", value)
        end
      end

      super()
    end

    def slice(*keys)
      hash = COLUMNS.map { |e| [e.to_sym, send(e)] }.to_h

      cls =
        if defined?(ActiveSupport::HashWithIndifferentAccess)
          ActiveSupport::HashWithIndifferentAccess
        else
          HashWithIndifferentAccess
        end

      cls.new(hash).slice(*keys)
    end

    def self.columns_hash
      column = ActiveRecord::ConnectionAdapters::Column
      COLUMNS.map { |e| [e, column.new(e, nil, 'integer', nil)] }.to_h
    end
  end
  # rubocop:enable Style/ClassAndModuleChildren

  def define_model
    base = self.class
    base = base.superclass until base.const_defined?('Model')
    stub_const('Model', base::Model)
  end

  before(:each) do
    define_model
  end

  describe 'update_records' do
    let(:records) { [double(:record)] }

    it 'calls _update_records' do
      expect(subject).to receive(:_update_records).with(
        records,
        raise_on_validation_failure: false,
        raise_on_stale_objects: false
      )

      subject.update_records(records)
    end
  end

  describe 'update_records!' do
    let(:records) { [double(:record)] }

    it 'calls _update_records' do
      expect(subject).to receive(:_update_records).with(
        records,
        raise_on_validation_failure: true,
        raise_on_stale_objects: true
      )

      subject.update_records!(records)
    end
  end

  describe '_update_records' do
    let(:records) { [double(:record)] }

    let(:changed_records) { [double(:changed_record)] }
    let(:valid) { [records.first] }
    let(:failed_records) { [double(:failed_record)] }
    let(:current_time) { double(:current_time) }
    let(:previous_lock_values) { {} }
    let(:primary_key) { 'id' }
    let(:ids) { valid }
    let(:query) { double(:query) }
    let(:connection) { double(:connection) }
    let(:raise_on_validation_failure) { false }
    let(:raise_on_stale_objects) { false }
    let(:stale_objects) { [] }

    let(:result) do
      ActiveRecord::Update::Result.new(valid, failed_records, stale_objects)
    end

    before(:each) do
      allow(subject).to receive(:changed_records).and_return(changed_records)
      allow(subject).to receive(:current_time).and_return(current_time)
      allow(subject).to receive(:quoted_table_alias).and_return('"foos"')
      allow(subject).to receive(:primary_key).and_return(primary_key)
      allow(subject).to receive(:build_result).and_return(result)
      allow(subject).to receive(:perform_update_records_query).and_return(ids)
      allow(subject).to receive(:sql_for_update_records).and_return(query)
      allow(subject).to receive(:restore_lock)
      allow(subject).to receive(:update_timestamp)
      allow(subject).to receive(:mark_changes_applied)
      allow(subject).to receive(:validate_records)
        .and_return([valid, failed_records])

      allow(subject).to receive(:connection).and_return(connection)
    end

    def update_records
      subject.send(
        :_update_records, records,
        raise_on_validation_failure: raise_on_validation_failure,
        raise_on_stale_objects: raise_on_stale_objects
      )
    end

    it 'calls "changed_records"' do
      expect(subject).to receive(:changed_records).with(records)
      update_records
    end

    it 'calls "validate_records"' do
      expect(subject).to receive(:validate_records)
        .with(changed_records, raise_on_validation_failure)

      update_records
    end

    it 'calls "current_time"' do
      expect(subject).to receive(:current_time)
      update_records
    end

    it 'calls "sql_for_update_records"' do
      expect(subject).to receive(:sql_for_update_records)
        .with(valid, current_time, previous_lock_values)

      update_records
    end

    it 'calls "perform_update_records_query"' do
      expect(subject).to receive(:perform_update_records_query)
        .with(query, primary_key)

      update_records
    end

    it 'calls "build_result"' do
      expect(subject).to receive(:build_result).with(valid, failed_records, ids)
      update_records
    end

    it 'calls "restore_lock" for the stale objects' do
      expect(subject).to receive(:restore_lock)
        .with(stale_objects, previous_lock_values)

      update_records
    end

    it 'calls "validate_result"' do
      expect(subject).to receive(:validate_result)
        .with(result, raise_on_stale_objects)

      update_records
    end

    it 'calls "update_timestamp"' do
      expect(subject).to receive(:update_timestamp).with(valid, current_time)
      update_records
    end

    it 'calls "mark_changes_applied"' do
      expect(subject).to receive(:mark_changes_applied).with(valid)
      update_records
    end

    it "returns the updated ID's" do
      expect(update_records.ids).to eq(ids)
    end

    it 'returns the failed records' do
      expect(update_records.failed_records).to eq(failed_records)
    end

    context 'when no attributes have changed' do
      let(:changed_records) { [] }
      let(:valid) { [] }

      before(:each) do
        allow(subject).to receive(:sql_for_update_records).and_call_original
      end

      it 'does not raise any errors' do
        expect { update_records }.to_not raise_error
      end

      it 'returns an empty ActiveRecord::Update::Result object' do
        expect(update_records.updates?).to eq(false)
      end
    end

    context 'when attributes have changed' do
      before(:each) do
        allow(subject).to receive(:sql_for_update_records).and_call_original
      end

      context 'when no records are valid' do
        let(:valid) { [] }

        it 'does not raise any errors' do
          expect { update_records }.to_not raise_error
        end

        it 'returns an empty ActiveRecord::Update::Result object' do
          expect(update_records.updates?).to eq(false)
        end

        it 'returns the failed objects' do
          expect(update_records.failed_records).to match_array(failed_records)
        end
      end
    end

    context 'when an exception has been raised' do
      let(:error) { 'foo' }

      before(:each) do
        allow(subject).to receive(:sql_for_update_records).and_raise(error)
      end

      it 'calls "restore_lock" for all records', :aggregate_failures do
        expect(subject).to receive(:restore_lock)
          .with(records, previous_lock_values)

        expect { update_records }.to raise_error(error)
      end

      it 're-raises the exception' do
        expect { update_records }.to raise_error(error)
      end
    end

    context 'when a stale object occurs' do
      let(:record_type) { Struct.new(:id, :updated_at) }
      let(:record1) { record_type.new(1) }
      let(:record2) { record_type.new(2) }
      let(:records) { [record1, record2] }
      let(:valid) { records }
      let(:failed_records) { [] }
      let(:stale_objects) { [record2] }
      let(:successful_records) { [record1] }

      it 'calls "update_timestamp" for the successful objects' do
        expect(subject).to receive(:update_timestamp)
          .with([record1], current_time)

        update_records
      end

      it 'calls "mark_changes_applied" for the successful objects' do
        expect(subject).to receive(:mark_changes_applied)
          .with(successful_records)

        update_records
      end

      context 'when "raise_on_stale_objects" is true' do
        let(:raise_on_stale_objects) { true }

        it 'updates the timestamp for the successful records',
          :aggregate_failures do
          expect(subject).to receive(:update_timestamp)
            .with(successful_records, current_time)

          error = ActiveRecord::StaleObjectError
          expect { update_records }.to raise_error(error)
        end
      end
    end
  end

  describe 'changed_records' do
    self::Model = Struct.new(:changed?, :new_record?) do
      def initialize(params = {})
        params.each { |k, v| public_send(:"#{k}=", v) }
      end

      # This is needed for Ruby 1.9.3, otherwise changed?= does not work
      define_method :'changed?=' do |value|
        self[:changed?] = value
      end

      # This is needed for Ruby 1.9.3, otherwise new_record?= does not work
      define_method :'new_record?=' do |value|
        self[:new_record?] = value
      end

      def changed?
        self[:changed?]
      end

      def new_record?
        self[:new_record?]
      end
    end

    before(:each) do
      stub_const('Model', self.class::Model)
    end

    def changed_records
      subject.send(:changed_records, records)
    end

    context 'when the records contain new records' do
      let(:records) { [Model.new(new_record?: true, changed?: true)] }

      it 'filters out the new records' do
        expect(changed_records).to be_empty
      end
    end

    context 'when the records contain unchanged records' do
      let(:records) { [Model.new(new_record?: false, changed?: false)] }

      it 'filters out the unchanged records' do
        expect(changed_records).to be_empty
      end
    end

    context 'when the records contain changed and no new records' do
      let(:records) { [Model.new(new_record?: false, changed?: true)] }

      it 'returns the records' do
        expect(changed_records).to eq(records)
      end
    end

    context 'when the records contain a mixture of records' do
      let(:expected_records) do
        [
          Model.new(new_record?: false, changed?: true),
          Model.new(new_record?: false, changed?: true)
        ]
      end

      let(:records) do
        [
          Model.new(new_record?: true, changed?: true),
          Model.new(new_record?: false, changed?: false),
          *expected_records
        ]
      end

      it 'filters out the unchanged and the new records' do
        expect(changed_records).to eq(expected_records)
      end
    end
  end

  describe 'validate_records' do
    let(:raise_on_validation_failure) { false }

    let(:model) do
      Struct.new(:valid?) do
        def save
        end

        def save!
        end

        if defined?(ActiveModel::Model)
          include ActiveModel::Model
        else
          include ActiveRecord::Validations
          include ActiveRecord::AttributeMethods
        end

        def initialize(valid)
          self[:valid?] = valid
        end

        def self.i18n_scope
          :activerecord
        end

        def self.columns_hash
          {}
        end

        def self.primary_key
          'id'
        end

        def new_record?
          true
        end

        def valid?
          self[:valid?]
        end
      end
    end

    def validate_records
      subject.send(:validate_records, records, raise_on_validation_failure)
    end

    shared_examples 'raise on validation failure' do
      context 'when "raise_on_validation_failure" is `true`' do
        let(:records) { [model.new(false), model.new(false)] }
        let(:raise_on_validation_failure) { true }

        it 'raises an ActiveRecord::RecordInvalid error' do
          expect { validate_records }
            .to raise_error(ActiveRecord::RecordInvalid, 'Validation failed: ')
        end
      end
    end

    context 'when no records are valid' do
      let(:records) { [model.new(false), model.new(false)] }

      it 'returns a tuple where the first element is an empty array' do
        expect(validate_records.first).to be_empty
      end

      it 'adds all the records to the second element of the returned tuple' do
        expect(validate_records.second).to match_array(records)
      end

      include_examples 'raise on validation failure'
    end

    context 'when all records are valid' do
      let(:records) { [model.new(true), model.new(true)] }

      it 'adds all the records to the frist element of the returned tuple' do
        expect(validate_records.first).to match_array(records)
      end

      it 'returns a tuple where the second element is an empty array' do
        expect(validate_records.second).to be_empty
      end

      context 'when "raise_on_validation_failure" is `true`' do
        let(:raise_on_validation_failure) { true }

        it 'does not raise any errors' do
          expect { validate_records }.to_not raise_error
        end
      end
    end

    context 'when some of the records are valid' do
      let(:valid) { model.new(true) }
      let(:invalid) { model.new(false) }
      let(:records) { [invalid, valid] }

      it 'adds the valid records to the frist element of the returned tuple' do
        expect(validate_records.first).to contain_exactly(valid)
      end

      it 'adds the invalid records to the second element of the returned ' \
        'tuple' do
        expect(validate_records.second).to contain_exactly(invalid)
      end

      include_examples 'raise on validation failure'
    end
  end

  describe 'sql_for_update_records' do
    # rubocop:disable Style/ClassAndModuleChildren
    class self::Model < superclass::Model
      include Dirty

      define_attribute_methods :id, :foo, :bar if defined?(ActiveModel::Dirty)

      def self.ancestors
        super + [ActiveRecord::Base]
      end

      def self.primary_key
        'id'
      end

      def id=(value)
        return if value == @id
        @attributes ||= {}
        @attributes['id'] = value
        id_will_change!
        @id = value
      end

      def foo=(value)
        return if value == @foo
        @attributes ||= {}
        @attributes['foo'] = value
        foo_will_change!
        @foo = value
      end

      def bar=(value)
        return if value == @bar
        @attributes ||= {}
        @attributes['bar'] = value
        bar_will_change!
        @bar = value
      end

      def clone_attribute_value(reader_method, attribute_name)
        value = send(reader_method, attribute_name)
        value.duplicable? ? value.clone : value
      rescue TypeError, NoMethodError
        value
      end
    end

    class self::Foo < ActiveRecord::Base
    end
    # rubocop:enable Style/ClassAndModuleChildren

    before(:each) do
      stub_const('Foo', self.class::Foo)
    end

    subject { Foo }

    let(:connection) { double(:connection) }
    let(:schema_cache) { double(:schema_cache) }
    let(:arel_table) { double(:arel_table) }

    let(:column) { Struct.new(:name, :sql_type, :primary) }

    let(:columns_hash) do
      all_attributes.map { |e| [e, column.new(e, type_map[e])] }.to_h
    end

    let(:type_map) do
      {
        id: 'integer',
        foo: 'character varying(255)',
        bar: 'boolean',
        updated_at: 'timestamp without time zone'
      }.stringify_keys
    end

    let(:primary_key) { 'id' }
    let(:timestamp) { Time.at(0).utc }
    let(:previous_lock_values) { {} }
    let(:changed_attributes) { %w(foo bar updated_at) }
    let(:all_attributes) { [primary_key] + changed_attributes }
    let(:quoted_table_alias) { 'foos_2' }
    let(:column_names_for_sql) { '"id", "foo", "bar", "updated_at"' }
    let(:sql_template) { 'sql template' }

    let(:values_for_sql) do
      "(1, 4, 5, '1970-01-01 00:00:00.000000'), " \
      "(2, 2, 3, '1970-01-01 00:00:00.000000')"
    end

    let(:changed_attributes_for_sql) do
      '"foo" = "foos_2"."foo", "bar" = "foos_2"."bar", ' \
        '"updated_at" = "records_2"."updated_at"'
    end

    let(:records) do
      [
        Model.new(id: 1, foo: 4, bar: 5),
        Model.new(id: 2, foo: 2, bar: 3)
      ]
    end

    let(:changed_values) do
      [
        [1, 4, 5, timestamp],
        [2, 2, 3, timestamp]
      ]
    end

    let(:type_casts) do
      '(NULL::integer, NULL::character varying(255), NULL::boolean, ' \
        'NULL::timestamp without time zone)'
    end

    let(:query) do
      <<-SQL.strip_heredoc.strip
        UPDATE "foos" SET
          #{changed_attributes_for_sql}
        FROM (
          VALUES
            #{type_casts},
            #{values_for_sql}
        )
        AS foos_2(#{column_names_for_sql})
        WHERE "foos"."id" = foos_2."id"
        RETURNING "foos"."id"
      SQL
    end

    let(:sql_template) do
      <<-SQL.strip_heredoc.strip.freeze
        UPDATE %{table} SET
          %{set_columns}
        FROM (
          VALUES
            %{type_casts},
            %{values}
        )
        AS %{alias}(%{columns})
        WHERE %{table}.%{primary_key} = %{alias}.%{primary_key}
        RETURNING %{table}.%{primary_key}
      SQL
    end

    let(:format_options) do
      {
        table: subject.quoted_table_name,
        set_columns: changed_attributes_for_sql,
        type_casts: type_casts,
        values: values_for_sql,
        alias: quoted_table_alias,
        columns: column_names_for_sql,
        primary_key: subject.send(:quoted_primary_key)
      }
    end

    before(:each) do
      quote = ->(value) { %("#{value}") }

      # connection
      allow(connection).to receive(:quote_table_name, &quote)
      allow(connection).to receive(:quote_column_name, &quote)
      allow(connection).to receive(:quote, &:to_s)
      allow(connection).to receive(:schema_cache).and_return(schema_cache)

      # schema_cache
      allow(schema_cache).to receive(:table_exists?).and_return(true)
      allow(schema_cache).to receive(:primary_keys).and_return(primary_key)

      # subject
      allow(subject).to receive(:columns_hash).and_return(columns_hash)

      allow(subject).to receive(:connection).and_return(connection)
      allow(subject).to receive(:type_casts).and_return(type_casts)
      allow(subject).to receive(:changed_values).and_return(changed_values)
      allow(subject).to receive(:values_for_sql).and_return(values_for_sql)

      allow(subject).to receive(:changed_attributes)
        .and_return(changed_attributes)

      allow(subject).to receive(:all_attributes).and_return(all_attributes)

      allow(subject).to receive(:quoted_table_alias)
        .and_return(quoted_table_alias)

      allow(subject).to receive(:changed_attributes_for_sql)
        .and_return(changed_attributes_for_sql)

      allow(subject).to receive(:column_names_for_sql)
        .and_return(column_names_for_sql)

      allow(subject).to receive(:build_sql_template).and_return(sql_template)

      allow(subject).to receive(:build_format_options)
        .and_return(format_options)
    end

    def sql_for_update_records
      subject.send(
        :sql_for_update_records, records, timestamp, previous_lock_values
      )
    end

    it 'returns the SQL used for the "update_records" method' do
      expect(sql_for_update_records).to eq(query)
    end

    it 'calls "changed_attributes" with the given records' do
      expect(subject).to receive(:changed_attributes).with(records)
      sql_for_update_records
    end

    it 'calls "changed_attributes_for_sql" with the changed attributes' do
      expect(subject).to receive(:changed_attributes_for_sql)
        .with(changed_attributes, quoted_table_alias)

      sql_for_update_records
    end

    it 'calls "all_attributes"' do
      expect(subject).to receive(:all_attributes).with(changed_attributes)
      sql_for_update_records
    end

    it 'calls "quoted_table_alias"' do
      expect(subject).to receive(:quoted_table_alias)
      sql_for_update_records
    end

    it 'calls "changed_values" with the records and the changed attributes' do
      expect(subject).to receive(:changed_values)
        .with(records, all_attributes, timestamp, previous_lock_values)

      sql_for_update_records
    end

    it 'calls "values_for_sql" with the records and the changed attributes' do
      expect(subject).to receive(:values_for_sql).with(changed_values)
      sql_for_update_records
    end

    it 'calls "column_names_for_sql" with the primary key and changed '\
      'attributes' do
      expect(subject).to receive(:column_names_for_sql)
        .with(all_attributes)

      sql_for_update_records
    end

    it 'calls "build_sql_template"' do
      expect(subject).to receive(:build_sql_template).with(no_args)
      sql_for_update_records
    end

    it 'calls "build_format_options"' do
      expect(subject).to receive(:build_format_options).with(format_options)
        .and_return(format_options)

      sql_for_update_records
    end

    it 'calls "format"' do
      expect(subject).to receive(:format).with(sql_template, format_options)
      sql_for_update_records
    end
  end

  describe 'current_time' do
    let(:now) { Time.at(0) }

    before(:each) do
      allow(Time).to receive(:now).and_return(now)
      allow(subject).to receive(:default_timezone).and_return(default_timezone)
    end

    def current_time
      subject.send(:current_time)
    end

    context 'when the ActiveRecord default timezone is UTC' do
      let(:default_timezone) { :utc }

      it 'returns the current time in UTC' do
        expect(current_time).to eq(now.getutc)
      end
    end

    context 'when the ActiveRecord default timezone is local' do
      let(:default_timezone) { :local }

      it 'returns the current time in the local timezone' do
        expect(current_time).to eq(now)
      end
    end
  end

  describe 'quoted_table_alias' do
    let(:connection) { double(:connection) }

    # rubocop:disable Style/ClassAndModuleChildren
    class self::Foo < ActiveRecord::Base
    end
    # rubocop:enable Style/ClassAndModuleChildren

    subject { Foo }

    let(:quote_table_name) { '"foos_2"' }

    before(:each) do
      stub_const('Foo', self.class::Foo)

      allow(subject).to receive(:connection).and_return(connection)

      allow(connection).to receive(:quote_table_name)
        .and_return(quote_table_name)
    end

    def quoted_table_alias
      subject.send(:quoted_table_alias)
    end

    it 'returns the table alias quoted' do
      expect(quoted_table_alias).to eq(quote_table_name)
    end
  end

  describe 'quote' do
    def quote
      subject.send(:quote, value)
    end

    context 'when the value is true' do
      let(:value) { true }

      it 'returns "TRUE"' do
        expect(quote).to eq('TRUE')
      end
    end

    context 'when the value is false' do
      let(:value) { false }

      it 'returns "FALSE"' do
        expect(quote).to eq('FALSE')
      end
    end

    context 'when the value is something else' do
      let(:value) { 1 }
      let(:connection) { double(:connection) }

      before(:each) do
        allow(subject).to receive(:connection).and_return(connection)
      end

      it 'calls "quote" on the connection' do
        expect(connection).to receive(:quote).with(value)
        quote
      end
    end
  end

  describe 'changed_attributes' do
    # rubocop:disable Style/ClassAndModuleChildren
    class self::Model < superclass::Model
      include Dirty

      define_attribute_methods :foo, :bar if defined?(ActiveModel::Dirty)

      def self.ancestors
        super + [ActiveRecord::Base]
      end

      def self.primary_key
        'id'
      end

      def foo=(value)
        return if value == @foo
        @attributes ||= {}
        @attributes['foo'] = value
        foo_will_change!
        @foo = value
      end

      def bar=(value)
        return if value == @bar
        @attributes ||= {}
        @attributes['bar'] = value
        bar_will_change!
        @bar = value
      end

      def clone_attribute_value(reader_method, attribute_name)
        value = send(reader_method, attribute_name)
        value.duplicable? ? value.clone : value
      rescue TypeError, NoMethodError
        value
      end
    end
    # rubocop:enable Style/ClassAndModuleChildren

    let(:locking_enabled) { false }
    let(:locking_column) { 'lock_version' }

    before(:each) do
      allow(subject).to receive(:locking_enabled?).and_return(locking_enabled)
      allow(subject).to receive(:locking_column).and_return(locking_column)
    end

    def changed_attributes
      subject.send(:changed_attributes, records)
    end

    context 'when the list of records is empty' do
      let(:records) { [] }

      it 'returns an empty list' do
        expect(changed_attributes).to be_empty
      end
    end

    context 'when none of the records have any changes' do
      let(:records) { [Model.new] }

      it 'returns an empty list' do
        expect(changed_attributes).to be_empty
      end
    end

    context 'when an attribute has changed' do
      let(:records) { [Model.new(foo: 3)] }

      it 'returns a list containing the name of the changed attribute' do
        expect(changed_attributes).to match_array(%w(foo updated_at))
      end

      it 'includes the "updated_at" attribute in the returned list' do
        expect(changed_attributes).to include('updated_at')
      end

      context 'when locking is enabled' do
        let(:locking_enabled) { true }

        it 'returns a list containing the name of the changed attribute' do
          expected = %w(foo updated_at) + [locking_column]
          expect(changed_attributes).to match_array(expected)
        end

        it 'includes the locking column attribute in the returned list' do
          expect(changed_attributes).to include(locking_column)
        end
      end
    end

    context 'when two attributes have changed' do
      let(:records) { [Model.new(foo: 3, bar: 4)] }

      it 'returns a list containing both of the changed attributes' do
        expect(changed_attributes).to match_array(%w(foo bar updated_at))
      end

      it 'includes the "updated_at" attribute in the returned list' do
        expect(changed_attributes).to include('updated_at')
      end
    end

    context 'when two attributes have changed in two different records' do
      let(:records) { [Model.new(foo: 3), Model.new(bar: 4)] }

      it 'returns a list containing both of the changed attributes' do
        expect(changed_attributes).to match_array(%w(foo bar updated_at))
      end

      it 'includes the "updated_at" attribute in the returned list' do
        expect(changed_attributes).to include('updated_at')
      end
    end

    context 'when the same attribute has changed in two different records' do
      let(:records) { [Model.new(foo: 3), Model.new(foo: 4)] }

      it 'returns a list containing the changed attribute once' do
        expect(changed_attributes).to match_array(%w(foo updated_at))
      end

      it 'includes the "updated_at" attribute in the returned list' do
        expect(changed_attributes).to include('updated_at')
      end
    end
  end

  describe 'changed_attributes_for_sql' do
    let(:table_alias) { 'alias' }
    let(:connection) { double(:connection) }

    before(:each) do
      allow(subject).to receive(:connection).and_return(connection)
      allow(connection).to receive(:quote_column_name) { |value| %("#{value}") }
    end

    def changed_attributes_for_sql
      subject.send(:changed_attributes_for_sql, changed_attributes, table_alias)
    end

    context 'when the changed attributes list is empty' do
      let(:changed_attributes) { [] }

      it 'raises an ArgumentError error' do
        expect { changed_attributes_for_sql }.to raise_error(ArgumentError)
      end
    end

    context 'when the changed attributes list is non-empty' do
      let(:changed_attributes) { %w(foo bar) }

      it 'formats the attributes for SQL' do
        expected = %("foo" = #{table_alias}."foo", "bar" = #{table_alias}."bar")
        expect(changed_attributes_for_sql).to eq(expected)
      end
    end
  end

  describe 'all_attributes' do
    let(:attributes) { %w(foo bar) }
    let(:primary_key) { 'id' }

    before(:each) do
      allow(subject).to receive(:primary_key).and_return(primary_key)
    end

    def all_attributes
      subject.send(:all_attributes, attributes)
    end

    it 'returns all attributes, including the primary key' do
      expected = [primary_key] + attributes
      expect(all_attributes).to eq(expected)
    end
  end

  describe 'type_casts' do
    # rubocop:disable Style/ClassAndModuleChildren
    class self::Foo < ActiveRecord::Base
    end
    # rubocop:enable Style/ClassAndModuleChildren

    subject { Foo }

    let(:primary_key) { 'id' }
    let(:column_names) { [primary_key] + %w(foo bar updated_at) }

    let(:connection) { double(:connection) }
    let(:schema_cache) { double(:schema_cache) }
    let(:column) { Struct.new(:name, :sql_type, :primary) }
    let(:locking_enabled) { false }
    let(:locking_column) { 'lock_version' }

    let(:columns_hash) do
      Hash[[*column_names].map { |e| [e, column.new(e, type_map[e])] }]
    end

    let(:type_map) do
      {
        id: 'integer',
        foo: 'character varying(255)',
        bar: 'boolean',
        updated_at: 'timestamp without time zone',
        locking_column => 'integer'
      }.stringify_keys
    end

    before(:each) do
      stub_const('Foo', self.class::Foo)

      allow(subject).to receive(:locking_enabled?).and_return(locking_enabled)
      allow(subject).to receive(:locking_column).and_return(locking_column)
      allow(subject).to receive(:columns_hash).and_return(columns_hash)
    end

    def type_casts
      subject.send(:type_casts, column_names)
    end

    it 'returns the type casts' do
      expected = '(' \
        'NULL::integer, '\
        'NULL::character varying(255), ' \
        'NULL::boolean, ' \
        'NULL::timestamp without time zone' \
      ')'

      expect(type_casts).to eq(expected)
    end

    context 'when locking is enabled' do
      let(:locking_enabled) { true }
      let(:column_names) { super().dup << locking_column }

      it 'raises the type casts, including the prev locking column' do
        expected = '(' \
          'NULL::integer, '\
          'NULL::integer, ' \
          'NULL::character varying(255), ' \
          'NULL::boolean, ' \
          'NULL::timestamp without time zone, ' \
          'NULL::integer' \
        ')'

        expect(type_casts).to eq(expected)
      end
    end

    context 'when the given list of changed attributes is nil' do
      let(:primary_key) { 'id' }
      let(:column_names) { nil }

      it 'raises a "No changed attributes given" error' do
        message = 'No column names given'
        expect { type_casts }.to raise_error(ArgumentError, message)
      end
    end

    context 'when the given list of changed attributes is empty' do
      let(:primary_key) { 'id' }
      let(:column_names) { [] }

      it 'raises a "No changed attributes given" error' do
        message = 'No column names given'
        expect { type_casts }.to raise_error(ArgumentError, message)
      end
    end
  end

  describe 'changed_values' do
    # rubocop:disable Style/ClassAndModuleChildren
    class self::Model < superclass::Model
      # To avoid comparing the `@errors` instance variable. When `dup` is called
      # `ActiveModel::Validations` will reset the `@errors` instance variable to
      # `nil` in the `initialize_dup` method. This will cause the existing
      # records, which don't have this instance variable, to be different from
      # the dup which will have this instance variable.
      def ==(other)
        [id, foo, bar] == [other.id, other.foo, other.bar]
      end
    end
    # rubocop:enable Style/ClassAndModuleChildren

    let(:changed_attributes) { %w(id foo bar updated_at) }
    let(:updated_at) { Time.at(0) }
    let(:connection) { double(:connection) }
    let(:locking_enabled) { false }
    let(:previous_lock_values) { {} }

    let(:records) do
      [
        Model.new(id: 1, foo: 3, bar: 4),
        Model.new(id: 2, foo: 5, bar: 6)
      ]
    end

    before(:each) do
      allow(subject).to receive(:locking_enabled?).and_return(locking_enabled)
      allow(subject).to receive(:connection).and_return(connection)
      allow(connection).to receive(:quote) { |v| v }
    end

    def changed_values
      subject.send(
        :changed_values,
        records,
        changed_attributes,
        updated_at,
        previous_lock_values
      )
    end

    it 'returns the changed values' do
      expected = [
        [1, 3, 4, updated_at],
        [2, 5, 6, updated_at]
      ]

      expect(changed_values).to eq(expected)
    end

    it 'does not change the input records', :aggregate_failures do
      input = records.map(&:dup)
      expect(records).to_not be(input)

      changed_values
      expect(records).to eq(input)
    end

    context 'when only few attributes have changed' do
      let(:changed_attributes) { %w(id bar updated_at) }

      it 'returns the values only for the changed attributes' do
        expected = [
          [1, 4, updated_at],
          [2, 6, updated_at]
        ]

        expect(changed_values).to eq(expected)
      end
    end

    context 'when the given list of records is nil' do
      let(:records) { nil }

      it 'raises a "No changed records given" error' do
        error_message = 'No changed records given'
        expect { changed_values }.to raise_error(ArgumentError, error_message)
      end
    end

    context 'when the given list of records is empty' do
      let(:records) { [] }

      it 'raises a "No changed records given" error' do
        error_message = 'No changed records given'
        expect { changed_values }.to raise_error(ArgumentError, error_message)
      end
    end

    context 'when the given list of changed attributes is nil' do
      let(:changed_attributes) { nil }

      it 'raises a "No changed attributes given" error' do
        error_message = 'No changed attributes given'
        expect { changed_values }.to raise_error(ArgumentError, error_message)
      end
    end

    context 'when the given list of changed attributes is empty' do
      let(:changed_attributes) { [] }

      it 'raises a "No changed attributes given" error' do
        error_message = 'No changed attributes given'
        expect { changed_values }.to raise_error(ArgumentError, error_message)
      end
    end

    context 'when locking is disabled' do
      let(:locking_enabled) { false }

      it 'does not change the "previous_lock_values" parameter' do
        expect { changed_values }.to_not change { previous_lock_values }
      end
    end

    context 'when locking is enabled' do
      # rubocop:disable Style/ClassAndModuleChildren
      class self::Model < superclass::Model
        attr_accessor :lock_version

        def slice(*keys)
          super.merge(lock_version: lock_version)
        end
      end
      # rubocop:enable Style/ClassAndModuleChildren

      let(:locking_enabled) { true }
      let(:lock_value) { 1 }
      let(:changed_attributes) { %w(id foo bar updated_at lock_version) }

      let(:records) do
        [
          Model.new(id: 1, foo: 3, bar: 4, lock_version: lock_value),
          Model.new(id: 2, foo: 5, bar: 6, lock_version: lock_value + 1)
        ]
      end

      it 'includes the previous and new value of the locking column' do
        expected = [
          [1, lock_value, 3, 4, lock_value + 1, updated_at],
          [2, lock_value + 1, 5, 6, lock_value + 2, updated_at]
        ]

        expect(changed_values).to eq(expected)
      end

      it 'adds the previous locking values to "previous_lock_values"' do
        expected = records.map { |r| [r.id, r.lock_version] }.to_h
        changed_values
        expect(previous_lock_values).to eq(expected)
      end
    end
  end

  describe 'increment_lock' do
    let(:lock_value) { 1 }
    let!(:record) { Struct.new(locking_column).new(lock_value) }
    let(:locking_column) { :lock_version }

    before(:each) do
      allow(subject).to receive(:locking_column).and_return(locking_column.to_s)
      allow(subject).to receive(:locking_enabled?).and_return(locking_enabled)
    end

    def increment_lock
      subject.send(:increment_lock, record)
    end

    context 'when locking is disabled' do
      let(:locking_enabled) { false }

      it 'does not changed the lock value' do
        expect { increment_lock }.to_not change(record, locking_column)
      end

      it 'returns nil' do
        expect(increment_lock).to be_nil
      end
    end

    context 'when locking is enabled' do
      let(:locking_enabled) { true }

      it 'changes the lock value' do
        expect { increment_lock }.to change(record, locking_column).by(1)
      end

      it 'returns the previous lock value' do
        expect(increment_lock).to eq(lock_value)
      end
    end
  end

  describe 'restore_lock' do
    let(:record_type) { Struct.new(:id, :lock_version) }
    let!(:records) { Array.new(2) { |e| record_type.new(e, e + 1) } }
    let(:lock_values) { records.map { |e| [e.id, e.lock_version - 1] }.to_h }

    before(:each) do
      allow(subject).to receive(:locking_column).and_return('lock_version')
      allow(subject).to receive(:locking_enabled?).and_return(locking_enabled)
    end

    def restore_lock
      subject.send(:restore_lock, records, lock_values)
    end

    context 'when locking is disabled' do
      let(:locking_enabled) { false }

      it 'does not change the lock values' do
        expect { restore_lock }.to_not change { records.map(&:lock_version) }
      end

      it 'returns nil' do
        expect(restore_lock).to be_nil
      end
    end

    context 'when locking is enabled' do
      let(:locking_enabled) { true }

      it 'restores the lock values' do
        restore_lock
        expect(records.map(&:lock_version)).to eq(lock_values.values)
      end

      context 'when the a record does not exist in "lock_values"' do
        let(:lock_values) { {} }

        it 'does not change the lock values' do
          expect { restore_lock }.to_not change { records.map(&:lock_version) }
        end
      end
    end
  end

  describe 'values_for_sql' do
    let(:connection) { double(:connection) }

    let(:changed_values) do
      [
        [1, 3, 4],
        [2, 5, 6]
      ]
    end

    before(:each) do
      allow(subject).to receive(:connection).and_return(connection)
      allow(connection).to receive(:quote) { |v| v }
    end

    def values_for_sql
      subject.send(:values_for_sql, changed_values)
    end

    it 'returns the changed values formatted for SQL' do
      expect(values_for_sql).to eq('(1, 3, 4), (2, 5, 6)')
    end

    context 'when the values need quoting' do
      let(:changed_values) do
        [
          [1, "fo'o", nil],
          [2, nil, "ba'r"]
        ]
      end

      before(:each) do
        allow(connection).to receive(:quote) do |value|
          case value
          when nil then 'NULL'
          when "fo'o" then "'fo''o'"
          when "ba'r" then "'ba''r'"
          else value
          end
        end
      end

      it 'properly quotes the values' do
        expect(values_for_sql).to eq("(1, 'fo''o', NULL), (2, NULL, 'ba''r')")
      end
    end

    context 'when the given list of changed values is nil' do
      let(:changed_values) { nil }

      it 'raises a "No changed attributes given" error' do
        error_message = 'No changed values given'
        expect { values_for_sql }.to raise_error(ArgumentError, error_message)
      end
    end

    context 'when the given list of changed values is empty' do
      let(:changed_values) { [] }

      it 'raises a "No changed attributes given" error' do
        error_message = 'No changed values given'
        expect { values_for_sql }.to raise_error(ArgumentError, error_message)
      end
    end
  end

  describe 'column_names_for_sql' do
    let(:column_names) { %w(id foo bar updated_at) }
    let(:connection) { double(:connection) }
    let(:locking_enabled) { false }
    let(:locking_column) { 'lock_version' }
    let(:prev_locking_column) { 'prev_lock_version' }

    before(:each) do
      allow(subject).to receive(:locking_enabled?).and_return(locking_enabled)
      allow(subject).to receive(:locking_column).and_return(locking_column)
      allow(subject).to receive(:prev_locking_column)
        .and_return(prev_locking_column)

      allow(subject).to receive(:connection).and_return(connection)
      allow(connection).to receive(:quote_column_name) { |v| %("#{v}") }
    end

    def column_names_for_sql
      subject.send(:column_names_for_sql, column_names)
    end

    it 'returns the column names formatted for SQL' do
      expect(column_names_for_sql).to eq('"id", "foo", "bar", "updated_at"')
    end

    context 'when locking is enabled' do
      let(:locking_enabled) { true }
      let(:column_names) { super() << locking_column }

      it 'returns the column names including the prev locking column' do
        expected = %("id", "#{prev_locking_column}", "foo", "bar", ) +
                   %("updated_at", "#{locking_column}")

        expect(column_names_for_sql).to eq(expected)
      end
    end

    context 'when the given list of changed attributes is nil' do
      let(:column_names) { nil }

      it 'raises a "No changed attributes given" error' do
        message = 'No column names given'
        expect { column_names_for_sql }.to raise_error(ArgumentError, message)
      end
    end

    context 'when the given list of changed attributes is empty' do
      let(:column_names) { [] }

      it 'raises a "No changed attributes given" error' do
        message = 'No column names given'
        expect { column_names_for_sql }.to raise_error(ArgumentError, message)
      end
    end
  end

  describe 'build_sql_template' do
    let(:locking_enabled) { false }

    before(:each) do
      allow(subject).to receive(:locking_enabled?).and_return(locking_enabled)
    end

    def build_sql_template
      subject.send(:build_sql_template)
    end

    it 'returns the SQL template' do
      sql1 = ActiveRecord::Base.const_get(:UPDATE_RECORDS_SQL_TEMPLATE)
      sql2 = ActiveRecord::Base.const_get(:UPDATE_RECORDS_SQL_FOOTER)

      expect(build_sql_template).to eq(sql1 + "\n" + sql2)
    end

    context 'when locking is enabled' do
      let(:locking_enabled) { true }

      it 'returns the template with the locking condition included' do
        const = :UPDATE_RECORDS_SQL_LOCKING_CONDITION
        sql = ActiveRecord::Base.const_get(const)
        expect(build_sql_template).to include(sql)
      end
    end

    context 'when locking is disabled' do
      let(:locking_enabled) { false }

      it 'returns the template without the locking condition' do
        const = :UPDATE_RECORDS_SQL_LOCKING_CONDITION
        sql = ActiveRecord::Base.const_get(const)
        expect(build_sql_template).to_not include(sql)
      end
    end
  end

  describe 'build_format_options' do
    let(:options) { { foo: 'a', bar: 'b' } }
    let(:connection) { double(:connection) }
    let(:locking_column) { 'c' }
    let(:prev_locking_column) { 'prev_' + locking_column }

    before(:each) do
      allow(subject).to receive(:locking_enabled?).and_return(locking_enabled)
      allow(subject).to receive(:connection).and_return(connection)

      allow(subject).to receive(:locking_column).and_return(locking_column)
      allow(subject).to receive(:prev_locking_column)
        .and_return(prev_locking_column)

      allow(connection).to receive(:quote_column_name) { |name| %("#{name}") }
    end

    def build_format_options
      subject.send(:build_format_options, options)
    end

    context 'when locking is enabled' do
      let(:locking_enabled) { true }

      it 'adds the locking column to the given options' do
        expected = options.merge(
          locking_column: %("#{locking_column}"),
          prev_locking_column: %("#{prev_locking_column}")
        )
        expect(build_format_options).to eq(expected)
      end
    end

    context 'when locking is disabled' do
      let(:locking_enabled) { false }

      it 'adds the locking column to the given options' do
        expect(build_format_options).to eq(options)
      end
    end
  end

  describe 'perform_update_records_query' do
    # rubocop:disable Style/ClassAndModuleChildren
    class self::Foo < ActiveRecord::Base
    end
    # rubocop:enable Style/ClassAndModuleChildren

    subject { Foo }

    let(:primary_key) { 'id' }
    let(:query) { double(:query) }

    let(:result) { double(:result) }
    let(:values) { [['1'], ['2']] }

    let(:connection) { double(:connection) }
    let(:schema_cache) { double(:schema_cache) }

    let(:columns) { [column.new('id', 'integer')] }

    let(:column) do
      Struct.new(:name, :sql_type, :primary) do
        def type_cast(value)
          value.to_i
        end
      end
    end

    before(:each) do
      stub_const('Foo', self.class::Foo)

      allow(subject).to receive(:connection).and_return(connection)
      allow(connection).to receive(:execute).and_return(result)
      allow(connection).to receive(:schema_cache).and_return(schema_cache)
      # For ActiveRecord 2.3
      allow(connection).to receive(:columns).and_return(columns)

      allow(schema_cache).to receive(:columns).and_return(columns)
      allow(schema_cache).to receive(:table_exists?).and_return(true)
      allow(schema_cache).to receive(:primary_keys).and_return('id')

      allow(result).to receive(:values).and_return(values)
    end

    def perform_update_records_query
      subject.send(:perform_update_records_query, query, primary_key)
    end

    it 'calls "connection.execute" with the given query', :aggregate_failures do
      expect(subject).to receive(:connection).and_return(connection)
      expect(connection).to receive(:execute).with(query)

      perform_update_records_query
    end

    it 'returns the primary keys of the records that were updated' do
      expect(perform_update_records_query).to eq([1, 2])
    end
  end

  describe 'validate_result' do
    let(:result) { ActiveRecord::Update::Result.new([], [], stale_objects) }
    let(:raise_on_stale_objects) { false }

    def validate_result
      subject.send(:validate_result, result, raise_on_stale_objects)
    end

    context 'when there are no stale objects' do
      let(:stale_objects) { [] }

      it 'does not raise any errors' do
        expect { validate_result }.to_not raise_error
      end
    end

    context 'when there are stale objects' do
      let(:stale_object1) { double(:stale_object) }
      let(:stale_object2) { double(:stale_object) }
      let(:stale_objects) { [stale_object1, stale_object2] }

      it 'does not raise any errors' do
        expect { validate_result }.to_not raise_error
      end

      context 'when raise_on_stale_objects is `true`' do
        let(:raise_on_stale_objects) { true }

        it 'raises an ActiveRecord::StaleObjectError error' do
          error = ActiveRecord::StaleObjectError
          expect { validate_result }.to raise_error(error)
        end

        it 'uses the first stale object to create the error' do
          begin
            validate_result
          rescue ActiveRecord::StaleObjectError => e
            # ActiveRecord 2.3 doesn't have the `record` method
            if e.respond_to?(:record)
              expect(e.record).to eq(stale_object1)
            else
              expect(true).to eq(true)
            end
          else
            # if this fails it means that the above call to `validate_result`
            # didn't raise an StaleObjectError error
            expect(false).to eq(true)
          end
        end
      end
    end
  end

  describe 'build_result' do
    let(:valid) { [double(:valid)] }
    let(:failed) { [double(:failed)] }
    let(:primary_keys) { [double(:primary_key)] }
    let(:stale_objects) { [double(:stale_objects)] }

    before(:each) do
      allow(subject).to receive(:extract_stale_objects)
        .and_return(stale_objects)
    end

    def build_result
      subject.send(:build_result, valid, failed, primary_keys)
    end

    def extract_fields(result)
      [result.ids, result.failed_records, result.stale_objects]
    end

    it 'returns the result' do
      expected = ActiveRecord::Update::Result.new(
        primary_keys, failed, stale_objects
      )
      expected = extract_fields(expected)

      actual = extract_fields(build_result)
      expect(actual).to eq(expected)
    end

    it 'calls "extract_stale_objects"' do
      expect(subject).to receive(:extract_stale_objects)
        .with(valid, primary_keys)

      build_result
    end
  end

  describe 'extract_stale_objects' do
    let(:locking_enabled) { false }
    let(:model) { Struct.new(:id) }

    def extract_stale_objects
      subject.send(:extract_stale_objects, records, primary_keys)
    end

    before(:each) do
      allow(subject).to receive(:locking_enabled?).and_return(locking_enabled)
      allow(subject).to receive(:primary_key).and_return('id')
    end

    context 'when the given records do not contain stale objects' do
      let(:primary_keys) { [1, 2] }
      let(:records) { primary_keys.map { |e| model.new(e) } }

      it 'returns an empty list' do
        expect(extract_stale_objects).to be_empty
      end
    end

    context 'when the given records contain stale objects' do
      let(:primary_keys) { [1] }
      let(:records) { Array.new(2) { |e| model.new(e) } }

      context 'when locking is enabled' do
        let(:locking_enabled) { true }

        it 'returns non-empty list' do
          expect(extract_stale_objects).to_not be_empty
        end
      end

      context 'when locking is disabled' do
        let(:locking_enabled) { false }

        it 'returns an empty list' do
          expect(extract_stale_objects).to be_empty
        end
      end
    end
  end

  describe 'update_timestamp' do
    let(:model) { Struct.new(:updated_at) }
    let(:records) { [model.new, model.new] }
    let(:timestamp) { Time.at(0) }

    def update_timestamp
      subject.send(:update_timestamp, records, timestamp)
    end

    it 'sets the timestamp for all the records' do
      result = update_timestamp.map(&:updated_at)
      expect(result).to contain_exactly(timestamp, timestamp)
    end
  end

  describe 'mark_changes_applied' do
    # rubocop:disable Style/ClassAndModuleChildren
    class self::Model < superclass::Model
      include Dirty

      define_attribute_methods :foo if defined?(ActiveModel::Dirty)

      def attribute(_)
        @foo
      end

      def self.ancestors
        super + [ActiveRecord::Base]
      end

      def self.primary_key
        'id'
      end

      def foo=(value)
        return if value == @foo
        @attributes ||= {}
        @attributes['foo'] = value
        foo_will_change!
        @foo = value
      end

      def clone_attribute_value(reader_method, attribute_name)
        value = send(reader_method, attribute_name)
        value.duplicable? ? value.clone : value
      rescue TypeError, NoMethodError
        value
      end
    end
    # rubocop:end Style/ClassAndModuleChildren

    let(:records) { [Model.new(foo: 1), Model.new(foo: 2)] }

    before(:each) do
      stub_const('Model', self.class::Model)
    end

    def mark_changes_applied
      subject.send(:mark_changes_applied, records)
    end

    it 'marks the changes applied for all the records' do
      mark_changes_applied
      expect(records.none?(&:changed?)).to be true
    end

    context 'when the record responds to the "changes_applied" method ' \
     '(ActiveRecord 4.1)' do
      it 'marks the changes applied for all the records' do
        mark_changes_applied
        expect(records).to_not include(be_changed)
      end
    end

    context 'when the record does not respond to the "changes_applied" ' \
      'method (ActiveRecord 2.3)' do
      class self::Model < superclass::Model
        undef_method :changes_applied if ActiveRecord::VERSION::MAJOR > 2
      end

      it 'marks the changes applied for all the records' do
        mark_changes_applied
        expect(records).to_not include(be_changed)
      end
    end
  end
end
