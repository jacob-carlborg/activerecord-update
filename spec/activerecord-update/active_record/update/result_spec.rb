require 'spec_helper'

describe ActiveRecord::Update::Result do
  subject do
    ActiveRecord::Update::Result.new(ids, failed_records, stale_objects)
  end

  let(:ids) { [1, 2] }
  let(:failed_records) { [] }
  let(:stale_objects) { [] }

  describe 'initialize' do
    it 'sets the "ids" attribute' do
      expect(subject.ids).to eq(ids)
    end

    it 'sets the "failed_records" attribute' do
      expect(subject.failed_records).to eq(failed_records)
    end
  end

  describe 'success?' do
    subject { super().success? }

    context 'when there are no failed records' do
      let(:failed_records) { [] }

      it { is_expected.to eq true }

      context 'when there are stale objects' do
        let(:stale_objects) { [double(:stale_object1), double(:stale_object1)] }

        it { is_expected.to eq false }
      end
    end

    context 'when there are failed records' do
      let(:failed_records) { [double(:failed), double(:failed)] }

      it { is_expected.to eq false }
    end
  end

  describe 'failed_records?' do
    subject { super().failed_records? }

    context 'when there are no failed records' do
      let(:failed_records) { [] }

      it { is_expected.to eq false }
    end

    context 'when there are failed records' do
      let(:failed_records) { [double(:failed), double(:failed)] }

      it { is_expected.to eq true }
    end
  end

  describe 'updates?' do
    subject { super().updates? }

    context 'when there are updated records' do
      let(:ids) { [1, 2] }

      it { is_expected.to eq true }
    end

    context 'when there are no updated records' do
      let(:ids) { [] }

      it { is_expected.to eq false }
    end
  end

  describe 'stale_objects?' do
    subject { super().stale_objects? }

    context 'when there are stale objects' do
      let(:stale_objects) { [double(:stale_object1), double(:stale_object1)] }

      it { is_expected.to eq true }
    end

    context 'when there are no stale objects' do
      let(:stale_objects) { [] }

      it { is_expected.to eq false }
    end
  end
end
