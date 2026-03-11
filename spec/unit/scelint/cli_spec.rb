# frozen_string_literal: true

require 'spec_helper'
require 'scelint/cli'

RSpec.describe Scelint::CLI do
  let(:fixtures_dir) { File.expand_path('../../fixtures/modules', __dir__) }
  let(:clean_module_path) { File.join(fixtures_dir, 'test_module_01') }
  let(:warning_module_path) { File.join(fixtures_dir, 'test_module_04') }
  let(:reserved_word_module_path) { File.join(fixtures_dir, 'test_module_12') }

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
    # Prevent any real .scelint file in the working directory from affecting tests.
    allow(described_class).to receive(:load_defaults).and_return([])
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

  describe '.scelint defaults file' do
    describe '.load_defaults' do
      before(:each) do
        allow(described_class).to receive(:load_defaults).and_call_original
      end

      it 'returns an empty array when no .scelint file exists' do
        allow(File).to receive(:exist?).with(described_class::DEFAULTS_FILE).and_return(false)
        expect(described_class.load_defaults).to eq([])
      end

      it 'returns args parsed from the file' do
        allow(File).to receive(:exist?).with(described_class::DEFAULTS_FILE).and_return(true)
        allow(File).to receive(:readlines).with(described_class::DEFAULTS_FILE, chomp: true)
                                          .and_return(['--allow-reserved-words', '--strict'])
        expect(described_class.load_defaults).to eq(['--allow-reserved-words', '--strict'])
      end

      it 'splits multiple args on a single line' do
        allow(File).to receive(:exist?).with(described_class::DEFAULTS_FILE).and_return(true)
        allow(File).to receive(:readlines).with(described_class::DEFAULTS_FILE, chomp: true)
                                          .and_return(['--allow-reserved-words --strict'])
        expect(described_class.load_defaults).to eq(['--allow-reserved-words', '--strict'])
      end

      it 'ignores blank lines' do
        allow(File).to receive(:exist?).with(described_class::DEFAULTS_FILE).and_return(true)
        allow(File).to receive(:readlines).with(described_class::DEFAULTS_FILE, chomp: true)
                                          .and_return(['', '--strict', ''])
        expect(described_class.load_defaults).to eq(['--strict'])
      end

      it 'ignores comment lines' do
        allow(File).to receive(:exist?).with(described_class::DEFAULTS_FILE).and_return(true)
        allow(File).to receive(:readlines).with(described_class::DEFAULTS_FILE, chomp: true)
                                          .and_return(['# this is a comment', '--strict'])
        expect(described_class.load_defaults).to eq(['--strict'])
      end
    end

    context 'when .scelint contains --allow-reserved-words' do
      before(:each) do
        allow(described_class).to receive(:load_defaults).and_return(['--allow-reserved-words'])
      end

      it 'applies the flag without passing it on the command line' do
        expect(run_cli([reserved_word_module_path])).to eq(0)
      end

      it 'can be overridden by --no-allow-reserved-words on the command line' do
        expect(run_cli(['--no-allow-reserved-words', reserved_word_module_path])).to eq(1)
      end
    end

    context 'when .scelint contains --strict' do
      before(:each) do
        allow(described_class).to receive(:load_defaults).and_return(['--strict'])
      end

      it 'applies --strict without passing it on the command line' do
        expect(run_cli([warning_module_path])).to eq(1)
      end
    end
  end

  describe '--allow-reserved-words flag' do
    context 'when a parameter name contains a reserved word' do
      it 'exits 1 without --allow-reserved-words' do
        expect(run_cli([reserved_word_module_path])).to eq(1)
      end

      it 'exits 0 with --allow-reserved-words' do
        expect(run_cli(['--allow-reserved-words', reserved_word_module_path])).to eq(0)
      end

      it 'exits 0 with --allow-reserved-words and --strict' do
        expect(run_cli(['--allow-reserved-words', '--strict', reserved_word_module_path])).to eq(0)
      end
    end
  end
end
