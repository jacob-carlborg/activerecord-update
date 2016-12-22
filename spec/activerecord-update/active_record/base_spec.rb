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
end
