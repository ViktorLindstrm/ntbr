import Config

# Use mock UART in tests
config :ntbr_domain, NTBR.Domain.Spinel.Client,
  uart_device: "mock",
  uart_adapter: NTBR.Domain.Spinel.UARTMock

# Use mock for NetworkManager client
config :ntbr_domain, NTBR.Domain.Thread.NetworkManager,
  client: NTBR.Domain.Spinel.ClientMock,
  topology_interval: 100,
  joiner_check_interval: 100

config :logger, level: :warning
