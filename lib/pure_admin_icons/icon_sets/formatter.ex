defmodule PureAdminIcons.IconSets.Formatter do
  @moduledoc """
  Behaviour and dispatcher for icon-set-specific identifier and package formatting.

  Each icon set implements this behaviour in its own module under `PureAdminIcons.IconSets.*`.
  The LiveView and other consumers call functions on this dispatcher, which routes to the
  correct module based on the icon's `icon_set_code`.

  Adding a new icon set:
  1. Create `lib/pure_admin_icons/icon_sets/{name}.ex` implementing this behaviour
  2. Register it in `@formatters` below
  3. No changes needed in the LiveView
  """

  @type icon :: %{
          required(:icon_set_code) => String.t(),
          required(:name) => String.t(),
          required(:style_code) => String.t(),
          required(:sizes) => [integer()],
          optional(any()) => any()
        }

  @type package :: {name :: String.t() | nil, url :: String.t() | nil}

  # ---- Identifiers ----
  @callback react_identifier(icon, size :: integer()) :: String.t() | nil
  @callback vue_identifier(icon, size :: integer()) :: String.t() | nil
  @callback svelte_identifier(icon, size :: integer()) :: String.t() | nil
  @callback cssclass_identifier(icon, size :: integer()) :: String.t() | nil
  @callback htmltag_identifier(icon, size :: integer()) :: String.t() | nil

  # ---- Packages (npm name + URL) ----
  @callback react_package(icon) :: package
  @callback vue_package(icon) :: package
  @callback svelte_package(icon) :: package
  @callback cssclass_package(icon) :: package
  @callback ios_package(icon) :: package
  @callback android_package(icon) :: package

  # ---- Sizes that vary the identifier (for the per-size loop in the modal) ----
  @callback react_identifier_sizes(icon) :: [integer()]
  @callback vue_identifier_sizes(icon) :: [integer()]
  @callback svelte_identifier_sizes(icon) :: [integer()]

  # htmltag_identifier is optional — default implementation wraps the cssclass
  # in `<i class="...">`. Override per-set when a different element / content
  # is canonical (Material Symbols use `<span class="…">ligature</span>`).
  @optional_callbacks [htmltag_identifier: 2]

  # Registry: icon_set_code → formatter module
  @formatters %{
    "fluentui" => PureAdminIcons.IconSets.Fluentui,
    "fontawesome" => PureAdminIcons.IconSets.Fontawesome,
    "heroicons" => PureAdminIcons.IconSets.Heroicons,
    "lucide" => PureAdminIcons.IconSets.Lucide,
    "material" => PureAdminIcons.IconSets.Material,
    "tabler" => PureAdminIcons.IconSets.Tabler,
    "bootstrap" => PureAdminIcons.IconSets.Bootstrap,
    "simpleicons" => PureAdminIcons.IconSets.Simpleicons,
    "carbon" => PureAdminIcons.IconSets.Carbon,
    "phosphor" => PureAdminIcons.IconSets.Phosphor,
    "remix" => PureAdminIcons.IconSets.Remix,
    "solar" => PureAdminIcons.IconSets.Solar,
    "mingcute" => PureAdminIcons.IconSets.Mingcute
  }

  @doc """
  Get the formatter module for an icon (or icon_set_code string).
  Returns the Generic formatter as fallback.
  """
  def for_icon(%{icon_set_code: code}), do: for_set(code)

  def for_set(code) when is_binary(code),
    do: Map.get(@formatters, code, PureAdminIcons.IconSets.Generic)

  def for_set(_), do: PureAdminIcons.IconSets.Generic

  # ---- Dispatch helpers ----

  def react_identifier(icon, size), do: for_icon(icon).react_identifier(icon, size)
  def vue_identifier(icon, size), do: for_icon(icon).vue_identifier(icon, size)
  def svelte_identifier(icon, size), do: for_icon(icon).svelte_identifier(icon, size)
  def cssclass_identifier(icon, size), do: for_icon(icon).cssclass_identifier(icon, size)

  def htmltag_identifier(icon, size) do
    mod = for_icon(icon)

    if function_exported?(mod, :htmltag_identifier, 2) do
      mod.htmltag_identifier(icon, size)
    else
      case cssclass_identifier(icon, size) do
        nil -> nil
        class -> ~s(<i class="#{class}"></i>)
      end
    end
  end

  def react_package(icon), do: for_icon(icon).react_package(icon)
  def vue_package(icon), do: for_icon(icon).vue_package(icon)
  def svelte_package(icon), do: for_icon(icon).svelte_package(icon)
  def cssclass_package(icon), do: for_icon(icon).cssclass_package(icon)
  def htmltag_package(icon), do: cssclass_package(icon)
  def ios_package(icon), do: for_icon(icon).ios_package(icon)
  def android_package(icon), do: for_icon(icon).android_package(icon)

  def react_identifier_sizes(icon) do
    if scalable?(icon), do: [0], else: for_icon(icon).react_identifier_sizes(icon)
  end

  def vue_identifier_sizes(icon) do
    if scalable?(icon), do: [0], else: for_icon(icon).vue_identifier_sizes(icon)
  end

  def svelte_identifier_sizes(icon) do
    if scalable?(icon), do: [0], else: for_icon(icon).svelte_identifier_sizes(icon)
  end

  def cssclass_identifier_sizes(icon) do
    if scalable?(icon), do: [0], else: [List.first(icon.sizes) || 24]
  end

  def htmltag_identifier_sizes(icon) do
    if scalable?(icon), do: [0], else: [List.first(icon.sizes) || 24]
  end

  defp scalable?(%{has_single_source: true}), do: true
  defp scalable?(_), do: false
end
