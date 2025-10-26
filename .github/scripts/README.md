# CI Scripts

## detect-domain-tests.sh

Intelligent test selection script for the domain CI workflow using **ExUnit tag-based filtering**.

### Purpose

This script analyzes which files changed in a PR and determines the minimal set of tests that need to run using ExUnit tags, significantly reducing CI time while maintaining confidence.

### Tag-Based Test Selection

The script uses ExUnit's built-in tagging system for precise test selection:

**Component Tags:**
- `:resources` - All resource-related tests
- `:spinel` - Spinel protocol tests
- `:thread` - Thread protocol tests
- `:validations` - Validation helper tests

**Specific Resource Tags:**
- `:network` - Network resource tests
- `:device` - Device resource tests
- `:border_router` - BorderRouter resource tests
- `:joiner` - Joiner resource tests

**Test Type Tags:**
- `:property` - Property-based tests (using PropCheck)
- `:unit` - Unit tests
- `:integration` - Integration/cross-cutting tests

**Scenario Tags:**
- `:lifecycle` - Network lifecycle tests
- `:hardware` - Hardware/RCP behavior tests
- `:security` - Security-related tests
- `:performance` - Performance tests
- `:regression` - Regression tests

### How It Works

The script examines changed files and maps them to ExUnit tag filters:

| Source Files Changed | Test Tags | Example Command |
|---------------------|-----------|-----------------|
| `lib/ntbr/domain/resources/network.ex` | `--only network --only integration` | Runs network + integration tests |
| `lib/ntbr/domain/resources/*` (multiple) | `--only resources --only integration` | Runs all resources + integration |
| `lib/ntbr/domain/spinel/*` | `--only spinel --only integration` | Runs spinel + integration tests |
| `lib/ntbr/domain/thread/*` | `--only thread --only integration` | Runs thread + integration tests |
| `lib/ntbr/domain/validations/*` | `--only validations` | Runs validation tests only |
| Multiple components OR core files | *(no tags)* | Runs all tests |
| Test files changed | *(no tags)* | Runs all tests |

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
test_pattern=--only network --only integration
test_description=Network resource + integration tests
```

### CI Integration

The script is automatically called by `.github/workflows/domain-ci.yml` during PR builds:

1. **PR Events**: Runs smart test selection
   - Detects changed files
   - Runs only relevant component tests + integration tests using tags
   - Uses 100 test iterations for faster feedback
   - Example: `mix test test/ntbr/domain/ --only spinel --only integration`

2. **Merge Events**: Runs all tests
   - Full test suite execution
   - Uses 500 test iterations for thorough validation
   - Example: `mix test test/ntbr/domain/`

### Examples

**Scenario 1: Working on network resource**
```bash
# Changed: domain/lib/ntbr/domain/resources/network.ex
# Command: mix test test/ntbr/domain/ --only network --only integration
# Runs: Network resource tests + all integration tests
# Time: ~5 minutes (vs 15 minutes for all tests)
```

**Scenario 2: Working on spinel frame parsing**
```bash
# Changed: domain/lib/ntbr/domain/spinel/frame.ex
# Command: mix test test/ntbr/domain/ --only spinel --only integration
# Runs: All spinel tests + integration tests
# Time: ~4 minutes
```

**Scenario 3: Updating mix.exs or multiple components**
```bash
# Changed: domain/mix.exs OR multiple lib directories
# Command: mix test test/ntbr/domain/
# Runs: All tests (no tag filtering)
# Time: ~15 minutes
```

### Adding Tags to New Tests

When adding new tests, tag them appropriately using `@moduletag`:

```elixir
defmodule NTBR.Domain.Spinel.NewFeatureTest do
  @moduledoc false
  use ExUnit.Case, async: true
  use PropCheck

  alias NTBR.Domain.Spinel.NewFeature

  # Required tags
  @moduletag :property      # Mark as property-based test
  @moduletag :spinel        # Component tag
  @moduletag :unit          # Unit test (vs integration)

  property "new feature works correctly" do
    forall input <- input_gen() do
      # test implementation
    end
  end
end
```

**For integration tests:**
```elixir
defmodule NTBR.Domain.Test.NewIntegrationTest do
  @moduledoc false
  use ExUnit.Case, async: false
  use PropCheck

  @moduletag :property
  @moduletag :integration    # Mark as integration test
  @moduletag :lifecycle      # Optional: specific scenario tag

  # test implementation
end
```

### Benefits

- **Faster feedback**: 5-10 minutes instead of 15+ minutes for focused changes
- **Resource efficient**: Reduces CI costs by running only necessary tests
- **Precise selection**: ExUnit tags allow granular control over which tests run
- **Safe**: Always includes integration tests to catch cross-component issues
- **Comprehensive on merge**: Full test suite runs when merging to main
- **Maintainable**: Tags are defined in test files, making the relationship explicit
