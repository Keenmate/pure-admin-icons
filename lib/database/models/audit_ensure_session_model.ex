# This code has been auto-generated
# Changes to this file will be lost on next generation

defmodule Database.Models.AuditEnsureSessionModel do
  @moduledoc """
  Model representing the result of audit.ensure_session
  """

  @fields [
    :ensure_session
  ]

  @enforce_keys @fields

  @derive Jason.Encoder
  defstruct @fields

  @type t() :: %__MODULE__{
    ensure_session: String.t()
  }

  use Accessible
end
