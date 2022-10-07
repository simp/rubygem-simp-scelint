# frozen_string_literal: true

require 'yaml'
require 'json'
require 'deep_merge'
require 'logger'
require 'compliance_engine'

require 'scelint/version'

module Scelint
  class Error < StandardError; end

  LEGACY_FACTS = [
    'architecture',
    'augeasversion',
    'blockdevices',
    %r{^blockdevice_[[:alnum:]]+_model$},
    %r{^blockdevice_[[:alnum:]]+_size$},
    %r{^blockdevice_[[:alnum:]]+_vendor$},
    'bios_release_date',
    'bios_vendor',
    'bios_version',
    'boardassettag',
    'boardmanufacturer',
    'boardproductname',
    'boardserialnumber',
    'chassisassettag',
    'chassistype',
    'dhcp_servers',
    'domain',
    'fqdn',
    'gid',
    'hardwareisa',
    'hardwaremodel',
    'hostname',
    'id',
    'interfaces',
    'ipaddress',
    'ipaddress6',
    %r{^ipaddress6_[[:alnum:]]+$},
    %r{^ipaddress_[[:alnum:]]+$},
    %r{^ldom_[[:alnum:]]+$},
    'lsbdistcodename',
    'lsbdistdescription',
    'lsbdistid',
    'lsbdistrelease',
    'lsbmajdistrelease',
    'lsbminordistrelease',
    'lsbrelease',
    'macaddress',
    %r{^macaddress_[[:alnum:]]+$},
    'macosx_buildversion',
    'macosx_productname',
    'macosx_productversion',
    'macosx_productversion_major',
    'macosx_productversion_minor',
    'macosx_productversion_patch',
    'manufacturer',
    'memoryfree',
    'memoryfree_mb',
    'memorysize',
    'memorysize_mb',
    %r{^mtu_[[:alnum:]]+$},
    'netmask',
    'netmask6',
    %r{^netmask6_[[:alnum:]]+$},
    %r{^netmask_[[:alnum:]]+$},
    'network',
    'network6',
    %r{^network6_[[:alnum:]]+$},
    %r{^network_[[:alnum:]]+$},
    'operatingsystem',
    'operatingsystemmajrelease',
    'operatingsystemrelease',
    'osfamily',
    'physicalprocessorcount',
    %r{^processor[[:digit:]]+$},
    'processorcount',
    'productname',
    'rubyplatform',
    'rubysitedir',
    'rubyversion',
    'scope6',
    %r{^scope6_[[:alnum:]]+$},
    'selinux',
    'selinux_config_mode',
    'selinux_config_policy',
    'selinux_current_mode',
    'selinux_enforced',
    'selinux_policyversion',
    'serialnumber',
    %r{^sp_[[:alnum:]]+$},
    %r{^ssh[[:alnum:]]+key$},
    %r{^sshfp_[[:alnum:]]+$},
    'swapencrypted',
    'swapfree',
    'swapfree_mb',
    'swapsize',
    'swapsize_mb',
    'windows_edition_id',
    'windows_installation_type',
    'windows_product_name',
    'windows_release_id',
    'system32',
    'uptime',
    'uptime_days',
    'uptime_hours',
    'uptime_seconds',
    'uuid',
    'xendomains',
    %r{^zone_[[:alnum:]]+_brand$},
    %r{^zone_[[:alnum:]]+_iptype$},
    %r{^zone_[[:alnum:]]+_name$},
    %r{^zone_[[:alnum:]]+_uuid$},
    %r{^zone_[[:alnum:]]+_id$},
    %r{^zone_[[:alnum:]]+_path$},
    %r{^zone_[[:alnum:]]+_status$},
    'zonename',
    'zones',
  ].freeze

  # Checks SCE data in the specified directories
  # @example Look for data in the current directory (the default)
  #    lint = Scelint::Lint.new()
  # @example Look for data in `/path/to/module`
  #    lint = Scelint::Lint.new('/path/to/module')
  # @example Look for data in all modules in the current directory
  #    lint = Scelint::Lint.new(Dir.glob('*'))
  class Lint
    attr_accessor :data, :errors, :warnings, :notes, :log

    def initialize(paths = ['.'], logger: Logger.new(STDOUT, level: Logger::INFO))
      @log = logger
      @errors = []
      @warnings = []
      @notes = []

      @data = ComplianceEngine::Data.new(*Array(paths))

      @data.files.each do |file|
        lint(file, @data.get(file))
      end

      validate
    end

    def files
      data.files
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
      not_ok = [
        'type',
        'settings',
        'parameter',
        'value',
        'remediation',
        'risk',
        'level',
        'reason',
      ]

      unless file_data.is_a?(Hash)
        warnings << "#{file}: bad confine '#{file_data}'"
        return
      end

      file_data.each_key do |key|
        warnings << "#{file}: unexpected key '#{key}' in confine '#{file_data}'" if not_ok.include?(key)
        if Scelint::LEGACY_FACTS.any? { |legacy_fact| legacy_fact.is_a?(Regexp) ? legacy_fact.match?(key) : (legacy_fact == key) }
          warning = "#{file}: legacy fact '#{key}' in confine '#{file_data}'"
          warnings << warning unless warnings.include?(warning)
        end
      end
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
        'id',
        'benchmark_version',
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

    def normalize_confinement(confine)
      normalized = []

      # Step 1, sort the hash keys
      sorted = confine.sort.to_h

      # Step 2, expand all possible combinations of Array values
      index = 0
      max_count = 1
      sorted.each_value { |value| max_count *= Array(value).size }

      sorted.each do |key, value|
        (index..(max_count - 1)).each do |i|
          normalized[i] ||= {}
          normalized[i][key] = Array(value)[i % Array(value).size]
        end
      end

      # Step 3, convert dotted fact names into a facts hash
      normalized.map do |c|
        c.each_with_object({}) do |(key, value), result|
          current = result
          parts = key.split('.')
          parts.each_with_index do |part, i|
            if i == parts.length - 1
              current[part] = value
            else
              current[part] ||= {}
              current = current[part]
            end
          end
        end
      end
    end

    def confines
      return @confines unless @confines.nil?

      @confines = []

      [:profiles, :ces, :checks, :controls].each do |type|
        data.public_send(type).each_value do |value|
          # FIXME: This is calling a private method
          value.send(:fragments).each_value do |v|
            next unless v.is_a?(Hash)
            next unless v.key?('confine')
            normalize_confinement(v['confine']).each do |confine|
              @confines << confine unless @confines.include?(confine)
            end
          end
        end
      end

      @confines
    end

    def validate
      if data.profiles.keys.empty?
        notes << 'No profiles found, unable to validate Hiera data'
        return nil
      end

      # Unconfined, verify that hiera data exists
      data.profiles.each_key do |profile|
        hiera = data.hiera([profile])
        if hiera.nil?
          errors << "Profile '#{profile}': Invalid Hiera data (returned nil)"
          next
        end
        if hiera.empty?
          warnings << "Profile '#{profile}': No Hiera data found"
          next
        end
        log.debug "Profile '#{profile}': Hiera data found (#{hiera.keys.count} keys)"
      end

      # Again, this time confined
      confines.each do |confine|
        data.facts = confine
        data.profiles.select { |_, value| value.ces&.count&.positive? || value.controls&.count&.positive? }.each_key do |profile|
          hiera = data.hiera([profile])
          if hiera.nil?
            errors << "Profile '#{profile}': Invalid Hiera data (returned nil) with facts #{confine}"
            next
          end
          if hiera.empty?
            warnings << "Profile '#{profile}': No Hiera data found with facts #{confine}"
            next
          end
          log.debug "Profile '#{profile}': Hiera data found (#{hiera.keys.count} keys) with facts #{confine}"
        end
      end
    end

    def lint(file, file_data)
      check_version(file, file_data)
      check_keys(file, file_data)

      check_profiles(file, file_data['profiles']) if file_data['profiles']
      check_ce(file, file_data['ce']) if file_data['ce']
      check_checks(file, file_data['checks']) if file_data['checks']
      check_controls(file, file_data['controls']) if file_data['controls']
    rescue => e
      errors << "#{file}: #{e.message} (not a hash?)"
    end
  end
end
