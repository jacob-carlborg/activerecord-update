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
    let(:primary_key) { 'id' }

    let(:records) do
      [
        Model.new(id: 1, foo: 4, bar: 5),
        Model.new(id: 2, foo: 2, bar: 3)
      ]
    end

    let(:changed_attributes) { Set.new(%w(id foo bar)) }
    let(:quoted_table_alias) { 'foos_2' }
    let(:values_for_sql) { '(1, 4, 5), (2, 2, 3)' }
    let(:column_names_for_sql) { '"id", "foo", "bar"' }

    let(:changed_attributes_for_sql) do
      '"id" = "foos_2"."id", "foo" = "foos_2"."foo", "bar" = "foos_2"."bar"'
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
      allow(subject).to receive(:connection).and_return(connection)
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
      subject.send(:sql_for_update_records, records)
    end

    it 'returns the SQL used for the "update_records" method' do
      expected = <<-SQL.strip_heredoc.strip
        UPDATE "foos" SET
          "id" = "foos_2"."id", "foo" = "foos_2"."foo", "bar" = "foos_2"."bar"
        FROM (
          VALUES (1, 4, 5), (2, 2, 3)
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

    it 'calls "values_for_sql" with the records and the changed attributes' do
      expect(subject).to receive(:values_for_sql)
        .with(records, changed_attributes, primary_key)

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
        values: values_for_sql,
        alias: quoted_table_alias,
        columns: column_names_for_sql,
        primary_key: subject.quoted_primary_key
      }

      expect(subject).to receive(:format).with(sql, options)
      sql_for_update_records
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
        expect(changed_attributes).to contain_exactly('foo')
      end
    end

    context 'when two attributes have changed' do
      let(:records) { [Model.new(foo: 3, bar: 4)] }

      it 'returns a list containing both of the changed attributes' do
        expect(changed_attributes).to match_array(%w(foo bar))
      end
    end

    context 'when two attributes have changed in two different records' do
      let(:records) { [Model.new(foo: 3), Model.new(bar: 4)] }

      it 'returns a list containing both of the changed attributes' do
        expect(changed_attributes).to match_array(%w(foo bar))
      end
    end

    context 'when the same attribute has changed in two different records' do
      let(:records) { [Model.new(foo: 3), Model.new(foo: 4)] }

      it 'returns a list containing the changed attribute once' do
        expect(changed_attributes).to contain_exactly('foo')
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
      let(:changed_attributes) { Set.new }

      it 'raises an ArgumentError error' do
        expect { changed_attributes_for_sql }.to raise_error(ArgumentError)
      end
    end

    context 'when the changed attributes list is non-empty' do
      let(:changed_attributes) { Set.new(%w(foo bar)) }

      it 'formats the attributes for SQL' do
        expected = %("foo" = #{table_alias}."foo", "bar" = #{table_alias}."bar")
        expect(changed_attributes_for_sql).to eq(expected)
      end
    end
  end

  describe 'values_for_sql' do
    let(:primary_key) { 'id' }
    let(:changed_attributes) { Set.new(%w(foo bar)) }
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

    def values_for_sql
      subject.send(:values_for_sql, records, changed_attributes, primary_key)
    end

    it 'returns the changed values formatted for SQL' do
      expect(values_for_sql).to eq('(1, 3, 4), (2, 5, 6)')
    end

    context 'when the values need quoting' do
      let(:records) do
        [
          Model.new(id: 1, foo: "fo'o"),
          Model.new(id: 2, bar: "ba'r")
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

    context 'when the given list of records is nil' do
      let(:records) { nil }

      it 'raises a "No changed records given" error' do
        error_message = 'No changed records given'
        expect { values_for_sql }.to raise_error(ArgumentError, error_message)
      end
    end

    context 'when the given list of records is empty' do
      let(:records) { [] }

      it 'raises a "No changed records given" error' do
        error_message = 'No changed records given'
        expect { values_for_sql }.to raise_error(ArgumentError, error_message)
      end
    end

    context 'when the given list of changed attributes is nil' do
      let(:changed_attributes) { nil }

      it 'raises a "No changed attributes given" error' do
        error_message = 'No changed attributes given'
        expect { values_for_sql }.to raise_error(ArgumentError, error_message)
      end
    end

    context 'when the given list of changed attributes is empty' do
      let(:changed_attributes) { [] }

      it 'raises a "No changed attributes given" error' do
        error_message = 'No changed attributes given'
        expect { values_for_sql }.to raise_error(ArgumentError, error_message)
      end
    end

    context 'when the primary key is nil' do
      let(:primary_key) { nil }

      it 'raises a "No changed attributes given" error' do
        error_message = 'No primary key given'
        expect { values_for_sql }.to raise_error(ArgumentError, error_message)
      end
    end

    context 'when the primary key is empty' do
      let(:primary_key) { '' }

      it 'raises a "No changed attributes given" error' do
        error_message = 'No primary key given'
        expect { values_for_sql }.to raise_error(ArgumentError, error_message)
      end
    end
  end

  describe 'column_names_for_sql' do
    let(:primary_key) { 'id' }
    let(:column_names) { Set.new(%w(foo bar)) }
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
end
