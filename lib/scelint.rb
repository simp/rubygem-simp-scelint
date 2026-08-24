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

  # Check SCE data in the specified directories
  # @example Look for data in the current directory (the default)
  #    lint = Scelint::Lint.new()
  # @example Look for data in `/path/to/module`
  #    lint = Scelint::Lint.new('/path/to/module')
  # @example Look for data in all modules in the current directory
  #    lint = Scelint::Lint.new(Dir.glob('*'))
  class Lint
    attr_accessor :data, :errors, :warnings, :notes, :log

    # Create a new Lint object
    #
    # @param paths [Array<String>] Paths to look for SCE data in. Defaults to ['.']
    # @param logger [Logger] A logger to send messages to. Defaults to an instance of Logger with the log level set to INFO.
    def initialize(paths = ['.'], logger: Logger.new(STDOUT, level: Logger::INFO), allow_reserved_words: false, resource_identity: {})
      @log = logger
      @allow_reserved_words = allow_reserved_words
      @resource_identity = resource_identity
      @errors = []
      @warnings = []
      @notes = []

      @data = ComplianceEngine::Data.new(*Array(paths))

      @data.files.each do |file|
        lint(file, @data.get(file))
      end

      merged_data_lint

      check_duplicate_check_definitions
      check_conflicting_values
      check_duplicate_resources

      validate
    end

    # Return an array of all the files found in the loaded data
    def files
      data.files
    end

    # Check that the value of the version key in the data is correct
    #
    # @param file [String] The path to the file being checked
    # @param file_data [String] The data to validate
    #
    # @note The version is currently hardcoded to '2.0.0'
    def check_version(file, file_data)
      errors << "#{file}: version check failed" unless file_data == '2.0.0'
    end

    # Check that all the top-level keys in the data are recognized
    #
    # @param file [String] The path to the file being checked
    # @param file_data [Hash] The data to validate
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

    # Check the title of the given data
    #
    # @param file [String] The path to the file being checked
    # @param file_data [String] The data to validate
    def check_title(file, file_data)
      warnings << "#{file}: bad title '#{file_data}'" unless file_data.is_a?(String)
    end

    # Check the description of the given data
    #
    # @param file [String] The path to the file being checked
    # @param file_data [String] The data to validate
    def check_description(file, file_data)
      warnings << "#{file}: bad description '#{file_data}'" unless file_data.is_a?(String)
    end

    # Check the controls in the given data
    #
    # @param file [String] The path to the file being checked
    # @param file_data [Hash] The data to validate
    def check_controls(file, file_data)
      if file_data.is_a?(Hash)
        file_data.each do |key, value|
          warnings << "#{file}: bad control '#{key}'" unless key.is_a?(String) && value # Should be truthy
        end
      else
        warnings << "#{file}: bad controls '#{file_data}'"
      end
    end

    # Check the CEs in a profile
    #
    # @param file [String] The path to the file being checked
    # @param file_data [Hash] The data to validate
    def check_profile_ces(file, file_data)
      if file_data.is_a?(Hash)
        file_data.each do |key, value|
          warnings << "#{file}: bad ce '#{key}'" unless key.is_a?(String) && value.is_a?(TrueClass)
        end
      else
        warnings << "#{file}: bad ces '#{file_data}'"
      end
    end

    # Check the checks in a profile
    #
    # @param file [String] The path to the file being checked
    # @param file_data [Hash] The data to validate
    def check_profile_checks(file, file_data)
      if file_data.is_a?(Hash)
        file_data.each do |key, value|
          warnings << "#{file}: bad check '#{key}'" unless key.is_a?(String) && value.is_a?(TrueClass)
        end
      else
        warnings << "#{file}: bad checks '#{file_data}'"
      end
    end

    # Check the confine data structure for any unexpected keys and legacy facts
    #
    # @param file [String] The path to the file being checked
    # @param file_data [Hash] The data to validate
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

    # Check identifiers
    #
    # @param file [String] The path to the file being checked
    # @param file_data [Hash] The data to validate
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

    # Check oval-ids
    #
    # @param file [String] The path to the file being checked
    # @param file_data [Array, Object] The data to validate
    def check_oval_ids(file, file_data)
      if file_data.is_a?(Array)
        file_data.each do |key|
          warnings << "#{file}: bad oval-id '#{key}'" unless key.is_a?(String)
        end
      else
        warnings << "#{file}: bad oval-ids '#{file_data}'"
      end
    end

    # Check imported_data
    #
    # @param file [String] The path to the file being checked
    # @param file_data [Hash] The data to validate
    def check_imported_data(file, file_data)
      ok = ['checktext', 'fixtext']

      file_data.each do |key, value|
        warnings << "#{file}: unexpected key '#{key}'" unless ok.include?(key)

        warnings << "#{file} (key '#{key}'): bad data '#{value}'" unless value.is_a?(String)
      end
    end

    # Check profiles
    #
    # @param file [String] The path to the file being checked
    # @param file_data [Hash] The data to validate
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

    # Check a CE
    #
    # @param file [String] The path to the file being checked
    # @param file_data [Hash] The data to validate
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

    # Check type
    #
    # @param file [String] The path to the file being checked
    # @param check [String] The name of the check
    # @param file_data [String] The data to validate
    def check_type(file, check, file_data)
      errors << "#{file} (check '#{check}'): unknown type '#{file_data}'" unless file_data == 'puppet-class-parameter'
    end

    # Check parameter
    #
    # @param file [String] The path to the file being checked
    # @param check [String] The name of the check
    # @param parameter [String] The parameter to validate
    def check_parameter(file, check, parameter)
      # Regular expression to match valid Puppet class parameter names
      valid_parameter = %r{\A([a-z][a-z0-9_]*::)+[a-z][a-z0-9_]*\z}
      # From https://www.puppet.com/docs/puppet/7/lang_reserved.html
      reserved_words = ['and', 'application', 'attr', 'case', 'component', 'consumes', 'default', 'define', 'elsif',
                        'environment', 'false', 'function', 'if', 'import', 'in', 'inherits', 'node',
                        'or', 'private', 'produces', 'regexp', 'site', 'true', 'type', 'undef', 'unit', 'unless',
                        'main', 'settings', 'init', 'any', 'array', 'binary', 'boolean', 'catalogentry', 'class',
                        'collection', 'callable', 'data', 'default', 'deferred', 'enum', 'float', 'hash', 'integer',
                        'notundef', 'numeric', 'optional', 'pattern', 'resource', 'regexp', 'runtime', 'scalar',
                        'semver', 'semVerRange', 'sensitive', 'string', 'struct', 'timespan', 'timestamp', 'tuple',
                        'type', 'undef', 'variant', 'facts', 'trusted', 'server_facts', 'title', 'name'].freeze

      unless parameter.is_a?(String) && !parameter.empty?
        errors << "#{file} (check '#{check}'): invalid parameter '#{parameter}'"
        return
      end

      unless parameter.match?(valid_parameter)
        errors << "#{file} (check '#{check}'): invalid parameter name '#{parameter}'"
        return
      end

      return if @allow_reserved_words

      parameter.split('::').each do |part|
        if reserved_words.include?(part)
          errors << "#{file} (check '#{check}'): parameter name '#{parameter}' contains reserved word '#{part}'"
        end
      end
    end

    # Check remediation
    #
    # @param file [String] The path to the file being checked
    # @param check [String] The name of the check
    # @param remediation_section [Hash] The remediation section to validate
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

    # Check a value
    #
    # @param _file [String] The path to the file being checked (currently unused)
    # @param _check [String] The name of the check (currently unused)
    # @param _value [Object] The value to be validated (currently unused)
    # @return [Boolean] Always returns true (currently)
    def check_value(_file, _check, _value) # rubocop:disable Naming/PredicateMethod
      # value could be anything
      true
    end

    # Check settings
    #
    # @param file [String] The path to the file being checked
    # @param check [String] The name of the check
    # @param file_data [Hash] The data to validate
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

    # Check CEs in a check
    #
    # @param file [String] The path to the file being checked
    # @param file_data [Array] The data to validate
    def check_check_ces(file, file_data)
      warnings << "#{file}: bad ces '#{file_data}'" unless file_data.is_a?(Array)

      file_data.each do |key|
        warnings << "#{file}: bad ce '#{key}'" unless key.is_a?(String)
      end
    end

    # Check checks
    #
    # @param file [String] The path to the file being checked
    # @param file_data [Hash] The data to validate
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

    # Normalize the given confinement hash by:
    # * Expanding all possible combinations of Array values
    # * Converting dotted fact names into a nested facts hash
    #
    # @param confine [Hash] The confinement hash to normalize
    # @return [Array<Hash>] An array of normalized confinement hashes
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

    # Retrieve confines from the loaded data
    #
    # @return [Array] An array of confinement data
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

    # Validate the Hiera data for each available profiles
    #
    # This method performs validation in two stages:
    # 1. Unconfined: Checks if Hiera data exists for each profile.
    # 2. Confined: Checks if Hiera data exists for each profile with specific facts.
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

    # Lint the given file
    #
    # @param file [String] The path to the file being checked
    # @param file_data [Hash] The data to validate
    def lint(file, file_data)
      unless file_data.is_a?(Hash)
        errors << "#{file}: Expected a Hash, got a #{file_data.class}"
        return
      end

      check_version(file, file_data['version'])

      check_keys(file, file_data)

      check_profiles(file, file_data['profiles']) if file_data['profiles']
      check_ce(file, file_data['ce']) if file_data['ce']
      check_checks(file, file_data['checks']) if file_data['checks']
      check_controls(file, file_data['controls']) if file_data['controls']
    rescue => e
      errors << "#{file}: #{e.message} (not a hash?)"
    end

    # Report checks whose definition is split across files and disagrees
    #
    # A check may legitimately be described by several files -- a checks file
    # supplying the enforcement data and a map file supplying 'ces' is the normal
    # arrangement.  What is never intentional is two files giving the same check
    # different enforcement data, because which one wins is decided by load order.
    #
    # Only 'type', 'settings' and 'confine' are compared.  The additive keys
    # ('ces', 'controls', 'identifiers', 'oval-ids', 'remediation') are how
    # multi-file definitions are meant to work, and comparing them would report
    # every map file in a normal data set.
    def check_duplicate_check_definitions
      data.checks.each do |check, component|
        fragments = component.component[:fragments].select { |_, fragment| fragment.is_a?(Hash) }
        next if fragments.size < 2

        # Files that carry no enforcement data at all are the map files this check
        # is supposed to be spread across, and are not what we are looking for.
        enforcement = fragments.transform_values { |fragment| fragment.slice('type', 'settings', 'confine') }
                               .reject { |_, fragment| fragment.empty? }
        next if enforcement.size < 2

        conflicts = conflicting_leaves(enforcement)

        if conflicts.empty?
          # Same enforcement data in more than one file.  Harmless today, but one
          # copy will eventually be edited and the other will not.
          notes << "Check '#{check}': identical definition in #{enforcement.keys.join(', ')}" if enforcement.values.uniq.size == 1
          next
        end

        conflicts.each do |path, sources|
          description = sources.map { |file, value| "#{value.inspect} in #{file}" }.join(', ')
          errors << "Check '#{check}': conflicting '#{path.join('/')}' (#{description})"
        end
      end
    end

    # Report checks that disagree about the value of the same Puppet class parameter
    #
    # When two checks in the same profile write the same place in the same
    # parameter, the winner is decided by the order the data happens to load in,
    # not by anything in the data.  Checks whose confinement cannot overlap are
    # skipped, since those are deliberate per-platform or per-role variants.
    def check_conflicting_values
      reported = {}

      data.profiles.each do |profile, component|
        settings = parameter_settings(data.check_mapping(component))

        settings.each do |path, contributors|
          contributors.combination(2) do |(check_a, value_a), (check_b, value_b)|
            next if value_a == value_b
            next if unioned?(value_a) || unioned?(value_b)
            next if disjoint_confinement?(check_a, check_b)

            key = [path, [check_a, check_b].sort]
            next if reported.key?(key)

            reported[key] = true
            errors << "Profile '#{profile}': '#{path.join('/')}' is #{value_a.inspect} in check '#{check_a}' " \
                      "and #{value_b.inspect} in check '#{check_b}'"
          end
        end
      end
    end

    # Report checks that declare the same underlying resource twice
    #
    # Some Puppet class parameters are hashes whose keys are only titles: what
    # actually identifies the resource lives in the value.  simp_windows'
    # registry_values is the usual example, where the registry path is 'key' plus
    # 'value' and the hash key is a human-readable label.  Two checks can then
    # give the same registry path two different labels, and the module turns that
    # into two resources with the same derived title, which fails to compile.
    #
    # Nothing in the data says which sub-keys identify a resource, so this only
    # runs for parameters named in :resource_identity, e.g.
    #
    #   { 'simp_windows::registry_values' => ['key', 'value'] }
    #
    # A pair that shares a profile is an error, because it is broken now.  A pair
    # that does not is a warning: it is only latent because the mapping happens to
    # keep them apart, and the next mapping change breaks it.
    def check_duplicate_resources
      return if @resource_identity.nil? || @resource_identity.empty?

      profiles = data.profiles.to_h.transform_values { |profile| data.check_mapping(profile).keys }

      resource_index.each_value do |declarations|
        declarations.combination(2) do |(check_a, key_a, value_a), (check_b, key_b, value_b)|
          next if check_a == check_b
          # The same label and the same content merges cleanly; that is one
          # resource described twice, not two resources.
          next if key_a == key_b && value_a == value_b
          next if disjoint_confinement?(check_a, check_b)

          shared = profiles.select { |_, checks| checks.include?(check_a) && checks.include?(check_b) }.keys
          report_duplicate_resource(check_a, key_a, check_b, key_b, shared)
        end
      end
    end

    private

    # Group the entries of every identity-bearing parameter by the resource they declare
    #
    # @return [Hash{Array => Array}] Resource identity to [check, hash key, value] triples
    def resource_index
      index = {}

      data.checks.each do |check, component|
        next unless component.type == 'puppet-class-parameter'

        settings = component.settings
        next unless settings.is_a?(Hash) && settings['value'].is_a?(Hash)

        identity_keys = @resource_identity[settings['parameter']]
        next if identity_keys.nil?

        settings['value'].each do |key, value|
          next unless value.is_a?(Hash)

          # Resource identities are compared case-insensitively.  Registry paths in
          # particular are written with inconsistent casing and are not case
          # sensitive, so 'HKLM\SOFTWARE' and 'HKLM\Software' are one resource.
          identity = identity_keys.map { |field| value[field].to_s.downcase }
          next if identity.any?(&:empty?)

          (index[[settings['parameter'], identity]] ||= []) << [check, key, value]
        end
      end

      index
    end

    # Record a duplicate resource declaration at the appropriate severity
    #
    # @param check_a [String] The name of a check
    # @param key_a [String] The hash key it declares the resource under
    # @param check_b [String] The name of a check
    # @param key_b [String] The hash key it declares the resource under
    # @param shared [Array<String>] Profiles containing both checks
    # @return [void]
    def report_duplicate_resource(check_a, key_a, check_b, key_b, shared)
      declarations = "'#{key_a}' in check '#{check_a}' and '#{key_b}' in check '#{check_b}'"

      if shared.empty?
        warnings << "Duplicate resource declared by #{declarations}. " \
                    'No profile contains both checks today, so this does not fail yet.'
      else
        errors << "Profile '#{shared.first}': duplicate resource declared by #{declarations}"
      end
    end

    # Collect every leaf of every mapped check's settings, keyed by location
    #
    # @param checks [ComplianceEngine::Checks] The checks to collect from
    # @return [Hash{Array<String> => Array}] Leaf location to [check name, value] pairs
    def parameter_settings(checks)
      result = {}

      checks.each do |check, component|
        next unless component.type == 'puppet-class-parameter'

        settings = component.settings
        next unless settings.is_a?(Hash) && settings['parameter'].is_a?(String)

        leaves(settings['value'], [settings['parameter']]).each do |path, value|
          (result[path] ||= []) << [check, value]
        end
      end

      result
    end

    # Flatten a value into its leaves, keyed by the path taken to reach each one
    #
    # @param value [Object] The value to flatten
    # @param prefix [Array<String>] The path to the value
    # @param result [Hash] The accumulator
    # @return [Hash{Array<String> => Object}] Leaf location to value
    def leaves(value, prefix = [], result = {})
      if value.is_a?(Hash)
        value.each { |key, item| leaves(item, prefix + [key.to_s], result) }
      else
        result[prefix] = value
      end

      result
    end

    # Find leaves that more than one file sets to different values
    #
    # @param fragments [Hash{String => Hash}] File name to fragment
    # @return [Hash{Array<String> => Array}] Leaf location to [file, value] pairs
    def conflicting_leaves(fragments)
      by_path = {}

      fragments.each do |file, fragment|
        leaves(fragment).each { |path, value| (by_path[path] ||= []) << [file, value] }
      end

      by_path.select do |_, sources|
        values = sources.map(&:last)
        values.uniq.size > 1 && values.none? { |value| unioned?(value) }
      end
    end

    # Return true if two of these values would be combined rather than one winning
    #
    # Hashes are merged key by key, and arrays are unioned, so two checks
    # contributing different arrays to the same location both get their way.  That
    # is the documented behaviour rather than a conflict.  Only scalars are
    # decided by load order.
    #
    # @param value [Object] A value from the settings of a check
    # @return [Boolean]
    def unioned?(value)
      value.is_a?(Array)
    end

    # Return true if two checks can be shown never to apply at the same time
    #
    # Two confinements are disjoint when they constrain the same fact to sets of
    # values that do not overlap.  Negated values ('!foo') are not interpreted, so
    # a confinement using them is never treated as disjoint.
    #
    # @param check_a [String] The name of a check
    # @param check_b [String] The name of a check
    # @return [Boolean] true only when the two provably cannot overlap
    def disjoint_confinement?(check_a, check_b)
      confine_a = data.checks[check_a]&.[]('confine')
      confine_b = data.checks[check_b]&.[]('confine')
      return false unless confine_a.is_a?(Hash) && confine_b.is_a?(Hash)

      (confine_a.keys & confine_b.keys).any? do |fact|
        values_a = Array(confine_a[fact]).map(&:to_s)
        values_b = Array(confine_b[fact]).map(&:to_s)
        next false if (values_a + values_b).any? { |value| value.start_with?('!') }

        !values_a.intersect?(values_b)
      end
    end

    # Merge a ComplianceEngine::Collection object into a Hash
    #
    # @param collection [ComplianceEngine::Collection] A collection object
    # @return [Hash] The merged data
    def merge(collection)
      collection.to_h.reduce({}) { |result, value| result.merge!(value[0] => value[1].to_h) }
    end

    # Perform lint checks on merged data
    def merged_data_lint
      check_profiles('merged data', merge(data.profiles))
      check_ce('merged data', merge(data.ces))
      check_checks('merged data', merge(data.checks))
      check_controls('merged data', merge(data.controls))
    end
  end
end
