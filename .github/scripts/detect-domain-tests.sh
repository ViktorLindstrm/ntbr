#!/bin/bash
set -euo pipefail

# This script detects which domain tests should run based on changed files
# Usage: ./detect-domain-tests.sh <base_ref> <head_ref>

BASE_REF="${1:-origin/main}"
HEAD_REF="${2:-HEAD}"

echo "Detecting changed files between $BASE_REF and $HEAD_REF..."

# Get list of changed files in the domain directory
CHANGED_FILES=$(git diff --name-only "$BASE_REF...$HEAD_REF" -- domain/ || echo "")

if [ -z "$CHANGED_FILES" ]; then
  echo "No domain files changed"
  echo "test_pattern=test/ntbr/domain/"
  exit 0
fi

echo "Changed files:"
echo "$CHANGED_FILES"
echo ""

# Initialize component flags
resources_changed=false
spinel_changed=false
thread_changed=false
validations_changed=false
core_changed=false

# Analyze changed files
while IFS= read -r file; do
  case "$file" in
    domain/lib/ntbr/domain/resources/*)
      resources_changed=true
      ;;
    domain/lib/ntbr/domain/spinel/*)
      spinel_changed=true
      ;;
    domain/lib/ntbr/domain/thread/*)
      thread_changed=true
      ;;
    domain/lib/ntbr/domain/validations/*)
      validations_changed=true
      ;;
    domain/mix.exs|domain/config/*|domain/lib/ntbr/domain/application.ex)
      core_changed=true
      ;;
    domain/test/*)
      # Test files changed - we'll need to run all tests to be safe
      core_changed=true
      ;;
  esac
done <<< "$CHANGED_FILES"

# Count how many components changed
components_count=0
[ "$resources_changed" = true ] && ((components_count++))
[ "$spinel_changed" = true ] && ((components_count++))
[ "$thread_changed" = true ] && ((components_count++))
[ "$validations_changed" = true ] && ((components_count++))

echo "Components changed:"
echo "  Resources: $resources_changed"
echo "  Spinel: $spinel_changed"
echo "  Thread: $thread_changed"
echo "  Validations: $validations_changed"
echo "  Core files: $core_changed"
echo "  Component count: $components_count"
echo ""

# Determine test pattern
if [ "$core_changed" = true ] || [ $components_count -gt 1 ]; then
  # Run all tests if core files changed or multiple components changed
  echo "Running ALL tests (core files or multiple components changed)"
  echo "test_pattern=test/ntbr/domain/"
  echo "test_description=All domain tests (multiple components or core files changed)"
elif [ $components_count -eq 1 ]; then
  # Run specific component tests + integration tests
  if [ "$resources_changed" = true ]; then
    echo "Running RESOURCES tests only"
    echo "test_pattern=test/ntbr/domain/resources/ test/ntbr/domain/*_properties_test.exs"
    echo "test_description=Resources + integration tests"
  elif [ "$spinel_changed" = true ]; then
    echo "Running SPINEL tests only"
    echo "test_pattern=test/ntbr/domain/spinel/ test/ntbr/domain/*_properties_test.exs"
    echo "test_description=Spinel + integration tests"
  elif [ "$thread_changed" = true ]; then
    echo "Running THREAD tests only"
    echo "test_pattern=test/ntbr/domain/thread/ test/ntbr/domain/*_properties_test.exs"
    echo "test_description=Thread + integration tests"
  elif [ "$validations_changed" = true ]; then
    echo "Running VALIDATIONS tests only"
    echo "test_pattern=test/ntbr/domain/validations/ test/ntbr/domain/*_properties_test.exs"
    echo "test_description=Validations + integration tests"
  fi
else
  # No relevant changes detected, run all tests to be safe
  echo "Running ALL tests (no specific component changes detected)"
  echo "test_pattern=test/ntbr/domain/"
  echo "test_description=All domain tests"
fi
