defmodule NTBR.Domain.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/your_org/ntbr"

  def project do
    [
      app: :ntbr_domain,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),

      # Documentation
      name: "NTBR Domain",
      source_url: @source_url,
      docs: docs(),

      # Testing
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        quality: :test
      ],
      test_paths: ["test"],
      test_pattern: "*_test.exs",

      # Dialyzer
      dialyzer: dialyzer()
    ]
  end

  def application do
    [
      mod: {NTBR.Domain.Application, []},
      extra_applications: [:logger, :crypto, :runtime_tools]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # ========================================
      # Ash Framework - Domain Logic
      # ========================================
      {:ash, "~> 3.7.6"},
      {:ash_state_machine, "~> 0.2"},

      # Data Layers for Ash Resources
      # Optional: if you want persistence
      {:ash_postgres, "~> 2.4", optional: true},
      # Note: ETS data layer is built into Ash
      #Diagrams
      {:ash_diagram, "~> 0.2.0"},
      {:ex_cmd, "~> 0.16.0"},
      {:req, "~> 0.5.15"},

      # ========================================
      # Hardware Communication
      # ========================================
      {:circuits_uart, "~> 1.5"},

      # ========================================
      # Infrastructure
      # ========================================
      {:phoenix_pubsub, "~> 2.1"},
      {:jason, "~> 1.4"},
      {:telemetry, "~> 1.2"},

      # ========================================
      # Utilities
      # ========================================
      {:nimble_options, "~> 1.1"},
      {:typed_struct, "~> 0.3"},

      # ========================================
      # Development Tools
      # ========================================
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},

      # ========================================
      # Testing
      # ========================================
      {:propcheck, "~> 1.5", only: :test},
      # {:stream_data, "~> 1.1", only: :test},
      {:mox, "~> 1.1", only: :test},
      {:excoveralls, "~> 0.18", only: :test},
      {:junit_formatter, "~> 3.3", only: :test}
    ]
  end

  defp aliases do
    [
      # Run all quality checks
      quality: [
        "format --check-formatted",
        "deps.unlock --check-unused",
        "compile --warnings-as-errors",
        "test",
        "credo --strict",
        "dialyzer"
      ],

      # Setup for first time
      setup: ["deps.get", "deps.compile"],

      # Quick tests
      "test.quick": ["test --exclude slow"],
      "test.property": ["test --only property"],

      # Type checking
      "dialyzer.explain": ["dialyzer --format dialyxir"]
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: [
        "README.md": [title: "Overview"],
        "ARCHITECTURE.md": [title: "Architecture"],
        "CHANGELOG.md": [title: "Changelog"]
      ],
      groups_for_modules: [
        "Spinel Protocol": [
          NTBR.Domain.Spinel.Frame,
          NTBR.Domain.Spinel.Command,
          NTBR.Domain.Spinel.Property,
          NTBR.Domain.Spinel.DataEncoder,
          NTBR.Domain.Spinel.Client,
          NTBR.Domain.Spinel.UART
        ],
        "Spinel Resources": [
          NTBR.Domain.Spinel.Resources.PropertyState,
          NTBR.Domain.Spinel.Resources.CommandLog,
          NTBR.Domain.Spinel.Resources.Frame
        ],
        "Thread Network": [
          NTBR.Domain.Thread.NetworkManager,
          NTBR.Domain.Thread.TopologyManager
        ],
        "Domain Resources": [
          NTBR.Domain.Resources.Network,
          NTBR.Domain.Resources.Device,
          NTBR.Domain.Resources.BorderRouter,
          NTBR.Domain.Resources.Joiner
        ],
        "Calculations & Validations": [
          NTBR.Domain.Calculations.NetworkDataset,
          NTBR.Domain.Validations.TidRange,
          NTBR.Domain.Validations.ValidCommand
        ]
      ]
    ]
  end

  defp dialyzer do
    [
      plt_add_apps: [:ex_unit, :mix],
      plt_core_path: "priv/plts",
      plt_local_path: "priv/plts",
      flags: [
        :unmatched_returns,
        :error_handling,
        :underspecs
      ],
      # Ignore warnings from dependencies
      ignore_warnings: ".dialyzer_ignore.exs",
      list_unused_filters: true
    ]
  end
end
