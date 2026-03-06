# frozen_string_literal: true

require 'spec_helper'
require 'scelint/cli'

RSpec.describe Scelint::CLI do
  let(:fixtures_dir) { File.expand_path('../../fixtures/modules', __dir__) }
  let(:clean_module_path) { File.join(fixtures_dir, 'test_module_01') }
  let(:warning_module_path) { File.join(fixtures_dir, 'test_module_04') }

  # Runs the CLI via .start (as a user would invoke from the command line),
  # captures the SystemExit status, and suppresses stdout noise from the logger.
  def run_cli(args)
    Scelint::CLI.start(args)
  rescue SystemExit => e
    e.status
  end

  before(:each) do
    # Silence logger output to keep spec output clean.
    allow(Logger).to receive(:new).and_return(Logger.new(File::NULL))
  end

  describe 'invocation without an explicit subcommand' do
    context 'with a path argument' do
      it 'lints the given path' do
        expect(run_cli([clean_module_path])).to eq(0)
      end

      it 'lints multiple path arguments' do
        expect(run_cli([clean_module_path, warning_module_path])).to eq(0)
      end
    end

    context 'with no path argument' do
      it 'defaults to linting the current directory' do
        # The repo root has no SCE data, so lint finds no files and exits 0
        expect(run_cli([])).to eq(0)
      end
    end
  end

  describe 'explicit lint subcommand' do
    it 'lints the given path' do
      expect(run_cli(['lint', clean_module_path])).to eq(0)
    end

    it 'defaults to current directory when no path is given' do
      expect(run_cli(['lint'])).to eq(0)
    end
  end

  describe 'exit codes' do
    context 'when there are no errors and no warnings' do
      it 'exits 0' do
        expect(run_cli([clean_module_path])).to eq(0)
      end
    end

    context 'when there are warnings but no errors' do
      it 'exits 0 without --strict' do
        expect(run_cli([warning_module_path])).to eq(0)
      end

      it 'exits 1 with --strict' do
        expect(run_cli(['--strict', warning_module_path])).to eq(1)
      end
    end
  end

  describe '--quiet flag' do
    it 'exits 0 on a clean module' do
      expect(run_cli(['--quiet', clean_module_path])).to eq(0)
    end
  end

  describe '--verbose flag' do
    it 'exits 0 on a clean module' do
      expect(run_cli(['--verbose', clean_module_path])).to eq(0)
    end
  end

  describe '--debug flag' do
    it 'exits 0 on a clean module' do
      expect(run_cli(['--debug', clean_module_path])).to eq(0)
    end
  end
end
