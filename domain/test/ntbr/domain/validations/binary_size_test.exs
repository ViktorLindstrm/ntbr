defmodule NTBR.Domain.Validations.BinarySizeTest do
  @moduledoc false
  # Tests for BinarySize validation helper.
  #
  # Tests validation of binary attribute sizes in Ash resources.
  use ExUnit.Case, async: true
  use PropCheck

  alias NTBR.Domain.Validations.BinarySize

  @moduletag :property
  @moduletag :validations
  @moduletag :unit

  # Define a minimal test resource for validation testing
  defmodule TestResource do
    @moduledoc false
    use Ash.Resource,
      domain: NTBR.Domain,
      data_layer: Ash.DataLayer.Ets

    attributes do
      uuid_primary_key(:id)
      attribute(:field, :binary, public?: true)
      attribute(:network_key, :binary, public?: true)
      attribute(:eui64, :binary, public?: true)
      attribute(:xpanid, :binary, public?: true)
      attribute(:pskc, :binary, public?: true)
      attribute(:backbone_iid, :binary, public?: true)
      attribute(:key, :binary, public?: true)
    end

    actions do
      default_accept(:*)
      defaults([:read, :destroy, create: :*, update: :*])
    end
  end

  # Create a test changeset helper using actual Ash changesets
  defp make_changeset(attributes) do
    TestResource
    |> Ash.Changeset.for_create(:create, attributes)
  end

  # ============================================================================
  # BASIC VALIDATION TESTS
  # ============================================================================

  describe "validate/2 with exact size match" do
    test "returns :ok when binary has exact size" do
      changeset = make_changeset(%{network_key: :crypto.strong_rand_bytes(16)})
      opts = [field: :network_key, size: 16]

      assert :ok = BinarySize.validate(changeset, opts)
    end

    test "returns error when binary is too small" do
      changeset = make_changeset(%{network_key: :crypto.strong_rand_bytes(8)})
      opts = [field: :network_key, size: 16]

      assert {:error, [field: :network_key, message: message]} =
               BinarySize.validate(changeset, opts)

      assert message =~ "must be exactly 16 bytes"
      assert message =~ "got 8 bytes"
    end

    test "returns error when binary is too large" do
      changeset = make_changeset(%{network_key: :crypto.strong_rand_bytes(32)})
      opts = [field: :network_key, size: 16]

      assert {:error, [field: :network_key, message: message]} =
               BinarySize.validate(changeset, opts)

      assert message =~ "must be exactly 16 bytes"
      assert message =~ "got 32 bytes"
    end
  end

  describe "validate/2 with nil values" do
    test "returns error when nil and allow_nil? is false (default)" do
      changeset = make_changeset(%{network_key: nil})
      opts = [field: :network_key, size: 16]

      assert {:error, [field: :network_key, message: "is required"]} =
               BinarySize.validate(changeset, opts)
    end

    test "returns :ok when nil and allow_nil? is true" do
      changeset = make_changeset(%{eui64: nil})
      opts = [field: :eui64, size: 8, allow_nil?: true]

      assert :ok = BinarySize.validate(changeset, opts)
    end

    test "returns error when nil and allow_nil? is explicitly false" do
      changeset = make_changeset(%{network_key: nil})
      opts = [field: :network_key, size: 16, allow_nil?: false]

      assert {:error, [field: :network_key, message: "is required"]} =
               BinarySize.validate(changeset, opts)
    end
  end

  describe "validate/2 with non-binary values" do
    test "returns error for string value" do
      changeset = make_changeset(%{network_key: "not a binary"})
      opts = [field: :network_key, size: 16]

      assert {:error, [field: :network_key, message: "must be a binary"]} =
               BinarySize.validate(changeset, opts)
    end

    test "returns error for integer value" do
      changeset = make_changeset(%{network_key: 12345})
      opts = [field: :network_key, size: 16]

      assert {:error, [field: :network_key, message: "must be a binary"]} =
               BinarySize.validate(changeset, opts)
    end

    test "returns error for map value" do
      changeset = make_changeset(%{network_key: %{foo: :bar}})
      opts = [field: :network_key, size: 16]

      assert {:error, [field: :network_key, message: "must be a binary"]} =
               BinarySize.validate(changeset, opts)
    end
  end

  # ============================================================================
  # PROPERTY TESTS
  # ============================================================================

  property "validates correct sizes always pass" do
    forall {size, binary} <- sized_binary_gen() do
      changeset = make_changeset(%{field: binary})
      opts = [field: :field, size: size]

      BinarySize.validate(changeset, opts) == :ok
    end
  end

  property "validates incorrect sizes always fail" do
    forall {expected_size, actual_size} <- different_sizes_gen() do
      binary = :crypto.strong_rand_bytes(actual_size)
      changeset = make_changeset(%{field: binary})
      opts = [field: :field, size: expected_size]

      match?({:error, _}, BinarySize.validate(changeset, opts))
    end
  end

  property "nil values with allow_nil? true always pass" do
    forall size <- integer(1, 64) do
      changeset = make_changeset(%{field: nil})
      opts = [field: :field, size: size, allow_nil?: true]

      BinarySize.validate(changeset, opts) == :ok
    end
  end

  property "nil values with allow_nil? false always fail" do
    forall size <- integer(1, 64) do
      changeset = make_changeset(%{field: nil})
      opts = [field: :field, size: size, allow_nil?: false]

      match?({:error, _}, BinarySize.validate(changeset, opts))
    end
  end

  # ============================================================================
  # COMMON USE CASE TESTS
  # ============================================================================

  describe "common Thread network use cases" do
    test "validates 16-byte network key" do
      # Valid
      changeset = make_changeset(%{network_key: :crypto.strong_rand_bytes(16)})
      assert :ok = BinarySize.validate(changeset, field: :network_key, size: 16)

      # Invalid - too short
      changeset = make_changeset(%{network_key: :crypto.strong_rand_bytes(15)})

      assert {:error, _} =
               BinarySize.validate(changeset, field: :network_key, size: 16)
    end

    test "validates 8-byte EUI-64" do
      # Valid
      changeset = make_changeset(%{eui64: :crypto.strong_rand_bytes(8)})
      assert :ok = BinarySize.validate(changeset, field: :eui64, size: 8)

      # Valid - nil allowed
      changeset = make_changeset(%{eui64: nil})
      assert :ok = BinarySize.validate(changeset, field: :eui64, size: 8, allow_nil?: true)

      # Invalid - wrong size
      changeset = make_changeset(%{eui64: :crypto.strong_rand_bytes(6)})
      assert {:error, _} = BinarySize.validate(changeset, field: :eui64, size: 8)
    end

    test "validates 8-byte extended PAN ID" do
      # Valid
      changeset = make_changeset(%{xpanid: :crypto.strong_rand_bytes(8)})
      assert :ok = BinarySize.validate(changeset, field: :xpanid, size: 8)

      # Invalid
      changeset = make_changeset(%{xpanid: :crypto.strong_rand_bytes(10)})
      assert {:error, _} = BinarySize.validate(changeset, field: :xpanid, size: 8)
    end

    test "validates 16-byte PSKc" do
      # Valid
      changeset = make_changeset(%{pskc: :crypto.strong_rand_bytes(16)})
      assert :ok = BinarySize.validate(changeset, field: :pskc, size: 16)

      # Valid - nil allowed
      changeset = make_changeset(%{pskc: nil})
      assert :ok = BinarySize.validate(changeset, field: :pskc, size: 16, allow_nil?: true)
    end

    test "validates 8-byte backbone interface ID" do
      # Valid
      changeset = make_changeset(%{backbone_iid: :crypto.strong_rand_bytes(8)})
      assert :ok = BinarySize.validate(changeset, field: :backbone_iid, size: 8)

      # Valid - nil allowed
      changeset = make_changeset(%{backbone_iid: nil})

      assert :ok =
               BinarySize.validate(changeset, field: :backbone_iid, size: 8, allow_nil?: true)
    end
  end

  # ============================================================================
  # EDGE CASES
  # ============================================================================

  describe "edge cases" do
    test "validates zero-length binary" do
      changeset = make_changeset(%{field: <<>>})
      assert :ok = BinarySize.validate(changeset, field: :field, size: 0)

      changeset = make_changeset(%{field: <<>>})
      assert {:error, _} = BinarySize.validate(changeset, field: :field, size: 1)
    end

    test "validates large binaries" do
      large_binary = :crypto.strong_rand_bytes(1024)
      changeset = make_changeset(%{field: large_binary})
      assert :ok = BinarySize.validate(changeset, field: :field, size: 1024)
    end

    test "field not present in changeset" do
      changeset = make_changeset(%{})
      opts = [field: :missing_field, size: 16]

      # Should treat as nil
      assert {:error, [field: :missing_field, message: "is required"]} =
               BinarySize.validate(changeset, opts)
    end
  end

  # ============================================================================
  # ERROR MESSAGE TESTS
  # ============================================================================

  describe "error messages" do
    test "includes expected and actual sizes" do
      changeset = make_changeset(%{key: :crypto.strong_rand_bytes(10)})
      {:error, [field: :key, message: message]} = BinarySize.validate(changeset, field: :key, size: 16)

      assert message =~ "16 bytes"
      assert message =~ "10 bytes"
    end

    test "specifies field name in error" do
      changeset = make_changeset(%{network_key: :crypto.strong_rand_bytes(8)})

      {:error, [field: field, message: _]} =
        BinarySize.validate(changeset, field: :network_key, size: 16)

      assert field == :network_key
    end
  end

  # ============================================================================
  # OPTION VALIDATION TESTS
  # ============================================================================

  describe "option validation" do
    test "requires field option" do
      changeset = make_changeset(%{key: <<1, 2, 3>>})

      assert_raise ArgumentError, fn ->
        BinarySize.validate(changeset, size: 3)
      end
    end

    test "requires size option" do
      changeset = make_changeset(%{key: <<1, 2, 3>>})

      assert_raise ArgumentError, fn ->
        BinarySize.validate(changeset, field: :key)
      end
    end
  end

  # ============================================================================
  # GENERATORS
  # ============================================================================

  defp sized_binary_gen do
    let size <- integer(1, 64) do
      {size, :crypto.strong_rand_bytes(size)}
    end
  end

  defp different_sizes_gen do
    let {expected, actual} <- {integer(1, 32), integer(1, 32)} do
      # Ensure they're different
      if expected == actual do
        {expected, actual + 1}
      else
        {expected, actual}
      end
    end
  end
end
