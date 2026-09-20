defmodule PureAdminIcons.IconSets.Mingcute do
  @moduledoc """
  Identifier and package formatting for MingCute Icons.

  MingCute ships an icon font and SVGs but no first-party component libraries,
  so integration goes through Iconify:

  - React:  `@iconify/react`  (`<Icon icon="mingcute:align-arrow-down-line" />`)
  - Vue:    `@iconify/vue`
  - Svelte: `@iconify/svelte`
  - CSS:    `@iconify/tailwind` class (`icon-[mingcute--align-arrow-down-line]`)

  Iconify names are `mingcute:{kebab-name}-{style-suffix}` where the suffix is
  `line` for outline and `fill` for filled.
  """
  @behaviour PureAdminIcons.IconSets.Formatter

  alias PureAdminIcons.Naming

  @prefix "mingcute"

  @impl true
  def react_identifier(icon, _size) do
    "import { Icon } from '@iconify/react'\n<Icon icon=\"#{iconify_name(icon)}\" />"
  end

  @impl true
  def vue_identifier(icon, _size) do
    "import { Icon } from '@iconify/vue'\n<Icon icon=\"#{iconify_name(icon)}\" />"
  end

  @impl true
  def svelte_identifier(icon, _size) do
    "import Icon from '@iconify/svelte'\n<Icon icon=\"#{iconify_name(icon)}\" />"
  end

  @impl true
  def cssclass_identifier(icon, _size) do
    "icon-[#{@prefix}--#{slug(icon)}-#{suffix(icon.style_code)}]"
  end

  @impl true
  def react_package(_), do: {"@iconify/react", "https://www.npmjs.com/package/@iconify/react"}

  @impl true
  def vue_package(_), do: {"@iconify/vue", "https://www.npmjs.com/package/@iconify/vue"}

  @impl true
  def svelte_package(_), do: {"@iconify/svelte", "https://www.npmjs.com/package/@iconify/svelte"}

  @impl true
  def cssclass_package(_),
    do: {"@iconify/tailwind", "https://www.npmjs.com/package/@iconify/tailwind"}

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

  # mingcute:{kebab-name}-{style-suffix}
  defp iconify_name(icon), do: "#{@prefix}:#{slug(icon)}-#{suffix(icon.style_code)}"

  defp slug(icon), do: Naming.kebab_case(icon.name)

  defp suffix("filled"), do: "fill"
  defp suffix(_), do: "line"
end
