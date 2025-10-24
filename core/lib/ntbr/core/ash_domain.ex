defmodule Core.AshDomain do
  @moduledoc """
  Ash Domain for the NTBR Border Router core resources.
  
  This domain provides the main API surface for interacting with Thread
  network state, Spinel protocol frames, and RCP status.
  
  ## Resources
  
  - `Core.Resources.ThreadNetwork` - Thread network state and operations
  - `Core.Resources.SpinelFrame` - Spinel protocol frame capture and analysis
  - `Core.Resources.RCPStatus` - RCP connection and health monitoring
  
  ## Usage
  
      # Direct resource access
      Core.Resources.ThreadNetwork.read_all!()
      
      # Via domain
      Core.AshDomain.read!(Core.Resources.ThreadNetwork)
  """
  
  use Ash.Domain,
    extensions: [
      AshGraphql.Domain,
      AshJsonApi.Domain
    ]

  resources do
    resource Core.Resources.ThreadNetwork do
      define :create_network, action: :create
      define :read_network, action: :read, args: [:id]
      define :list_networks, action: :read_all
      define :update_network, action: :update
      define :form_network, action: :form_network, args: [:dataset]
      define :attach_to_network, action: :attach, args: [:dataset]
    end

    resource Core.Resources.SpinelFrame do
      define :capture_frame, action: :capture
      define :recent_frames, action: :recent, args: [:limit, :direction]
      define :frames_by_network, action: :by_network, args: [:network_id]
      define :frames_by_command, action: :by_command, args: [:command]
      define :frames_with_errors, action: :with_errors
      define :frame_statistics, action: :statistics
    end

    resource Core.Resources.RCPStatus do
      define :current_status, action: :current
      define :update_status, action: :update
      define :connection_history, action: :history, args: [:hours]
    end
  end

  # Optional: Authorization policies
  # policies do
  #   policy action_type(:read) do
  #     authorize_if always()
  #   end
  #   
  #   policy action_type([:create, :update, :destroy]) do
  #     authorize_if actor_attribute_equals(:role, :admin)
  #   end
  # end
end
