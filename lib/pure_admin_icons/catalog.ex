defmodule PureAdminIcons.Catalog do
  @moduledoc """
  Cached catalog totals — total icon count, icon-set count, and set titles —
  for hot-path rendering: the site header, the page `<title>`, and the
  SEO/OpenGraph meta tags in the root layout.

  Backed by `:persistent_term` so reads never hit the DB. Refreshed after each
  sync via `refresh/0` (see `PureAdminIcons.Sync.Worker.sync_all/1`), and lazily
  on first read if the cache is cold. Mirrors `PureAdminIcons.IconSets.Color`.

  Everything is derived from a single `Icons.list_icon_sets/0` call, since the
  per-set model already carries `icon_count` and `title`.
  """

  alias PureAdminIcons.Icons

  @cache_key {__MODULE__, :stats}

  @doc "Total number of icons across all sets."
  def icon_count, do: stats().icon_count

  @doc "Number of icon sets."
  def set_count, do: stats().set_count

  @doc "Icon-set display titles, in the order returned by the DB."
  def set_titles, do: stats().set_titles

  @doc ~S"""
  Icon count rounded down to the nearest thousand, comma-grouped, with a
  trailing `+` — e.g. `58671` → `"58,000+"`. Used in the page title / meta tags.
  """
  def icon_count_display do
    icon_count()
    |> div(1000)
    |> Kernel.*(1000)
    |> group_thousands()
    |> Kernel.<>("+")
  end

  @doc ~S"""
  Set titles joined as a sentence fragment — e.g. `"A, B & C"` — for the
  meta/OpenGraph description. Empty string when the catalog is empty.
  """
  def set_titles_sentence do
    case set_titles() do
      [] -> ""
      [only] -> only
      titles -> Enum.join(Enum.drop(titles, -1), ", ") <> " & " <> List.last(titles)
    end
  end

  @doc "Full stats map; lazily refreshes from the DB when the cache is cold."
  def stats do
    case :persistent_term.get(@cache_key, nil) do
      nil -> refresh()
      stats -> stats
    end
  end

  @doc "Recompute the cache from the DB. Call after a sync."
  def refresh do
    sets = Icons.list_icon_sets()

    stats = %{
      icon_count: Enum.sum(Enum.map(sets, &(&1.icon_count || 0))),
      set_count: length(sets),
      set_titles: Enum.map(sets, & &1.title)
    }

    :persistent_term.put(@cache_key, stats)
    stats
  end

  # 58000 -> "58,000"
  defp group_thousands(n) when is_integer(n) do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end
end
