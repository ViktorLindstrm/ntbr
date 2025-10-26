# CI Scripts

## detect-domain-tests.sh

Intelligent test selection script for the domain CI workflow.

### Purpose

This script analyzes which files changed in a PR and determines the minimal set of tests that need to run, significantly reducing CI time while maintaining confidence.

### How It Works

The script examines changed files and maps them to test categories:

| Source Files Changed | Tests Run |
|---------------------|-----------|
| `lib/ntbr/domain/resources/*` | Resources tests + Integration tests |
| `lib/ntbr/domain/spinel/*` | Spinel tests + Integration tests |
| `lib/ntbr/domain/thread/*` | Thread tests + Integration tests |
| `lib/ntbr/domain/validations/*` | Validations tests + Integration tests |
| Multiple components OR core files | All tests |
| Test files changed | All tests |

**Integration tests** (always included in PRs):
- `network_lifecycle_properties_test.exs`
- `advanced_security_properties_test.exs`
- `hardware_properties_test.exs`
- `performance_properties_test.exs`
- `regression_properties_test.exs`
- `security_chaos_properties_test.exs`

### Usage

```bash
./detect-domain-tests.sh <base_ref> <head_ref>
```

**Example:**
```bash
./detect-domain-tests.sh origin/main HEAD
```

**Output:**
```
test_pattern=test/ntbr/domain/spinel/ test/ntbr/domain/*_properties_test.exs
test_description=Spinel + integration tests
```

### CI Integration

The script is automatically called by `.github/workflows/domain-ci.yml` during PR builds:

1. **PR Events**: Runs smart test selection
   - Detects changed files
   - Runs only relevant component tests + integration tests
   - Uses 100 test iterations for faster feedback

2. **Merge Events**: Runs all tests
   - Full test suite execution
   - Uses 500 test iterations for thorough validation

### Examples

**Scenario 1: Working on network resource**
```bash
# Changed: domain/lib/ntbr/domain/resources/network.ex
# Runs: test/ntbr/domain/resources/ + integration tests
# Time: ~5 minutes (vs 15 minutes for all tests)
```

**Scenario 2: Working on spinel frame parsing**
```bash
# Changed: domain/lib/ntbr/domain/spinel/frame.ex
# Runs: test/ntbr/domain/spinel/ + integration tests
# Time: ~4 minutes
```

**Scenario 3: Updating mix.exs or multiple components**
```bash
# Changed: domain/mix.exs OR multiple lib directories
# Runs: All tests
# Time: ~15 minutes
```

### Benefits

- **Faster feedback**: 5-10 minutes instead of 15+ minutes for focused changes
- **Resource efficient**: Reduces CI costs by running only necessary tests
- **Safe**: Always includes integration tests to catch cross-component issues
- **Comprehensive on merge**: Full test suite runs when merging to main
