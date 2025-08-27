# frozen_string_literal: true

require 'scelint'
require 'thor'
require 'logger'

# SCELint CLI
class Scelint::CLI < Thor
  class_option :quiet, type: :boolean, aliases: '-q', default: false
  class_option :verbose, type: :boolean, aliases: '-v', default: false
  class_option :debug, type: :boolean, aliases: '-d', default: false

  desc 'lint PATH', 'Lint all files in PATH'
  option :strict, type: :boolean, aliases: '-s', default: false
  def lint(*paths)
    paths = ['.'] if paths.nil? || paths.empty?
    lint = Scelint::Lint.new(paths, logger: logger)

    count = lint.files.count

    if count.zero?
      logger.error 'No SCE data found.'
      exit 0
    end

    lint.errors.each do |error|
      logger.error error
    end

    lint.warnings.each do |warning|
      logger.warn warning
    end

    lint.notes.each do |note|
      logger.info note
    end

    message = "Checked #{count} files."
    if lint.errors.empty?
      message += '  No errors.'
      exit_code = 0
    else
      message += "  #{lint.errors.count} errors."
      exit_code = 1
    end

    unless lint.warnings.empty?
      message += "  #{lint.warnings.count} warnings."
      exit_code = 1 if options[:strict]
    end

    message += " #{lint.notes.count} notes." unless lint.notes.empty?

    logger.info message
    exit exit_code
  rescue => e
    logger.fatal e.message
  end
  default_task :lint

  private

  def logger
    return @logger if @logger
    @logger = Logger.new(STDOUT)
    if options[:quiet]
      @logger.level = Logger::FATAL
    elsif options[:debug]
      @logger.level = Logger::DEBUG
    elsif options[:verbose]
      @logger.level = Logger::INFO
    else
      @logger.level = Logger::INFO
      @logger.formatter = proc do |_severity, _datetime, _progname, msg|
        "#{msg}\n"
      end
    end
    @logger
  end
end
