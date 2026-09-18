defmodule PureAdminIcons.IconSets.Carbon do
  @moduledoc """
  Identifier and package formatting for Carbon Icons.

  - React: `@carbon/icons-react` (`<Add size={32} />`, PascalCase; filled variants
    append `Filled`, e.g. `WarningFilled`)
  - Svelte: `carbon-icons-svelte` (`import Add from "carbon-icons-svelte/lib/Add.svelte"`)

  Component names are the PascalCase of the icon name (`accessibility--color` ->
  `AccessibilityColor`) plus `Filled` for the filled style. No official Vue/CSS or
  native mobile package is wired up here.
  """
  @behaviour PureAdminIcons.IconSets.Formatter

  alias PureAdminIcons.Naming

  @impl true
  def react_identifier(icon, _size) do
    comp = component(icon)
    "import { #{comp} } from '@carbon/icons-react'\n<#{comp} size={32} />"
  end

  @impl true
  def vue_identifier(_icon, _size), do: nil

  @impl true
  def svelte_identifier(icon, _size) do
    comp = component(icon)
    ~s(import #{comp} from "carbon-icons-svelte/lib/#{comp}.svelte"\n<#{comp} />)
  end

  @impl true
  def cssclass_identifier(_icon, _size), do: nil

  @impl true
  def react_package(_),
    do: {"@carbon/icons-react", "https://www.npmjs.com/package/@carbon/icons-react"}

  @impl true
  def vue_package(_), do: {nil, nil}

  @impl true
  def svelte_package(_),
    do: {"carbon-icons-svelte", "https://www.npmjs.com/package/carbon-icons-svelte"}

  @impl true
  def cssclass_package(_), do: {nil, nil}

  @impl true
  def ios_package(_), do: {nil, nil}

  @impl true
  def android_package(_), do: {nil, nil}

  @impl true
  def react_identifier_sizes(icon), do: [List.first(icon.sizes) || 32]

  @impl true
  def vue_identifier_sizes(icon), do: [List.first(icon.sizes) || 32]

  @impl true
  def svelte_identifier_sizes(icon), do: [List.first(icon.sizes) || 32]

  # PascalCase name + `Filled` for the filled style.
  defp component(icon) do
    base = Naming.pascal_case(icon.name)
    if icon.style_code == "filled", do: base <> "Filled", else: base
  end
end
