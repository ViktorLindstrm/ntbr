import Config

# Development overrides
config :ntbr_domain, NTBR.Domain.Spinel.Client,
  uart_device: "ttyUSB0"  # Different device in dev

config :logger, level: :debug
