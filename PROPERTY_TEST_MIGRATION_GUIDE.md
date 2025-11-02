# Migration Guide: Updating Property Tests to Use AshGenerators

This guide shows how to migrate existing property test files to use the new `NTBR.Domain.Test.AshGenerators` module for better type safety and Ash constraint compliance.

## Benefits of Migration

1. **Type Safety**: All generators have `@spec` annotations
2. **Constraint Compliance**: Generators respect Ash resource constraints
3. **Consistency**: Same patterns across all tests
4. **Maintainability**: Centralized generator logic
5. **PropCheck Best Practices**: Proper use of `let`, `measure`, etc.

## Step-by-Step Migration

### Step 1: Add Module Alias

Add the AshGenerators alias to your test module:

```elixir
defmodule YourPropertyTest do
  use ExUnit.Case, async: true
  use PropCheck
  
  alias NTBR.Domain.Resources.{Network, Device, Joiner}
  alias NTBR.Domain.Test.AshGenerators  # Add this line
  
  # ... rest of test
end
```

### Step 2: Replace Local Generators

Replace local generator definitions with calls to `AshGenerators`:

#### Example: UUID Generation

**Before**:
```elixir
defp uuid_gen do
  :crypto.strong_rand_bytes(16)  # ❌ Returns binary, not UUID string
end
```

**After**:
```elixir
# Remove local definition, use AshGenerators.uuid_gen()
# It's already available in the AshGenerators module
```

#### Example: Network Name Generation

**Before**:
```elixir
defp network_name_gen do
  let chars <- list(char(?a..?z)) do
    to_string(chars)  # ❌ No length constraint
  end
end
```

**After**:
```elixir
# Remove local definition, use AshGenerators.network_name_gen()
# It properly constrains length to 1..16
```

#### Example: Device Attributes

**Before**:
```elixir
defp device_attrs_gen(network_id) do
  %{
    network_id: network_id,
    rloc16: :rand.uniform(0xFFFF),  # ❌ Not using PropCheck
    extended_address: :crypto.strong_rand_bytes(8),  # ❌ Eager evaluation
    device_type: Enum.random([:end_device, :router, :leader])  # ❌ Not using PropCheck
  }
end
```

**After**:
```elixir
# Remove local definition, use AshGenerators.device_attrs_gen(network_id)
# OR if you need custom logic, build on top of it:
defp custom_device_attrs_gen(network_id) do
  let base_attrs <- AshGenerators.device_attrs_gen(network_id, nil) do
    let custom_field <- your_custom_generator() do
      Map.put(base_attrs, :custom_field, custom_field)
    end
  end
end
```

### Step 3: Update Generator Usage in Properties

Replace all generator calls:

**Before**:
```elixir
property "test" do
  forall attrs <- my_local_gen() do
    # test logic
  end
end
```

**After**:
```elixir
property "test" do
  forall attrs <- AshGenerators.network_attrs_gen() do
    # test logic
  end
end
```

### Step 4: Remove Old Generator Definitions

After migration, remove the old generator definitions from the bottom of your test file.

## Common Migration Patterns

### Pattern 1: Simple Replacement

**File**: `device_property_test.exs`

**Before**:
```elixir
defp eui64_gen do
  :crypto.strong_rand_bytes(8)
end

property "test eui64" do
  forall eui <- eui64_gen() do
    byte_size(eui) == 8
  end
end
```

**After**:
```elixir
# Remove eui64_gen definition

property "test eui64" do
  forall eui <- AshGenerators.extended_address_gen() do
    byte_size(eui) == 8
  end
end
```

### Pattern 2: Composite Generators

**Before**:
```elixir
defp valid_device_attrs do
  let {rloc, eui, type} <- {
    integer(0, 0xFFFF),
    eui64_gen(),
    device_type_gen()
  } do
    %{
      rloc16: rloc,
      extended_address: eui,
      device_type: type
    }
  end
end
```

**After**:
```elixir
# Remove local definition entirely if you can use AshGenerators.device_attrs_gen()
# OR if you need specific customization:
defp valid_device_attrs do
  let base <- AshGenerators.device_attrs_gen("placeholder", nil) do
    # base already has all the proper fields with constraints
    base
  end
end

# Better: just use AshGenerators.device_attrs_gen(network_id) directly in the property
```

### Pattern 3: Generators with Test-Specific Logic

When you need test-specific behavior, build on top of AshGenerators:

**Before**:
```elixir
defp device_with_parent_gen(network_id) do
  %{
    network_id: network_id,
    rloc16: :rand.uniform(0xFFFF),
    extended_address: :crypto.strong_rand_bytes(8),
    device_type: :end_device,
    parent_id: :crypto.strong_rand_bytes(16)  # ❌ Should be UUID
  }
end
```

**After**:
```elixir
defp device_with_parent_gen(network_id, parent_id) do
  # Use the proper generator with parent_id
  AshGenerators.device_attrs_gen(network_id, parent_id)
end

# Or if you need additional customization:
defp device_with_custom_parent_gen(network_id) do
  let parent_id <- AshGenerators.uuid_gen() do
    let device_attrs <- AshGenerators.device_attrs_gen(network_id, parent_id) do
      # device_attrs now has proper parent_id (UUID)
      device_attrs
    end
  end
end
```

## Files to Migrate

### High Priority
These files likely have issues similar to the ones fixed:

1. **`device_property_test.exs`**
   - Has `eui64_gen` that can use `AshGenerators.extended_address_gen()`
   - Has `device_type_gen` that can use `AshGenerators.device_type_gen()`

2. **`network_property_test.exs`**
   - Check for network attribute generators
   - May benefit from `AshGenerators.network_name_gen()`

3. **`joiner_property_test.exs`**
   - Likely has PSKD generation
   - Can use `AshGenerators.pskd_gen()` and `AshGenerators.joiner_attrs_gen()`

4. **`border_router_property_test.exs`**
   - Can use `AshGenerators.border_router_attrs_gen()`

### Medium Priority
These might have some generators but may be working fine:

5. **`network_lifecycle_properties_test.exs`**
6. **`performance_properties_test.exs`**
7. **`regression_properties_test.exs`**
8. **`security_chaos_properties_test.exs`**

### Low Priority
Spinel tests are infrastructure-level and may not need Ash generators:

9. **`spinel/frame_property_test.exs`**
10. **`spinel/property_test.exs`**

## Validation Checklist

After migrating a file:

- [ ] All `alias NTBR.Domain.Test.AshGenerators` added
- [ ] All local generators using eager evaluation removed
- [ ] All UUID generation uses `AshGenerators.uuid_gen()`
- [ ] All string generators respect length constraints
- [ ] All integer generators use proper ranges
- [ ] No `measure/3` with functions (use values instead)
- [ ] No direct `Ash.read!` calls with IDs (use `Ash.get!` instead)
- [ ] All parent_id references use UUIDs, not binaries
- [ ] Old generator definitions removed (unless truly custom)
- [ ] Tests still pass (if you have Elixir environment)

## Example: Full File Migration

**Before** (`device_property_test.exs` excerpt):
```elixir
defmodule NTBR.Domain.Resources.DevicePropertyTest do
  use ExUnit.Case, async: true
  use PropCheck

  alias NTBR.Domain.Resources.{Device, Network}

  property "device creation" do
    forall {rloc, eui} <- {integer(0, 0xFFFF), eui64_gen()} do
      {:ok, network} = Network.create(%{name: "T", network_name: "T"})
      {:ok, device} = Device.create(%{
        network_id: network.id,
        rloc16: rloc,
        extended_address: eui
      })
      device.rloc16 == rloc
    end
  end

  defp eui64_gen, do: :crypto.strong_rand_bytes(8)
end
```

**After** (`device_property_test.exs` excerpt):
```elixir
defmodule NTBR.Domain.Resources.DevicePropertyTest do
  use ExUnit.Case, async: true
  use PropCheck

  alias NTBR.Domain.Resources.{Device, Network}
  alias NTBR.Domain.Test.AshGenerators  # Added

  property "device creation" do
    # Using proper generators with let
    forall network_attrs <- AshGenerators.network_attrs_gen() do
      {:ok, network} = Network.create(network_attrs)
      
      forall device_attrs <- AshGenerators.device_attrs_gen(network.id, nil) do
        case Device.create(device_attrs) do
          {:ok, device} ->
            device.rloc16 == device_attrs.rloc16 and
            device.extended_address == device_attrs.extended_address
          {:error, _} -> false
        end
      end
    end
  end

  # No local generators needed - removed eui64_gen
end
```

## Testing Your Migration

### Quick Test
Run the specific test file:
```bash
cd domain
mix test test/ntbr/domain/resources/device_property_test.exs
```

### Property Tests Only
```bash
cd domain
mix test --only property
```

### Verbose Mode
```bash
cd domain
mix test --only property --trace
```

## Common Pitfalls

### ❌ Pitfall 1: Using Eager Evaluation
```elixir
# WRONG
defp my_gen do
  :crypto.strong_rand_bytes(8)  # Evaluated once, not per test case
end
```

### ✅ Solution: Use PropCheck Generators
```elixir
# CORRECT
defp my_gen do
  binary(8)  # Generated fresh for each test case
end

# OR better: use AshGenerators
AshGenerators.extended_address_gen()
```

### ❌ Pitfall 2: Not Using `let` for Dependencies
```elixir
# WRONG
defp device_with_network do
  network_id = Ecto.UUID.generate()  # Eager
  %{network_id: network_id, rloc16: :rand.uniform(0xFFFF)}
end
```

### ✅ Solution: Use `let` Properly
```elixir
# CORRECT
defp device_with_network do
  let network_id <- AshGenerators.uuid_gen() do
    let device_attrs <- AshGenerators.device_attrs_gen(network_id, nil) do
      device_attrs
    end
  end
end
```

### ❌ Pitfall 3: Incorrect measure Usage
```elixir
# WRONG
property "test" do
  forall size <- integer(1, 100) do
    result = do_work(size)
    result == :ok
  end
  |> measure("Size", fn s -> s end)  # Function not allowed
end
```

### ✅ Solution: Pass Value Directly
```elixir
# CORRECT
property "test" do
  forall size <- integer(1, 100) do
    result = do_work(size)
    (result == :ok)
    |> measure("Size", size)  # Pass value, not function
  end
end
```

## Need Help?

If you encounter issues during migration:

1. Check `PROPERTY_TEST_IMPROVEMENTS.md` for detailed examples
2. Look at `advanced_security_properties_test.exs` as a reference
3. Review `domain/test/support/ash_generators.ex` for available generators
4. Consult PropCheck official tests: https://github.com/alfert/propcheck/tree/master/test

## Summary

Migration is straightforward:
1. Add `alias NTBR.Domain.Test.AshGenerators`
2. Replace local generators with `AshGenerators.*` calls
3. Remove old generator definitions
4. Test to ensure everything works

The result will be more maintainable, type-safe, and reliable property tests.
