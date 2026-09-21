# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Scelint::Lint do
  # Each test assumes 3 files, no errors, no warnings, no notes.
  # Exceptions are listed below.
  let(:lint_files) { { '04' => 37, '11' => 2, '15' => 4 } }
  let(:lint_errors) { { '12' => 2, '15' => 2 } }
  let(:lint_warnings) { { '04' => 17 } }
  let(:lint_notes) { { '11' => 1, '15' => 1 } }

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

      it 'has expected notes' do
        expect(lint.notes).to be_instance_of(Array)
        pp lint.notes if lint.notes.count != (lint_notes[index] || 0)
        expect(lint.notes.count).to eq(lint_notes[index] || 0)
      end
    end
  end

  context 'with checks that disagree about a value' do
    subject(:lint) do
      described_class.new([File.join(File.expand_path('../../fixtures', __dir__), 'modules', 'test_module_15')])
    end

    it 'reports a check whose definition is split across files and disagrees' do
      expect(lint.errors).to include(a_string_matching(%r{'15_conflicting_definition': conflicting 'settings/value'}))
    end

    it 'notes a check defined identically in more than one file' do
      expect(lint.notes).to include(a_string_matching(%r{'15_identical_definition': identical definition}))
    end

    it 'reports two checks that write the same parameter differently' do
      expect(lint.errors).to include(a_string_matching(%r{'test_module_15::shared_param/a key'}))
    end

    it 'ignores checks whose confinement cannot overlap' do
      expect(lint.errors).not_to include(a_string_matching(%r{confined_param}))
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
    let(:total_notes) do
      test_modules.sum do |test_module|
        index = File.basename(test_module).delete_prefix('test_module_')
        lint_notes[index] || 0
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

    it 'has expected notes' do
      pending "The number of notes isn't a simple addition."
      expect(lint.notes).to be_instance_of(Array)
      pp lint.notes if lint.notes.count != total_notes
      expect(lint.notes.count).to eq(total_notes)
    end
  end
end
