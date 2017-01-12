require 'spec_helper'

describe ActiveRecord::Base do
  subject { ActiveRecord::Base }

  # rubocop:disable Style/ClassAndModuleChildren
  class self::Model
    include ActiveModel::Model

    attr_accessor :id
    attr_accessor :foo
    attr_accessor :bar

    def slice(*keys)
      hash = { id: id, foo: foo, bar: bar }
      ActiveSupport::HashWithIndifferentAccess.new(hash).slice(*keys)
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
      expect(subject).to receive(:_update_records)
        .with(records, raise_on_validation_failure: false)

      subject.update_records(records)
    end
  end

  describe 'update_records!' do
    let(:records) { [double(:record)] }

    it 'calls _update_records' do
      expect(subject).to receive(:_update_records)
        .with(records, raise_on_validation_failure: true)

      subject.update_records!(records)
    end
  end

  describe '_update_records' do
    let(:records) { [double(:record)] }

    let(:changed_records) { [double(:changed_record)] }
    let(:valid) { [double(:valid)] }
    let(:failed_records) { [double(:failed_record)] }
    let(:current_time) { double(:current_time) }
    let(:primary_key) { 'id' }
    let(:ids) { [1, 2] }
    let(:query) { double(:query) }
    let(:connection) { double(:connection) }
    let(:raise_on_validation_failure) { false }

    before(:each) do
      allow(subject).to receive(:changed_records).and_return(changed_records)
      allow(subject).to receive(:current_time).and_return(current_time)
      allow(subject).to receive(:quoted_table_alias).and_return('"foos"')
      allow(subject).to receive(:primary_key).and_return(primary_key)
      allow(subject).to receive(:perform_update_records_query).and_return(ids)
      allow(subject).to receive(:sql_for_update_records).and_return(query)
      allow(subject).to receive(:update_timestamp)
      allow(subject).to receive(:mark_changes_applied)
      allow(subject).to receive(:validate_records)
        .and_return([valid, failed_records])

      allow(subject).to receive(:connection).and_return(connection)
    end

    def update_records
      subject.send(
        :_update_records, records,
        raise_on_validation_failure: raise_on_validation_failure
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
        .with(valid, current_time)

      update_records
    end

    it 'calls "perform_update_records_query"' do
      expect(subject).to receive(:perform_update_records_query)
        .with(query, primary_key)

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
  end

  describe 'changed_records' do
    self::Model = Struct.new(:changed?, :new_record?) do
      def initialize(params = {})
        params.each { |k, v| public_send(:"#{k}=", v) }
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
        include ActiveModel::Model

        def initialize(valid)
          self[:valid?] = valid
        end

        def self.i18n_scope
          :activerecord
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
      include ActiveModel::Dirty

      define_attribute_methods :id, :foo, :bar

      def id=(value)
        id_will_change! unless value == @id
        @id = value
      end

      def foo=(value)
        foo_will_change! unless value == @foo
        @foo = value
      end

      def bar=(value)
        bar_will_change! unless value == @bar
        @bar = value
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

    let(:columns) do
      [primary_key, *changed_attributes].map { |e| column.new(e, type_map[e]) }
    end

    let(:type_map) do
      {
        id: 'integer',
        foo: 'character varying(255)',
        bar: 'boolean'
      }.stringify_keys
    end

    let(:primary_key) { 'id' }
    let(:timestamp) { Time.at(0).utc }
    let(:changed_attributes) { [primary_key, 'foo', 'bar'] }
    let(:quoted_table_alias) { 'foos_2' }
    let(:column_names_for_sql) { '"id", "foo", "bar"' }

    let(:values_for_sql) do
      "(1, 4, 5, '1970-01-01 00:00:00.000000'), " \
      "(2, 2, 3, '1970-01-01 00:00:00.000000')"
    end

    let(:changed_attributes_for_sql) do
      '"id" = "foos_2"."id", "foo" = "foos_2"."foo", "bar" = "foos_2"."bar"'
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
      '(NULL::integer, NULL::character varying(255), NULL::boolean)'
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
      allow(schema_cache).to receive(:columns).and_return(columns)

      # subject
      allow(subject).to receive(:connection).and_return(connection)
      allow(subject).to receive(:type_casts).and_return(type_casts)
      allow(subject).to receive(:changed_values).and_return(changed_values)
      allow(subject).to receive(:values_for_sql).and_return(values_for_sql)

      allow(subject).to receive(:changed_attributes)
        .and_return(changed_attributes)

      allow(subject).to receive(:quoted_table_alias)
        .and_return(quoted_table_alias)

      allow(subject).to receive(:changed_attributes_for_sql)
        .and_return(changed_attributes_for_sql)

      allow(subject).to receive(:column_names_for_sql)
        .and_return(column_names_for_sql)
    end

    def sql_for_update_records
      subject.send(:sql_for_update_records, records, timestamp)
    end

    it 'returns the SQL used for the "update_records" method' do
      expected = <<-SQL.strip_heredoc.strip
        UPDATE "foos" SET
          "id" = "foos_2"."id", "foo" = "foos_2"."foo", "bar" = "foos_2"."bar"
        FROM (
          VALUES
            (NULL::integer, NULL::character varying(255), NULL::boolean),
            (1, 4, 5, '1970-01-01 00:00:00.000000'), (2, 2, 3, '1970-01-01 00:00:00.000000')
        )
        AS foos_2("id", "foo", "bar")
        WHERE "foos"."id" = foos_2."id"
        RETURNING "foos"."id"
      SQL

      expect(sql_for_update_records).to eq(expected)
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

    it 'calls "quoted_table_alias"' do
      expect(subject).to receive(:quoted_table_alias)
      sql_for_update_records
    end

    it 'calls "changed_values" with the records and the changed attributes' do
      expect(subject).to receive(:changed_values)
        .with(records, primary_key, changed_attributes, timestamp)

      sql_for_update_records
    end

    it 'calls "values_for_sql" with the records and the changed attributes' do
      expect(subject).to receive(:values_for_sql).with(changed_values)
      sql_for_update_records
    end

    it 'calls "column_names_for_sql" with the primary key and changed '\
      'attributes' do
      expect(subject).to receive(:column_names_for_sql)
        .with(primary_key, changed_attributes)

      sql_for_update_records
    end

    it 'calls "format"' do
      sql = subject.const_get('UPDATE_RECORDS_SQL_TEMPLATE')

      options = {
        table: subject.quoted_table_name,
        set_columns: changed_attributes_for_sql,
        type_casts: type_casts,
        values: values_for_sql,
        alias: quoted_table_alias,
        columns: column_names_for_sql,
        primary_key: subject.quoted_primary_key
      }

      expect(subject).to receive(:format).with(sql, options)
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
      include ActiveModel::Dirty

      define_attribute_methods :foo, :bar

      def foo=(value)
        foo_will_change! unless value == @foo
        @foo = value
      end

      def bar=(value)
        bar_will_change! unless value == @bar
        @bar = value
      end
    end
    # rubocop:enable Style/ClassAndModuleChildren

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

  describe 'type_casts' do
    # rubocop:disable Style/ClassAndModuleChildren
    class self::Foo < ActiveRecord::Base
    end
    # rubocop:enable Style/ClassAndModuleChildren

    subject { Foo }

    let(:primary_key) { 'id' }
    let(:column_names) { %w(foo bar) }

    let(:connection) { double(:connection) }
    let(:schema_cache) { double(:schema_cache) }
    let(:column) { Struct.new(:name, :sql_type, :primary) }

    let(:columns) do
      [primary_key, *column_names].map { |e| column.new(e, type_map[e]) }
    end

    let(:type_map) do
      {
        id: 'integer',
        foo: 'character varying(255)',
        bar: 'boolean'
      }.stringify_keys
    end

    before(:each) do
      stub_const('Foo', self.class::Foo)

      allow(subject).to receive(:connection).and_return(connection)
      allow(connection).to receive(:schema_cache).and_return(schema_cache)

      allow(schema_cache).to receive(:columns).and_return(columns)
      allow(schema_cache).to receive(:table_exists?).and_return(true)
      allow(schema_cache).to receive(:primary_keys).and_return(primary_key)
    end

    def type_casts
      subject.send(:type_casts, primary_key, column_names)
    end

    it 'returns the type casts' do
      expected = '(NULL::integer, NULL::character varying(255), NULL::boolean)'
      expect(type_casts).to eq(expected)
    end

    context 'when the primary key is nil' do
      let(:primary_key) { nil }

      it 'raises a "No changed attributes given" error' do
        message = 'No primary key given'
        expect { type_casts }.to raise_error(ArgumentError, message)
      end
    end

    context 'when the primary key is empty' do
      let(:primary_key) { '' }

      it 'raises a "No changed attributes given" error' do
        message = 'No primary key given'
        expect { type_casts }.to raise_error(ArgumentError, message)
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

    let(:primary_key) { 'id' }
    let(:changed_attributes) { %w(foo bar) }
    let(:updated_at) { Time.at(0) }
    let(:connection) { double(:connection) }

    let(:records) do
      [
        Model.new(id: 1, foo: 3, bar: 4),
        Model.new(id: 2, foo: 5, bar: 6)
      ]
    end

    before(:each) do
      allow(subject).to receive(:connection).and_return(connection)
      allow(connection).to receive(:quote) { |v| v }
    end

    def changed_values
      subject.send(
        :changed_values, records, primary_key, changed_attributes, updated_at
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
      input = records.deep_dup
      expect(records).to_not be(input)

      changed_values
      expect(records).to eq(input)
    end

    context 'when only few attributes have changed' do
      let(:changed_attributes) { %w(bar) }

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

    context 'when the primary key is nil' do
      let(:primary_key) { nil }

      it 'raises a "No changed attributes given" error' do
        error_message = 'No primary key given'
        expect { changed_values }.to raise_error(ArgumentError, error_message)
      end
    end

    context 'when the primary key is empty' do
      let(:primary_key) { '' }

      it 'raises a "No changed attributes given" error' do
        error_message = 'No primary key given'
        expect { changed_values }.to raise_error(ArgumentError, error_message)
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
    let(:primary_key) { 'id' }
    let(:column_names) { %w(foo bar) }
    let(:connection) { double(:connection) }

    before(:each) do
      allow(subject).to receive(:connection).and_return(connection)
      allow(connection).to receive(:quote_column_name) { |v| %("#{v}") }
    end

    def column_names_for_sql
      subject.send(:column_names_for_sql, primary_key, column_names)
    end

    it 'returns the column names formatted for SQL' do
      expect(column_names_for_sql).to eq('"id", "foo", "bar"')
    end

    context 'when the primary key is nil' do
      let(:primary_key) { nil }

      it 'raises a "No changed attributes given" error' do
        message = 'No primary key given'
        expect { column_names_for_sql }.to raise_error(ArgumentError, message)
      end
    end

    context 'when the primary key is empty' do
      let(:primary_key) { '' }

      it 'raises a "No changed attributes given" error' do
        message = 'No primary key given'
        expect { column_names_for_sql }.to raise_error(ArgumentError, message)
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
      include ActiveModel::Dirty

      define_attribute_methods :foo

      def attribute(_)
        @foo
      end

      def foo=(value)
        foo_will_change! unless value == @foo
        @foo = value
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
  end
end
