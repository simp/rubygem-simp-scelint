# frozen_string_literal: true

require 'yaml'
require 'json'
require 'deep_merge'

require 'scelint/version'

module Scelint
  class Error < StandardError; end
  # Your code goes here...

  class Lint
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
              Dir.glob("#{path}/#{dir}/**/*.#{type}").each do |file|
                @data[file] = parse(file)
                merged_data = merged_data.deep_merge!(@data[file])
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

      @data.each do |file, data|
        lint(file, data)
      end

      @data
    end

    def parse(file)
      return @data[file] if @data[file]

      type = case file
             when %r{\.yaml$}
               'yaml'
             when %r{\.json$}
               'json'
             else
               nil
             end
      return YAML.safe_load(File.read(file)) if type == 'yaml'
      return JSON.parse(File.read(file)) if type == 'json'

      raise "Failed to determine file type of '#{file}'"
    end

    def files
      @data.keys - ['merged data']
    end

    def warnings
      @warnings
    end

    def errors
      @errors
    end

    def check_version(file, data)
      @errors << "Version check failed in #{file}." unless data['version'] == '2.0.0'
    end

    def check_keys(file, data)
      ok = [
        'version',
        'profiles',
        'ce',
        'checks',
        'controls',
      ]

      data.keys.each do |key|
        @warnings << "Unexpected key '#{key}' found in #{file}." unless ok.include?(key)
      end
    end

    def check_title(file, data)
      @warnings << "Bad title #{data} in #{file}." unless data.is_a?(String)
    end

    def check_description(file, data)
      @warnings << "Bad description #{data} in #{file}." unless data.is_a?(String)
    end

    def check_controls(file, data)
      if data.is_a?(Hash)
        data.each do |key, value|
          @warnings << "Bad control #{key} in #{file}." unless key.is_a?(String) && value # Should be truthy
        end
      else
        @warnings << "Bad controls #{data} in #{file}."
      end
    end

    def check_profile_ces(file, data)
      if data.is_a?(Hash)
        data.each do |key, value|
          @warnings << "Bad ce #{key} in #{file}." unless key.is_a?(String) && value.is_a?(TrueClass)
        end
      else
        @warnings << "Bad ces #{data} in #{file}."
      end
    end

    def check_confine(file, data)
      @warnings << "Bad confine #{data} in #{file}." unless data.is_a?(Hash)
    end

    def check_identifiers(file, data)
      if data.is_a?(Hash)
        data.each do |key, value|
          if key.is_a?(String) && value.is_a?(Array)
            value.each do |identifier|
              @warnings << "Bad identifier #{identifier} in #{file}." unless identifier.is_a?(String)
            end
          else
            @warnings << "Bad identifier #{key} in #{file}."
          end
        end
      else
        @warnings << "Bad identifiers #{data} in #{file}."
      end
    end

    def check_oval_ids(file, data)
      if data.is_a?(Array)
        data.each do |key|
          @warnings << "Bad oval-id #{key} in #{file}." unless key.is_a?(String)
        end
      else
        @warnings << "Bad oval-ids #{data} in #{file}."
      end
    end

    def check_imported_data(file, data)
      ok = ['checktext', 'fixtext']

      data.each do |key, value|
        @warnings << "Unexpected key '#{key}' found in #{file}" unless ok.include?(key)

        @warnings << "Bad #{key} data in #{file}: '#{value}'" unless value.is_a?(String)
      end
    end

    def check_profiles(file, data)
      ok = [
        'title',
        'description',
        'controls',
        'ces',
        'confine',
      ]

      data.each do |profile, value|
        value.keys.each do |key|
          @warnings << "Unexpected key '#{key}' found in #{file} (profile '#{profile}')." unless ok.include?(key)
        end

        check_title(file, value['title']) unless value['title'].nil?
        check_description(file, value['description']) unless value['description'].nil?
        check_controls(file, value['controls']) unless value['controls'].nil?
        check_profile_ces(file, value['ces']) unless value['ces'].nil?
        check_confine(file, value['confine']) unless value['confine'].nil?
      end
    end

    def check_ce(file, data)
      ok = [
        'title',
        'description',
        'controls',
        'identifiers',
        'oval-ids',
        'confine',
        'imported_data',
      ]

      data.each do |ce, value|
        value.keys.each do |key|
          @warnings << "Unexpected key '#{key}' found in #{file} (CE '#{ce}')." unless ok.include?(key)
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

    def check_type(file, check, data)
      @errors << "Unknown type '#{data}' found in #{file} (check '#{check}')." unless data == 'puppet-class-parameter'
    end

    def check_parameter(file, check, parameter)
      @errors << "Invalid parameter #{parameter} in #{file} (check '#{check}')." unless parameter.is_a?(String) && !parameter.empty?
    end

    def check_value(file, check, value)
      # value could be anything
      true
    end

    def check_settings(file, check, data)
      ok = ['parameter', 'value']

      if data.nil?
        @errors << "Missing settings in check '#{check}' in #{file}."
        return false
      end

      if data.key?('parameter')
        check_parameter(file, check, data['parameter'])
      else
        @errors << "Missing parameter in #{file} (check '#{check}')."
      end

      if data.key?('value')
        check_value(file, check, data['value'])
      else
        @errors << "Missing parameter in #{file} (check '#{check}')."
      end

      data.keys.each do |key|
        @warnings << "Unexpected key '#{key}' found in #{file} (check '#{check}')." unless ok.include?(key)
      end
    end

    def check_check_ces(file, data)
      @warnings << "Bad ces #{data} in #{file}." unless data.is_a?(Array)

      data.each do |key|
        @warnings << "Bad ce #{key} in #{file}." unless key.is_a?(String)
      end
    end

    def check_checks(file, data)
      ok = [
        'type',
        'settings',
        'controls',
        'identifiers',
        'oval-ids',
        'ces',
        'confine',
      ]

      data.each do |check, value|
        value.keys.each do |key|
          @warnings << "Unexpected key '#{key}' found in #{file} (check '#{check}')." unless ok.include?(key)
        end

        check_type(file, check, value['type']) if value['type'] || file == 'merged data'
        check_settings(file, check, value['settings']) if value['settings'] || file == 'merged data'
        check_controls(file, value['controls']) unless value['controls'].nil?
        check_identifiers(file, value['identifiers']) unless value['identifiers'].nil?
        check_oval_ids(file, value['oval-ids']) unless value['oval-ids'].nil?
        check_check_ces(file, value['ces']) unless value['ces'].nil?
        check_confine(file, value['confine']) unless value['confine'].nil?
      end
    end

    def lint(file, data)
      check_version(file, data)
      check_keys(file, data)

      check_profiles(file, data['profiles']) if data['profiles']
      check_ce(file, data['ce']) if data['ce']
      check_checks(file, data['checks']) if data['checks']
      check_controls(file, data['controls']) if data['controls']
    end
  end
end
