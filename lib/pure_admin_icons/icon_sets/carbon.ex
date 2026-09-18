defmodule PureAdminIcons.IconSets.Carbon do
  @moduledoc """
  Identifier and package formatting for Carbon Icons.

  - React: `@carbon/icons-react` (`<Add size={32} />`, PascalCase; filled variants
    append `Filled`, e.g. `WarningFilled`)
  - Svelte: `carbon-icons-svelte` (`import Add from "carbon-icons-svelte/lib/Add.svelte"`)

  Component names are the PascalCase of the icon name (`accessibility--color` ->
  `AccessibilityColor`) plus `Filled` for the filled style. Number-leading names get
  a `_` prefix and keep their original casing, matching Carbon (`4K` -> `_4K`,
  `4K--filled` -> `_4KFilled`) — so the component derives from the source slug (via
  the stored filename), not the lowercased display name. No official Vue/CSS or
  native mobile package is wired up here.
  """
  @behaviour PureAdminIcons.IconSets.Formatter

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

  # Carbon component name: PascalCase of the source slug (original casing preserved),
  # `_` prefix for number-leading names, `Filled` suffix for the filled style.
  defp component(icon) do
    base = icon |> slug() |> pascalize()
    base = if String.match?(base, ~r/\A\d/), do: "_" <> base, else: base
    if icon.style_code == "filled", do: base <> "Filled", else: base
  end

  # The stored filename is `{slug}.svg` and keeps the source casing (e.g. `4K.svg`).
  defp slug(%{filenames: filenames}) when is_map(filenames) and map_size(filenames) > 0 do
    filenames |> Map.values() |> List.first() |> to_string() |> String.replace_suffix(".svg", "")
  end

  defp slug(icon), do: icon.name

  # Capitalize the first char of each `--`/`-`/space-separated word, preserving the
  # rest (unlike Naming.pascal_case, which downcases it — losing `4K`'s uppercase K).
  defp pascalize(str) do
    str
    |> String.split(~r/[-_\s]+/, trim: true)
    |> Enum.map_join("", &upcase_first/1)
  end

  defp upcase_first(<<first::utf8, rest::binary>>), do: String.upcase(<<first::utf8>>) <> rest
  defp upcase_first(""), do: ""
end
