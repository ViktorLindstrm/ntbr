# Property Test Failures Investigation - Workflow Domain

**Date**: 2025-11-02  
**CI Run**: #64 (19012291451)  
**Total Tests**: 223 properties, 146 unit tests  
**Failures**: 66 failures

## Executive Summary

Property-based testing in the Workflow (Domain) component has revealed systematic issues across multiple test categories. The failures fall into several distinct patterns that indicate both test implementation issues and potential domain logic problems.

## Failure Categories

### 1. Data Validation Errors (HIGH PRIORITY)

#### 1.1 Invalid Attribute Errors
**Tests Affected**: 
- `eclipse attack: isolated devices detect partitioning` 
- `error messages don't leak existence of resources`

**Error Pattern**:
```elixir
** (MatchError) no match of right hand side value: {:error, %Ash.Error.Invalid{
  errors: [%Ash.Error.Changes.InvalidAttribute{
    field: :parent_id, 
    message: "is invalid", 
    value: <<0, 0, 0, 0, 0, 0, 0, 10>>
  }]
}}
```

**Root Cause**: Property test generators are creating invalid data that doesn't match domain constraints:
- `parent_id` field receives binary data when UUID expected
- `name` field exceeds max length constraint (16 characters)

**Impact**: Tests fail before exercising actual property logic

**Recommended Fix**:
- Update generators to respect Ash resource constraints
- Add proper type generators for UUID fields
- Enforce string length constraints in generators

---

#### 1.2 State Inconsistency Errors  
**Test Affected**: `conflicting state reports from multiple sources are resolved`

**Error Pattern**:
```elixir
** (Protocol.UndefinedError) protocol Enumerable not implemented for type BitString
Got value: "469dd773-160d-4d87-9faf-c0e22b877dad"
```

**Root Cause**: Test passes UUID string to function expecting enumerable collection

**Impact**: Test design flaw - incorrect function usage

**Recommended Fix**:
- Review test implementation at `advanced_security_properties_test.exs:500`
- Correct parameter passing to `Network.read!/2`

---

### 2. API Misuse Errors (MEDIUM PRIORITY)

#### 2.1 Measurement API Incompatibility
**Test Affected**: `amplification attacks: responses are not larger than requests`

**Error Pattern**:
```elixir
** (FunctionClauseError) no function clause matching in :proper.measure/3
```

**Root Cause**: PropCheck's `measure/3` expects different argument structure than provided. The test uses:
```elixir
|> measure("Request size", fn size -> size end)
```

But PropCheck expects measurement to wrap the property, not chain after `forall`.

**Impact**: Test never executes

**Recommended Fix**:
- Restructure measurement calls to match PropCheck API
- Reference PropCheck documentation for correct measurement syntax

---

### 3. Test Framework Issues (MEDIUM PRIORITY)

#### 3.1 Counter-Example Reporting Bug
**Test Affected**: `error messages don't leak existence of resources`

**Error Pattern**:
```elixir
** (FunctionClauseError) no function clause matching in 
PropCheck.StateM.Reporter.pretty_print_counter_example_parallel/1

Attempted function clauses:
  def pretty_print_counter_example_parallel(-{seq, [par1, par2]}-)
  
Got: {<<binary>>, <<binary>>}
```

**Root Cause**: PropCheck expects parallel state machine counter-examples in specific format, but test provides tuple of binaries

**Impact**: Prevents proper error reporting, obscures actual failure

**Recommended Fix**:
- Either restructure test data to match expected format
- Or file issue with PropCheck if this is a bug

---

### 4. Property Logic Failures (HIGH PRIORITY - DOMAIN CORRECTNESS)

#### 4.1 Resource Exhaustion Property
**Test Affected**: `resource exhaustion via malformed requests is prevented`

**Failure**: Property found counter-example after 100 tests

**Details**: Test generates list of 100+ binary payloads representing malformed requests. After shrinking, found minimal failing case with ~100 binary strings.

**Implications**: 
- Either the property is too strict
- Or there's a genuine resource exhaustion vulnerability
- Needs investigation to determine if this is expected behavior

**Recommended Action**:
- Review implementation of resource limits
- Determine if failing case represents actual vulnerability
- May need to refine property to exclude benign cases

---

## Test Infrastructure Analysis

### Generators Issue
Many failures stem from generators not respecting Ash resource constraints:

1. **Binary vs String**: Some fields expect strings but receive binaries
2. **UUID Format**: Fields typed as UUID receive random binaries instead of valid UUIDs
3. **Length Constraints**: String generators don't respect `max_length` attributes
4. **Type Mismatches**: parent_id expects UUID but gets 8-byte binary

### Recommendations for Generator Improvements:

```elixir
# Example: Proper UUID generator
def uuid_gen do
  let bytes <- binary(16) do
    UUID.binary_to_string!(bytes)
  end
end

# Example: Constrained string generator  
def network_name_gen do
  let length <- integer(1, 16) do
    let chars <- vector(length, char(?a..?z)) do
      to_string(chars)
    end
  end
end
```

---

## Time-Intensive Tests

Several properties take excessive time:

1. **`constant-time comparison prevents timing attacks`**: 175.3 seconds (35.7% of total)
2. **`byzantine routers providing false topology`**: 65.6 seconds (13.4% of total)  
3. **`eclipse attack: isolated devices detect partitioning`**: 24.1 seconds (4.9% of total)

**Analysis**: These timing-based tests need careful analysis:
- Constant-time test duration expected for timing attack validation
- Byzantine router test may be creating too many network simulations
- Eclipse attack test creates 13 fake devices per iteration

**Recommendations**:
- Consider reducing test case counts for expensive properties in PR runs
- Use `PROPCHECK_NUMTESTS` environment variable strategically
- May need to optimize test setup/teardown

---

## Specific Test Files Needing Attention

### `advanced_security_properties_test.exs`
- Lines 163, 258, 471, 646, 697: Multiple fundamental issues
- Needs comprehensive review of generator usage
- API usage inconsistencies with PropCheck

### `network_lifecycle_properties_test.exs`  
- Review needed but no failures in latest run
- Appears to be working correctly

---

## Priority Recommendations

### Immediate (P0):
1. Fix generator type mismatches (UUID, string length)
2. Correct API usage for `measure/3` 
3. Fix state enumeration error in conflict resolution test

### Short-term (P1):
4. Investigate resource exhaustion counter-example validity
5. Optimize time-intensive security tests
6. Review and fix counter-example reporting issues

### Medium-term (P2):
7. Create generator library with proper Ash constraint support
8. Add generator tests to validate constraint compliance
9. Document property test patterns and best practices
10. Leverage Elixir 1.18 type system with @spec and typed generators

---

## Implementation Strategy

### Phase 1: Core Generator Library (Ash + Type-Safe)

Create a typed generator module that respects Ash resource constraints and uses Elixir 1.18 type specifications:

```elixir
defmodule NTBR.Domain.Test.Generators do
  @moduledoc """
  Type-safe PropCheck generators for Ash resources.
  Respects all Ash constraints and uses Elixir 1.18 type system.
  """
  use PropCheck
  
  @type uuid :: String.t()
  @type network_name :: String.t()
  
  @spec uuid_gen() :: PropCheck.type()
  def uuid_gen do
    let bytes <- binary(16) do
      UUID.binary_to_string!(bytes)
    end
  end
  
  @spec network_name_gen() :: PropCheck.type()
  def network_name_gen do
    # Respects Network.name constraint: min_length: 1, max_length: 16
    let length <- integer(1, 16) do
      let chars <- vector(length, char(?a..?z)) do
        to_string(chars)
      end
    end
  end
  
  @spec device_attrs_gen(uuid()) :: PropCheck.type()
  def device_attrs_gen(network_id) do
    let {rloc16, extended_addr, device_type} <- 
      {integer(0, 0xFFFF), binary(8), oneof([:end_device, :router, :leader, :reed])} do
      %{
        network_id: network_id,
        rloc16: rloc16,
        extended_address: extended_addr,
        device_type: device_type
      }
    end
  end
end
```

### Phase 2: Fix Specific Test Issues

1. **`resource_enumeration_gen` fix** (line 748):
   ```elixir
   defp resource_enumeration_gen do
     # Generate valid UUIDs, not raw bytes
     {uuid_gen(), uuid_gen()}
   end
   ```

2. **`measure/3` API fix** (line 664):
   ```elixir
   # WRONG:
   forall size <- integer(1, 1000) do
     # ...
   end |> measure("Request size", fn size -> size end)
   
   # CORRECT:
   measure("Request size", 
     forall size <- integer(1, 1000) do
       # ...
     end,
     fn size -> size end
   )
   ```

3. **Network.read!/2 fix** (line 500):
   ```elixir
   # WRONG: Passing UUID string as filter opts
   Network.read!(network_id)
   
   # CORRECT: Use proper Ash API
   Network.by_id!(network_id)
   # OR
   Network.read!([id: network_id])
   ```

### Phase 3: Leverage Elixir 1.18 Types

Add type specifications to all property test helper functions:

```elixir
@spec create_test_network(String.t()) :: {:ok, Network.t()} | {:error, term()}
defp create_test_network(name_suffix) do
  Network.create(%{
    name: "Test-#{name_suffix}",
    network_name: "TestNet-#{name_suffix}"
  })
end

@spec create_test_device(uuid(), map()) :: {:ok, Device.t()} | {:error, term()}
defp create_test_device(network_id, attrs \\ %{}) do
  default_attrs = %{
    network_id: network_id,
    rloc16: :rand.uniform(0xFFFF),
    extended_address: :crypto.strong_rand_bytes(8)
  }
  
  Device.create(Map.merge(default_attrs, attrs))
end
```

---

## Success Metrics

- [ ] All 66 failing tests pass
- [ ] No test takes longer than 30 seconds (except timing-attack tests)
- [ ] Generators respect all Ash resource constraints
- [ ] All generator functions have @spec type annotations
- [ ] CI run completes in under 15 minutes for PRs
- [ ] Type system catches generator/constraint mismatches at compile time

---

## References

- CI Run: https://github.com/ViktorLindstrm/ntbr/actions/runs/19012291451
- Test Files: `/home/runner/work/ntbr/ntbr/domain/test/ntbr/domain/`
- PropCheck Docs: https://hexdocs.pm/propcheck/
- Elixir 1.18 Types: https://hexdocs.pm/elixir/1.18.0/typespecs.html
- Ash Framework: https://hexdocs.pm/ash/
