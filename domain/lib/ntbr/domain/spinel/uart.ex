defmodule NTBR.Domain.Spinel.UART do
  @moduledoc """
  UART transport layer for Spinel communication.
  
  Handles UART device communication with configurable adapter for testing.
  The adapter can be swapped for a mock in tests.
  
  ## Configuration
  
      # config/config.exs
      config :ntbr_domain,
        uart_adapter: Circuits.UART,  # or NTBR.Domain.Spinel.UART.Mock for testing
        uart_device: "ttyACM0",
        uart_speed: 460_800
  """

  @adapter Application.compile_env(:ntbr_domain, :uart_adapter, Circuits.UART)

  @type uart :: pid() | port()
  @type device :: String.t()
  @type opts :: keyword()

  @doc """
  Open a UART device.
  
  ## Options
  
  - `:speed` - Baud rate (default: 460_800)
  - `:active` - Active mode (default: true for message-based receiving)
  - `:framing` - Framing protocol (default: none, raw bytes)
  
  ## Examples
  
      {:ok, uart} = UART.open("ttyACM0")
      {:ok, uart} = UART.open("ttyACM0", speed: 115_200)
  """
  @spec open(device(), opts()) :: {:ok, uart()} | {:error, term()}
  def open(device, opts \\ []) do
    default_opts = [
      speed: 460_800,
      active: true,
      data_bits: 8,
      stop_bits: 1,
      parity: :none,
      flow_control: :none
    ]

    merged_opts = Keyword.merge(default_opts, opts)

    case @adapter.open(device, merged_opts) do
      {:ok, _uart} = result ->
        # Give device time to initialize
        Process.sleep(100)
        result

      error ->
        error
    end
  end

  @doc """
  Write data to UART.
  
  ## Examples
  
      UART.write(uart, <<0x80, 0x01>>)
  """
  @spec write(uart(), binary()) :: :ok | {:error, term()}
  def write(uart, data) when is_binary(data) do
    @adapter.write(uart, data)
  end

  @doc """
  Close UART connection.
  
  ## Examples
  
      UART.close(uart)
  """
  @spec close(uart()) :: :ok
  def close(uart) do
    @adapter.close(uart)
  end

  @doc """
  Read data from UART (when not in active mode).
  
  ## Examples
  
      {:ok, data} = UART.read(uart, 1000)
  """
  @spec read(uart(), timeout()) :: {:ok, binary()} | {:error, term()}
  def read(uart, timeout \\ 5000) do
    @adapter.read(uart, timeout)
  end

  @doc """
  Drain any pending data from UART buffer.
  """
  @spec drain(uart()) :: :ok
  def drain(uart) do
    @adapter.drain(uart)
  end

  @doc """
  Flush UART buffers.
  """
  @spec flush(uart()) :: :ok
  def flush(uart) do
    @adapter.flush(uart)
  end
end
