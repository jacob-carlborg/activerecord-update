require 'active_record_helper'

describe 'integration' do
  let!(:record1) { Record.create(bar: bar) }
  let!(:record2) { Record.create(bar: bar) }
  let(:records) { [record1, record2] }
  let(:foo) { 1 }
  let(:bar) { 2 }

  let(:expected) do
    [
      Record.new(foo: foo, bar: bar),
      Record.new(bar: bar + 1)
    ].map { |e| e.slice(:foo, :bar) }
  end

  describe 'ActiveRecord::Base#update_records' do
    before(:each) do
      record1.foo = foo
      record2.bar = bar + 1
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
      now = Time.at(0)
      Timecop.freeze(now) { Record.update_records(records) }
      updated_ats = records.map(&:updated_at)
      expect(updated_ats).to contain_exactly(now, now)
    end

    context 'when a records fails to updated to due being stale' do
      before(:each) do
        record1.foo = foo
        record2.bar = bar + 1
        allow(Record).to receive(:extract_stale_objects).and_return(records)

        # Update the database behind the back of ActiveRecord to simulate a
        # different process updating the database causing a stale object error
        ActiveRecord::Base.connection.exec_query('UPDATE records SET '\
          "lock_version = #{record1.lock_version + 1} WHERE id = #{record1.id}")
      end

      it 'does not update the lock attribute' do
        Record.update_records(records)
        expect(records.map(&:lock_version)).to all(eq(0))
      end
    end
  end

  describe 'ActiveRecord::Base#update_records!' do
    context 'when a record fails to validate' do
      let!(:expected) do
        records.dup.map { |e| e.slice(:foo, :bar) }
      end

      before(:each) do
        record1.foo = foo
        record2.bar = 0
      end

      let(:expected) do
        Array.new(2) { Record.new(bar: bar).slice(:foo, :bar) }
      end

      it 'raises an ActiveRecord::RecordInvalid error' do
        error = ActiveRecord::RecordInvalid
        msg = 'Validation failed: Bar must be greater than 1'
        expect { Record.update_records!(records) }.to raise_error(error, msg)
      end

      it 'does not update the records', :aggregate_failures do
        error = ActiveRecord::RecordInvalid
        expect { Record.update_records!(records) }.to raise_error(error)
        attrs = records.map { |e| e.reload.slice(:foo, :bar) }
        expect(attrs).to eq(expected)
      end
    end

    context 'when a records fails to updated to due being stale' do
      before(:each) do
        record1.foo = foo
        record2.bar = bar + 1

        # Update the database behind the back of ActiveRecord to simulate a
        # different process updating the database causing a stale object error
        ActiveRecord::Base.connection.exec_query('UPDATE records SET '\
          "lock_version = #{record1.lock_version + 1} WHERE id = #{record1.id}")
      end

      it 'raises an ActiveRecord::StaleObjectError error' do
        error = ActiveRecord::StaleObjectError
        expect { Record.update_records!(records) }.to raise_error(error)
      end

      it 'does not update the stale records', :aggregate_failures do
        expected = [Record.new(bar: bar), Record.new(bar: bar + 1)]
          .map { |e| e.slice(:foo, :bar) }

        error = ActiveRecord::StaleObjectError
        expect { Record.update_records!(records) }.to raise_error(error)

        attrs = records.map { |e| e.reload.slice(:foo, :bar) }
        expect(attrs).to eq(expected)
      end

      it 'does not update the lock attribute' do
        error = ActiveRecord::StaleObjectError
        expect { Record.update_records!(records) }.to raise_error(error)

        expect(records.map(&:lock_version)).to all(eq(0))
      end
    end
  end
end
