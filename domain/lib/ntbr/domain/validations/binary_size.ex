defmodule NTBR.Domain.Validations.BinarySize do
  @moduledoc """
  Helper module for validating binary attribute sizes.
  
  Since Ash 3.6.2 doesn't support constraints on binary attributes,
  use this module to create size validations.
  
  ## Usage
  
      validations do
        validate {NTBR.Domain.Validations.BinarySize, field: :network_key, size: 16}
        validate {NTBR.Domain.Validations.BinarySize, field: :eui64, size: 8, allow_nil?: true}
      end
  """

  @doc """
  Validates that a binary field has an exact byte size.
  
  ## Options
  
  - `:field` - The attribute name (required)
  - `:size` - The required byte size (required)
  - `:allow_nil?` - Whether nil is allowed (default: false)
  
  ## Examples
  
      # Must be exactly 16 bytes, cannot be nil
      validate {BinarySize, field: :network_key, size: 16}
      
      # Must be exactly 8 bytes, can be nil
      validate {BinarySize, field: :eui64, size: 8, allow_nil?: true}
  """
  def validate(changeset, opts) do
    # Validate required options
    field = case Keyword.fetch(opts, :field) do
      {:ok, f} -> f
      :error -> raise ArgumentError, "BinarySize validation requires :field option"
    end

    size = case Keyword.fetch(opts, :size) do
      {:ok, s} -> s
      :error -> raise ArgumentError, "BinarySize validation requires :size option"
    end

    allow_nil? = Keyword.get(opts, :allow_nil?, false)

    case Ash.Changeset.get_attribute(changeset, field) do
      nil ->
        if allow_nil? do
          :ok
        else
          {:error,
           field: field,
           message: "is required"}
        end

      value when is_binary(value) ->
        actual_size = byte_size(value)

        if actual_size == size do
          :ok
        else
          {:error,
           field: field,
           message: "must be exactly #{size} bytes, got #{actual_size} bytes"}
        end

      _other ->
        {:error,
         field: field,
         message: "must be a binary"}
    end
  end
end
