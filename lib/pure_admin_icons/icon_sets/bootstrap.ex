defmodule PureAdminIcons.IconSets.Bootstrap do
  @moduledoc """
  Identifier and package formatting for Bootstrap Icons.

  - React: `react-bootstrap-icons` (`<HeartFill />`, PascalCase; `Icon` prefix for
    number-leading names, e.g. `Icon1Circle`)
  - Vue: `bootstrap-icons-vue` (`<BIconHeartFill />`)
  - CSS class: `bootstrap-icons` webfont (`<i class="bi bi-heart-fill"></i>`)

  Filled variants append `Fill` (React/Vue) or `-fill` (CSS). No official Svelte
  or native mobile package.
  """
  @behaviour PureAdminIcons.IconSets.Formatter

  alias PureAdminIcons.Naming

  @impl true
  def react_identifier(icon, _size) do
    comp = react_component(icon)
    "import { #{comp} } from 'react-bootstrap-icons'\n<#{comp} />"
  end

  @impl true
  def vue_identifier(icon, _size) do
    comp = "BIcon" <> pascal_with_fill(icon)
    "import { #{comp} } from 'bootstrap-icons-vue'\n<#{comp} />"
  end

  @impl true
  def svelte_identifier(_icon, _size), do: nil

  @impl true
  def cssclass_identifier(icon, _size) do
    suffix = if icon.style_code == "filled", do: "-fill", else: ""
    "bi bi-#{Naming.kebab_case(icon.name)}#{suffix}"
  end

  @impl true
  def react_package(_),
    do: {"react-bootstrap-icons", "https://www.npmjs.com/package/react-bootstrap-icons"}

  @impl true
  def vue_package(_),
    do: {"bootstrap-icons-vue", "https://www.npmjs.com/package/bootstrap-icons-vue"}

  @impl true
  def svelte_package(_), do: {nil, nil}

  @impl true
  def cssclass_package(_), do: {"bootstrap-icons", "https://www.npmjs.com/package/bootstrap-icons"}

  @impl true
  def ios_package(_), do: {nil, nil}

  @impl true
  def android_package(_), do: {nil, nil}

  @impl true
  def react_identifier_sizes(icon), do: [List.first(icon.sizes) || 16]

  @impl true
  def vue_identifier_sizes(icon), do: [List.first(icon.sizes) || 16]

  @impl true
  def svelte_identifier_sizes(icon), do: [List.first(icon.sizes) || 16]

  # PascalCase name + `Fill` for the filled style.
  defp pascal_with_fill(icon) do
    base = Naming.pascal_case(icon.name)
    if icon.style_code == "filled", do: base <> "Fill", else: base
  end

  # react-bootstrap-icons prefixes number-leading names with `Icon`
  # (e.g. `1-circle` -> `Icon1Circle`).
  defp react_component(icon) do
    base = Naming.pascal_case(icon.name)
    base = if String.match?(base, ~r/\A\d/), do: "Icon" <> base, else: base
    if icon.style_code == "filled", do: base <> "Fill", else: base
  end
end
