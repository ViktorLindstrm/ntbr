defmodule NTBR.Infra.MixProject do
  use Mix.Project

  def project do
    [
      app: :ntbr_infra,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      
      # Test configuration
      test_paths: ["test"],
      test_pattern: "*_test.exs",
      
      # Config
      config_path: "config/config.exs"
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {NTBR.Infra.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:junit_formatter, "~> 3.3", only: :test}
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end
end
