# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Scelint::Lint do
  def test_module
    "test_module_#{File.basename(__FILE__).split('_')[1]}"
  end

  def fixtures
    File.expand_path('../../fixtures', __dir__)
  end

  def module_path
    File.join(fixtures, 'modules', test_module)
  end

  subject(:lint) { described_class.new([module_path]) }

  context 'validating test data' do
    it 'initializes' do
      expect(lint).to be_instance_of(described_class)
    end

    it 'checks files' do
      expect(lint.files.count).to eq(37)
    end

    it 'has errors' do
      expect(lint.errors.count).to eq(13)
    end

    it 'has no warnings' do
      expect(lint.warnings).to eq([])
    end
  end
end
