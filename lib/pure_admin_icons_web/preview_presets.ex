defmodule PureAdminIconsWeb.PreviewPresets do
  @moduledoc """
  Shared source of the icon preview colour presets and their button styling.

  The presets are loaded from `priv/preview_presets.json` at compile time and
  used by the search page (QuickPresets picker) and the icon detail modal
  (ColorPicker). Keeping them here avoids loading the JSON — and duplicating the
  style helper — in every consumer.
  """

  @presets :pure_admin_icons
           |> :code.priv_dir()
           |> Path.join("preview_presets.json")
           |> File.read!()
           |> Jason.decode!()
  @external_resource Path.join(:code.priv_dir(:pure_admin_icons), "preview_presets.json")

  @doc "The full list of preview presets (maps with \"key\", \"label\", \"color\", \"bg\")."
  def all, do: @presets

  @doc "Inline `style` string for a preset button/swatch background + text colour."
  def button_style(%{"bg" => "checker", "color" => color}) do
    "background-image: repeating-conic-gradient(#e5e7eb 0% 25%, #fff 0% 50%); background-size: 8px 8px; color: #{color};"
  end

  def button_style(%{"bg" => bg, "color" => color}) do
    "background-color: #{bg}; color: #{color};"
  end
end
