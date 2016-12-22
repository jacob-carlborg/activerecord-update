require 'spec_helper'

describe ActiveRecord::Base do
  subject { ActiveRecord::Base }

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
    class Model
      include ActiveModel::Dirty
      include ActiveModel::Model

      attr_reader :foo
      attr_reader :bar

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
end
