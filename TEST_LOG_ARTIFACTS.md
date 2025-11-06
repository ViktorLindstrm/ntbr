# Test Log Artifact Storage for GitHub Copilot

This repository captures complete test output logs and uploads them as GitHub Actions artifacts, making them accessible to GitHub Copilot for analysis.

## Implementation

### What It Does
All test runs in GitHub Actions now capture their complete output to log files using `tee`:

```bash
mix test --formatter ExUnit.CLIFormatter --trace --slowest 10 2>&1 | tee test-output.log
```

This approach:
- **Preserves console output**: Developers still see all test output in the Actions UI
- **Captures everything**: Redirects both stdout and stderr to the log file
- **No dependencies**: Uses standard Unix tools, no additional packages needed

### Artifact Upload
Each workflow uploads the test log as an artifact **only when tests fail**:

```yaml
- name: Upload test logs
  if: failure()
  uses: actions/upload-artifact@v4
  with:
    name: test-logs-<module>-${{ github.run_id }}
    path: <module>/test-output.log
    if-no-files-found: ignore
    retention-days: 30
```

The `if: failure()` ensures logs are only uploaded when tests fail or time out, reducing storage usage.

## Accessing Test Logs

### For Copilot
GitHub Copilot can access test logs through:
1. **GitHub Actions API**: Query artifacts for a specific workflow run
2. **Direct download**: Download artifacts programmatically using the artifact ID

**Note**: Logs are only available when tests fail or time out.

### For Developers
Test logs are available in the GitHub Actions UI when tests fail:
1. Navigate to the failed workflow run
2. Scroll to "Artifacts" section
3. Download `test-logs-<module>-<run_id>`

If tests pass, no log artifacts are uploaded.

## Modules Covered
- `core` - Core module tests
- `domain` - Domain module tests
- `web` - Web module tests
- `firmware` - Firmware module tests
- `infra` - Infrastructure module tests

## Log Retention
Test logs are retained for **30 days** after the workflow run completes.
