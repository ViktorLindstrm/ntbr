defmodule NTBR.Domain do
  use Ash.Domain

  resources do
    # Spinel Protocol Resources 
    resource NTBR.Domain.Spinel.Resources.PropertyState
    resource NTBR.Domain.Spinel.Resources.CommandLog
    
    # Thread Network Resources
    resource NTBR.Domain.Resources.Network
    resource NTBR.Domain.Resources.Device
    resource NTBR.Domain.Resources.BorderRouter
    resource NTBR.Domain.Resources.Joiner
  end
end
