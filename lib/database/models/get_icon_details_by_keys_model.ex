# This code has been auto-generated
# Changes to this file will be lost on next generation

defmodule Database.Models.GetIconDetailsByKeysModel do
  @moduledoc """
  Model representing the result of public.get_icon_details_by_keys
  """

  @fields [
    :request_index,
    :icon_id,
    :icon_set_code,
    :icon_set_title,
    :name,
    :nrm_name,
    :style_code,
    :sizes,
    :has_single_source,
    :is_scalable,
    :filenames
  ]

  @enforce_keys @fields

  @derive Jason.Encoder
  defstruct @fields

  @type t() :: %__MODULE__{
    request_index: integer(),
    icon_id: integer(),
    icon_set_code: String.t(),
    icon_set_title: String.t(),
    name: String.t(),
    nrm_name: String.t(),
    style_code: String.t(),
    sizes: list(integer()),
    has_single_source: boolean(),
    is_scalable: boolean(),
    filenames: map() | list()
  }

  use Accessible
end
