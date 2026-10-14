# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Scelint::Lint do
  # Each test assumes 3 files, no errors, no warnings, no notes.
  # Exceptions are listed below.
  let(:lint_files) { { '04' => 37, '11' => 2 } }
  let(:lint_errors) { { '12' => 2 } }
  let(:lint_warnings) { { '04' => 17 } }
  let(:lint_notes) { { '11' => 1 } }

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

  # broken_module_00 contains a check whose value is an array instead of a
  # hash (a `ces` key deleted by mistake, leaving the list directly under
  # the check id).  compliance_engine raises when merging it, which used to
  # abort the entire lint run before any errors were reported.  It is kept
  # out of the test_module_* glob above because merging it poisons Hiera
  # validation for every other module's profiles when linted together.
  context 'validating a module with an unmergeable check' do
    subject(:lint) { described_class.new([broken_module]) }

    let(:broken_module) do
      File.join(File.expand_path('../../fixtures', __dir__), 'modules', 'broken_module_00')
    end

    it 'initializes' do
      expect(lint).to be_instance_of(described_class)
    end

    it 'reports the file and check that are malformed' do
      expect(lint.errors).to include(match(%r{checks\.yaml \(check 'broken_00_check'\): contains something other than a hash}))
    end

    it 'reports the check that cannot be merged' do
      expect(lint.errors).to include(match(%r{\Amerged data: unable to merge check 'broken_00_check'}))
    end

    it 'reports the profile whose Hiera data cannot be rendered' do
      expect(lint.errors).to include(match(%r{\AProfile 'broken_00_profile': unable to render Hiera data}))
    end

    it 'reports nothing else' do
      expect(lint.errors.count).to eq(3)
      expect(lint.warnings).to be_empty
      expect(lint.notes).to be_empty
    end
  end
end
