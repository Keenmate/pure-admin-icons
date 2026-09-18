defmodule PureAdminIcons.IconSets.Remix do
  @moduledoc """
  Identifier and package formatting for Remix Icon.

  - React: `@remixicon/react` (`<RiHeartFill />`, `Ri` + PascalCase + `Line`/`Fill`)
  - CSS class: `remixicon` webfont (`<i class="ri-heart-fill"></i>`)

  Remix bakes the style into the name via its native suffixes: our `outline` ->
  `line`, `filled` -> `fill`. No official Vue/Svelte or native mobile package is
  wired up here.
  """
  @behaviour PureAdminIcons.IconSets.Formatter

  alias PureAdminIcons.Naming

  @impl true
  def react_identifier(icon, _size) do
    comp = "Ri" <> Naming.pascal_case(icon.name) <> String.capitalize(native(icon))
    "import { #{comp} } from '@remixicon/react'\n<#{comp} />"
  end

  @impl true
  def vue_identifier(_icon, _size), do: nil

  @impl true
  def svelte_identifier(_icon, _size), do: nil

  @impl true
  def cssclass_identifier(icon, _size) do
    "ri-#{Naming.kebab_case(icon.name)}-#{native(icon)}"
  end

  @impl true
  def react_package(_), do: {"@remixicon/react", "https://www.npmjs.com/package/@remixicon/react"}

  @impl true
  def vue_package(_), do: {nil, nil}

  @impl true
  def svelte_package(_), do: {nil, nil}

  @impl true
  def cssclass_package(_), do: {"remixicon", "https://www.npmjs.com/package/remixicon"}

  @impl true
  def ios_package(_), do: {nil, nil}

  @impl true
  def android_package(_), do: {nil, nil}

  @impl true
  def react_identifier_sizes(icon), do: [List.first(icon.sizes) || 24]

  @impl true
  def vue_identifier_sizes(icon), do: [List.first(icon.sizes) || 24]

  @impl true
  def svelte_identifier_sizes(icon), do: [List.first(icon.sizes) || 24]

  # Remix's native style suffix: outline -> "line", filled -> "fill".
  defp native(icon), do: if(icon.style_code == "filled", do: "fill", else: "line")
end
