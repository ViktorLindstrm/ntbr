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

# Configure JUnit formatter for test reporting
config :junit_formatter,
  report_file: "test-junit-report.xml",
  report_dir: "_build/test/lib/ntbr_domain",
  print_report_file: true,
  prepend_project_name?: true,
  include_filename?: true,
  include_file_line?: true

