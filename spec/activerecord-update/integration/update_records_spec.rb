require 'active_record_helper'

describe 'integration' do
  describe 'ActiveRecord::Base#update_records' do
    let!(:record1) { Record.create }
    let!(:record2) { Record.create }
    let(:records) { [record1, record2] }
    let(:foo) { 1 }
    let(:bar) { 1 }
    let(:now) { Time.at(0) }

    let(:expected) do
      [
        Record.new(foo: foo),
        Record.new(bar: bar)
      ].map { |e| e.slice(:foo, :bar) }
    end

    before(:each) do
      record1.foo = foo
      record2.bar = bar
    end

    it 'updates the given records' do
      Record.update_records(records)
      attrs = records.map { |e| e.reload.slice(:foo, :bar) }
      expect(attrs).to match_array(expected)
    end

    it 'returns the ids of the records which were updated' do
      ids = Record.update_records(records).ids
      expect(ids).to match_array(records.map(&:id))
    end

    it 'updates the "updated_at" attribute' do
      Timecop.freeze(now) { Record.update_records(records) }
      updated_ats = records.map(&:updated_at)
      expect(updated_ats).to contain_exactly(now, now)
    end
  end
end
