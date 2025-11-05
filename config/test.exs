import Config

# Configure JUnit formatter for test reporting - Web module
config :junit_formatter,
  report_file: "test-junit-report.xml",
  report_dir: "_build/test/lib/web",
  print_report_file: true,
  prepend_project_name?: true,
  include_filename?: true,
  include_file_line?: true
