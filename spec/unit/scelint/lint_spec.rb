# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Scelint::Lint do
  # Each test assumes 3 files, no errors, no warnings, no notes.
  # Exceptions are listed below.
  let(:lint_files) { { '04' => 37, '11' => 2, '16' => 4 } }
  let(:lint_errors) { { '12' => 2, '13' => 4, '16' => 3 } }
  let(:lint_warnings) { { '04' => 17, '13' => 2 } }
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

  context 'when the merged-data pass raises' do
    let(:lint) do
      described_class.new([File.join(File.expand_path('../../fixtures', __dir__), 'modules', 'test_module_00')])
    end

    it 'reports the exception against merged data instead of raising' do
      allow(lint).to receive(:check_checks).and_raise(StandardError, 'boom')

      expect { lint.send(:merged_data_lint) }.not_to raise_error
      expect(lint.errors).to include('merged data: boom')
    end
  end

  context 'with CEs that resolve to more than one rule' do
    subject(:lint) do
      described_class.new([File.join(File.expand_path('../../fixtures', __dir__), 'modules', 'test_module_16')])
    end

    it 'reports a CE given different oval-ids by different files' do
      expect(lint.errors).to include(a_string_matching(%r{'16_ce_conflicting': conflicting oval-ids}))
    end

    it 'ignores ids that differ only by a prefix' do
      expect(lint.errors).not_to include(a_string_matching(%r{16_ce_prefixed}))
    end

    it "reports ids where one only ends with the other, without a '_' before it" do
      expect(lint.errors).to include(a_string_matching(%r{'16_ce_suffix_only': conflicting oval-ids}))
    end

    it "ignores ids whose XCCDF namespace is written with ':' instead of '.'" do
      expect(lint.errors).not_to include(a_string_matching(%r{16_ce_colon_namespace}))
    end

    it 'reports a rule whose name only ends with the other rule name' do
      expect(lint.errors).to include(a_string_matching(%r{'16_ce_shorter_name': conflicting oval-ids}))
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

  # Each of these modules has one malformed shape that used to crash the run,
  # or to be reported only as warnings.  The first pattern is the error that
  # names the offending data; every module must report at least that, and
  # nothing may escape as an exception.
  {
    '01' => [%r{ces\.yaml: 'ce' must be a hash, got Array}],
    '02' => [%r{profile\.yaml: 'profiles' must be a hash, got Array}],
    '03' => [%r{checks\.yaml: 'checks' must be a hash, got Array}],
    '04' => [
      %r{profile\.yaml \(profile 'broken_04_profile'\): contains something other than a hash},
      %r{\AProfile 'broken_04_profile': unable to render Hiera data .* with facts },
    ],
    '05' => [%r{\Amerged data \(check 'broken_05_check'\): settings must be a hash, got String}],
    '06' => [%r{\AProfile 'broken_06_profile': unable to render Hiera data}],
    '07' => [%r{checks\.yaml \(check 'broken_07_check'\): malformed remediation section disabled, expecting an array}],
  }.each do |index, expected_errors|
    context "validating broken_module_#{index}" do
      subject(:lint) { described_class.new([broken_module]) }

      let(:broken_module) do
        File.join(File.expand_path('../../fixtures', __dir__), 'modules', "broken_module_#{index}")
      end

      it 'reports the malformed data' do
        expected_errors.each do |pattern|
          expect(lint.errors).to include(match(pattern))
        end
      end
    end
  end

  context 'validating broken_module_05' do
    subject(:lint) { described_class.new([File.join(File.expand_path('../../fixtures', __dir__), 'modules', 'broken_module_05')]) }

    it 'warns about the file that has a non-hash settings value' do
      expect(lint.warnings).to include(match(%r{checks\.yaml \(check 'broken_05_check'\): settings must be a hash, got String}))
    end
  end

  context 'validating broken_module_06' do
    subject(:lint) { described_class.new([File.join(File.expand_path('../../fixtures', __dir__), 'modules', 'broken_module_06')]) }

    it 'warns about the check that has a non-array ces value' do
      expect(lint.warnings).to include(match(%r{checks\.yaml \(check 'broken_06_check'\): bad ces 'broken_06_ce'}))
    end
  end
end
