# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe Scelint::Lint do
  subject(:lint) { described_class.new([tmpdir]) }

  let(:tmpdir) { Dir.mktmpdir }

  after(:each) { FileUtils.rm_rf(tmpdir) }

  describe '#check_parameter' do
    before(:each) { lint.errors.clear }

    context 'with valid parameters' do
      it 'accepts a simple two-part parameter' do
        lint.check_parameter('file', 'check', 'module::param')
        expect(lint.errors).to be_empty
      end

      it 'accepts a three-part parameter' do
        lint.check_parameter('file', 'check', 'module::subclass::param')
        expect(lint.errors).to be_empty
      end

      it 'accepts parameters with digits and underscores' do
        lint.check_parameter('file', 'check', 'module2::my_param_1')
        expect(lint.errors).to be_empty
      end

      it 'accepts a parameter with multiple underscores' do
        lint.check_parameter('file', 'check', 'my_module::my_class::my_param')
        expect(lint.errors).to be_empty
      end
    end

    context 'when parameter is not a non-empty string' do
      it 'errors on nil' do
        lint.check_parameter('file', 'check', nil)
        expect(lint.errors).to include("file (check 'check'): invalid parameter ''")
      end

      it 'errors on empty string' do
        lint.check_parameter('file', 'check', '')
        expect(lint.errors).to include("file (check 'check'): invalid parameter ''")
      end

      it 'errors on an integer' do
        lint.check_parameter('file', 'check', 42)
        expect(lint.errors).to include("file (check 'check'): invalid parameter '42'")
      end

      it 'does not produce an invalid parameter name error (returns early)' do
        lint.check_parameter('file', 'check', nil)
        expect(lint.errors).not_to include(match(%r{invalid parameter name}))
      end
    end

    context 'when parameter format is invalid' do
      it 'errors when there is no namespace separator' do
        lint.check_parameter('file', 'check', 'param_only')
        expect(lint.errors).to include("file (check 'check'): invalid parameter name 'param_only'")
      end

      it 'errors when the parameter starts with an uppercase letter' do
        lint.check_parameter('file', 'check', 'Module::param')
        expect(lint.errors).to include("file (check 'check'): invalid parameter name 'Module::param'")
      end

      it 'errors when a segment starts with an uppercase letter' do
        lint.check_parameter('file', 'check', 'module::MyParam')
        expect(lint.errors).to include("file (check 'check'): invalid parameter name 'module::MyParam'")
      end

      it 'errors when the parameter starts with an underscore' do
        lint.check_parameter('file', 'check', '_module::param')
        expect(lint.errors).to include("file (check 'check'): invalid parameter name '_module::param'")
      end

      it 'errors when the parameter contains a hyphen' do
        lint.check_parameter('file', 'check', 'module::my-param')
        expect(lint.errors).to include("file (check 'check'): invalid parameter name 'module::my-param'")
      end

      it 'errors when the parameter has a trailing ::' do
        lint.check_parameter('file', 'check', 'module::')
        expect(lint.errors).to include("file (check 'check'): invalid parameter name 'module::'")
      end

      it 'errors when the parameter has a leading ::' do
        lint.check_parameter('file', 'check', '::module::param')
        expect(lint.errors).to include("file (check 'check'): invalid parameter name '::module::param'")
      end

      it 'errors when the parameter uses a single colon instead of ::' do
        lint.check_parameter('file', 'check', 'classname:parameter')
        expect(lint.errors).to include("file (check 'check'): invalid parameter name 'classname:parameter'")
      end

      it 'does not produce a reserved word error (returns early)' do
        lint.check_parameter('file', 'check', 'param_only')
        expect(lint.errors).not_to include(match(%r{reserved word}))
      end
    end

    context 'when parameter contains a reserved word' do
      it 'errors when the last segment is a reserved word' do
        lint.check_parameter('file', 'check', 'module::type')
        expect(lint.errors).to include("file (check 'check'): parameter name 'module::type' contains reserved word 'type'")
      end

      it 'errors when the first segment is a reserved word' do
        lint.check_parameter('file', 'check', 'class::param')
        expect(lint.errors).to include("file (check 'check'): parameter name 'class::param' contains reserved word 'class'")
      end

      it 'errors when a middle segment is a reserved word' do
        lint.check_parameter('file', 'check', 'module::if::param')
        expect(lint.errors).to include("file (check 'check'): parameter name 'module::if::param' contains reserved word 'if'")
      end

      it 'produces one error per reserved word segment' do
        lint.check_parameter('file', 'check', 'class::type')
        expect(lint.errors).to include("file (check 'check'): parameter name 'class::type' contains reserved word 'class'")
        expect(lint.errors).to include("file (check 'check'): parameter name 'class::type' contains reserved word 'type'")
      end

      it 'does not error on a parameter that merely contains a reserved word as a substring' do
        lint.check_parameter('file', 'check', 'module::typewriter')
        expect(lint.errors).to be_empty
      end
    end
  end

  describe 'parameter validation via full lint' do
    def write_checks(dir, checks_yaml)
      profile_dir = File.join(dir, 'SIMP', 'compliance_profiles')
      FileUtils.mkdir_p(profile_dir)
      File.write(File.join(profile_dir, 'checks.yaml'), checks_yaml)
    end

    context 'with an unnamespaced parameter' do
      before(:each) do
        write_checks(tmpdir, <<~YAML)
          ---
          version: '2.0.0'
          checks:
            test_check:
              type: puppet-class-parameter
              settings:
                parameter: bad_param
                value: foo
        YAML
      end

      it 'produces an invalid parameter name error' do
        expect(lint.errors).to include(match(%r{invalid parameter name 'bad_param'}))
      end
    end

    context 'with a parameter containing a reserved word' do
      before(:each) do
        write_checks(tmpdir, <<~YAML)
          ---
          version: '2.0.0'
          checks:
            test_check:
              type: puppet-class-parameter
              settings:
                parameter: module::class
                value: foo
        YAML
      end

      it 'produces a reserved word error' do
        expect(lint.errors).to include(match(%r{contains reserved word 'class'}))
      end
    end

    context 'with a valid parameter' do
      before(:each) do
        write_checks(tmpdir, <<~YAML)
          ---
          version: '2.0.0'
          checks:
            test_check:
              type: puppet-class-parameter
              settings:
                parameter: my_module::my_param
                value: foo
        YAML
      end

      it 'produces no parameter errors' do
        expect(lint.errors).not_to include(match(%r{invalid parameter}))
        expect(lint.errors).not_to include(match(%r{reserved word}))
      end
    end
  end
end
