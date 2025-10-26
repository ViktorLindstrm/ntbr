# PropCheck configuration for property-based tests
# Note: PropCheck 1.5 starts automatically - no need to call PropCheck.start()
Application.put_env(:propcheck, :verbose, true)
Application.put_env(:propcheck, :numtests, System.get_env("PROPCHECK_NUMTESTS", "100") |> String.to_integer())
Application.put_env(:propcheck, :search_steps, System.get_env("PROPCHECK_SEARCH_STEPS", "10000") |> String.to_integer())

ExUnit.start()

IO.puts("\n=== Domain Test Configuration ===")
IO.puts("PropCheck iterations: #{Application.get_env(:propcheck, :numtests)}")
IO.puts("Search steps: #{Application.get_env(:propcheck, :search_steps)}")
IO.puts("=================================\n")
