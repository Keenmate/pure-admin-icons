defmodule PureAdminIcons.IconSets.Phosphor do
  @moduledoc """
  Identifier and package formatting for Phosphor Icons.

  Phosphor encodes the style as a `weight` prop / class prefix, not as part of the
  component name — the same icon renders any weight:

  - React: `@phosphor-icons/react` (`<HeartIcon weight="fill" />`, PascalCase + `Icon`)
  - Vue: `@phosphor-icons/vue` (`<PhHeart weight="fill" />`, `Ph` + PascalCase)
  - Svelte: `phosphor-svelte` (`<HeartIcon weight="fill" />`, PascalCase + `Icon`)
  - CSS class: `@phosphor-icons/web` (`<i class="ph-fill ph-heart"></i>`)

  Our style codes map to Phosphor weights: `filled` -> `fill`, everything else is
  its own weight (`thin`/`light`/`regular`/`bold`/`duotone`). `regular` is the
  default, so its snippets omit the weight.
  """
  @behaviour PureAdminIcons.IconSets.Formatter

  alias PureAdminIcons.Naming

  @weights %{
    "thin" => "thin",
    "light" => "light",
    "regular" => "regular",
    "bold" => "bold",
    "filled" => "fill",
    "duotone" => "duotone"
  }

  @impl true
  def react_identifier(icon, _size) do
    comp = Naming.pascal_case(icon.name) <> "Icon"
    "import { #{comp} } from '@phosphor-icons/react'\n<#{comp}#{weight_attr(icon)} />"
  end

  @impl true
  def vue_identifier(icon, _size) do
    comp = "Ph" <> Naming.pascal_case(icon.name)
    "import { #{comp} } from '@phosphor-icons/vue'\n<#{comp}#{weight_attr(icon)} />"
  end

  @impl true
  def svelte_identifier(icon, _size) do
    comp = Naming.pascal_case(icon.name) <> "Icon"
    "import { #{comp} } from 'phosphor-svelte'\n<#{comp}#{weight_attr(icon)} />"
  end

  @impl true
  def cssclass_identifier(icon, _size) do
    "#{ph_prefix(icon)} ph-#{Naming.kebab_case(icon.name)}"
  end

  @impl true
  def react_package(_),
    do: {"@phosphor-icons/react", "https://www.npmjs.com/package/@phosphor-icons/react"}

  @impl true
  def vue_package(_),
    do: {"@phosphor-icons/vue", "https://www.npmjs.com/package/@phosphor-icons/vue"}

  @impl true
  def svelte_package(_), do: {"phosphor-svelte", "https://www.npmjs.com/package/phosphor-svelte"}

  @impl true
  def cssclass_package(_),
    do: {"@phosphor-icons/web", "https://www.npmjs.com/package/@phosphor-icons/web"}

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

  defp weight(icon), do: Map.get(@weights, icon.style_code, "regular")

  # `regular` is the component default — omit the prop for it.
  defp weight_attr(icon) do
    case weight(icon) do
      "regular" -> ""
      w -> ~s( weight="#{w}")
    end
  end

  # Webfont class prefix: `ph` (regular) or `ph-<weight>`.
  defp ph_prefix(icon) do
    case weight(icon) do
      "regular" -> "ph"
      w -> "ph-#{w}"
    end
  end
end
