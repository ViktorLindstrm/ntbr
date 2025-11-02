# PropCheck Test Fixes - Based on Official Patterns

**Reference**: https://github.com/alfert/propcheck/tree/master/test  
**Date**: 2025-11-02

## Key Learnings from PropCheck Test Suite

### 1. Proper `measure/3` Usage

**Signature**: `measure(test, title, number_or_list) :: test`

**WRONG** (Current code):
```elixir
property "amplification attacks: responses are not larger than requests" do
  forall size <- integer(1, 1000) do
    # test logic
  end
  |> measure("Request size", fn size -> size end)  # ❌ WRONG
end
```

**CORRECT** (From PropCheck):
```elixir
property "amplification attacks: responses are not larger than requests" do
  forall size <- integer(1, 1000) do
    measure("Request size", size,  # ✅ CORRECT: measure wraps the property
      # test logic here
      true  # or actual property check
    )
  end
end
```

**Or with pipe**:
```elixir
property "with measurement" do
  forall size <- integer(1, 1000) do
    result = do_work(size)
    # First the property check, then measure
    (result == :ok)
    |> measure("Work size", size)
  end
end
```

### 2. Proper `let` Usage with Type Safety

From `let_test.exs`:

```elixir
# Simple let with type constraints
def kilo_numbers do
  let num <- integer(1, 1000) do
    num
  end
end

# Chained lets for dependent values
def nondecreasing_triples do
  let [
    l <- integer(),
    m <- integer(^l, :inf),  # Use ^l to reference l
    h <- integer(^m, :inf)   # Use ^m to reference m
  ] do
    {l, m, h}
  end
end

# For Ash UUID constraints
def uuid_generator do
  let bytes <- binary(16) do
    # Convert to UUID string format
    <<a::32, b::16, c::16, d::16, e::48>> = bytes
    format_uuid(a, b, c, d, e)
  end
end
```

### 3. State Machine Testing Pattern

From `counter_dsl_test.exs`:

```elixir
defmodule MyResourceTest do
  use ExUnit.Case
  use PropCheck
  use PropCheck.StateM.ModelDSL
  
  # Model state
  def initial_state, do: %{resources: []}
  
  # Command generator
  def command_gen(state) do
    frequency([
      {5, {:create, [resource_attrs_gen()]}},
      {3, {:read, [existing_id_gen(state)]}},
      {2, {:delete, [existing_id_gen(state)]}}
    ])
  end
  
  defcommand :create do
    def impl(attrs), do: Resource.create(attrs)
    def next(state, [attrs], {:ok, resource}) do
      %{state | resources: [resource | state.resources]}
    end
    def post(_state, _args, result), do: match?({:ok, _}, result)
  end
  
  property "resource state machine" do
    forall cmds <- commands(__MODULE__) do
      {history, state, result} = run_commands(__MODULE__, cmds)
      
      (result == :ok)
      |> when_fail(
        IO.puts("""
        History: #{inspect(history, pretty: true)}
        State: #{inspect(state, pretty: true)}
        Result: #{inspect(result, pretty: true)}
        """)
      )
    end
  end
end
```

### 4. Generator Best Practices

From `basic_types_test.exs` and `let_test.exs`:

```elixir
# Sized generators for recursive structures
def sized_list_gen do
  sized(size, sized_list_gen(size))
end

def sized_list_gen(0), do: []
def sized_list_gen(n) do
  [integer() | sized_list_gen(n - 1)]
end

# Constrained generators
def network_name_gen do
  # Ash constraint: min_length: 1, max_length: 16
  let length <- integer(1, 16) do
    let chars <- vector(length, char(?a..?z)) do
      to_string(chars)
    end
  end
end

# UUID generator respecting Ash types
def uuid_gen do
  let bytes <- binary(16) do
    # Convert to string UUID as expected by Ash
    UUID.binary_to_string!(bytes)
  end
end

# Attribute map generators with dependencies
def device_attrs_gen(network_id) do
  let {rloc16, extended_addr, device_type, parent_id} <- {
    integer(0, 0xFFFF),
    binary(8),
    oneof([:end_device, :router, :leader, :reed]),
    oneof([uuid_gen(), nil])
  } do
    %{
      network_id: network_id,
      rloc16: rloc16,
      extended_address: extended_addr,
      device_type: device_type,
      parent_id: parent_id
    }
  end
end
```

### 5. Property Options

From multiple test files:

```elixir
# Set number of tests
property "fast test", [:verbose, {:numtests, 100}] do
  forall x <- integer() do
    x == x
  end
end

# Expected to fail (for testing shrinking)
@tag will_fail: true
property "shrinking test", [scale_numtests(10)] do
  forall n <- integer(100, 1000) do
    n != 180  # Will fail and shrink to 180
  end
end

# With configuration from helper
use PropCheck, default_opts: &PropCheck.TestHelpers.config/0
```

---

## Specific Fixes for NTBR Domain Tests

### Fix 1: `resource_enumeration_gen` (Line 748)

**Current** (WRONG):
```elixir
defp resource_enumeration_gen do
  existing_id = :crypto.strong_rand_bytes(16)  # ❌ Returns binary
  non_existing_id = :crypto.strong_rand_bytes(16)
  {existing_id, non_existing_id}
end
```

**Fixed** (CORRECT):
```elixir
defp resource_enumeration_gen do
  let {existing_bytes, non_existing_bytes} <- 
    {binary(16), binary(16)} do
    {
      UUID.binary_to_string!(existing_bytes),
      UUID.binary_to_string!(non_existing_bytes)
    }
  end
end
```

### Fix 2: Amplification Attack Property (Line 646)

**Current** (WRONG):
```elixir
property "amplification attacks: responses are not larger than requests" do
  forall size <- integer(1, 1000) do
    request = generate_request(size)
    response = send_request(request)
    
    byte_size(response) <= byte_size(request)
  end
  |> measure("Request size", fn size -> size end)  # ❌ Wrong API
end
```

**Fixed** (CORRECT):
```elixir
property "amplification attacks: responses are not larger than requests" do
  forall size <- integer(1, 1000) do
    request = generate_request(size)
    response = send_request(request)
    
    result = byte_size(response) <= byte_size(request)
    
    result
    |> measure("Request size", size)  # ✅ Correct: number, not function
  end
end
```

### Fix 3: Eclipse Attack Property (Line 258)

**Current** (WRONG):
```elixir
property "eclipse attack: isolated devices detect partitioning" do
  forall scenario <- eclipse_scenario_gen() do
    # Create devices
    devices = Enum.map(1..scenario.fake_count, fn _ ->
      Device.create(%{
        network_id: network.id,
        parent_id: <<0, 0, 0, 0, 0, 0, 0, 10>>  # ❌ Binary, not UUID
      })
    end)
    # ...
  end
end
```

**Fixed** (CORRECT):
```elixir
property "eclipse attack: isolated devices detect partitioning" do
  forall scenario <- eclipse_scenario_gen() do
    {:ok, network} = create_test_network("eclipse")
    
    # Generate proper UUIDs for parent_id
    devices = Enum.map(1..scenario.fake_count, fn _ ->
      let parent_id <- oneof([uuid_gen(), nil]) do
        Device.create!(%{
          network_id: network.id,
          rloc16: :rand.uniform(0xFFFF),
          extended_address: :crypto.strong_rand_bytes(8),
          parent_id: parent_id  # ✅ Proper UUID or nil
        })
      end
    end)
    # ...
  end
end
```

### Fix 4: Network.read! API Usage (Line 500)

**Current** (WRONG):
```elixir
property "conflicting state reports from multiple sources are resolved" do
  forall scenario <- conflict_scenario_gen() do
    {:ok, network} = Network.create(...)
    
    # Try to read - WRONG API usage
    devices = Network.read!(network.id)  # ❌ Expects opts, not ID
  end
end
```

**Fixed** (CORRECT):
```elixir
property "conflicting state reports from multiple sources are resolved" do
  forall scenario <- conflict_scenario_gen() do
    {:ok, network} = Network.create(...)
    
    # Use proper Ash read API
    devices = Device
    |> Ash.Query.filter(network_id == ^network.id)
    |> Ash.read!()
    
    # Or use code interface if defined:
    devices = Device.by_network!(network.id)
  end
end
```

---

## Type-Safe Generator Module (New)

Create `/home/runner/work/ntbr/ntbr/domain/test/support/generators.ex`:

```elixir
defmodule NTBR.Domain.Test.Generators do
  @moduledoc """
  Type-safe PropCheck generators for Ash resources.
  
  Based on PropCheck official patterns from:
  https://github.com/alfert/propcheck/tree/master/test
  
  All generators respect Ash resource constraints and use
  Elixir 1.18 type specifications.
  """
  use PropCheck
  
  @type uuid :: String.t()
  
  ## UUID Generators
  
  @spec uuid_gen() :: PropCheck.type()
  @doc """
  Generates a valid UUID v4 string compatible with Ash's uuid_primary_key.
  """
  def uuid_gen do
    let bytes <- binary(16) do
      UUID.binary_to_string!(bytes)
    end
  end
  
  ## Network Generators
  
  @spec network_name_gen() :: PropCheck.type()
  @doc """
  Generates valid network names respecting Ash constraint:
  - min_length: 1
  - max_length: 16
  """
  def network_name_gen do
    let length <- integer(1, 16) do
      let chars <- vector(length, char(?a..?z)) do
        to_string(chars)
      end
    end
  end
  
  @spec network_attrs_gen() :: PropCheck.type()
  @doc "Generates valid Network creation attributes"
  def network_attrs_gen do
    let {name, net_name} <- {network_name_gen(), network_name_gen()} do
      %{
        name: name,
        network_name: net_name
      }
    end
  end
  
  ## Device Generators
  
  @spec rloc16_gen() :: PropCheck.type()
  @doc "Generates RLOC16 in valid range [0, 0xFFFF]"
  def rloc16_gen, do: integer(0, 0xFFFF)
  
  @spec extended_address_gen() :: PropCheck.type()
  @doc "Generates 8-byte extended address"
  def extended_address_gen, do: binary(8)
  
  @spec device_type_gen() :: PropCheck.type()
  @doc "Generates valid device types per Ash constraint"
  def device_type_gen do
    oneof([:end_device, :router, :leader, :reed])
  end
  
  @spec device_attrs_gen(uuid(), uuid() | nil) :: PropCheck.type()
  @doc """
  Generates valid Device creation attributes.
  
  Respects all Ash constraints:
  - network_id: required UUID
  - parent_id: optional UUID  
  - rloc16: 0..0xFFFF
  - extended_address: 8 bytes
  """
  def device_attrs_gen(network_id, parent_id \\ nil) do
    let {rloc16, extended_addr, device_type} <- {
      rloc16_gen(),
      extended_address_gen(),
      device_type_gen()
    } do
      %{
        network_id: network_id,
        rloc16: rloc16,
        extended_address: extended_addr,
        device_type: device_type,
        parent_id: parent_id
      }
    end
  end
  
  ## Joiner Generators
  
  @spec pskd_gen() :: PropCheck.type()
  @doc "Generates valid Pre-Shared Key for Device (PSKD)"
  def pskd_gen do
    # PSKD should be 6-32 characters
    let length <- integer(6, 32) do
      let chars <- vector(length, oneof([char(?0..?9), char(?A..?Z)])) do
        to_string(chars)
      end
    end
  end
  
  @spec joiner_attrs_gen(uuid()) :: PropCheck.type()
  @doc "Generates valid Joiner creation attributes"
  def joiner_attrs_gen(network_id) do
    let {eui64, pskd, timeout} <- {
      binary(8),
      pskd_gen(),
      integer(30, 300)
    } do
      %{
        network_id: network_id,
        eui64: eui64,
        pskd: pskd,
        timeout: timeout
      }
    end
  end
end
```

---

## Testing the Generators

Create `/home/runner/work/ntbr/ntbr/domain/test/support/generators_test.exs`:

```elixir
defmodule NTBR.Domain.Test.GeneratorsTest do
  @moduledoc "Tests for type-safe generators"
  use ExUnit.Case
  use PropCheck
  
  alias NTBR.Domain.Test.Generators
  alias NTBR.Domain.Resources.{Network, Device}
  
  @moduletag :generators
  
  property "uuid_gen produces valid UUIDs" do
    forall uuid <- Generators.uuid_gen() do
      is_binary(uuid) and
      String.length(uuid) == 36 and
      String.contains?(uuid, "-")
    end
  end
  
  property "network_name_gen respects length constraints" do
    forall name <- Generators.network_name_gen() do
      len = String.length(name)
      len >= 1 and len <= 16
    end
  end
  
  property "network_attrs_gen creates valid networks" do
    forall attrs <- Generators.network_attrs_gen() do
      case Network.create(attrs) do
        {:ok, network} ->
          is_binary(network.id) and
          String.length(network.name) <= 16
        {:error, _} ->
          false
      end
    end
  end
  
  property "device_attrs_gen creates valid devices" do
    forall network_attrs <- Generators.network_attrs_gen() do
      {:ok, network} = Network.create(network_attrs)
      
      forall device_attrs <- Generators.device_attrs_gen(network.id) do
        case Device.create(device_attrs) do
          {:ok, device} ->
            device.network_id == network.id and
            device.rloc16 >= 0 and
            device.rloc16 <= 0xFFFF and
            byte_size(device.extended_address) == 8
          {:error, _} ->
            false
        end
      end
    end
  end
end
```

---

## Migration Checklist

- [ ] Create `test/support/generators.ex` with type-safe generators
- [ ] Create `test/support/generators_test.exs` to validate generators
- [ ] Fix `resource_enumeration_gen` to use UUID strings
- [ ] Fix `measure/3` usage in amplification attack property
- [ ] Fix `Network.read!` API usage in conflict resolution property
- [ ] Fix device creation with proper UUID parent_id
- [ ] Add @spec annotations to all test helper functions
- [ ] Run generator tests to validate Ash constraint compliance
- [ ] Run full property test suite
- [ ] Update documentation with PropCheck patterns

---

## References

- PropCheck Official Tests: https://github.com/alfert/propcheck/tree/master/test
- PropCheck Hexdocs: https://hexdocs.pm/propcheck/
- Ash Framework: https://hexdocs.pm/ash/
- UUID Library: https://hexdocs.pm/elixir_uuid/
