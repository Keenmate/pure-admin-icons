defmodule PureAdminIconsWeb.IconSearchLive do
  use PureAdminIconsWeb, :live_view

  require Logger

  alias PureAdminIcons.Icons
  alias PureAdminIcons.Icons.Icon
  alias PureAdminIcons.IconSets
  alias PureAdminIcons.SearchMetricsCollector
  alias Phoenix.LiveView.JS

  import PureAdminIconsWeb.Components.PlatformIcons
  import PureAdminIcons.Translations, only: [t: 1, t: 2]

  @per_page 30

  # Load preview presets from JSON config at compile time
  @preview_presets :pure_admin_icons
                   |> :code.priv_dir()
                   |> Path.join("preview_presets.json")
                   |> File.read!()
                   |> Jason.decode!()
  @external_resource Path.join(:code.priv_dir(:pure_admin_icons), "preview_presets.json")
  defp preview_presets, do: @preview_presets

  defp preset_button_style(%{"bg" => "checker", "color" => color}) do
    "background-image: repeating-conic-gradient(#e5e7eb 0% 25%, #fff 0% 50%); background-size: 8px 8px; color: #{color};"
  end

  defp preset_button_style(%{"bg" => bg, "color" => color}) do
    "background-color: #{bg}; color: #{color};"
  end

  # Compact swatch for the quick-preset bar: shows a half-and-half circle (bg left, color right)
  defp preset_swatch_style(%{"bg" => "checker", "color" => color}) do
    "background: linear-gradient(90deg, #e5e7eb 50%, #{color} 50%);"
  end

  defp preset_swatch_style(%{"bg" => bg, "color" => color}) do
    "background: linear-gradient(90deg, #{bg} 50%, #{color} 50%);"
  end

  @impl true
  def mount(_params, _session, socket) do
    mount_start = System.monotonic_time()
    connected = connected?(socket)

    # Get preferences from connect params (passed from JS localStorage)
    # get_connect_params returns nil during static render, so we use defaults
    connect_params = get_connect_params(socket) || %{}
    view_mode = connect_params["view_mode"] || "grid"
    icon_list_size = connect_params["icon_list_size"] || 32

    # Per-icon-set platform prefs: %{icon_set_code => %{platform => bool}}
    # Migration: if old shape (flat map) exists, treat it as the default for all sets
    raw_prefs = connect_params["platform_prefs"] || %{}
    platform_prefs_by_set = parse_platform_prefs(raw_prefs)

    # Basket: restore the list of picked icons from localStorage (via connect params).
    # Stored as full icon maps so the drawer can render + bulk-download without a DB hit.
    basket = restore_basket(connect_params["basket"])

    {last_sync_us, last_sync_result} = :timer.tc(fn -> Icons.get_last_sync() end)

    {last_sync_at, discrepancy_count} =
      case last_sync_result do
        {:ok, syncs} when is_list(syncs) and syncs != [] ->
          # Multiple icon sets: get latest finish time and sum discrepancies
          latest = Enum.max_by(syncs, & &1.finished_at, DateTime)

          total_discrepancies =
            Enum.sum(Enum.map(syncs, &((&1.success_data || %{})["discrepancy_count"] || 0)))

          {latest.finished_at, total_discrepancies}

        {:ok, sync} when is_map(sync) ->
          {sync.finished_at, (sync.success_data || %{})["discrepancy_count"] || 0}

        _ ->
          {nil, 0}
      end

    {list_sets_us, icon_sets} = :timer.tc(fn -> Icons.list_icon_sets() end)
    all_styles = icon_sets |> Enum.flat_map(& &1.styles) |> Enum.uniq() |> Enum.sort()
    all_sizes = icon_sets |> Enum.flat_map(& &1.sizes) |> Enum.uniq() |> Enum.sort()

    {count_us, icon_count} = :timer.tc(fn -> Icons.count() end)

    socket =
      socket
      |> assign(icon_count: icon_count)
      |> assign(icon_sets: icon_sets)
      |> assign(all_styles: all_styles)
      |> assign(all_sizes: all_sizes)
      |> assign(platform_prefs_by_set: platform_prefs_by_set)
      |> assign(platform_prefs: default_platform_prefs())
      |> assign(view_mode: view_mode)
      |> assign(icon_list_size: icon_list_size)
      |> assign(last_sync_at: last_sync_at)
      |> assign(discrepancy_count: discrepancy_count)
      |> assign(basket: basket)
      |> assign(basket_ids: basket_ids(basket))
      |> assign(basket_open: false)

    duration_ms =
      System.convert_time_unit(System.monotonic_time() - mount_start, :native, :millisecond)

    measurements = %{
      duration_ms: duration_ms,
      get_last_sync_ms: div(last_sync_us, 1000),
      list_icon_sets_ms: div(list_sets_us, 1000),
      icon_count_ms: div(count_us, 1000)
    }

    metadata = %{connected: connected}

    :telemetry.execute([:pure_admin_icons, :icon_search, :mount], measurements, metadata)

    Logger.info(
      "[icon_search.mount] connected=#{connected} total=#{duration_ms}ms " <>
        "(get_last_sync=#{measurements.get_last_sync_ms}ms " <>
        "list_icon_sets=#{measurements.list_icon_sets_ms}ms " <>
        "count=#{measurements.icon_count_ms}ms)"
    )

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    handle_params_start = System.monotonic_time()
    connected = connected?(socket)

    query = params["q"] || ""
    styles = parse_list(params["styles"])
    sizes = parse_sizes(params["sizes"])
    icon_sets = parse_list(params["set"])
    page = parse_page(params["page"])

    # On very first connected mount with no filter params, restore from localStorage
    {styles, sizes, icon_sets} =
      if connected and no_filter_params?(params) and
           not Map.get(socket.assigns, :filters_initialized, false) do
        connect_params = get_connect_params(socket) || %{}

        saved_styles =
          List.wrap(connect_params["filter_styles"] || []) |> Enum.filter(&is_binary/1)

        saved_sizes =
          List.wrap(connect_params["filter_sizes"] || [])
          |> Enum.map(&to_int/1)
          |> Enum.reject(&is_nil/1)

        saved_sets =
          List.wrap(connect_params["filter_icon_sets"] || []) |> Enum.filter(&is_binary/1)

        {saved_styles, saved_sizes, saved_sets}
      else
        {styles, sizes, icon_sets}
      end

    assigns = %{
      selected_styles: styles,
      selected_sizes: sizes,
      selected_icon_sets: icon_sets,
      page: page
    }

    {search_us, icons} = :timer.tc(fn -> search_icons(query, assigns) end)

    total_count =
      case icons do
        [first | _] -> first.total_items
        [] -> 0
      end

    if connected do
      SearchMetricsCollector.record(
        query,
        List.first(sizes),
        List.first(styles),
        total_count,
        "web",
        List.first(icon_sets)
      )
    end

    total_pages = max(1, ceil(total_count / @per_page))

    # Compute available styles/sizes based on selected icon sets
    {available_styles, available_sizes} =
      case icon_sets do
        [] ->
          {socket.assigns.all_styles, socket.assigns.all_sizes}

        selected ->
          filtered = Enum.filter(socket.assigns.icon_sets, &(&1.code in selected))

          {
            filtered |> Enum.flat_map(& &1.styles) |> Enum.uniq() |> Enum.sort(),
            filtered |> Enum.flat_map(& &1.sizes) |> Enum.uniq() |> Enum.sort()
          }
      end

    page_title = if query != "", do: "#{query} — Icon Search", else: nil

    socket =
      assign(socket,
        page_title: page_title,
        query: query,
        selected_styles: styles,
        selected_sizes: sizes,
        selected_icon_sets: icon_sets,
        available_styles: available_styles,
        available_sizes: available_sizes,
        page: page,
        icons: icons,
        total_count: total_count,
        total_pages: total_pages,
        selected_icon: nil,
        filters_initialized: true
      )
      |> maybe_save_filters(styles, sizes, icon_sets)

    duration_ms =
      System.convert_time_unit(
        System.monotonic_time() - handle_params_start,
        :native,
        :millisecond
      )

    measurements = %{duration_ms: duration_ms, search_ms: div(search_us, 1000)}

    metadata = %{
      connected: connected,
      query: query,
      page: page,
      filtered: styles != [] or sizes != [] or icon_sets != [],
      result_count: length(icons),
      total_count: total_count
    }

    :telemetry.execute(
      [:pure_admin_icons, :icon_search, :handle_params],
      measurements,
      metadata
    )

    Logger.info(
      "[icon_search.handle_params] connected=#{connected} total=#{duration_ms}ms " <>
        "search=#{measurements.search_ms}ms q=#{inspect(query)} page=#{page} " <>
        "filtered=#{metadata.filtered} results=#{metadata.result_count}/#{metadata.total_count}"
    )

    {:noreply, socket}
  end

  defp no_filter_params?(params) do
    is_nil(params["styles"]) and is_nil(params["sizes"]) and is_nil(params["set"])
  end

  defp to_int(val) when is_integer(val), do: val

  defp to_int(val) when is_binary(val) do
    case Integer.parse(val) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp to_int(_), do: nil

  defp maybe_save_filters(socket, styles, sizes, icon_sets) do
    if connected?(socket) do
      push_event(socket, "save_filters", %{
        styles: styles,
        sizes: sizes,
        icon_sets: icon_sets
      })
    else
      socket
    end
  end

  # ── Basket helpers ────────────────────────────────────────────
  defp basket_ids(basket), do: MapSet.new(basket, &to_string(&1.icon_id))

  defp put_basket(socket, basket) do
    socket
    |> assign(basket: basket, basket_ids: basket_ids(basket))
    |> push_event("save_basket", %{basket: basket})
  end

  # Restore the basket from connect params (a list of JSON maps with string keys).
  # Atomize known top-level keys so the grid/list components and Icon/Formatter
  # helpers (which pattern-match atom keys) work on restored entries. Nested maps
  # (filenames, platform_identifiers) keep string keys — Icon helpers tolerate both.
  defp restore_basket(list) when is_list(list) do
    list
    |> Enum.map(&atomize_basket_item/1)
    |> Enum.reject(&is_nil/1)
  end

  defp restore_basket(_), do: []

  defp atomize_basket_item(item) when is_map(item) do
    atomized =
      for {k, v} <- item, key = to_known_atom(k), key != nil, into: %{}, do: {key, v}

    if Map.has_key?(atomized, :icon_id), do: atomized, else: nil
  end

  defp atomize_basket_item(_), do: nil

  # Convert a JSON key to an existing atom, or nil if unknown (avoids atom-table
  # exhaustion from arbitrary client input).
  defp to_known_atom(k) when is_atom(k), do: k

  defp to_known_atom(k) when is_binary(k) do
    String.to_existing_atom(k)
  rescue
    ArgumentError -> nil
  end

  defp to_known_atom(_), do: nil

  # Build a plain-text block listing every basket icon's platform identifiers,
  # using each icon set's enabled + supported platforms.
  defp build_copy_all_text(basket, prefs_by_set) do
    basket
    |> Enum.map(fn icon ->
      header = "#{icon.name} (#{icon.icon_set_code}/#{icon.style_code})"

      lines =
        icon
        |> preferred_platforms_for(prefs_by_set, 8)
        |> Enum.map(fn platform -> "  #{platform}: #{get_platform_id(icon, platform)}" end)

      Enum.join([header | lines], "\n")
    end)
    |> Enum.join("\n\n")
  end

  # Compact payload for the client-side bulk download hook: one entry per basket
  # icon with its display name, set, and the SVG URL (default size). Icons with no
  # resolvable SVG URL are dropped.
  defp basket_download_payload(basket) do
    basket
    |> Enum.map(fn icon ->
      %{
        name: icon.name,
        set: icon.icon_set_code,
        style: icon.style_code,
        url: Icon.svg_url(icon, default_size(icon.sizes))
      }
    end)
    |> Enum.reject(&is_nil(&1.url))
  end

  defp parse_page(nil), do: 1
  defp parse_page(""), do: 1

  defp parse_page(page_str) do
    case Integer.parse(page_str) do
      {page, _} when page > 0 -> page
      _ -> 1
    end
  end

  defp parse_list(nil), do: []
  defp parse_list(""), do: []

  defp parse_list(str) do
    str
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(&1 != ""))
  end

  defp parse_sizes(nil), do: []
  defp parse_sizes(""), do: []

  defp parse_sizes(sizes_str) do
    sizes_str
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(&1 != ""))
    |> Enum.map(&String.to_integer/1)
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    {:noreply, push_patch(socket, to: build_path(socket, q: query, page: 1))}
  end

  def handle_event("toggle_size", %{"size" => size}, socket) do
    size = String.to_integer(size)
    sizes = socket.assigns.selected_sizes
    new_sizes = if size in sizes, do: List.delete(sizes, size), else: [size | sizes]
    {:noreply, push_patch(socket, to: build_path(socket, sizes: new_sizes, page: 1))}
  end

  def handle_event("toggle_style", %{"style" => style}, socket) do
    styles = socket.assigns.selected_styles
    new_styles = if style in styles, do: List.delete(styles, style), else: [style | styles]
    {:noreply, push_patch(socket, to: build_path(socket, styles: new_styles, page: 1))}
  end

  def handle_event("toggle_icon_set", %{"set" => icon_set}, socket) do
    sets = socket.assigns.selected_icon_sets
    new_sets = if icon_set in sets, do: List.delete(sets, icon_set), else: [icon_set | sets]

    # Prune styles/sizes that aren't available in the new icon set selection
    {new_styles, new_sizes} =
      case new_sets do
        [] ->
          {socket.assigns.selected_styles, socket.assigns.selected_sizes}

        selected ->
          filtered = Enum.filter(socket.assigns.icon_sets, &(&1.code in selected))
          avail_styles = filtered |> Enum.flat_map(& &1.styles) |> Enum.uniq()
          avail_sizes = filtered |> Enum.flat_map(& &1.sizes) |> Enum.uniq()

          {
            Enum.filter(socket.assigns.selected_styles, &(&1 in avail_styles)),
            Enum.filter(socket.assigns.selected_sizes, &(&1 in avail_sizes))
          }
      end

    {:noreply,
     push_patch(socket,
       to: build_path(socket, icon_sets: new_sets, styles: new_styles, sizes: new_sizes, page: 1)
     )}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply,
     push_patch(socket, to: build_path(socket, styles: [], sizes: [], icon_sets: [], page: 1))}
  end

  def handle_event("change_page", %{"page" => page}, socket) do
    {:noreply, push_patch(socket, to: build_path(socket, page: String.to_integer(page)))}
  end

  def handle_event("select_icon", %{"id" => id}, socket) do
    # Look in the current results first, then fall back to the basket so cards
    # opened from the drawer work even when they're not on the current page.
    icon =
      Enum.find(socket.assigns.icons, &(to_string(&1.icon_id) == id)) ||
        Enum.find(socket.assigns.basket, &(to_string(&1.icon_id) == id))
    # Fetch metrics for this icon (from raw table, fast enough for single icon)
    metrics = if icon, do: Icons.icon_metrics(icon.icon_id), else: %{}
    # Load this icon set's prefs (or defaults)
    prefs =
      if icon,
        do: prefs_for_set(socket.assigns.platform_prefs_by_set, icon.icon_set_code),
        else: default_platform_prefs()

    {:noreply, assign(socket, selected_icon: icon, icon_metrics: metrics, platform_prefs: prefs)}
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply, assign(socket, selected_icon: nil)}
  end

  def handle_event("toggle_basket_drawer", _params, socket) do
    open = !socket.assigns.basket_open
    socket = assign(socket, basket_open: open)
    # Tell the designer preview to (re)load — it mounts off-screen at page load,
    # so the canvas can be empty until the drawer is actually opened.
    socket = if open, do: push_event(socket, "basket_drawer_opened", %{}), else: socket
    {:noreply, socket}
  end

  def handle_event("close_basket_drawer", _params, socket) do
    {:noreply, assign(socket, basket_open: false)}
  end

  def handle_event("toggle_basket", %{"id" => id}, socket) do
    id = to_string(id)

    new_basket =
      if MapSet.member?(socket.assigns.basket_ids, id) do
        Enum.reject(socket.assigns.basket, &(to_string(&1.icon_id) == id))
      else
        case Enum.find(socket.assigns.icons, &(to_string(&1.icon_id) == id)) do
          nil -> socket.assigns.basket
          icon -> socket.assigns.basket ++ [icon]
        end
      end

    {:noreply, put_basket(socket, new_basket)}
  end

  def handle_event("clear_basket", _params, socket) do
    {:noreply, put_basket(socket, [])}
  end

  def handle_event("copy_all_identifiers", _params, socket) do
    text = build_copy_all_text(socket.assigns.basket, socket.assigns.platform_prefs_by_set)
    {:noreply, push_event(socket, "copy_all_ids", %{text: text})}
  end

  def handle_event("toggle_platform", %{"platform" => platform}, socket) do
    icon = socket.assigns.selected_icon

    if icon do
      prefs = socket.assigns.platform_prefs
      key = String.to_existing_atom(platform)
      new_prefs = Map.update!(prefs, key, &(!&1))

      # Update per-set storage
      new_by_set = Map.put(socket.assigns.platform_prefs_by_set, icon.icon_set_code, new_prefs)

      socket =
        socket
        |> assign(:platform_prefs, new_prefs)
        |> assign(:platform_prefs_by_set, new_by_set)
        |> push_event("save_platform_prefs", new_by_set)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_event("toggle_view", %{"mode" => mode}, socket) do
    socket =
      socket
      |> assign(view_mode: mode)
      |> push_event("save_view_mode", %{mode: mode})

    {:noreply, socket}
  end

  def handle_event("track_download", %{"icon-id" => icon_id, "size" => size} = params, socket) do
    require Logger
    naming = params["naming"] || "original"
    Logger.info("[metrics] track_download icon_id=#{icon_id} size=#{size} naming=#{naming}")
    # `size` may be a single pixel value ("24"), a comma-joined list
    # ("32,64,128") for PNG-ZIP batches, "0" for scalable single-SVG downloads,
    # or "" for scalable icons with no size grid. Parse defensively.
    size_opt =
      case size do
        s when is_binary(s) and s != "" ->
          case Integer.parse(s) do
            {n, ""} -> n
            _ -> nil
          end

        _ ->
          nil
      end

    # `naming` can be:
    #   - "designer:png-zip" / "popover:png-zip"  (surface:format, ready to split)
    #   - "original"/"pascal"/"kebab"/"snake"     (SVG filename-naming from the inline download link)
    # For the bare forms, surface is "inline" and format is "svg-<naming>".
    {surface, format} =
      case String.split(naming, ":", parts: 2) do
        [s, f] -> {s, f}
        [n] -> {"inline", "svg-#{n}"}
      end

    Task.start(fn ->
      case Icons.track_action(
             String.to_integer(icon_id),
             "download",
             "web",
             size: size_opt,
             surface: surface,
             format: format
           ) do
        :ok ->
          Logger.info("[metrics] track_download OK icon_id=#{icon_id} #{surface}/#{format}")

        {:error, reason} ->
          Logger.error("[metrics] track_download FAILED icon_id=#{icon_id}: #{inspect(reason)}")
      end
    end)

    {:noreply, socket}
  end

  def handle_event("track_copy", %{"icon-id" => icon_id, "platform" => platform} = params, socket) do
    require Logger
    Logger.info("[metrics] track_copy icon_id=#{icon_id} platform=#{platform}")
    size = params["size"]

    Task.start(fn ->
      opts = [platform: platform]

      opts =
        case size do
          s when is_binary(s) and s != "" -> [{:size, String.to_integer(s)} | opts]
          _ -> opts
        end

      case Icons.track_action(String.to_integer(icon_id), "copy", "web", opts) do
        :ok ->
          Logger.info("[metrics] track_copy OK icon_id=#{icon_id} platform=#{platform}")

        {:error, reason} ->
          Logger.error("[metrics] track_copy FAILED icon_id=#{icon_id}: #{inspect(reason)}")
      end
    end)

    {:noreply, socket}
  end

  defp atomize_keys(map) do
    Map.new(map, fn {k, v} ->
      key = if is_binary(k), do: String.to_existing_atom(k), else: k
      {key, v}
    end)
  end

  defp build_path(socket, overrides) do
    query = Keyword.get(overrides, :q, socket.assigns.query)
    styles = Keyword.get(overrides, :styles, socket.assigns.selected_styles)
    sizes = Keyword.get(overrides, :sizes, socket.assigns.selected_sizes)
    icon_sets = Keyword.get(overrides, :icon_sets, socket.assigns.selected_icon_sets)
    page = Keyword.get(overrides, :page, socket.assigns.page)

    params =
      []
      |> maybe_add_param("q", query, "")
      |> maybe_add_list("set", icon_sets)
      |> maybe_add_list("styles", styles)
      |> maybe_add_list("sizes", Enum.map(sizes, &to_string/1))
      |> maybe_add_param("page", page, 1)

    case params do
      [] -> "/"
      _ -> "/?" <> URI.encode_query(params)
    end
  end

  defp maybe_add_param(params, _key, value, default) when value == default, do: params
  defp maybe_add_param(params, key, value, _default), do: [{key, value} | params]

  # Default platform preferences for any new icon set
  defp default_platform_prefs do
    %{
      ios: true,
      android: true,
      react: true,
      vue: true,
      svelte: true,
      cssclass: true,
      htmltag: true,
      filename: true
    }
  end

  # Get prefs for a specific icon set, falling back to defaults
  defp prefs_for_set(prefs_by_set, icon_set_code) do
    case Map.get(prefs_by_set, icon_set_code) do
      nil -> default_platform_prefs()
      prefs -> Map.merge(default_platform_prefs(), prefs)
    end
  end

  # Parse the platform_prefs from connect_params.
  # Supports both new shape (%{set => prefs}) and legacy flat shape (%{platform => bool}).
  defp parse_platform_prefs(raw) when is_map(raw) and map_size(raw) == 0, do: %{}

  defp parse_platform_prefs(raw) when is_map(raw) do
    # Detect legacy shape: top-level keys are platform names (ios/android/...) not set codes
    legacy_keys = ["ios", "android", "react", "vue", "svelte", "cssclass", "htmltag", "filename"]
    is_legacy = raw |> Map.keys() |> Enum.any?(&(&1 in legacy_keys))

    if is_legacy do
      # Migrate flat shape: apply to all known sets
      flat = atomize_pref_values(raw)

      ["fluentui", "fontawesome", "heroicons", "lucide", "tabler"]
      |> Enum.map(fn set -> {set, flat} end)
      |> Map.new()
    else
      # New shape: %{set => prefs}
      Map.new(raw, fn {set, prefs} -> {set, atomize_pref_values(prefs)} end)
    end
  end

  defp parse_platform_prefs(_), do: %{}

  defp atomize_pref_values(prefs) when is_map(prefs) do
    Map.new(prefs, fn {k, v} ->
      key = if is_binary(k), do: String.to_existing_atom(k), else: k
      val = if is_binary(v), do: v == "true", else: v
      {key, val}
    end)
  end

  defp atomize_pref_values(_), do: %{}

  defp maybe_add_list(params, _key, []), do: params

  defp maybe_add_list(params, key, list) do
    [{key, Enum.join(Enum.sort(list), ",")} | params]
  end

  defp search_icons(query, assigns) do
    # Use page-based pagination (new DbContext approach)
    opts = [limit: @per_page, page: assigns.page]

    opts =
      case assigns.selected_styles do
        [] -> opts
        styles -> [{:styles, styles} | opts]
      end

    opts =
      case assigns.selected_sizes do
        [] -> opts
        sizes -> [{:sizes, sizes} | opts]
      end

    opts =
      case assigns.selected_icon_sets do
        [] -> opts
        icon_sets -> [{:icon_sets, icon_sets} | opts]
      end

    case Icons.search(query, opts) do
      {:ok, results} -> results
      {:error, _} -> []
    end
  end

  defp get_total_count(query, assigns) do
    opts = []

    opts =
      case assigns.selected_styles do
        [] -> opts
        styles -> [{:styles, styles} | opts]
      end

    opts =
      case assigns.selected_sizes do
        [] -> opts
        sizes -> [{:sizes, sizes} | opts]
      end

    opts =
      case assigns.selected_icon_sets do
        [] -> opts
        icon_sets -> [{:icon_sets, icon_sets} | opts]
      end

    Icons.search_count(query, opts)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex flex-col">
      <!-- Hidden element for metrics tracking from JS -->
      <div id="metrics-tracker" phx-hook="MetricsTracker" class="hidden"></div>
       <Layouts.site_nav
        icon_count={@icon_count}
        set_count={length(@icon_sets)}
        basket_count={length(@basket)}
      />
      <%!-- Hero with search and filters --%>
      <div class="hero-gradient py-4 px-4 border-b border-base-300">
        <div class="max-w-5xl mx-auto text-center mb-3">
          <p class="text-sm text-base-content/50">
            {t("iconSearch.messages.mcpPromptPrefix")}
            <a
              href="https://www.npmjs.com/package/@keenmate/pure-admin-icons-mcp"
              target="_blank"
              rel="noreferrer"
              class="text-primary hover:underline"
            >
              {t("iconSearch.messages.mcpPromptLink")}
            </a> {t("iconSearch.messages.mcpPromptSuffix")}
          </p>
        </div>
        
        <div class="max-w-5xl mx-auto">
          <!-- Search Bar + View Toggle -->
          <div class="flex gap-3 mb-6 items-center">
            <form phx-change="search" phx-submit="search" class="flex-1">
              <div class="relative">
                <div class="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
                  <svg
                    class="h-5 w-5 text-base-content/50"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"
                    />
                  </svg>
                </div>
                
                <input
                  type="text"
                  name="query"
                  value={@query}
                  placeholder={t("iconSearch.placeholders.search")}
                  phx-debounce="300"
                  class="w-full pl-10 pr-4 py-3 rounded-lg border border-base-content/25 bg-base-content/10 shadow-sm search-glow text-base-content text-lg"
                  autofocus
                />
              </div>
            </form>
            
            <div class="flex items-center gap-2">
              <div class="view-toggle">
                <button
                  phx-click={
                    JS.toggle(to: "#filters-panel", in: "fade-in-scale", out: "fade-out-scale")
                  }
                  class={[
                    "btn-action",
                    if(@selected_styles != [] || @selected_sizes != [] || @selected_icon_sets != [],
                      do: "bg-primary text-primary-content",
                      else: "text-base-content/70 hover:text-base-content"
                    )
                  ]}
                >
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M3 4a1 1 0 011-1h16a1 1 0 011 1v2.586a1 1 0 01-.293.707l-6.414 6.414a1 1 0 00-.293.707V17l-4 4v-6.586a1 1 0 00-.293-.707L3.293 7.293A1 1 0 013 6.586V4z"
                    />
                  </svg> <span class="hidden sm:inline">{t("iconSearch.buttons.filters")}</span>
                </button>
              </div>
              
              <div class="view-toggle" id="view-mode" phx-hook="ViewMode">
                <button
                  phx-click="toggle_view"
                  phx-value-mode="grid"
                  class={[
                    "btn-action",
                    if(@view_mode == "grid",
                      do: "bg-primary text-primary-content",
                      else: "text-base-content/70 hover:text-base-content"
                    )
                  ]}
                >
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M4 6a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2H6a2 2 0 01-2-2V6zM14 6a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2V6zM4 16a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2H6a2 2 0 01-2-2v-2zM14 16a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2v-2z"
                    />
                  </svg> <span class="hidden sm:inline">{t("iconSearch.buttons.grid")}</span>
                </button>
                <button
                  phx-click="toggle_view"
                  phx-value-mode="list"
                  class={[
                    "btn-action",
                    if(@view_mode == "list",
                      do: "bg-primary text-primary-content",
                      else: "text-base-content/70 hover:text-base-content"
                    )
                  ]}
                >
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M4 6h16M4 10h16M4 14h16M4 18h16"
                    />
                  </svg> <span class="hidden sm:inline">{t("iconSearch.buttons.list")}</span>
                </button>
              </div>
            </div>
          </div>
          <!-- Filters (collapsible) -->
          <div
            id="filters-panel"
            class="mb-6 p-4 bg-base-200/50 rounded-lg border border-base-300 space-y-4"
            style="display: none;"
          >
            <!-- Icon Set Filter -->
            <div>
              <span class="text-sm font-semibold text-base-content block mb-2">
                {t("iconSearch.headers.sets")}
              </span>
              <div class="flex flex-wrap gap-x-4 gap-y-2">
                <%= for icon_set <- @icon_sets do %>
                  <label class="inline-flex items-center cursor-pointer gap-1.5">
                    <input
                      type="checkbox"
                      phx-click="toggle_icon_set"
                      phx-value-set={icon_set.code}
                      checked={icon_set.code in @selected_icon_sets}
                      class="w-4 h-4 rounded border-base-content/25 focus:ring-primary"
                    />
                    <span
                      class="text-sm text-base-content/70"
                      title={t("iconSearch.tooltips.iconSetCount", %{count: icon_set.icon_count})}
                    >
                      {icon_set.title}
                    </span>
                  </label>
                <% end %>
              </div>
            </div>
            <!-- Style Filter -->
            <div>
              <span class="text-sm font-semibold text-base-content block mb-2">
                {t("iconSearch.headers.styles")}
              </span>
              <div class="flex flex-wrap gap-x-4 gap-y-2">
                <%= for style <- @available_styles do %>
                  <label class="inline-flex items-center cursor-pointer gap-1.5">
                    <input
                      type="checkbox"
                      phx-click="toggle_style"
                      phx-value-style={style}
                      checked={style in @selected_styles}
                      class="w-4 h-4 rounded border-base-content/25 focus:ring-primary"
                    /> <span class="text-sm text-base-content/70 capitalize">{style}</span>
                  </label>
                <% end %>
              </div>
            </div>
            <!-- Size Filters -->
            <div>
              <span class="text-sm font-semibold text-base-content block mb-2">
                {t("iconSearch.headers.sizes")}
              </span>
              <div class="flex flex-wrap gap-x-4 gap-y-2">
                <%= if Enum.any?(@icon_sets, & &1.has_single_source) do %>
                  <label class="inline-flex items-center cursor-pointer gap-1.5">
                    <input
                      type="checkbox"
                      phx-click="toggle_size"
                      phx-value-size="0"
                      checked={0 in @selected_sizes}
                      class="w-4 h-4 rounded border-base-content/25 focus:ring-primary"
                    />
                    <span
                      class="text-sm text-base-content/70"
                      title={t("iconSearch.tooltips.scalable")}
                    >
                      {t("common.labels.scalable")}
                    </span>
                  </label>
                <% end %>
                
                <%= for size <- @available_sizes do %>
                  <label class="inline-flex items-center cursor-pointer gap-1.5">
                    <input
                      type="checkbox"
                      phx-click="toggle_size"
                      phx-value-size={size}
                      checked={size in @selected_sizes}
                      class="w-4 h-4 rounded border-base-content/25 focus:ring-primary"
                    /> <span class="text-sm text-base-content/70">{size}</span>
                  </label>
                <% end %>
              </div>
            </div>
          </div>
          <!-- Active Filters Display -->
          <%= if @selected_styles != [] || @selected_sizes != [] || @selected_icon_sets != [] do %>
            <div class="flex flex-wrap gap-2 mb-4 items-center">
              <span class="text-sm font-medium text-base-content/70">
                {t("iconSearch.labels.activeFilters")}
              </span>
              <%= for icon_set <- Enum.sort(@selected_icon_sets) do %>
                <button
                  type="button"
                  phx-click="toggle_icon_set"
                  phx-value-set={icon_set}
                  class="badge badge-sm gap-1 cursor-pointer hover:opacity-80"
                  style={IconSets.Color.badge_style(icon_set)}
                >
                  {icon_set} <span class="text-lg leading-none">&times;</span>
                </button>
              <% end %>
              
              <%= for style <- Enum.sort(@selected_styles) do %>
                <button
                  type="button"
                  phx-click="toggle_style"
                  phx-value-style={style}
                  class="badge badge-sm badge-neutral gap-1 cursor-pointer hover:opacity-80"
                >
                  {style} <span class="text-lg leading-none">&times;</span>
                </button>
              <% end %>
              
              <%= for size <- Enum.sort(@selected_sizes) do %>
                <button
                  type="button"
                  phx-click="toggle_size"
                  phx-value-size={size}
                  class="badge badge-sm badge-ghost gap-1 cursor-pointer hover:opacity-80"
                >
                  {if size == 0, do: t("common.labels.scalable"), else: "#{size}px"}
                  <span class="text-lg leading-none">&times;</span>
                </button>
              <% end %>
              
              <button
                phx-click="clear_filters"
                class="text-sm text-primary hover:text-primary/80 ml-1"
              >
                {t("iconSearch.buttons.clearAll")}
              </button>
            </div>
          <% end %>
        </div>
      </div>
       <%!-- Content --%>
      <main class="px-4 py-6 sm:px-6 lg:px-8 flex-1">
        <div class={[
          "mx-auto transition-[max-width] duration-200",
          if(@selected_icon, do: "max-w-7xl xl:max-w-[80vw]", else: "max-w-7xl")
        ]}>
          <!-- Results Count, Icon Size Slider & Pager -->
          <div class="flex flex-wrap justify-between items-center mb-4 gap-3">
            <div class="text-sm text-base-content/70">
              <%= if @total_count > 0 do %>
                {t("iconSearch.messages.resultsRange", %{
                  from: (@page - 1) * 30 + 1,
                  to: min(@page * 30, @total_count),
                  total: @total_count
                })}
              <% end %>
            </div>
            
            <div class="flex items-center gap-3">
              <div
                class={["flex items-center gap-2", if(@view_mode != "list", do: "hidden")]}
                id="icon-size-slider"
                phx-hook="IconSizeSlider"
              >
                <svg
                  class="w-4 h-4 text-base-content/50"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M4 8V4m0 0H8M4 4l5 5m11-1V4m0 0h-4m4 0l-5 5M4 16v4m0 0h4m-4 0l5-5m11 5l-5-5m5 5v-4m0 4h-4"
                  />
                </svg>
                <input
                  type="range"
                  min="24"
                  max="64"
                  value={@icon_list_size}
                  step="4"
                  class="icon-size-range range range-xs range-primary w-20 cursor-pointer"
                />
                <span class="icon-size-label text-xs text-base-content/50 w-8">
                  {@icon_list_size}px
                </span>
              </div>
              
              <div
                id="quick-presets"
                phx-hook="QuickPresets"
                class="relative"
                data-presets={Jason.encode!(preview_presets())}
              >
                <button type="button" class="quick-preset-trigger btn-pager gap-2">
                  <span
                    class="quick-preset-swatch w-4 h-4 rounded-sm border border-base-content/20"
                    style="background: linear-gradient(135deg, #ffffff 50%, #212121 50%);"
                  >
                  </span> <span class="quick-preset-label text-xs">Classic Light</span>
                  <svg
                    class="w-3 h-3 text-base-content/50"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M19 9l-7 7-7-7"
                    />
                  </svg>
                </button>
                <div
                  class="quick-preset-dropdown hidden py-1 rounded-lg bg-base-100 border border-base-content/20 shadow-xl z-50 w-44 max-h-64 overflow-y-auto"
                  style="position: fixed; top: 0; left: 0;"
                >
                  <%= for preset <- Enum.sort_by(preview_presets(), & &1["label"]) do %>
                    <button
                      type="button"
                      data-preset={preset["key"]}
                      data-color={preset["color"]}
                      data-bg={preset["bg"]}
                      data-label={preset["label"]}
                      class="quick-preset w-full text-left px-3 py-1.5 text-sm cursor-pointer hover:opacity-80"
                      style={preset_button_style(preset)}
                    >
                      {preset["label"]}
                    </button>
                  <% end %>
                </div>
              </div>
               <.pager current_page={@page} total_pages={@total_pages} />
            </div>
          </div>
          <!-- Master/detail split: on xl the detail panel sits inline beside the grid;
               below xl it renders as a fixed overlay modal (see #modal-container). -->
          <div class="xl:flex xl:gap-6 xl:items-start">
            <div class={["min-w-0", if(@selected_icon, do: "xl:w-3/5", else: "w-full")]}>
          <!-- Icon Display (Grid or List) - Both rendered, CSS controls visibility -->
          <div id="icon-display-popovers" phx-hook="FloatingPopover">
            <div id="icon-display" phx-hook="IconColorFilter">
              <div class="view-grid">
                <.icon_grid
                  icons={@icons}
                  selected_styles={@selected_styles}
                  selected_sizes={@selected_sizes}
                  selected_icon_sets={@selected_icon_sets}
                  platform_prefs_by_set={@platform_prefs_by_set}
                  available_styles={@available_styles}
                  basket_ids={@basket_ids}
                  id_prefix=""
                />
              </div>

              <div class="view-list">
                <.icon_list
                  icons={@icons}
                  platform_prefs_by_set={@platform_prefs_by_set}
                  selected_sizes={@selected_sizes}
                  available_sizes={@available_sizes}
                  icon_list_size={@icon_list_size}
                  basket_ids={@basket_ids}
                  id_prefix=""
                />
              </div>
            </div>
          </div>
          <!-- Bottom Pager -->
          <%= if @total_pages > 1 do %>
            <div class="flex justify-end mt-6">
              <.pager current_page={@page} total_pages={@total_pages} />
            </div>
          <% end %>
          <!-- Empty State -->
          <%= if @query != "" and @icons == [] do %>
            <div class="text-center py-16">
              <svg
                class="h-16 w-16 text-base-content/50 mx-auto mb-4"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M9.172 16.172a4 4 0 015.656 0M9 10h.01M15 10h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
                />
              </svg>
              <p class="text-base-content/70">{t("iconSearch.empty.noResults", %{query: @query})}</p>
              
              <p class="text-sm text-base-content/50 mt-1">{t("iconSearch.empty.noResultsHint")}</p>
            </div>
          <% end %>
            </div>
            <!-- Icon Detail (LiveComponent — isolated render cycle).
                 Stable #modal-container prevents morphdom sibling mismatch when it appears/disappears.
                 Inline 40% panel on xl; fixed overlay modal below xl (positioning is inside the component). -->
            <div id="modal-container" class={if(@selected_icon, do: "xl:w-2/5 xl:flex-shrink-0")}>
              <%= if @selected_icon do %>
                <.live_component
                  module={PureAdminIconsWeb.IconModalComponent}
                  id="icon-modal"
                  icon={@selected_icon}
                  platform_prefs={@platform_prefs}
                  metrics={@icon_metrics}
                />
              <% end %>
            </div>
          </div>
        </div>
      </main>
      <!-- Basket drawer (right-side slide-over). Reuses the same grid/list cards
           as the search results, namespaced with id_prefix="basket-" so SVG
           container ids don't collide with the main display. -->
      <div
        class={["fixed inset-0 z-[60]", if(!@basket_open, do: "pointer-events-none")]}
        aria-hidden={to_string(!@basket_open)}
      >
        <div
          class={[
            "fixed inset-0 bg-black/50 transition-opacity duration-200",
            if(@basket_open, do: "opacity-100", else: "opacity-0")
          ]}
          phx-click="close_basket_drawer"
        >
        </div>
        <div class={[
          "fixed right-0 top-0 h-full w-full max-w-md bg-base-100 shadow-2xl flex flex-col transition-transform duration-200",
          if(@basket_open, do: "translate-x-0", else: "translate-x-full")
        ]}>
          <!-- Header -->
          <div class="flex items-center justify-between gap-2 px-4 py-3 border-b border-base-300">
            <div class="flex items-baseline gap-2 min-w-0">
              <h2 class="text-lg font-bold text-base-content">{t("iconSearch.headers.basket")}</h2>
              <span class="text-sm text-base-content/50">
                {t("iconSearch.messages.basketCount", %{count: length(@basket)})}
              </span>
            </div>
            <button
              type="button"
              phx-click="close_basket_drawer"
              class="p-1.5 rounded-lg text-base-content/60 hover:text-base-content hover:bg-base-200 transition-colors"
              title={t("common.buttons.close")}
            >
              <.icon name="hero-x-mark" class="size-5" />
            </button>
          </div>
          <!-- Actions -->
          <div
            id="basket-actions"
            phx-hook="BasketActions"
            data-basket={Jason.encode!(basket_download_payload(@basket))}
            class="px-4 py-3 border-b border-base-300"
          >
            <div class="grid grid-cols-3 gap-2">
              <button
                type="button"
                data-basket-action="svg-zip"
                disabled={@basket == []}
                class="btn-action flex-col gap-1 py-2 h-auto text-xs disabled:opacity-40 disabled:pointer-events-none"
                title={t("iconSearch.buttons.downloadSvgZip")}
              >
                <.icon name="hero-arrow-down-tray" class="size-5" />
                <span>SVG</span>
              </button>
              <button
                type="button"
                data-basket-action="png-zip"
                disabled={@basket == []}
                class="btn-action flex-col gap-1 py-2 h-auto text-xs disabled:opacity-40 disabled:pointer-events-none"
                title={t("iconSearch.buttons.downloadPngZip")}
              >
                <.icon name="hero-photo" class="size-5" />
                <span>PNG</span>
              </button>
              <button
                type="button"
                phx-click="copy_all_identifiers"
                disabled={@basket == []}
                class="btn-action flex-col gap-1 py-2 h-auto text-xs disabled:opacity-40 disabled:pointer-events-none"
                title={t("iconSearch.buttons.copyAllIds")}
              >
                <.icon name="hero-clipboard-document" class="size-5" />
                <span>IDs</span>
              </button>
            </div>
            <%= if @basket != [] do %>
              <button
                type="button"
                phx-click="clear_basket"
                class="mt-2 w-full text-xs text-base-content/50 hover:text-error transition-colors py-1"
              >
                {t("iconSearch.buttons.clearBasket")}
              </button>
            <% end %>
          </div>
          <!-- Designer (collapsible): reuses the real DownloadDesigner controls +
               a preset picker. All settings write the shared localStorage the bulk
               SVG/PNG exports read, so "current/last config" applies to downloads. -->
          <%= if @basket != [] do %>
            <% designer_icon = List.first(@basket) %>
            <div class="border-b border-base-300">
              <button
                type="button"
                phx-click={JS.toggle(to: "#basket-designer-panel", in: "fade-in-scale", out: "fade-out-scale")}
                class="w-full flex items-center justify-between px-4 py-2.5 text-sm font-medium text-base-content/80 hover:bg-base-200 transition-colors"
              >
                <span class="inline-flex items-center gap-1.5">
                  <.icon name="hero-swatch" class="size-4" /> {t("iconSearch.buttons.designer")}
                </span>
                <.icon name="hero-chevron-down" class="size-4" />
              </button>
              <div id="basket-designer-panel" style="display: none;" class="px-4 pb-3 space-y-3">
                <p class="text-xs text-base-content/50">{t("iconSearch.messages.designerHint")}</p>
                <!-- Preset / color picker (compact) -->
                <div
                  id="basket-quick-presets"
                  phx-hook="QuickPresets"
                  class="relative"
                  data-presets={Jason.encode!(preview_presets())}
                >
                  <button type="button" class="quick-preset-trigger btn-pager gap-2">
                    <span
                      class="quick-preset-swatch w-4 h-4 rounded-sm border border-base-content/20"
                      style="background: linear-gradient(135deg, #ffffff 50%, #212121 50%);"
                    >
                    </span> <span class="quick-preset-label text-xs">Classic Light</span>
                    <svg class="w-3 h-3 text-base-content/50" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
                    </svg>
                  </button>
                  <div
                    class="quick-preset-dropdown hidden py-1 rounded-lg bg-base-100 border border-base-content/20 shadow-xl z-50 w-44 max-h-64 overflow-y-auto"
                    style="position: fixed; top: 0; left: 0;"
                  >
                    <%= for preset <- Enum.sort_by(preview_presets(), & &1["label"]) do %>
                      <button
                        type="button"
                        data-preset={preset["key"]}
                        data-color={preset["color"]}
                        data-bg={preset["bg"]}
                        data-label={preset["label"]}
                        class="quick-preset w-full text-left px-3 py-1.5 text-sm cursor-pointer hover:opacity-80"
                        style={preset_button_style(preset)}
                      >
                        {preset["label"]}
                      </button>
                    <% end %>
                  </div>
                </div>
                <!-- Designer controls (no per-icon download buttons — the bulk
                     actions above handle downloads). Preview shows the first icon. -->
                <div
                  id={"basket-download-designer-#{designer_icon.icon_id}"}
                  phx-hook="DownloadDesigner"
                  data-name={designer_icon.name}
                  data-svg-url={
                    if Map.get(designer_icon, :has_single_source, false),
                      do: Icon.svg_url(designer_icon, 0),
                      else: Icon.svg_url(designer_icon, List.first(designer_icon.sizes))
                  }
                >
                  <div class="bg-base-100 rounded-lg p-3 space-y-3">
                    <div class="flex items-center gap-3">
                      <canvas
                        class="designer-preview rounded-lg border border-base-300 flex-shrink-0"
                        width="72"
                        height="72"
                        style="width: 72px; height: 72px;"
                      >
                      </canvas>
                      <label class="flex-1 flex items-center gap-2 cursor-pointer text-xs text-base-content/70">
                        <input type="checkbox" class="designer-include-colors w-3.5 h-3.5 rounded border-base-300" />
                        <span>{t("iconDetail.labels.includeColors")}</span>
                      </label>
                    </div>
                    <!-- Sliders full-width (label above) — a narrow drawer squishes
                         side-by-side ranges into unusable pills. -->
                    <div class="space-y-2 text-xs">
                      <div>
                        <div class="flex items-center justify-between text-base-content/70 mb-1">
                          <span>{t("iconDetail.labels.padding")}</span>
                          <span class="designer-padding-label text-base-content/50">10%</span>
                        </div>
                        <input type="range" min="0" max="40" value="10" class="designer-padding range range-xs range-primary w-full" />
                      </div>
                      <div>
                        <div class="flex items-center justify-between text-base-content/70 mb-1">
                          <span>{t("iconDetail.labels.corners")}</span>
                          <span class="designer-radius-label text-base-content/50">20%</span>
                        </div>
                        <input type="range" min="0" max="50" value="20" class="designer-radius range range-xs range-primary w-full" />
                      </div>
                    </div>
                    <div class="flex flex-wrap items-center gap-x-3 gap-y-1 text-xs">
                      <span class="text-base-content/70">{t("iconDetail.labels.sizes")}</span>
                      <%= for size <- [32, 64, 128, 256, 512, 1024] do %>
                        <label class="inline-flex items-center gap-1 cursor-pointer">
                          <input type="checkbox" checked class="designer-size w-3.5 h-3.5 rounded border-base-300" value={size} />
                          <span class="text-base-content/70">{size}</span>
                        </label>
                      <% end %>
                      <div class="flex items-center gap-1">
                        <input type="number" min="1" max="4096" placeholder={t("iconDetail.placeholders.customSize")} class="designer-custom-size w-16 px-2 py-0.5 border border-base-300 rounded" />
                        <span class="text-base-content/50">px</span>
                      </div>
                    </div>
                    <label class="px-3 py-1.5 rounded text-xs font-medium cursor-pointer border border-base-300 hover:bg-base-200 inline-flex items-center gap-1.5" title={t("iconDetail.tooltips.importSettings")}>
                      <.icon name="hero-arrow-up-tray" class="size-4" /> {t("iconDetail.buttons.importSettings")}
                      <input type="file" accept=".json" class="designer-import-file hidden" />
                    </label>
                  </div>
                </div>
              </div>
            </div>
          <% end %>
          <!-- Items -->
          <div class="flex-1 overflow-y-auto p-4">
            <%= if @basket == [] do %>
              <div class="text-center py-16">
                <.icon name="hero-shopping-bag" class="size-12 text-base-content/30 mx-auto mb-3" />
                <p class="text-base-content/70">{t("iconSearch.empty.basket")}</p>
                <p class="text-sm text-base-content/50 mt-1">{t("iconSearch.empty.basketHint")}</p>
              </div>
            <% else %>
              <%!-- Always the compact grid cards here, regardless of the page's
                    grid/list view mode — a wide table won't fit the narrow drawer. --%>
              <div id="basket-popovers" phx-hook="FloatingPopover">
                <div id="basket-display" phx-hook="IconColorFilter">
                  <.icon_grid
                    icons={@basket}
                    selected_styles={[]}
                    selected_sizes={[]}
                    selected_icon_sets={[]}
                    platform_prefs_by_set={@platform_prefs_by_set}
                    available_styles={[]}
                    basket_ids={@basket_ids}
                    id_prefix="basket-"
                  />
                </div>
              </div>
            <% end %>
          </div>
        </div>
      </div>
      <!-- Footer -->
      <footer class="border-t border-base-300 bg-base-200/50">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
          <div class="grid grid-cols-1 sm:grid-cols-3 gap-6">
            <!-- Branding -->
            <div>
              <Layouts.logo class="text-lg" />
              <p class="text-xs text-base-content/50 mt-2">
                {t("iconSearch.messages.footerTagline", %{
                  count: @icon_count,
                  sets: length(@icon_sets)
                })}
              </p>
              
              <p class="text-xs text-base-content/40 mt-1">
                {t("iconSearch.messages.madeByPrefix")}
                <a
                  href="https://keenmate.com"
                  rel="noreferrer"
                  referrerpolicy="origin"
                  class="text-primary hover:underline"
                >
                  KeenMate
                </a>
              </p>
            </div>
            <!-- Links -->
            <div>
              <h4 class="text-sm font-semibold text-base-content mb-2">
                {t("iconSearch.headers.resources")}
              </h4>
              
              <ul class="space-y-1 text-xs text-base-content/60">
                <li>
                  <a href="/docs/api" class="hover:text-primary">{t("iconSearch.links.apiDocs")}</a>
                </li>
                
                <li>
                  <a href="/docs/mcp" class="hover:text-primary">{t("iconSearch.links.mcpServer")}</a>
                </li>
                
                <li>
                  <a href="/docs/llms" class="hover:text-primary">
                    {t("iconSearch.links.llmIntegration")}
                  </a>
                </li>
                
                <li>
                  <a href="/api/health" class="hover:text-primary">
                    {t("iconSearch.links.healthCheck")}
                  </a>
                </li>
              </ul>
            </div>
            <!-- Icon Sets -->
            <div>
              <h4 class="text-sm font-semibold text-base-content mb-2">
                {t("iconSearch.headers.iconSets")}
              </h4>
              
              <ul class="space-y-1 text-xs text-base-content/60">
                <%= for icon_set <- @icon_sets do %>
                  <li>
                    <a
                      href={icon_set.homepage_url}
                      target="_blank"
                      rel="noreferrer"
                      class="hover:text-primary"
                    >
                      {icon_set.title}
                    </a> <span class="text-base-content/30">({icon_set.icon_count})</span>
                  </li>
                <% end %>
              </ul>
            </div>
          </div>
          <!-- Bottom bar -->
          <div class="mt-6 pt-4 border-t border-base-300/50 flex flex-col sm:flex-row justify-between items-center gap-2 text-xs text-base-content/40">
            <span>{t("iconSearch.messages.licenseNotice")}</span>
            <%= if @last_sync_at do %>
              <div class="flex items-center gap-2">
                <span>
                  {t("iconSearch.messages.lastSynced", %{when: format_sync_time(@last_sync_at)})}
                </span>
                <%= if @discrepancy_count > 0 do %>
                  <a href="/sync/discrepancies" class="text-warning hover:opacity-80 hover:underline">
                    {t("iconSearch.messages.discrepancies", %{count: @discrepancy_count})}
                  </a>
                <% end %>
              </div>
            <% end %>
          </div>
        </div>
      </footer>
    </div>
    """
  end

  # icon_modal extracted to PureAdminIconsWeb.IconModalComponent (LiveComponent)
  # See lib/pure_admin_icons_web/live/icon_modal_component.ex

  defp _old_modal_placeholder do
    # This block replaces ~570 lines of the old defp icon_modal/1.
    # Keeping this marker so git blame shows the extraction.
    nil
  end

  defp pager(assigns) do
    ~H"""
    <div class="flex items-center gap-2">
      <button
        :if={@current_page > 1}
        phx-click="change_page"
        phx-value-page={@current_page - 1}
        class="btn-pager"
      >
        {t("common.buttons.previous")}
      </button>
      <button
        :if={@current_page <= 1}
        disabled
        class="btn-pager-disabled"
      >
        {t("common.buttons.previous")}
      </button>
      <span class="text-sm text-base-content/70">
        {t("common.pagination.pageOf", %{page: @current_page, total: @total_pages})}
      </span>
      <button
        :if={@current_page < @total_pages}
        phx-click="change_page"
        phx-value-page={@current_page + 1}
        class="btn-pager"
      >
        {t("common.buttons.next")}
      </button>
      <button
        :if={@current_page >= @total_pages}
        disabled
        class="btn-pager-disabled"
      >
        {t("common.buttons.next")}
      </button>
    </div>
    """
  end

  attr :icon_id, :any, required: true
  attr :in_basket, :boolean, required: true
  attr :class, :string, default: nil

  # Small +/✓ toggle that adds/removes an icon from the basket. `onclick`
  # stops propagation so it doesn't also trigger the card's select_icon.
  defp basket_toggle(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="toggle_basket"
      phx-value-id={@icon_id}
      title={
        if @in_basket,
          do: t("iconSearch.tooltips.removeFromBasket"),
          else: t("iconSearch.tooltips.addToBasket")
      }
      class={[
        "basket-toggle inline-flex items-center justify-center w-7 h-7 rounded-lg transition-colors shadow-sm border",
        if(@in_basket,
          do: "bg-primary text-primary-content border-primary hover:bg-primary/80",
          else:
            "bg-base-100/90 text-base-content/40 border-base-300 hover:text-primary hover:bg-base-100"
        ),
        @class
      ]}
    >
      <.icon name={if @in_basket, do: "hero-check", else: "hero-plus"} class="size-4" />
    </button>
    """
  end

  defp icon_grid(assigns) do
    # Hide style badge if all icons in this result page share the same style
    show_style_badge = assigns.icons |> Enum.map(& &1.style_code) |> Enum.uniq() |> length() > 1
    assigns = assign(assigns, :show_style_badge, show_style_badge)

    ~H"""
    <div class="flex flex-wrap justify-center gap-4 [&>*]:w-44">
      <%= for icon <- @icons do %>
        <div
          phx-click="select_icon"
          phx-value-id={icon.icon_id}
          class="icon-card bg-base-200 rounded-lg cursor-pointer flex flex-col relative"
          title={"#{icon.icon_set_code} / #{icon.name}"}
        >
          <.basket_toggle
            icon_id={icon.icon_id}
            in_basket={MapSet.member?(@basket_ids, to_string(icon.icon_id))}
            class="absolute bottom-2 right-2 z-10"
          />
          <!-- Top accent bar — colored by icon set, follows the rounded card corners -->
          <div class="h-1.5 w-full rounded-t-lg" style={IconSets.Color.bar_style(icon.icon_set_code)}>
          </div>
          
          <div class="icon-card-body">
            <div class="icon-card-name flex items-center justify-center gap-1" title={icon.name}>
              <%= cond do %>
                <% Map.get(icon, :exact_match, 0) == 1 -> %>
                  <span
                    class="inline-flex items-center text-primary"
                    title={t("iconSearch.tooltips.exactMatch")}
                  >
                    <.icon name="hero-check-badge" class="size-3.5" />
                  </span>
                <% Map.get(icon, :synonym_exact_match, 0) == 1 -> %>
                  <span
                    class="inline-flex items-center text-primary/70"
                    title={t("iconSearch.tooltips.exactMatchSynonym")}
                  >
                    <.icon name="hero-tag" class="size-3.5" />
                  </span>
                <% true -> %>
              <% end %>
               {icon.name}
            </div>
            
            <%= if @show_style_badge do %>
              <div class="flex justify-center mt-1.5">
                <span class="badge badge-sm badge-neutral capitalize">{icon.style_code}</span>
              </div>
            <% end %>
            
            <div
              class="icon-card-thumb icon-preview-bg bg-white/80"
              id={"#{@id_prefix}grid-svg-#{icon.icon_id}"}
              phx-update="ignore"
            >
              <span
                class="inline-svg-icon inline-flex items-center justify-center w-12 h-12"
                data-svg-url={Icon.svg_url(icon, default_size(icon.sizes))}
              >
              </span>
            </div>
            
            <div class="icon-card-sizes">
              <%= if Map.get(icon, :has_single_source, false) do %>
                <div
                  class="has-popover text-2xl leading-none font-bold"
                  title={t("iconSearch.tooltips.scalableRenders")}
                >
                  ∞
                  <div class="floating-popover">
                    <%= for platform <- preferred_platforms_for(icon, @platform_prefs_by_set, 2) do %>
                      <button
                        type="button"
                        class={["floating-popover-btn", platform_color(platform)]}
                        title={t("iconSearch.tooltips.copyPlatformIdentifier", %{platform: platform})}
                        phx-click={
                          JS.dispatch("phx:copy_text", detail: copy_detail(icon, platform, 0))
                        }
                      >
                        <.platform_icon name={to_string(platform)} class="w-5 h-5" />
                      </button>
                    <% end %>
                    
                    <button
                      type="button"
                      class="quick-designer-download floating-popover-btn text-base-content/60"
                      title={t("iconSearch.tooltips.downloadPngZip")}
                      data-icon-id={icon.icon_id}
                      data-svg-url={Icon.svg_url(icon, default_size(icon.sizes))}
                      data-name={icon.name}
                    >
                      <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          stroke-width="2"
                          d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4"
                        />
                      </svg>
                    </button>
                  </div>
                </div>
              <% else %>
                <%= for size <- icon.sizes do %>
                  <div class="has-popover">
                    {size}px
                    <div class="floating-popover">
                      <%= for platform <- preferred_platforms_for(icon, @platform_prefs_by_set, 2) do %>
                        <button
                          type="button"
                          class={["floating-popover-btn", platform_color(platform)]}
                          title={
                            t("iconSearch.tooltips.copyPlatformIdentifierSized", %{
                              platform: platform,
                              size: size
                            })
                          }
                          phx-click={
                            JS.dispatch("phx:copy_text", detail: copy_detail(icon, platform, size))
                          }
                        >
                          <.platform_icon name={to_string(platform)} class="w-5 h-5" />
                        </button>
                      <% end %>
                      
                      <button
                        type="button"
                        class="quick-designer-download floating-popover-btn text-base-content/60"
                        title={t("iconSearch.tooltips.downloadPngZip")}
                        data-icon-id={icon.icon_id}
                        data-svg-url={Icon.svg_url(icon, size)}
                        data-name={icon.name}
                      >
                        <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path
                            stroke-linecap="round"
                            stroke-linejoin="round"
                            stroke-width="2"
                            d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4"
                          />
                        </svg>
                      </button>
                    </div>
                  </div>
                <% end %>
              <% end %>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp icon_list(assigns) do
    assigns =
      assign(
        assigns,
        :display_sizes,
        if(assigns.selected_sizes == [],
          do: assigns.available_sizes,
          else: Enum.sort(assigns.selected_sizes)
        )
      )

    ~H"""
    <%!-- Mobile: card layout --%>
    <div class="md:hidden space-y-3">
      <%= for icon <- @icons do %>
        <div
          phx-click="select_icon"
          phx-value-id={icon.icon_id}
          class="bg-base-200 rounded-lg p-3 cursor-pointer hover:bg-base-300 transition-colors border border-base-300"
        >
          <div class="flex items-center gap-2">
            <div id={"#{@id_prefix}mobile-svg-#{icon.icon_id}"} phx-update="ignore" class="flex-shrink-0">
              <span
                class="icon-card-preview icon-preview-bg inline-svg-icon inline-flex items-center justify-center rounded bg-white/80 p-1.5"
                style={"width: #{trunc(@icon_list_size * 1.5)}px; height: #{trunc(@icon_list_size * 1.5)}px;"}
                data-svg-url={Icon.svg_url(icon, default_size(icon.sizes))}
              >
              </span>
            </div>

            <div class="flex-1 min-w-0">
              <div class="font-medium text-base-content truncate mb-1">{icon.name}</div>

              <div class="flex flex-wrap gap-1 mt-0.5">
                <span class="badge badge-sm" style={IconSets.Color.badge_style(icon.icon_set_code)}>
                  {icon.icon_set_code}
                </span> <span class="badge badge-sm badge-neutral capitalize">{icon.style_code}</span>
              </div>
            </div>

            <.basket_toggle
              icon_id={icon.icon_id}
              in_basket={MapSet.member?(@basket_ids, to_string(icon.icon_id))}
              class="flex-shrink-0"
            />
          </div>
          
          <div class="flex flex-wrap gap-1 mt-1">
            <%= if Map.get(icon, :has_single_source, false) do %>
              <span
                class="badge badge-sm badge-ghost"
                title={t("iconSearch.tooltips.scalableRenders")}
              >
                ∞
              </span>
            <% else %>
              <%= for size <- icon.sizes do %>
                <span class="badge badge-sm badge-ghost">{size}px</span>
              <% end %>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
     <%!-- Desktop: table layout --%>
    <div class="hidden md:block bg-base-200 rounded-lg border border-base-300">
      <div>
        <table class="w-full text-sm">
          <thead class="bg-base-200 border-b-2 border-base-300 sticky-table-header">
            <tr>
              <th
                class="w-16 px-4 py-4 text-left font-semibold text-base-content text-base sticky bg-base-200 z-20"
                style="top: var(--sticky-header-height, 0px)"
              >
                {t("common.tableHeaders.icon")}
              </th>
              
              <th
                class="px-4 py-4 text-left font-semibold text-base-content text-base sticky bg-base-200 z-20"
                style="top: var(--sticky-header-height, 0px)"
              >
                {t("common.tableHeaders.set")}
              </th>
              
              <th
                class="px-4 py-4 text-left font-semibold text-base-content text-base sticky bg-base-200 z-20"
                style="top: var(--sticky-header-height, 0px)"
              >
                {t("iconSearch.tableHeaders.name")}
              </th>
              
              <th
                class="w-24 px-4 py-4 text-center font-semibold text-base-content text-base sticky bg-base-200 z-20"
                style="top: var(--sticky-header-height, 0px)"
              >
                {t("common.tableHeaders.style")}
              </th>
              
              <%= for size <- @display_sizes do %>
                <th
                  class="w-16 px-2 py-4 text-center font-semibold text-base-content text-sm sticky bg-base-200 z-20"
                  style="top: var(--sticky-header-height, 0px)"
                >
                  {size}
                </th>
              <% end %>
            </tr>
          </thead>
          
          <tbody class="divide-y divide-base-300">
            <%= for icon <- @icons do %>
              <tr
                phx-click="select_icon"
                phx-value-id={icon.icon_id}
                class="list-row"
              >
                <td class="px-4 py-3">
                  <div class="flex items-center gap-2">
                    <.basket_toggle
                      icon_id={icon.icon_id}
                      in_basket={MapSet.member?(@basket_ids, to_string(icon.icon_id))}
                      class="flex-shrink-0"
                    />
                    <div id={"#{@id_prefix}list-svg-#{icon.icon_id}"} phx-update="ignore">
                      <span
                        class="icon-list-preview icon-preview-bg inline-svg-icon inline-flex items-center justify-center rounded bg-white/80 p-1"
                        style={"width: #{@icon_list_size}px; height: #{@icon_list_size}px;"}
                        data-svg-url={Icon.svg_url(icon, default_size(icon.sizes))}
                      >
                      </span>
                    </div>
                  </div>
                </td>
                
                <td class="px-4 py-3">
                  <span class="badge badge-sm" style={IconSets.Color.badge_style(icon.icon_set_code)}>
                    {icon.icon_set_code}
                  </span>
                </td>
                
                <td class="px-4 py-3 font-medium text-base-content">{icon.name}</td>
                
                <td class="px-4 py-3 text-center">
                  <span class="px-2 py-0.5 rounded text-xs bg-base-200 text-base-content/70 capitalize">
                    {icon.style_code}
                  </span>
                </td>
                
                <%= if Map.get(icon, :has_single_source, false) do %>
                  <td class="px-2 py-3 text-center" colspan={length(@display_sizes)}>
                    <div
                      class="has-popover inline-block text-base-content/80 font-bold text-lg"
                      title={t("iconSearch.tooltips.scalableRenders")}
                    >
                      {t("common.labels.scalable")}
                      <div class="floating-popover">
                        <%= for platform <- preferred_platforms_for(icon, @platform_prefs_by_set, 2) do %>
                          <button
                            type="button"
                            class={["floating-popover-btn", platform_color(platform)]}
                            title={
                              t("iconSearch.tooltips.copyPlatformIdentifier", %{platform: platform})
                            }
                            phx-click={
                              JS.dispatch("phx:copy_text", detail: copy_detail(icon, platform, 0))
                            }
                            phx-value-stop-propagation="true"
                          >
                            <.platform_icon name={to_string(platform)} class="w-5 h-5" />
                          </button>
                        <% end %>
                        
                        <button
                          type="button"
                          class="quick-designer-download floating-popover-btn text-base-content/60"
                          title={t("iconSearch.tooltips.downloadPngZip")}
                          data-icon-id={icon.icon_id}
                          data-svg-url={Icon.svg_url(icon, default_size(icon.sizes))}
                          data-name={icon.name}
                        >
                          <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path
                              stroke-linecap="round"
                              stroke-linejoin="round"
                              stroke-width="2"
                              d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4"
                            />
                          </svg>
                        </button>
                      </div>
                    </div>
                  </td>
                <% else %>
                  <%= for size <- @display_sizes do %>
                    <td class="px-2 py-3 text-center">
                      <%= if size in icon.sizes do %>
                        <div class="has-popover inline-block text-success font-black text-lg">
                          ✓
                          <div class="floating-popover">
                            <%= for platform <- preferred_platforms_for(icon, @platform_prefs_by_set, 2) do %>
                              <button
                                type="button"
                                class={["floating-popover-btn", platform_color(platform)]}
                                title={
                                  t("iconSearch.tooltips.copyPlatformIdentifierSized", %{
                                    platform: platform,
                                    size: size
                                  })
                                }
                                phx-click={
                                  JS.dispatch("phx:copy_text",
                                    detail: copy_detail(icon, platform, size)
                                  )
                                }
                                phx-value-stop-propagation="true"
                              >
                                <.platform_icon name={to_string(platform)} class="w-5 h-5" />
                              </button>
                            <% end %>
                            
                            <button
                              type="button"
                              class="quick-designer-download floating-popover-btn text-base-content/60"
                              title={t("iconSearch.tooltips.downloadPngZip")}
                              data-icon-id={icon.icon_id}
                              data-svg-url={Icon.svg_url(icon, size)}
                              data-name={icon.name}
                            >
                              <svg
                                class="w-5 h-5"
                                fill="none"
                                stroke="currentColor"
                                viewBox="0 0 24 24"
                              >
                                <path
                                  stroke-linecap="round"
                                  stroke-linejoin="round"
                                  stroke-width="2"
                                  d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4"
                                />
                              </svg>
                            </button>
                          </div>
                        </div>
                      <% else %>
                        <span class="text-base-content/50">✗</span>
                      <% end %>
                    </td>
                  <% end %>
                <% end %>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  defp default_size([]), do: 0

  defp default_size(sizes) do
    if 24 in sizes, do: 24, else: hd(sizes)
  end

  defp get_ios_id(icon) do
    size = default_size(icon.sizes) |> to_string()
    Map.get(Icon.platform_ids(icon, "ios"), size, "N/A")
  end

  defp get_android_id(icon) do
    size = default_size(icon.sizes) |> to_string()
    Map.get(Icon.platform_ids(icon, "android"), size, "N/A")
  end

  # Get the first N enabled platforms from user preferences
  defp preferred_platforms(prefs, count) do
    [:ios, :android, :react, :vue, :svelte, :cssclass, :htmltag, :filename]
    |> Enum.filter(&Map.get(prefs, &1, false))
    |> Enum.take(count)
  end

  # Get the first N preferred platforms FOR a specific icon — uses the icon set's
  # own prefs (from platform_prefs_by_set, falling back to defaults) AND filters
  # out platforms the set doesn't actually support (e.g. iOS/Android only exist
  # for FluentUI). Used by grid/list popovers so each icon shows only the
  # platforms relevant to its own icon set.
  defp preferred_platforms_for(icon, prefs_by_set, count) do
    prefs = prefs_for_set(prefs_by_set, icon.icon_set_code)

    [:ios, :android, :react, :vue, :svelte, :cssclass, :htmltag, :filename]
    |> Enum.filter(&Map.get(prefs, &1, false))
    |> Enum.filter(&platform_supported?(icon, &1))
    |> Enum.take(count)
  end

  # Does the icon's set actually have this platform? Inspects the formatter
  # package callbacks — a {nil, _} package means the set has no real
  # distribution for that platform.
  defp platform_supported?(icon, :ios), do: package_present?(ios_package(icon))
  defp platform_supported?(icon, :android), do: package_present?(android_package(icon))
  defp platform_supported?(icon, :react), do: package_present?(react_package(icon))
  defp platform_supported?(icon, :vue), do: package_present?(vue_package(icon))
  defp platform_supported?(icon, :svelte), do: package_present?(svelte_package(icon))
  defp platform_supported?(icon, :cssclass), do: package_present?(cssclass_package(icon))
  defp platform_supported?(icon, :htmltag), do: package_present?(cssclass_package(icon))
  defp platform_supported?(_, :filename), do: true
  defp platform_supported?(_, _), do: false

  defp package_present?({name, _url}) when is_binary(name) and name != "", do: true
  defp package_present?(_), do: false

  defp platform_color(:ios), do: "text-primary"
  defp platform_color(:android), do: "text-success"
  defp platform_color(:react), do: "text-cyan-600"
  defp platform_color(:vue), do: "text-emerald-600"
  defp platform_color(:svelte), do: "text-orange-600"
  defp platform_color(:cssclass), do: "text-pink-600"
  defp platform_color(:htmltag), do: "text-fuchsia-600"
  defp platform_color(:filename), do: "text-base-content/70"
  defp platform_color(_), do: "text-base-content/70"

  defp get_platform_id(icon, :ios), do: get_ios_id(icon)
  defp get_platform_id(icon, :android), do: get_android_id(icon)
  defp get_platform_id(icon, :react), do: react_identifier(icon, default_size(icon.sizes))
  defp get_platform_id(icon, :vue), do: vue_identifier(icon, default_size(icon.sizes))
  defp get_platform_id(icon, :svelte), do: svelte_identifier(icon, default_size(icon.sizes))
  defp get_platform_id(icon, :cssclass), do: cssclass_identifier(icon, default_size(icon.sizes))
  defp get_platform_id(icon, :htmltag), do: htmltag_identifier(icon, default_size(icon.sizes))
  defp get_platform_id(icon, :filename), do: Icon.svg_filename(icon, default_size(icon.sizes))
  defp get_platform_id(_, _), do: "N/A"

  # Get platform identifier for a specific size
  defp copy_detail(icon, :filename, size) do
    filename = Icon.svg_filename(icon, size) || ""

    %{
      text: filename,
      platform: "filename",
      filename: filename,
      name: icon.name,
      style: icon.style_code,
      size: size,
      icon_id: icon.icon_id
    }
  end

  defp copy_detail(icon, platform, size) do
    %{
      text: get_platform_id_for_size(icon, platform, size),
      platform: to_string(platform),
      size: size,
      icon_id: icon.icon_id
    }
  end

  defp get_platform_id_for_size(icon, :ios, size) do
    Map.get(Icon.platform_ids(icon, "ios"), to_string(size), "N/A")
  end

  defp get_platform_id_for_size(icon, :android, size) do
    Map.get(Icon.platform_ids(icon, "android"), to_string(size), "N/A")
  end

  defp get_platform_id_for_size(icon, :react, size), do: react_identifier(icon, size)
  defp get_platform_id_for_size(icon, :vue, size), do: vue_identifier(icon, size)
  defp get_platform_id_for_size(icon, :svelte, size), do: svelte_identifier(icon, size)
  defp get_platform_id_for_size(icon, :cssclass, size), do: cssclass_identifier(icon, size)
  defp get_platform_id_for_size(icon, :htmltag, size), do: htmltag_identifier(icon, size)
  defp get_platform_id_for_size(icon, :filename, size), do: Icon.svg_filename(icon, size)
  defp get_platform_id_for_size(_, _, _), do: "N/A"

  # Identifier and package helpers — delegate to per-icon-set formatter modules
  # in lib/pure_admin_icons/icon_sets/. Adding a new icon set means adding one
  # file there, no changes here.
  alias PureAdminIcons.IconSets.Formatter

  defp react_identifier(icon, size), do: Formatter.react_identifier(icon, size)
  defp svelte_identifier(icon, size), do: Formatter.svelte_identifier(icon, size)
  defp vue_identifier(icon, size), do: Formatter.vue_identifier(icon, size)
  defp cssclass_identifier(icon, size), do: Formatter.cssclass_identifier(icon, size)
  defp htmltag_identifier(icon, size), do: Formatter.htmltag_identifier(icon, size)

  defp react_package(icon), do: Formatter.react_package(icon)
  defp svelte_package(icon), do: Formatter.svelte_package(icon)
  defp vue_package(icon), do: Formatter.vue_package(icon)
  defp cssclass_package(icon), do: Formatter.cssclass_package(icon)
  defp htmltag_package(icon), do: Formatter.htmltag_package(icon)
  defp ios_package(icon), do: Formatter.ios_package(icon)
  defp android_package(icon), do: Formatter.android_package(icon)

  defp react_identifier_sizes(icon), do: Formatter.react_identifier_sizes(icon)
  defp svelte_identifier_sizes(icon), do: Formatter.svelte_identifier_sizes(icon)
  defp vue_identifier_sizes(icon), do: Formatter.vue_identifier_sizes(icon)
  defp cssclass_identifier_sizes(icon), do: Formatter.cssclass_identifier_sizes(icon)
  defp htmltag_identifier_sizes(icon), do: Formatter.htmltag_identifier_sizes(icon)

  # Color method display helpers
  defp color_method_label("fill"), do: "CSS: fill / color"
  defp color_method_label("stroke"), do: "CSS: stroke / color"
  defp color_method_label("multicolor"), do: "Multicolor"
  defp color_method_label(_), do: ""

  defp color_method_class("fill"), do: "bg-blue-100 text-blue-700"
  defp color_method_class("stroke"), do: "bg-emerald-100 text-emerald-700"
  defp color_method_class("multicolor"), do: "bg-amber-100 text-amber-700"
  defp color_method_class(_), do: "bg-base-200 text-base-content/70"

  # Format numbers with k/m suffixes (1000 -> 1k, 3400 -> 3.4k, 1500000 -> 1.5m)
  defp format_number(n) when n >= 1_000_000 do
    formatted = Float.round(n / 1_000_000, 1)
    if formatted == trunc(formatted), do: "#{trunc(formatted)}m", else: "#{formatted}m"
  end

  defp format_number(n) when n >= 1_000 do
    formatted = Float.round(n / 1_000, 1)
    if formatted == trunc(formatted), do: "#{trunc(formatted)}k", else: "#{formatted}k"
  end

  defp format_number(n), do: to_string(n)

  # Format sync timestamp as relative time or date
  defp format_sync_time(nil), do: "Never"

  defp format_sync_time(%DateTime{} = dt) do
    now = DateTime.utc_now()
    diff_seconds = DateTime.diff(now, dt, :second)

    cond do
      diff_seconds < 60 -> "just now"
      diff_seconds < 3600 -> "#{div(diff_seconds, 60)} minutes ago"
      diff_seconds < 86400 -> "#{div(diff_seconds, 3600)} hours ago"
      diff_seconds < 604_800 -> "#{div(diff_seconds, 86400)} days ago"
      true -> Calendar.strftime(dt, "%Y-%m-%d %H:%M UTC")
    end
  end
end
