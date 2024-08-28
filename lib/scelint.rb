# frozen_string_literal: true

require 'yaml'
require 'json'
require 'deep_merge'

require 'scelint/version'

module Scelint
  class Error < StandardError; end

  # Checks SCE data in the specified directories
  # @example Look for data in the current directory (the default)
  #    lint = Scelint::Lint.new()
  # @example Look for data in `/path/to/module`
  #    lint = Scelint::Lint.new('/path/to/module')
  # @example Look for data in all modules in the current directory
  #    lint = Scelint::Lint.new(Dir.glob('*'))
  class Lint
    attr_accessor :data, :errors, :warnings

    def initialize(paths = ['.'])
      @data = {}
      @errors = []
      @warnings = []

      merged_data = {}

      paths.each do |path|
        if File.directory?(path)
          [
            'SIMP/compliance_profiles',
            'simp/compliance_profiles',
          ].each do |dir|
            ['yaml', 'json'].each do |type|
              Dir.glob("#{path}/#{dir}/**/*.#{type}") do |file|
                @data[file] = parse(file)
                merged_data = merged_data.deep_merge!(Marshal.load(Marshal.dump(@data[file])))
              end
            end
          end
        elsif File.exist?(path)
          @data[path] = parse(path)
        else
          raise "Can't find path '#{path}'"
        end
      end

      return nil if @data.empty?

      @data['merged data'] = merged_data

      @data.each do |file, file_data|
        lint(file, file_data)
      end
    end

    def parse(file)
      return data[file] if data[file]

      type = case file
             when %r{\.yaml$}
               'yaml'
             when %r{\.json$}
               'json'
             else
               errors << "#{file}: Failed to determine file type"
               nil
             end
      begin
        return YAML.safe_load(File.read(file)) if type == 'yaml'
        return JSON.parse(File.read(file)) if type == 'json'
      rescue => e
        errors << "#{file}: Failed to parse file: #{e.message}"
      end

      {}
    end

    def files
      data.keys - ['merged data']
    end

    def check_version(file, file_data)
      errors << "#{file}: version check failed" unless file_data['version'] == '2.0.0'
    end

    def check_keys(file, file_data)
      ok = [
        'version',
        'profiles',
        'ce',
        'checks',
        'controls',
      ]

      file_data.each_key do |key|
        warnings << "#{file}: unexpected key '#{key}'" unless ok.include?(key)
      end
    end

    def check_title(file, file_data)
      warnings << "#{file}: bad title '#{file_data}'" unless file_data.is_a?(String)
    end

    def check_description(file, file_data)
      warnings << "#{file}: bad description '#{file_data}'" unless file_data.is_a?(String)
    end

    def check_controls(file, file_data)
      if file_data.is_a?(Hash)
        file_data.each do |key, value|
          warnings << "#{file}: bad control '#{key}'" unless key.is_a?(String) && value # Should be truthy
        end
      else
        warnings << "#{file}: bad controls '#{file_data}'"
      end
    end

    def check_profile_ces(file, file_data)
      if file_data.is_a?(Hash)
        file_data.each do |key, value|
          warnings << "#{file}: bad ce '#{key}'" unless key.is_a?(String) && value.is_a?(TrueClass)
        end
      else
        warnings << "#{file}: bad ces '#{file_data}'"
      end
    end

    def check_profile_checks(file, file_data)
      if file_data.is_a?(Hash)
        file_data.each do |key, value|
          warnings << "#{file}: bad check '#{key}'" unless key.is_a?(String) && value.is_a?(TrueClass)
        end
      else
        warnings << "#{file}: bad checks '#{file_data}'"
      end
    end

    def check_confine(file, file_data)
      warnings << "#{file}: bad confine '#{file_data}'" unless file_data.is_a?(Hash)
    end

    def check_identifiers(file, file_data)
      if file_data.is_a?(Hash)
        file_data.each do |key, value|
          if key.is_a?(String) && value.is_a?(Array)
            value.each do |identifier|
              warnings << "#{file}: bad identifier '#{identifier}'" unless identifier.is_a?(String)
            end
          else
            warnings << "#{file}: bad identifier '#{key}'"
          end
        end
      else
        warnings << "#{file}: bad identifiers '#{file_data}'"
      end
    end

    def check_oval_ids(file, file_data)
      if file_data.is_a?(Array)
        file_data.each do |key|
          warnings << "#{file}: bad oval-id '#{key}'" unless key.is_a?(String)
        end
      else
        warnings << "#{file}: bad oval-ids '#{file_data}'"
      end
    end

    def check_imported_data(file, file_data)
      ok = ['checktext', 'fixtext']

      file_data.each do |key, value|
        warnings << "#{file}: unexpected key '#{key}'" unless ok.include?(key)

        warnings << "#{file} (key '#{key}'): bad data '#{value}'" unless value.is_a?(String)
      end
    end

    def check_profiles(file, file_data)
      ok = [
        'title',
        'description',
        'controls',
        'ces',
        'checks',
        'confine',
      ]

      file_data.each do |profile, value|
        value.each_key do |key|
          warnings << "#{file} (profile '#{profile}'): unexpected key '#{key}'" unless ok.include?(key)
        end

        check_title(file, value['title']) unless value['title'].nil?
        check_description(file, value['description']) unless value['description'].nil?
        check_controls(file, value['controls']) unless value['controls'].nil?
        check_profile_ces(file, value['ces']) unless value['ces'].nil?
        check_profile_checks(file, value['checks']) unless value['checks'].nil?
        check_confine(file, value['confine']) unless value['confine'].nil?
      end
    end

    def check_ce(file, file_data)
      ok = [
        'title',
        'description',
        'controls',
        'identifiers',
        'oval-ids',
        'confine',
        'imported_data',
        'notes',
      ]

      file_data.each do |ce, value|
        value.each_key do |key|
          warnings << "#{file} (CE '#{ce}'): unexpected key '#{key}'" unless ok.include?(key)
        end

        check_title(file, value['title']) unless value['title'].nil?
        check_description(file, value['description']) unless value['description'].nil?
        check_controls(file, value['controls']) unless value['controls'].nil?
        check_identifiers(file, value['identifiers']) unless value['identifiers'].nil?
        check_oval_ids(file, value['oval-ids']) unless value['oval-ids'].nil?
        check_confine(file, value['confine']) unless value['confine'].nil?
        check_imported_data(file, value['imported_data']) unless value['imported_data'].nil?
      end
    end

    def check_type(file, check, file_data)
      errors << "#{file} (check '#{check}'): unknown type '#{file_data}'" unless file_data == 'puppet-class-parameter'
    end

    def check_parameter(file, check, parameter)
      errors << "#{file} (check '#{check}'): invalid parameter '#{parameter}'" unless parameter.is_a?(String) && !parameter.empty?
    end

    def check_remediation(file, check, remediation_section)
      reason_ok = [
        'reason',
      ]

      risk_ok = [
        'level',
        'reason',
      ]

      if remediation_section.is_a?(Hash)
        remediation_section.each do |section, value|
          case section
          when 'scan-false-positive', 'disabled'
            value.each do |reason|
              # If the element in the remediation section isn't a hash, it is incorrect.
              if reason.is_a?(Hash)
                # Check for unknown elements and warn the user rather than failing
                (reason.keys - reason_ok).each do |unknown_element|
                  warnings << "#{file} (check '#{check}'): Unknown element #{unknown_element} in remediation section #{section}"
                end
                errors << "#{file} (check '#{check}'): malformed remediation section #{section}, must be an array of reason hashes." unless reason['reason'].is_a?(String)
              else
                errors << "#{file} (check '#{check}'): malformed remediation section #{section}, must be an array of reason hashes."
              end
            end
          when 'risk'
            value.each do |risk|
              # If the element in the remediation section isn't a hash, it is incorrect.
              if risk.is_a?(Hash)
                # Check for unknown elements and warn the user rather than failing
                (risk.keys - risk_ok).each do |unknown_element|
                  warnings << "#{file} (check '#{check}'): Unknown element #{unknown_element} in remediation section #{section}"
                end
                # Since reasons are optional here, we won't be checking for those

                errors << "#{file} (check '#{check}'): malformed remediation section #{section}, must be an array of hashes containing levels and reasons." unless risk['level'].is_a?(Integer)
              else
                errors << "#{file} (check '#{check}'): malformed remediation section #{section}, must be an array of hashes containing levels and reasons."
              end
            end
          else
            warnings << "#{file} (check '#{check}'): #{section} is not a recognized section within the remediation section"
          end
        end
      else
        errors << "#{file} (check '#{check}'): malformed remediation section, expecting a hash."
      end
    end

    def check_value(_file, _check, _value)
      # value could be anything
      true
    end

    def check_settings(file, check, file_data)
      ok = ['parameter', 'value']

      if file_data.nil?
        msg = "#{file} (check '#{check}'): missing settings"
        if file == 'merged data'
          errors << msg
        else
          warnings << msg
        end
        return false
      end

      if file_data.key?('parameter')
        check_parameter(file, check, file_data['parameter'])
      else
        msg = "#{file} (check '#{check}'): missing key 'parameter'"
        if file == 'merged data'
          errors << msg
        else
          warnings << msg
        end
      end

      if file_data.key?('value')
        check_value(file, check, file_data['value'])
      else
        msg = "#{file} (check '#{check}'): missing key 'value'"
        if file == 'merged data'
          errors << msg
        else
          warnings << msg
        end
      end

      file_data.each_key do |key|
        warnings << "#{file} (check '#{check}'): unexpected key '#{key}'" unless ok.include?(key)
      end
    end

    def check_check_ces(file, file_data)
      warnings << "#{file}: bad ces '#{file_data}'" unless file_data.is_a?(Array)

      file_data.each do |key|
        warnings << "#{file}: bad ce '#{key}'" unless key.is_a?(String)
      end
    end

    def check_checks(file, file_data)
      ok = [
        'type',
        'settings',
        'controls',
        'identifiers',
        'oval-ids',
        'ces',
        'confine',
        'remediation',
      ]

      file_data.each do |check, value|
        if value.nil?
          warnings << "#{file} (check '#{check}'): empty value"
          next
        end

        if value.is_a?(Hash)
          value.each_key do |key|
            warnings << "#{file} (check '#{check}'): unexpected key '#{key}'" unless ok.include?(key)
          end
        else
          errors << "#{file} (check '#{check}'): contains something other than a hash, this is most likely caused by a missing note or ce element under the check"
        end

        check_type(file, check, value['type']) if value['type'] || file == 'merged data'
        check_settings(file, check, value['settings']) if value['settings'] || file == 'merged data'
        unless value['remediation'].nil?
          check_remediation(file, check, value['remediation']) if value['remediation']
        end
        check_controls(file, value['controls']) unless value['controls'].nil?
        check_identifiers(file, value['identifiers']) unless value['identifiers'].nil?
        check_oval_ids(file, value['oval-ids']) unless value['oval-ids'].nil?
        check_check_ces(file, value['ces']) unless value['ces'].nil?
        check_confine(file, value['confine']) unless value['confine'].nil?
      end
    end

    def lint(file, file_data)
      check_version(file, file_data)
      check_keys(file, file_data)

      check_profiles(file, file_data['profiles']) if file_data['profiles']
      check_ce(file, file_data['ce']) if file_data['ce']
      check_checks(file, file_data['checks']) if file_data['checks']
      check_controls(file, file_data['controls']) if file_data['controls']
    end
  end
end
