defmodule PureAdminIcons.Icons do
  @moduledoc """
  The Icons context - handles searching and querying icons from multiple icon sets.
  Uses PostgreSQL stored functions via Database.DbContext.
  """

  alias PureAdminIcons.Repo
  alias Database.DbContext

  def search(query, opts \\ []) do
    criteria = build_search_criteria(query, opts)
    page = opts[:page] || 1
    page_size = opts[:limit] || 50
    criteria_json = Jason.encode!(criteria)

    case DbContext.search_icons(criteria_json, page, page_size) do
      {:ok, results} -> {:ok, results}
      {:error, _} = error -> error
    end
  end

  def search!(query, opts \\ []) do
    case search(query, opts) do
      {:ok, results} -> results
      {:error, error} -> raise "Search failed: #{inspect(error)}"
    end
  end

  defp build_search_criteria(query, opts) do
    criteria = %{}

    criteria =
      if query && query != "", do: Map.put(criteria, "search_text", query), else: criteria

    criteria =
      case opts[:icon_sets] do
        nil -> criteria
        [] -> criteria
        sets when is_list(sets) -> Map.put(criteria, "icon_sets", sets)
      end

    criteria =
      case opts[:styles] do
        nil -> criteria
        [] -> criteria
        styles when is_list(styles) -> Map.put(criteria, "styles", styles)
      end

    criteria =
      case opts[:sizes] do
        nil ->
          criteria

        [] ->
          criteria

        sizes when is_list(sizes) ->
          # Special: size 0 means "scalable icons only"
          if 0 in sizes do
            criteria = Map.put(criteria, "has_single_source", true)
            # If there are also pixel sizes, include them too
            pixel_sizes = Enum.reject(sizes, &(&1 == 0))

            case pixel_sizes do
              [] -> criteria
              [size | _] -> Map.put(criteria, "size", size)
            end
          else
            [size | _] = sizes
            Map.put(criteria, "size", size)
          end
      end

    criteria =
      case opts[:categories] do
        nil -> criteria
        [] -> criteria
        cats when is_list(cats) -> Map.put(criteria, "categories", cats)
      end

    criteria
  end

  def search_count(query, opts \\ []) do
    case search(query, Keyword.put(opts, :limit, 1)) do
      {:ok, [first | _]} -> first.total_items
      {:ok, []} -> 0
      {:error, _} -> 0
    end
  end

  def count(opts \\ []) do
    icon_set = opts[:icon_set]

    case DbContext.get_icon_count(icon_set || :eg_value_not_provided) do
      {:ok, [%{get_icon_count: count}]} -> count
      {:ok, []} -> 0
      {:error, _} -> 0
    end
  end

  def counts_by_icon_set do
    case DbContext.get_icon_counts_by_set() do
      {:ok, results} ->
        results
        |> Enum.map(fn %{icon_set_code: code, count: count} -> {code, count} end)
        |> Map.new()

      {:error, _} ->
        %{}
    end
  end

  def list_icon_sets(locale \\ nil) do
    lang = locale || PureAdminIcons.Translations.Locale.get()

    case DbContext.get_icon_sets(lang) do
      {:ok, results} -> results
      {:error, _} -> []
    end
  end

  def get_icon!(id) do
    case DbContext.get_icon_detail(id) do
      {:ok, [icon]} -> icon
      {:ok, []} -> raise "Icon not found: #{id}"
      {:error, error} -> raise "Failed to get icon: #{inspect(error)}"
    end
  end

  def get_icon(id) do
    case DbContext.get_icon_detail(id) do
      {:ok, [icon]} -> {:ok, icon}
      {:ok, []} -> {:error, :not_found}
      {:error, _} = error -> error
    end
  end

  @doc """
  Tracks an icon action in metrics.

  Accepts these opts:

  - `:size` — integer, pixel size (nil for scalable or unknown)
  - `:surface` — where in the UI the action originated
    (`"inline"`, `"popover"`, `"designer"`, …)
  - `:format` — what was produced
    (`"cssclass"`, `"htmltag"`, `"filename"`, `"png-zip"`,
    `"svg-kebab"`/`"svg-snake"`/`"svg-pascal"`/`"svg-original"`,
    identifier codes like `"ios"`/`"android"`, …)

  Legacy `:platform` opt supported during transition — if it contains `:`
  it's split into surface/format, otherwise it's treated as the format and
  surface defaults to `"inline"`. Explicit `:surface`/`:format` win.
  """
  def track_action(icon_id, action, source, opts \\ []) do
    size = opts[:size]
    {surface, format} = split_platform(opts)

    case PureAdminIcons.Audit.track_action(opts[:session_uid], source, icon_id, action,
           size: size,
           surface: surface,
           format: format,
           platform: opts[:platform],
           utm: opts[:utm]
         ) do
      {:ok, _} -> :ok
      {:error, _} = error -> error
    end
  end

  defp split_platform(opts) do
    case {opts[:surface], opts[:format], opts[:platform]} do
      {s, f, _} when is_binary(s) or is_binary(f) ->
        {s, f}

      {nil, nil, p} when is_binary(p) ->
        case String.split(p, ":", parts: 2) do
          [s, f] -> {s, f}
          [f] -> {"inline", f}
        end

      _ ->
        {nil, nil}
    end
  end

  def icon_metrics(icon_id) do
    case DbContext.get_icon_metrics(icon_id) do
      {:ok, results} ->
        results
        |> Enum.map(fn %{action_code: action, period_code: period, count: count} ->
          {{action, period}, count}
        end)
        |> Map.new()

      {:error, _} ->
        %{}
    end
  end

  # Raw long-form rows straight from public.get_stats_overview (v1.11+).
  # Each row: %{source_code, period_code, action_code, surface_code,
  # format_code, count}. Callers pivot as needed.
  def stats_overview_raw do
    case DbContext.get_stats_overview() do
      {:ok, rows} -> {:ok, rows}
      {:error, _} = error -> error
    end
  end

  # v1.11+ `get_stats_overview` returns a long-form row per
  # (source, period, action, surface, format). Pivot to the wide shape the
  # LiveView expects: one row per (source, period) with copies/downloads/
  # searches summed across all surfaces and formats.
  def stats_overview do
    case DbContext.get_stats_overview() do
      {:ok, rows} ->
        pivoted =
          rows
          |> Enum.group_by(
            fn r -> {r.source_code, r.period_code} end,
            fn r -> {r.action_code, r.count || 0} end
          )
          |> Enum.map(fn {{source, period}, action_counts} ->
            by_action =
              action_counts
              |> Enum.group_by(fn {a, _} -> a end, fn {_, c} -> c end)
              |> Map.new(fn {a, cs} -> {a, Enum.sum(cs)} end)

            %{
              source_code: source,
              period_code: period,
              copies: Map.get(by_action, "copy", 0),
              downloads: Map.get(by_action, "download", 0),
              searches: Map.get(by_action, "search", 0)
            }
          end)

        {:ok, pivoted}

      {:error, _} = error ->
        error
    end
  end

  def popular_icons_from_cube(opts \\ []) do
    period = opts[:period] || "30d"
    action = opts[:action] || "copy"
    limit = opts[:limit] || 20
    # Pass nil (not :eg_value_not_provided) so positional params stay aligned —
    # the DB function treats NULL as "no filter" for optional params
    icon_set = opts[:icon_set]
    style = opts[:style]
    source = opts[:source]

    Repo.query(
      "select * from public.get_popular_icons($1, $2, $3, $4, $5, $6)",
      [period, action, icon_set, style, source, limit]
    )
    |> Database.Processors.GetPopularIconsProcessor.parse_result()
  end

  def get_last_sync(icon_set_code \\ nil) do
    case DbContext.get_last_sync(icon_set_code || :eg_value_not_provided) do
      {:ok, [sync]} -> {:ok, sync}
      {:ok, []} -> {:ok, nil}
      {:ok, syncs} when is_list(syncs) -> {:ok, syncs}
      {:error, _} = error -> error
    end
  end

  def create_job_run(run_by, job_type, job_data \\ nil) do
    case DbContext.create_job_run(run_by, job_type, job_data || :eg_value_not_provided) do
      {:ok, [%{create_job_run: job_run_id}]} -> {:ok, job_run_id}
      {:error, _} = error -> error
    end
  end

  def update_job_run(job_run_id, status, success_data \\ nil, fail_data \\ nil) do
    Repo.query("SELECT public.update_job_run($1, $2, $3, $4)", [
      job_run_id,
      status,
      success_data,
      fail_data
    ])
  end
end
