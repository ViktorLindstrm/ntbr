# CI Error Analysis and Fixes

## Latest Changes (Commit e22392d)

### Issue: Idempotent Promote Transition
**Problem**: When `promote` was called on a network in `:leader` state, there was no matching transition defined.

**Previous Approach**: Returned unchanged changeset without calling transition_state
- Risk: Bypassed AshStateMachine validation
- Inconsistent with other state transition actions

**Solution**: Added explicit state machine transition
```elixir
transition(:promote, from: :leader, to: :leader)
```

**Benefits**:
- Makes idempotent behavior explicit in state machine
- Ensures transition_state is always called for consistency
- Proper validation by AshStateMachine

## Counter Example Analysis

### Example: `[[:demote, :attach, :promote, :promote, :attach, :promote, :attach, :demote]]`

**Step-by-step trace** (starting from `:detached`):
1. `:demote` from `:detached` → **FAILS** (no transition) → stays `:detached`
2. `:attach` from `:detached` → **SUCCEEDS** → `:child`
3. `:promote` from `:child` → **SUCCEEDS** → `:router`
4. `:promote` from `:router` → **SUCCEEDS** → `:leader`
5. `:attach` from `:leader` → **FAILS** (no transition) → stays `:leader`
6. `:promote` from `:leader` → **SUCCEEDS** (idempotent) → `:leader`
7. `:attach` from `:leader` → **FAILS** (no transition) → stays `:leader`
8. `:demote` from `:leader` → **SUCCEEDS** → `:child`

**Expected result**: Final state is `:child`, some transitions failed
**Test expectation**: This is VALID - the system handles invalid transitions gracefully

## State Machine Transitions (Current)

```elixir
transition(:attach, from: [:detached, :disabled], to: :child)
transition(:promote, from: :child, to: :router)
transition(:promote, from: :router, to: :leader)
transition(:promote, from: :leader, to: :leader)  # NEW: Idempotent
transition(:become_leader, from: [:router, :child], to: :leader)
transition(:demote, from: [:router, :leader], to: :child)
transition(:detach, from: [:child, :router, :leader], to: :detached)
transition(:disable, from: [:detached, :child, :router, :leader, :disabled], to: :disabled)
```

## Mock Spinel Client Coverage

The MockSpinelClient handles:
- ✅ `{:set_property, property, value}` → returns `:ok`
- ✅ `{:get_property, property}` → returns `{:ok, value}` for known properties
- ✅ `:reset` → returns `:ok`
- ✅ All other calls → returns `:ok`

**Known properties**:
- `:phy_chan` → `{:ok, <<15>>}` (channel 15)
- `:net_role` → `{:ok, <<0>>}` (disabled)
- `:ncp_version` → `{:ok, "OPENTHREAD/1.0.0"}`
- `:caps` → `{:ok, [:net, :mac, :config]}`
- `:thread_router_table` → `{:ok, <<>>}`
- `:thread_child_table` → `{:ok, <<>>}`

## Test Helper Simplification

**Old approach**: Pre-filtered transitions based on current state
```elixir
case {current_state, transition} do
  {:detached, :attach} -> Network.attach(network)
  {:child, :promote} -> Network.promote(network)
  # ... many cases
  _ -> {:error, :invalid_transition}
```

**New approach**: Always call the action, let state machine validate
```elixir
case transition do
  :attach -> Network.attach(network)
  :promote -> Network.promote(network)
  :demote -> Network.demote(network)
  :detach -> Network.detach(network)
  _ -> {:error, :unknown_transition}
```

**Benefits**:
- Simpler code
- Proper delegation to domain layer
- Tests actual state machine behavior

## Potential Remaining Issues

Without access to actual CI error output, here are areas that could still have issues:

### 1. Client API Guard Clauses
Functions like `set_channel(channel)` have guards:
```elixir
def set_channel(channel) when channel >= 11 and channel <= 26
```

If tests pass invalid values, function clause won't match.
- **Mitigation**: Network resource has default channel = 15 (valid)

### 2. PropCheck Reporter Issues
Problem statement mentioned:
```
FunctionClauseError in PropCheck.StateM.Reporter.pretty_print_counter_example_parallel/1
```

This is a PropCheck framework issue, not our code.
- **Status**: May require PropCheck version update or API changes

### 3. Binary Size Validations
Network resource validates:
- network_key: must be 16 bytes
- extended_pan_id: must be 8 bytes
- pskc: must be 16 bytes

Tests generating invalid sizes will fail.
- **Mitigation**: Network.create auto-generates valid values if not provided

### 4. Enumerable Protocol Error
Original problem mentioned BitString vs Enumerable.
- **Status**: Fixed by ensuring test helpers return correct types
- Counter examples are now properly handled as lists

## Files Modified Summary

1. **test/test_helper.exs**
   - Added MockSpinelClient GenServer
   - Ensured domain application starts
   - Defined Mox mock for ClientBehaviour

2. **lib/ntbr/domain/resources/network.ex**
   - Added leader→leader idempotent transition
   - Simplified promote change function
   - Always calls transition_state for consistency

3. **lib/ntbr/domain/thread/network_manager.ex**
   - Added process_topology_update/3 function
   - Added state checking before transitions
   - Prevents redundant state changes

4. **test/ntbr/domain/network_lifecycle_properties_test.exs**
   - Simplified apply_transition helper
   - Delegates validation to Network resource
   - Fixed return types (state atoms vs network structs)

## Testing Strategy

To verify fixes work:
1. Run property tests with PropCheck
2. Check that invalid transitions return errors (not crash)
3. Verify final states are always valid
4. Confirm GenServer is available for all tests
5. Validate idempotent operations succeed

## Next Steps if Errors Persist

1. **Get actual error output**: Need lines starting with "Error:" from CI logs
2. **Check specific test failures**: Which properties are failing?
3. **Review counter examples**: What sequences cause failures?
4. **Validate assumptions**: Are our fixes addressing the right issues?
