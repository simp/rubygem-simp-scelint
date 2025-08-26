### 0.4.0 / 2025-08-26
* Updates for recent rubocop and plugins
* Bump minimum required Ruby version to 3.2.0 (oldest version we're testing with)

### 0.3.0 / 2025-01-16
* Use compliance_engine gem for data ingest
* Check that all fact combinations return hiera data
* Add `notes` for info-level log items
* Re-add merged data checks
* Clean up for release

### 0.2.0 / 2024-10-29
* Add --strict option to make warnings fatal
* Warn on legacy facts in confine
* Make check_confine more strict
    - Warn if any confine key is another check key (to catch bad indentation in YAML source)
* Refactor CLI to use thor
* Add quiet/verbose/debug options to the CLI
* Bump minimum required Ruby version to 2.7.0 (oldest version we're testing with)
* Accept 'id' and 'benchmark_version' in profiles
* Fix accidental merge of nested data
* Make missing keys an error only on merged data
* Clarify error messages in `check_settings`
* Update gem email and homepage for move to SIMP org

### 0.1.0 / 2020-11-12
* Initial unreleased version
