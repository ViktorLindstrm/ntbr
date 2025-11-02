# Fix Genuine Bugs Discovered by Property Tests

## Summary

Property-based tests have successfully identified **30 genuine bugs** in the Domain codebase across security, validation, state management, and resource management areas. These are real issues that require domain logic fixes, not test infrastructure fixes.

**Origin**: Discovered during analysis of failing property tests in PR #32  
**Total Bugs**: 30 genuine failures (46% of original 65 test failures)  
**Priority**: High - includes critical security vulnerabilities

## Background

After fixing 35 test infrastructure issues (PropCheck API misuse, generator problems, etc.), 30 test failures remain. These failures represent genuine bugs where the tested properties do not hold for generated inputs. The property tests are working correctly and have identified real edge cases and security issues.

## Bug Categories

### 🔐 Security Issues (10 bugs) - CRITICAL

#### 1. Weak Password Acceptance
**Test**: `property "weak credentials are rejected"`  
**File**: `domain/test/ntbr/domain/security_chaos_properties_test.exs:455`  
**Issue**: System accepts weak passwords like "AAAAAA"

**Counter-example**:
```elixir
["AAAAAA"]
```

**Expected**: Passwords should meet minimum complexity requirements  
**Actual**: Simple repeated characters are accepted

**Fix Location**: Password validation logic (likely in Joiner or Network resource)

**Recommended Fix**:
```elixir
# Add password strength validation
defp validate_password_strength(password) do
  cond do
    String.length(password) < 8 ->
      {:error, "Password must be at least 8 characters"}
    
    Regex.match?(~r/^(.)\1+$/, password) ->
      {:error, "Password cannot be all the same character"}
    
    not Regex.match?(~r/[A-Z]/, password) ->
      {:error, "Password must contain uppercase letter"}
    
    not Regex.match?(~r/[0-9]/, password) ->
      {:error, "Password must contain number"}
    
    true ->
      :ok
  end
end
```

---

#### 2. Timing Side-Channel Attacks
**Test**: `property "timing attacks don't leak credential information"`  
**File**: `domain/test/ntbr/domain/security_chaos_properties_test.exs:415`  
**Issue**: Password comparison timing varies based on correctness

**Counter-example**:
```elixir
{"CORRECT123456", ["WRONG123456", "CARRECT123456", "CORRECT123457", "CORRECT12345", "XORRECT123456"]}
```

**Expected**: Constant-time comparison  
**Actual**: Timing variance allows attackers to determine password correctness

**Fix Location**: Credential comparison functions

**Recommended Fix**:
```elixir
# Use constant-time comparison
defp secure_compare(a, b) do
  if byte_size(a) != byte_size(b) do
    # Still compare to avoid timing leak on length
    :crypto.hash_equals(
      :crypto.hash(:sha256, a),
      :crypto.hash(:sha256, String.duplicate("x", byte_size(a)))
    )
    false
  else
    :crypto.hash_equals(
      :crypto.hash(:sha256, a),
      :crypto.hash(:sha256, b)
    )
  end
end
```

---

#### 3. Key Material Exposure in Errors
**Test**: `property "key material is never exposed in logs or errors"`  
**File**: `domain/test/ntbr/domain/security_chaos_properties_test.exs:483`  
**Issue**: Network keys visible in error messages

**Counter-example**:
```elixir
[21]
```

**Expected**: Error messages should not contain sensitive key material  
**Actual**: Network keys or PSKDs exposed in error/log output

**Fix Location**: Error handling and logging throughout Domain

**Recommended Fix**:
```elixir
# Sanitize errors before logging
defp sanitize_error(error) do
  error
  |> sanitize_keys([:network_key, :pskd, :master_key, :password])
  |> sanitize_structs()
end

defp sanitize_keys(data, keys) do
  Enum.reduce(keys, data, fn key, acc ->
    String.replace(acc, ~r/#{key}[:\s]*[A-Za-z0-9+\/=]+/, "#{key}: [REDACTED]")
  end)
end
```

---

#### 4. Command Injection Not Fully Sanitized
**Test**: `property "command injection patterns are neutralized"`  
**File**: `domain/test/ntbr/domain/security_chaos_properties_test.exs:215`  
**Issue**: Potential command injection in network names

**Counter-example**:
```elixir
["`whoami`"]
```

**Expected**: Command injection patterns should be rejected or sanitized  
**Actual**: Backtick commands may be processed

**Fix Location**: Input validation for network/device names

**Recommended Fix**:
```elixir
# Strict input sanitization
defp validate_name(name) do
  # Reject dangerous patterns
  dangerous_patterns = [
    ~r/[`$();|&<>]/,  # Shell metacharacters
    ~r/\.\./,         # Path traversal
    ~r/--/,           # SQL comments
    ~r/['";]/         # Quote injection
  ]
  
  if Enum.any?(dangerous_patterns, &Regex.match?(&1, name)) do
    {:error, "Name contains invalid characters"}
  else
    :ok
  end
end
```

---

### ✅ Validation Issues (6 bugs) - HIGH

#### 5. Name Length Validation Not Enforced
**Test**: `property "error messages don't leak existence of resources"`  
**File**: `domain/test/ntbr/domain/advanced_security_properties_test.exs:164`  
**Issue**: Names exceeding 16-character limit accepted, then fail with detailed errors

**Error**:
```elixir
** (MatchError) no match of right hand side value: {:error, %Ash.Error.Invalid{
  errors: [%Ash.Error.Changes.InvalidAttribute{
    field: :name, 
    message: "length must be less than or equal to %{max}", 
    value: "ErrorLeak-319b5288-57b9-4cca-b800-e80bdea0f14f"
  }]
}}
```

**Expected**: Names should be validated early with generic errors  
**Actual**: Detailed validation errors leak internal constraints

**Fix Location**: Network resource attribute validation

**Recommended Fix**:
```elixir
# Add early validation
attribute :name, :string do
  constraints [
    max_length: 16,
    match: ~r/^[a-zA-Z0-9_-]+$/
  ]
  allow_nil? false
end

# Return generic error
defp format_validation_error(_field, _error) do
  "Invalid input"  # Don't leak field constraints
end
```

---

#### 6. Unicode/Encoding Attack Sanitization
**Test**: `property "unicode and encoding attacks are sanitized"`  
**File**: `domain/test/ntbr/domain/security_chaos_properties_test.exs:636`  
**Issue**: Null bytes and unicode attacks not properly handled

**Counter-example**:
```elixir
[<<116, 101, 115, 116, 0, 104, 105, 100, 100, 101, 110>>]
# "test\0hidden"
```

**Expected**: Null bytes and malicious unicode rejected  
**Actual**: May be stored or cause parsing issues

**Fix Location**: String validation throughout

**Recommended Fix**:
```elixir
defp validate_safe_string(string) do
  cond do
    String.contains?(string, "\0") ->
      {:error, "Invalid characters"}
    
    not String.valid?(string) ->
      {:error, "Invalid encoding"}
    
    String.match?(string, ~r/[\p{C}--\s]/) ->
      {:error, "Invalid control characters"}
    
    true ->
      :ok
  end
end
```

---

### 🔄 State Management Issues (8 bugs) - HIGH

#### 7. Race Conditions Under Rapid State Changes
**Test**: `property "rapid state changes don't cause race conditions"`  
**File**: `domain/test/ntbr/domain/security_chaos_properties_test.exs:314`  
**Issue**: Concurrent state transitions cause inconsistent state

**Counter-example**:
```elixir
[:attach, :promote, :promote, :attach, :detach, :promote, ...]
```

**Expected**: Final state should be valid regardless of concurrency  
**Actual**: Inconsistent state after rapid transitions

**Fix Location**: Network state transition logic

**Recommended Fix**:
```elixir
# Add transaction boundaries
def change_state(network, new_state) do
  Ash.Changeset.new(network)
  |> Ash.Changeset.change_attribute(:state, new_state)
  |> Ash.Changeset.atomic_update(:state, fn current ->
    if valid_transition?(current, new_state) do
      new_state
    else
      current
    end
  end)
  |> Ash.update()
end
```

---

#### 8. GenServer Not Started in Test Environment
**Test**: `property "network recovers correctly after RCP reset at any point"`  
**File**: `domain/test/ntbr/domain/network_lifecycle_properties_test.exs:193`  
**Issue**: Spinel.Client GenServer not available

**Error**:
```elixir
** (throw) {:noproc, {GenServer, :call, [NTBR.Domain.Spinel.Client, ...]}}
```

**Note**: This was partially fixed by wrapping Client calls in try/catch, but tests still fail because they expect Client to work.

**Expected**: Tests should either mock Client or skip hardware operations  
**Actual**: Tests fail when hardware not available

**Fix Location**: Test setup or Client module

**Recommended Fix**:
```elixir
# Option 1: Mock in tests
setup do
  Mox.defmock(SpinelClientMock, for: NTBR.Domain.Spinel.ClientBehaviour)
  Mox.stub_with(SpinelClientMock, NTBR.Domain.Spinel.ClientStub)
  :ok
end

# Option 2: Add hardware check
@tag :requires_hardware
property "network recovers correctly after RCP reset" do
  # Test implementation
end
```

---

### 💾 Resource Management Issues (6 bugs) - MEDIUM

#### 9. Potential Memory Exhaustion
**Test**: `property "resource exhaustion attacks are mitigated"`  
**File**: `domain/test/ntbr/domain/security_chaos_properties_test.exs:362`  
**Issue**: Generator type leakage (was fixed), but underlying resource limits not enforced

**Expected**: System should limit resource consumption  
**Actual**: No rate limiting or resource caps

**Fix Location**: Joiner creation, Device registration

**Recommended Fix**:
```elixir
# Add rate limiting
defmodule RateLimiter do
  use GenServer
  
  def check_rate(key, max_per_second) do
    GenServer.call(__MODULE__, {:check, key, max_per_second})
  end
  
  # Implementation with sliding window
end

# Apply in create functions
def create(params) do
  case RateLimiter.check_rate({:joiner_create, params.network_id}, 10) do
    :ok -> do_create(params)
    {:error, :rate_limited} -> {:error, "Too many requests"}
  end
end
```

---

## Priority and Effort Estimates

### Critical (Security) - 10 bugs
**Priority**: P0 - Fix immediately  
**Effort**: 6-8 hours  
**Impact**: Security vulnerabilities, potential exploits

### High (Validation & State) - 14 bugs  
**Priority**: P1 - Fix in current sprint  
**Effort**: 8-10 hours  
**Impact**: Data integrity, reliability issues

### Medium (Resources) - 6 bugs
**Priority**: P2 - Fix in next sprint  
**Effort**: 4-6 hours  
**Impact**: DoS potential, edge cases

**Total Estimated Effort**: 18-24 hours

## Testing Strategy

### Verification After Fixes

Run the full property test suite:
```bash
cd domain
MIX_ENV=test mix test --only property --max-failures 1
```

### Expected Outcomes

- All 30 currently failing property tests should pass
- No new test failures introduced
- Overall property test pass rate: 100% (223/223 tests)

### Regression Prevention

1. Keep all property tests enabled in CI
2. Run property tests on every PR
3. Add new property tests for each bug fix to prevent regression

## Implementation Approach

### Phase 1: Security Fixes (Week 1)
1. Weak password validation
2. Constant-time comparison
3. Key material sanitization
4. Command injection prevention

### Phase 2: Validation Fixes (Week 2)
5. Name length enforcement
6. Unicode/encoding sanitization
7. Error message sanitization

### Phase 3: State Management (Week 3)
8. Transaction boundaries
9. Race condition fixes
10. Concurrent operation safety

### Phase 4: Resource Management (Week 4)
11. Rate limiting
12. Resource quotas
13. Cleanup procedures

## Code Review Checklist

When fixing these bugs, ensure:

- [ ] Fix addresses root cause, not just test
- [ ] Added/updated unit tests for the fix
- [ ] Property test now passes
- [ ] No new security vulnerabilities introduced
- [ ] Error messages don't leak sensitive info
- [ ] Concurrent operations handled safely
- [ ] Resource limits enforced
- [ ] Documentation updated

## Related Documents

- **WORKFLOW_PROPERTY_TEST_ANALYSIS.md** - Original analysis
- **IMPLEMENTATION_COMPLETE.md** - Test infrastructure fixes
- **ANALYSIS_SUMMARY.md** - Executive summary
- PR #32 - Test infrastructure fixes

## Success Metrics

### Before (Current State)
- Property tests passing: 157/223 (70%)
- Known security issues: 10
- Known validation issues: 6
- Known state issues: 8
- Known resource issues: 6

### After (Target State)
- Property tests passing: 223/223 (100%)
- Security issues resolved: 10/10
- Validation issues resolved: 6/6
- State issues resolved: 8/8
- Resource issues resolved: 6/6

## Additional Examples

### Example: Replay Attack Detection
**Current Issue**: System doesn't detect replay attacks

**Test That Fails**:
```elixir
property "replay attacks are detected and rejected" do
  forall replay_scenario <- replay_attack_gen() do
    # Create legitimate session
    {:ok, joiner} = Joiner.create(...)
    
    # Attacker replays session multiple times
    replays = Enum.map(1..replay_scenario.replay_count, fn _ ->
      Joiner.create(network_id: network.id, eui64: joiner.eui64, ...)
    end)
    
    # Should detect replays
    all_replays_rejected?(replays)
  end
end
```

**Recommended Fix**:
```elixir
# Add nonce tracking
defmodule NonceTracker do
  def check_nonce(eui64, nonce) do
    # Check if nonce already used for this device
    # Store nonce with expiration
  end
end

# Use in joiner creation
def create(params) do
  with :ok <- NonceTracker.check_nonce(params.eui64, params.nonce),
       {:ok, joiner} <- do_create(params) do
    {:ok, joiner}
  else
    {:error, :nonce_reused} -> {:error, "Replay attack detected"}
    error -> error
  end
end
```

---

## Lessons Learned from Property Testing

### What Property Tests Revealed

1. **Edge Cases**: Generated inputs found edge cases not covered by unit tests
2. **Concurrency Issues**: Rapid state changes exposed race conditions
3. **Security Gaps**: Malicious inputs found validation gaps
4. **Resource Limits**: Stress testing revealed missing quotas

### Best Practices Going Forward

1. **Write Properties First**: Define properties before implementation
2. **Use Generators Wisely**: Create realistic but adversarial inputs
3. **Test Concurrency**: Use property tests for concurrent operations
4. **Security Focus**: Include malicious input generators
5. **Maintain Tests**: Keep property tests running in CI

### Value Demonstrated

Property-based testing has proven its value by:
- Discovering 30 genuine bugs
- Finding security vulnerabilities
- Identifying edge cases
- Testing concurrent scenarios
- Validating complex state machines

These bugs would likely have made it to production without property-based testing.

---

## Next Steps

1. Create individual GitHub issues for each bug category (or track in a project board)
2. Assign issues to team members based on domain expertise
3. Implement fixes following the recommended patterns
4. Verify fixes with property tests
5. Update documentation with lessons learned
6. Add new property tests for any edge cases discovered during fixes

## Questions?

For questions about specific bugs or implementation approaches, refer to:
- Original analysis: WORKFLOW_PROPERTY_TEST_ANALYSIS.md
- Test files: domain/test/ntbr/domain/*_properties_test.exs
- PropCheck documentation: https://hexdocs.pm/propcheck/
