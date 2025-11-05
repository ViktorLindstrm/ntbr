import Config

# Configure JUnit formatter for test reporting
config :junit_formatter,
  report_file: "test-junit-report.xml",
  report_dir: "_build/test/lib/ntbr_core",
  print_report_file: true,
  prepend_project_name?: true,
  include_filename?: true,
  include_file_line?: true
