# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe Scelint::Lint do
  subject(:lint) { described_class.new([tmpdir]) }

  let(:tmpdir) { Dir.mktmpdir }

  after(:each) { FileUtils.rm_rf(tmpdir) }

  describe '#check_value' do
    before(:each) do
      lint.errors.clear
      lint.warnings.clear
    end

    context 'with ordinary values' do
      ['x', 0, false, '', [], {}, { 'a' => 1 }].each do |value|
        it "accepts #{value.inspect}" do
          lint.check_value('file', 'check', value)
          expect(lint.errors).to be_empty
          expect(lint.warnings).to be_empty
        end
      end
    end

    context 'with a null value' do
      it 'reports an error' do
        lint.check_value('file', 'check', nil)
        expect(lint.errors).to include(a_string_matching(%r{value is null}))
      end
    end

    context 'with a nested null' do
      [{ 'a' => nil }, [1, nil], { 'a' => { 'b' => [nil] } }].each do |value|
        it "warns on #{value.inspect}" do
          lint.check_value('file', 'check', value)
          expect(lint.errors).to be_empty
          expect(lint.warnings).to include("file (check 'check'): value contains a nested null")
        end
      end
    end

    context 'when the value key is missing' do
      it 'does not report a null value' do
        lint.check_settings('file', 'check', { 'parameter' => 'mod::param' })
        expect(lint.errors).not_to include(a_string_matching(%r{value is null}))
      end
    end
  end
end
