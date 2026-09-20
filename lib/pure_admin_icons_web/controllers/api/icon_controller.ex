defmodule PureAdminIconsWeb.API.IconController do
  use PureAdminIconsWeb, :controller

  alias PureAdminIcons.Icons
  alias PureAdminIcons.Icons.Icon
  alias PureAdminIcons.SearchMetricsCollector

  @doc """
  Search for icons across all icon sets.

  ## Query Parameters
    * `q` - Search query (required)
    * `set` - Filter by icon set (optional, repeatable, e.g., "fluentui", "lucide", "tabler", "heroicons", "fontawesome")
    * `size` - Filter by size (optional, e.g., "24", "48")
    * `style` - Filter by style (optional, e.g., "regular", "filled", "outline", "solid", "brands")
    * `limit` - Max results (optional, default: 50, max: 100)
    * `format` - Response format (optional, default: "json")
      * "json" - Full response with all fields
      * "compact" - Minimal JSON with name, style, url
      * "text" - Plain text, one icon per line (most token-efficient for AI)

  ## Examples

      GET /api/icons/search?q=pen
      GET /api/icons/search?q=pen&set=fluentui
      GET /api/icons/search?q=pen&set=lucide&set=tabler
      GET /api/icons/search?q=calendar&style=regular&limit=20
      GET /api/icons/search?q=pen&format=text
  """
  def search(conn, params) do
    query = params["q"] || ""
    icon_sets = parse_icon_sets(params["set"])
    size = parse_size(params["size"])
    style = params["style"]
    limit = parse_limit(params["limit"])
    format = params["format"] || "json"

    # Build search options
    opts = [limit: limit]
    opts = if icon_sets != [], do: Keyword.put(opts, :icon_sets, icon_sets), else: opts
    opts = if size, do: Keyword.put(opts, :sizes, [size]), else: opts
    opts = if style, do: Keyword.put(opts, :styles, [style]), else: opts

    icons = case Icons.search(query, opts) do
      {:ok, results} -> results
      {:error, _} -> []
    end
    result_count = length(icons)

    # Record search metrics (batched, non-blocking) - include first icon_set if filtered
    icon_set_code = if icon_sets != [], do: hd(icon_sets), else: nil
    SearchMetricsCollector.record(query, size, style, result_count, "api", icon_set_code)

    format_response(conn, format, %{query: query, icons: icons})
  end

  @doc """
  Get a single icon by ID.

  ## Examples

      GET /api/icons/123
  """
  def show(conn, %{"id" => id}) do
    case Integer.parse(id) do
      {icon_id, _} ->
        case Icons.get_icon(icon_id) do
          {:ok, icon} ->
            json(conn, %{icon: format_icon_detail(icon)})

          {:error, :not_found} ->
            conn |> put_status(404) |> json(%{error: "Icon not found"})

          {:error, _} ->
            conn |> put_status(500) |> json(%{error: "Internal error"})
        end

      :error ->
        conn |> put_status(400) |> json(%{error: "Invalid icon ID"})
    end
  end

  @doc """
  List all available icon sets with metadata.

  ## Examples

      GET /api/icon-sets
  """
  def icon_sets(conn, _params) do
    sets = Icons.list_icon_sets()

    formatted = Enum.map(sets, fn set ->
      %{
        code: set.code,
        title: set.title,
        description: set.description,
        notes: set.notes,
        license: set.license,
        homepage_url: set.homepage_url,
        github_url: set.github_url,
        styles: set.styles,
        sizes: set.sizes,
        default_size: set.default_size,
        style_color_methods: set.style_color_methods,
        is_scalable: set.is_scalable,
        has_single_source: set.has_single_source,
        icon_count: set.icon_count
      }
    end)

    json(conn, %{icon_sets: formatted})
  end

  defp parse_icon_sets(nil), do: []
  defp parse_icon_sets(""), do: []
  defp parse_icon_sets(set) when is_binary(set), do: [set]
  defp parse_icon_sets(sets) when is_list(sets), do: sets

  defp parse_size(nil), do: nil
  defp parse_size(""), do: nil

  defp parse_size(s) do
    case Integer.parse(s) do
      {size, _} -> size
      :error -> nil
    end
  end

  defp parse_limit(nil), do: 50
  defp parse_limit(""), do: 50

  defp parse_limit(s) do
    case Integer.parse(s) do
      {limit, _} -> min(limit, 100)
      :error -> 50
    end
  end

  # Full format for search results
  defp format_icon(icon) do
    %{
      id: icon.icon_id,
      icon_set: icon.icon_set_code,
      name: icon.name,
      style: icon.style_code,
      style_color_method: icon.style_color_method,
      sizes: icon.sizes,
      is_scalable: Map.get(icon, :is_scalable, false),
      has_single_source: Map.get(icon, :has_single_source, false),
      ios: Icon.platform_ids(icon, "ios"),
      android: Icon.platform_ids(icon, "android"),
      svg_url: Icon.svg_url(icon, default_size(icon.sizes))
    }
  end

  # Full format for icon detail
  defp format_icon_detail(icon) do
    single_source = Map.get(icon, :has_single_source, false)

    %{
      id: icon.icon_id,
      icon_set: icon.icon_set_code,
      icon_set_title: icon.icon_set_title,
      name: icon.name,
      style: icon.style_code,
      style_color_method: icon.style_color_method,
      sizes: icon.sizes,
      is_scalable: Map.get(icon, :is_scalable, false),
      has_single_source: single_source,
      filenames: icon.filenames,
      ios: Icon.platform_ids(icon, "ios"),
      android: Icon.platform_ids(icon, "android"),
      categories: icon.categories,
      phrases: icon.phrases,
      svg_urls:
        if single_source do
          [%{size: nil, url: Icon.svg_url(icon, 0)}]
        else
          Enum.map(icon.sizes, fn size -> %{size: size, url: Icon.svg_url(icon, size)} end)
        end
    }
  end

  defp default_size([]), do: 0
  defp default_size(sizes) when is_list(sizes) do
    if 24 in sizes, do: 24, else: hd(sizes)
  end

  defp default_size(_), do: 24

  # Response formatters

  defp format_response(conn, "compact", %{query: query, icons: icons}) do
    json(conn, %{
      query: query,
      count: length(icons),
      results: Enum.map(icons, &format_icon_compact/1)
    })
  end

  defp format_response(conn, "text", %{icons: icons}) do
    text =
      icons
      |> Enum.map(&format_icon_text/1)
      |> Enum.join("\n")

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, text)
  end

  defp format_response(conn, _json, %{query: query, icons: icons}) do
    json(conn, %{
      query: query,
      count: length(icons),
      results: Enum.map(icons, &format_icon/1)
    })
  end

  defp format_icon_compact(icon) do
    %{
      icon_set: icon.icon_set_code,
      name: icon.name,
      style: icon.style_code,
      url: Icon.svg_url(icon, default_size(icon.sizes))
    }
  end

  defp format_icon_text(icon) do
    url = Icon.svg_url(icon, default_size(icon.sizes))
    "[#{icon.icon_set_code}] #{icon.name} → #{icon.style_code}: #{url}"
  end
end
