defmodule PureAdminIcons.IconSets.Solar do
  @moduledoc """
  Identifier and package formatting for Solar Icons.

  Solar ships no first-party component libraries, so integration goes through
  Iconify (the de-facto distribution channel for the set):

  - React:  `@iconify/react`  (`<Icon icon="solar:black-hole-linear" />`)
  - Vue:    `@iconify/vue`
  - Svelte: `@iconify/svelte`
  - CSS:    `@iconify/tailwind` class (`icon-[solar--black-hole-linear]`)

  Iconify names are `solar:{kebab-name}-{style-suffix}`; our canonical style codes
  map back to Solar's native suffixes (outline->linear, filled->bold,
  duotone->bold-duotone, thin->outline, and line-duotone/broken verbatim).
  """
  @behaviour PureAdminIcons.IconSets.Formatter

  alias PureAdminIcons.Naming

  @prefix "solar"

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

  # solar:{kebab-name}-{style-suffix}
  defp iconify_name(icon), do: "#{@prefix}:#{slug(icon)}-#{suffix(icon.style_code)}"

  defp slug(icon), do: Naming.kebab_case(icon.name)

  # Canonical style code -> Solar's native Iconify suffix.
  defp suffix("outline"), do: "linear"
  defp suffix("filled"), do: "bold"
  defp suffix("duotone"), do: "bold-duotone"
  defp suffix("line-duotone"), do: "line-duotone"
  defp suffix("broken"), do: "broken"
  defp suffix("thin"), do: "outline"
  defp suffix(_), do: "linear"
end
