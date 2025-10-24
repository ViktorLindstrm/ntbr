defmodule Core.MixProject do
  use Mix.Project

  def project do
    [
      app: :core,
      version: "0.1.0",
      build_path: "../_build",
      config_path: "../config/config.exs",
      deps_path: "../deps",
      lockfile: "../mix.lock",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      
      # Docs
      name: "NTBR Core",
      docs: [
        main: "Core",
        extras: ["README.md"]
      ],
      
      # Dialyzer
      dialyzer: [
        plt_file: {:no_warn, "../priv/plts/core.plt"},
        plt_add_apps: [:mix, :ex_unit],
        flags: [:unmatched_returns, :error_handling, :underspecs]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :runtime_tools],
      mod: {Core.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Internal dependencies
      {:domain, in_umbrella: true},
      {:infra, in_umbrella: true},
      
      # Ash Framework
      {:ash, "~> 3.0"},
      {:ash_graphql, "~> 1.0"},
      {:ash_json_api, "~> 1.0"},
      
      # Development and testing
      {:propcheck, "~> 1.5", only: :test},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      test: "test --no-start"
    ]
  end
end
