#!/bin/bash
set -euo pipefail

# This script detects which domain tests should run based on changed files
# Uses ExUnit tags to intelligently select relevant tests
# Usage: ./detect-domain-tests.sh <base_ref> <head_ref>

BASE_REF="${1:-origin/main}"
HEAD_REF="${2:-HEAD}"

echo "Detecting changed files between $BASE_REF and $HEAD_REF..."

# Get list of changed files in the domain directory
CHANGED_FILES=$(git diff --name-only "$BASE_REF...$HEAD_REF" -- domain/ || echo "")

if [ -z "$CHANGED_FILES" ]; then
  echo "No domain files changed"
  echo "test_pattern="
  echo "test_description=All domain tests (no changes detected)"
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

# Track specific resources changed
network_changed=false
device_changed=false
border_router_changed=false
joiner_changed=false

# Analyze changed files
while IFS= read -r file; do
  case "$file" in
    # Specific resource files
    domain/lib/ntbr/domain/resources/network.ex)
      resources_changed=true
      network_changed=true
      ;;
    domain/lib/ntbr/domain/resources/device.ex)
      resources_changed=true
      device_changed=true
      ;;
    domain/lib/ntbr/domain/resources/border_router.ex)
      resources_changed=true
      border_router_changed=true
      ;;
    domain/lib/ntbr/domain/resources/joiner.ex)
      resources_changed=true
      joiner_changed=true
      ;;
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
      # Test files changed - run all tests to be safe
      core_changed=true
      ;;
  esac
done <<< "$CHANGED_FILES"

# Count how many components changed
components_count=0
[ "$resources_changed" = true ] && components_count=$((components_count + 1))
[ "$spinel_changed" = true ] && components_count=$((components_count + 1))
[ "$thread_changed" = true ] && components_count=$((components_count + 1))
[ "$validations_changed" = true ] && components_count=$((components_count + 1))

echo "Components changed:"
echo "  Resources: $resources_changed"
echo "    - Network: $network_changed"
echo "    - Device: $device_changed"
echo "    - BorderRouter: $border_router_changed"
echo "    - Joiner: $joiner_changed"
echo "  Spinel: $spinel_changed"
echo "  Thread: $thread_changed"
echo "  Validations: $validations_changed"
echo "  Core files: $core_changed"
echo "  Component count: $components_count"
echo ""

# Determine test pattern using ExUnit tags
if [ "$core_changed" = true ] || [ $components_count -gt 1 ]; then
  # Run all tests if core files changed or multiple components changed
  echo "Running ALL tests (core files or multiple components changed)"
  echo "test_pattern="
  echo "test_description=All domain tests (multiple components or core files changed)"
elif [ $components_count -eq 1 ]; then
  # Run specific component tests using tags
  if [ "$resources_changed" = true ]; then
    # Check if only one specific resource changed
    specific_resource_count=0
    [ "$network_changed" = true ] && specific_resource_count=$((specific_resource_count + 1))
    [ "$device_changed" = true ] && specific_resource_count=$((specific_resource_count + 1))
    [ "$border_router_changed" = true ] && specific_resource_count=$((specific_resource_count + 1))
    [ "$joiner_changed" = true ] && specific_resource_count=$((specific_resource_count + 1))

    if [ $specific_resource_count -eq 1 ]; then
      # Run tests for specific resource + integration tests
      if [ "$network_changed" = true ]; then
        echo "Running NETWORK tests + integration tests"
        echo "test_pattern=--only network --only integration"
        echo "test_description=Network resource + integration tests"
      elif [ "$device_changed" = true ]; then
        echo "Running DEVICE tests + integration tests"
        echo "test_pattern=--only device --only integration"
        echo "test_description=Device resource + integration tests"
      elif [ "$border_router_changed" = true ]; then
        echo "Running BORDER_ROUTER tests + integration tests"
        echo "test_pattern=--only border_router --only integration"
        echo "test_description=BorderRouter resource + integration tests"
      elif [ "$joiner_changed" = true ]; then
        echo "Running JOINER tests + integration tests"
        echo "test_pattern=--only joiner --only integration"
        echo "test_description=Joiner resource + integration tests"
      fi
    else
      # Multiple resources changed - run all resource tests + integration
      echo "Running ALL RESOURCES tests + integration tests"
      echo "test_pattern=--only resources --only integration"
      echo "test_description=All resource tests + integration tests"
    fi
  elif [ "$spinel_changed" = true ]; then
    echo "Running SPINEL tests + integration tests"
    echo "test_pattern=--only spinel --only integration"
    echo "test_description=Spinel protocol tests + integration tests"
  elif [ "$thread_changed" = true ]; then
    echo "Running THREAD tests + integration tests"
    echo "test_pattern=--only thread --only integration"
    echo "test_description=Thread protocol tests + integration tests"
  elif [ "$validations_changed" = true ]; then
    echo "Running VALIDATIONS tests only (no integration needed)"
    echo "test_pattern=--only validations"
    echo "test_description=Validation helper tests"
  fi
else
  # No relevant changes detected, run all tests to be safe
  echo "Running ALL tests (no specific component changes detected)"
  echo "test_pattern="
  echo "test_description=All domain tests"
fi
