defmodule NTBR.Domain.Application do
  @moduledoc """
  Application supervisor for the NTBR Domain.
  
  Starts the supervision tree for domain-level services:
  - PubSub for event broadcasting
  - NetworkManager (optional, only when needed)
  """
  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    Logger.info("Starting NTBR Domain Application")

    children = [
      # PubSub for domain events
      {Phoenix.PubSub, name: NTBR.PubSub}
      
      # NetworkManager can be started separately when needed
      # {NTBR.Domain.Thread.NetworkManager, []}
    ]

    opts = [strategy: :one_for_one, name: NTBR.Domain.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
