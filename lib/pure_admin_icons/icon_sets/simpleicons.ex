defmodule PureAdminIcons.IconSets.Simpleicons do
  @moduledoc """
  Identifier and package formatting for Simple Icons.

  - React: `@icons-pack/react-simple-icons` (`<SiGithub />`, `Si` + PascalCase of
    the brand slug)

  The component name derives from the Simple Icons *slug*, not the display title
  (`.NET` -> `dotnet` -> `SiDotnet`). We recover the slug from the stored filename,
  since the display name alone can't reconstruct it. No official Vue/Svelte/CSS or
  native mobile package is wired up.
  """
  @behaviour PureAdminIcons.IconSets.Formatter

  alias PureAdminIcons.Naming

  @impl true
  def react_identifier(icon, _size) do
    comp = "Si" <> Naming.pascal_case(slug(icon))
    "import { #{comp} } from '@icons-pack/react-simple-icons'\n<#{comp} />"
  end

  @impl true
  def vue_identifier(_icon, _size), do: nil

  @impl true
  def svelte_identifier(_icon, _size), do: nil

  @impl true
  def cssclass_identifier(_icon, _size), do: nil

  @impl true
  def react_package(_) do
    {"@icons-pack/react-simple-icons",
     "https://www.npmjs.com/package/@icons-pack/react-simple-icons"}
  end

  @impl true
  def vue_package(_), do: {nil, nil}

  @impl true
  def svelte_package(_), do: {nil, nil}

  @impl true
  def cssclass_package(_), do: {nil, nil}

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

  # The stored filename is `{slug}.svg`; recover the slug from it. Falls back to a
  # kebab of the display name if filenames are unavailable.
  defp slug(%{filenames: filenames}) when is_map(filenames) and map_size(filenames) > 0 do
    filenames |> Map.values() |> List.first() |> to_string() |> String.replace_suffix(".svg", "")
  end

  defp slug(icon), do: Naming.kebab_case(icon.name)
end
