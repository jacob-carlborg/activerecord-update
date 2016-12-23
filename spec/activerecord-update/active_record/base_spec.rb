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
