# `scelint`

Lint SIMP Compliance Engine data.

## Usage

With no arguments, the included `scelint` script will look for SCE data in the standard load path (`SIMP/compliance_profiles`) under the current directory.
Alternatively, any file arguments specified will be loaded directly.  Any directory arguments will be searched under the standard load path.

### Duplicate resource declarations

Some Puppet class parameters are hashes whose keys are only labels, with the
thing that actually identifies the resource living in the value.  `simp_windows`
uses this shape: the registry path is `key` plus `value`, and the hash key is a
human-readable description.

Two checks can then describe the same resource under two different labels, which
becomes two Puppet resources with the same derived title and fails to compile.
Nothing in the SCE data says which sub-keys identify a resource, so `scelint`
only looks for this where it is told to:

```
scelint --resource-identity 'simp_windows::registry_values=key,value' /path/to/module
```

Separate multiple parameters with `;`.  As with any other argument, this can be
kept in a `.scelint` file so it does not have to be repeated:

```
--resource-identity simp_windows::registry_values=key,value
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/silug/rubygem-simp-scelint.

