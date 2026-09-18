defmodule PureAdminIcons.Icons.Icon do
  @moduledoc """
  Icon struct and URL helper functions.
  Works with both the generated Database.Models.SearchIconsModel and other icon data.
  """

  @icon_sets ~w(fluentui lucide tabler heroicons fontawesome phosphor bootstrap remix material simpleicons carbon)

  # Define struct matching the database model fields
  defstruct [
    :icon_id,
    :icon_set_code,
    :name,
    :name_lower,
    :style_code,
    :sizes,
    :filenames,
    :ios_identifiers,
    :android_identifiers,
    :categories,
    # Search result fields
    :rank,
    :similarity,
    :total_items,
    :icon_set_title
  ]

  @doc "List of supported icon sets"
  def icon_sets, do: @icon_sets

  @doc """
  Get the configured icons directory path.
  Returns nil if not configured (use GitHub fallback).
  """
  def icons_dir do
    Application.get_env(:pure_admin_icons, :icons_path)
  end

  @doc """
  Generate SVG URL for an icon at a specific size.
  Returns nil if the filename is not available for the given size.
  For scalable icons, the size argument is ignored — there's only one SVG file.
  """
  def svg_url(icon, size) do
    case svg_filename(icon, size) do
      nil -> nil
      filename ->
        icon_set = get_icon_set(icon)
        style = get_style(icon)
        "/icons/#{icon_set}/#{style}/#{filename}"
    end
  end

  @doc """
  Generate the GitHub raw URL for an icon SVG.
  Only works for FluentUI icons - other icon sets should use local storage.
  """
  def github_svg_url(icon, size) do
    case get_icon_set(icon) do
      "fluentui" ->
        name = get_name(icon)
        style = get_style(icon)
        slug = name |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "_") |> String.trim("_")
        encoded_name = URI.encode(name)
        "https://raw.githubusercontent.com/microsoft/fluentui-system-icons/main/assets/#{encoded_name}/SVG/ic_fluent_#{slug}_#{size}_#{style}.svg"

      _ ->
        # Other icon sets don't have a GitHub fallback URL structure
        nil
    end
  end

  @doc """
  Get the local file system path for an icon SVG.
  Returns nil if icons_path is not configured.
  """
  def local_svg_path(icon, size) do
    case {icons_dir(), svg_filename(icon, size)} do
      {nil, _} -> nil
      {_, nil} -> nil
      {dir, filename} ->
        icon_set = get_icon_set(icon)
        style = get_style(icon)
        Path.join([dir, icon_set, style, filename])
    end
  end

  @doc """
  Generate the SVG filename for an icon at a specific size.
  Looks up the `filenames` map (keyed by size as string).
  For scalable icons, the size argument is ignored and the first available filename is returned.
  """
  def svg_filename(icon, size) do
    filenames = get_filenames(icon)

    cond do
      scalable?(icon) ->
        case Enum.find_value(filenames, fn {_k, v} -> v end) do
          nil -> nil
          filename -> filename
        end

      true ->
        size_key = to_string(size)
        case filenames do
          %{^size_key => filename} -> filename
          _ -> nil
        end
    end
  end

  @doc """
  Returns the per-size identifier map for a platform (e.g. "ios", "android").
  Reads from the new `platform_identifiers` jsonb if present, falls back to the
  legacy per-platform fields (`ios_identifiers`/`android_identifiers`) so the
  helper works during the schema transition.
  """
  def platform_ids(icon, platform) when is_binary(platform) do
    case get_platform_map(icon) do
      pi when is_map(pi) and map_size(pi) > 0 ->
        Map.get(pi, platform, %{})

      _ ->
        legacy_platform_ids(icon, platform)
    end
  end

  defp get_platform_map(%{platform_identifiers: pi}), do: pi
  defp get_platform_map(%{"platform_identifiers" => pi}), do: pi
  defp get_platform_map(_), do: nil

  defp legacy_platform_ids(%{ios_identifiers: m}, "ios") when is_map(m), do: m
  defp legacy_platform_ids(%{"ios_identifiers" => m}, "ios") when is_map(m), do: m
  defp legacy_platform_ids(%{android_identifiers: m}, "android") when is_map(m), do: m
  defp legacy_platform_ids(%{"android_identifiers" => m}, "android") when is_map(m), do: m
  defp legacy_platform_ids(_, _), do: %{}

  @doc """
  Returns true if the icon has a single source SVG that renders at any size
  (so the size argument is ignored when looking up filenames/identifiers).
  """
  def scalable?(%{has_single_source: true}), do: true
  def scalable?(%{"has_single_source" => true}), do: true
  def scalable?(_), do: false

  # Helper functions to extract fields from various icon representations
  # (struct, map with atom keys, map with string keys)

  defp get_icon_set(%{icon_set_code: code}) when not is_nil(code), do: code
  defp get_icon_set(%{icon_set: set}) when not is_nil(set), do: set
  defp get_icon_set(%{"icon_set_code" => code}) when not is_nil(code), do: code
  defp get_icon_set(%{"icon_set" => set}) when not is_nil(set), do: set
  defp get_icon_set(_), do: "fluentui"

  defp get_style(%{style_code: style}) when not is_nil(style), do: style
  defp get_style(%{style: style}) when not is_nil(style), do: style
  defp get_style(%{"style_code" => style}) when not is_nil(style), do: style
  defp get_style(%{"style" => style}) when not is_nil(style), do: style
  defp get_style(_), do: "regular"

  defp get_name(%{name: name}) when not is_nil(name), do: name
  defp get_name(%{"name" => name}) when not is_nil(name), do: name
  defp get_name(_), do: ""

  defp get_filenames(%{filenames: f}) when is_map(f), do: f
  defp get_filenames(%{"filenames" => f}) when is_map(f), do: f
  defp get_filenames(_), do: %{}
end
