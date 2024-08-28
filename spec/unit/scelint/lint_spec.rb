# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Scelint::Lint do
  # Each test assumes 3 files, no errors, no warnings.
  # Exceptions are listed below.
  let(:lint_files) { { '04' => 37 } }
  let(:lint_errors) { {} }
  let(:lint_warnings) { { '04' => 17 } }

  test_modules = Dir.glob(File.join(File.expand_path('../../fixtures', __dir__), 'modules', 'test_module_*'))
  test_modules.each do |test_module|
    context "validating #{File.basename(test_module)}" do
      subject(:lint) { described_class.new([test_module]) }

      let(:index) { File.basename(test_module).delete_prefix('test_module_') }

      it 'initializes' do
        expect(lint).to be_instance_of(described_class)
      end

      it 'checks files' do
        expect(lint.files).to be_instance_of(Array)
        pp lint.files if lint.files.count != (lint_files[index] || 3)
        expect(lint.files.count).to eq(lint_files[index] || 3)
      end

      it 'has the expected data' do
        lint.files.each do |file|
          require 'yaml'
          expect(lint.data[file]).to eq(YAML.safe_load(File.read(file)))
        end
      end

      it 'has expected errors' do
        expect(lint.errors).to be_instance_of(Array)
        pp lint.errors if lint.errors.count != (lint_errors[index] || 0)
        expect(lint.errors.count).to eq(lint_errors[index] || 0)
      end

      it 'has expected warnings' do
        expect(lint.warnings).to be_instance_of(Array)
        pp lint.warnings if lint.warnings.count != (lint_warnings[index] || 0)
        expect(lint.warnings.count).to eq(lint_warnings[index] || 0)
      end
    end
  end

  context 'validating all test modules at once' do
    subject(:lint) { described_class.new(test_modules) }

    let(:total_files) do
      test_modules.sum do |test_module|
        index = File.basename(test_module).delete_prefix('test_module_')
        lint_files[index] || 3
      end
    end
    let(:total_errors) do
      test_modules.sum do |test_module|
        index = File.basename(test_module).delete_prefix('test_module_')
        lint_errors[index] || 0
      end
    end
    let(:total_warnings) do
      test_modules.sum do |test_module|
        index = File.basename(test_module).delete_prefix('test_module_')
        lint_warnings[index] || 0
      end
    end

    it 'initializes' do
      expect(lint).to be_instance_of(described_class)
    end

    it 'checks files' do
      expect(lint.files).to be_instance_of(Array)
      pp lint.files if lint.files.count != total_files
      expect(lint.files.count).to eq(total_files)
    end

    it 'has expected errors' do
      expect(lint.errors).to be_instance_of(Array)
      pp lint.errors if lint.errors.count != total_errors
      expect(lint.errors.count).to eq(total_errors)
    end

    it 'has expected warnings' do
      expect(lint.warnings).to be_instance_of(Array)
      pp lint.warnings if lint.warnings.count != total_warnings
      expect(lint.warnings.count).to eq(total_warnings)
    end
  end
end
