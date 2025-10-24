import Config

# Spinel Client defaults
config :ntbr_domain, NTBR.Domain.Spinel.Client,
  uart_device: System.get_env("NTBR_UART_DEVICE", "ttyACM0"),
  uart_speed: 460_800,
  uart_adapter: Circuits.UART,
  response_timeout: 5_000

# NetworkManager defaults
config :ntbr_domain, NTBR.Domain.Thread.NetworkManager,
  topology_interval: 30_000,
  joiner_check_interval: 10_000

# Ash Framework
config :ntbr_domain, :ash_domains, [NTBR.Domain]

# Import environment-specific config
import_config "#{config_env()}.exs"
