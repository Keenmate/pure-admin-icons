defmodule PureAdminIconsWeb.API.IconExportController do
  @moduledoc """
  Bulk icon export as a single ZIP.

  Two actions, same request shape (a list of `(set, name, style)` icons):

    POST /api/icons/png-zip   body: {"icons": [...], "sizes": [24, 48]}
    POST /api/icons/svg-zip   body: {"icons": [...]}

  `png_zip` rasterizes each icon at each requested size (via `Rasterizer`);
  `svg_zip` bundles the raw source SVGs. Zip entries are namespaced
  `set/style/name[-size]` so the same icon requested in multiple styles never
  collides.

  Guardrails:
  - Per-IP rate limit (`RateLimiter`) → 429.
  - PNG render-units cap (`icons × sizes`) and SVG icon-count cap → 422. The
    "don't ask us to render 50k icons at every size" defense.

  Security:
  - The client never supplies a filesystem path. `name` is only a DB lookup key;
    the path is built from trusted DB columns via `Icon.local_svg_path/2` and
    re-checked to be inside `Icon.icons_dir/0`.
  - Requested sizes are validated against `Rasterizer.allowed_sizes/0`.

  Tracking: one `icon_metric` row per rendered PNG (per icon × size) for PNG, and
  one row per icon for SVG. `source: "api"`, `surface: "direct"`,
  `format: "png-zip"` / `"svg-zip"`.
  """
  use PureAdminIconsWeb, :controller

  require Logger

  alias Database.DbContext
  alias PureAdminIcons.{Icons, RateLimiter, Rasterizer}
  alias PureAdminIcons.Icons.Icon

  @max_units 200
  @max_icons 500
  @rate_limit 10
  @rate_scale :timer.minutes(1)

  # --- PNG ----------------------------------------------------------------------

  def png_zip(conn, %{"icons" => icons, "sizes" => sizes}) do
    with {:rate, {:allow, _}} <- {:rate, rate(conn)},
         {:ok, sizes} <- validate_sizes(sizes),
         {:ok, icons} <- validate_icons(icons),
         :ok <- check_units(icons, sizes),
         {:ok, models} <- DbContext.get_icon_details_by_keys(icons) do
      case build_png_zip(icons, models, sizes) do
        {:ok, zip} -> send_zip(conn, zip, "pure-admin-icons-pngs.zip")
        {:error, :empty} -> empty_result(conn, icons, models)
      end
    else
      err -> handle_error(conn, err)
    end
  end

  def png_zip(conn, _), do: bad_request(conn, "Expected `icons` (list) and `sizes` (list)")

  # --- SVG ----------------------------------------------------------------------

  def svg_zip(conn, %{"icons" => icons}) do
    with {:rate, {:allow, _}} <- {:rate, rate(conn)},
         {:ok, icons} <- validate_icons(icons),
         :ok <- check_icon_count(icons),
         {:ok, models} <- DbContext.get_icon_details_by_keys(icons) do
      case build_svg_zip(icons, models) do
        {:ok, zip} -> send_zip(conn, zip, "pure-admin-icons-svgs.zip")
        {:error, :empty} -> empty_result(conn, icons, models)
      end
    else
      err -> handle_error(conn, err)
    end
  end

  def svg_zip(conn, _), do: bad_request(conn, "Expected `icons` (list)")

  # --- zip assembly -------------------------------------------------------------

  defp build_png_zip(icons, models, sizes) do
    rendered = for m <- models, size <- sizes, do: png_entry(m, size)
    finalize(icons, models, rendered, %{sizes: sizes}, "pure-admin-icons-pngs.zip")
  end

  defp build_svg_zip(icons, models) do
    collected = for m <- models, do: svg_entry(m)
    finalize(icons, models, collected, %{}, "pure-admin-icons-svgs.zip")
  end

  defp finalize(icons, models, results, extra, zip_name) do
    files = for {:ok, entry} <- results, do: entry

    if files == [] do
      {:error, :empty}
    else
      failures = for {:error, label} <- results, do: label
      man = manifest(icons, models, Map.merge(extra, %{files: length(files), failures: failures}))
      {:ok, {_n, zip}} = :zip.create(String.to_charlist(zip_name), [{~c"manifest.json", man} | files], [:memory])
      {:ok, zip}
    end
  end

  defp png_entry(model, size) do
    label = "#{model.icon_set_code}/#{model.style_code}/#{safe_base(model.name)}-#{size}.png"

    with path when is_binary(path) <- source_path(model),
         true <- within_icons_dir?(path) and File.exists?(path),
         {:ok, png} <- Rasterizer.render_png(path, size) do
      track(model, size, "png-zip")
      {:ok, {String.to_charlist(label), png}}
    else
      _ -> {:error, label}
    end
  end

  defp svg_entry(model) do
    label = "#{model.icon_set_code}/#{model.style_code}/#{safe_base(model.name)}.svg"

    with path when is_binary(path) <- source_path(model),
         true <- within_icons_dir?(path) and File.exists?(path),
         {:ok, svg} <- File.read(path) do
      track(model, nil, "svg-zip")
      {:ok, {String.to_charlist(label), svg}}
    else
      _ -> {:error, label}
    end
  end

  defp track(model, size, format) do
    Icons.track_action(model.icon_id, "download", "api", size: size, surface: "direct", format: format)
  end

  # Largest available source SVG → best upscale quality. Scalable single-source
  # icons ignore the size argument (one file), so any value resolves the same SVG.
  defp source_path(model), do: Icon.local_svg_path(model, source_size(model))

  defp source_size(%{has_single_source: true}), do: 0
  defp source_size(%{sizes: [_ | _] = sizes}), do: Enum.max(sizes)

  defp source_size(%{filenames: f}) when is_map(f) and map_size(f) > 0 do
    f |> Map.keys() |> Enum.map(&to_int/1) |> Enum.reject(&is_nil/1) |> Enum.max(fn -> 0 end)
  end

  defp source_size(_), do: 0

  # Belt-and-suspenders: the path is already built from trusted DB columns, but
  # confirm it resolves inside the configured icons directory before touching disk.
  defp within_icons_dir?(path) do
    base = Path.expand(Icon.icons_dir())
    full = Path.expand(path)
    full == base or String.starts_with?(full, base <> "/")
  end

  defp manifest(icons, models, extra) do
    resolved = MapSet.new(models, & &1.request_index)

    skipped =
      icons
      |> Enum.with_index()
      |> Enum.reject(fn {_triple, idx} -> MapSet.member?(resolved, idx) end)
      |> Enum.map(fn {triple, _idx} -> triple end)

    base = %{
      generator: "icons.pureadmin.io — API bulk export",
      requested: length(icons),
      resolved: length(models),
      skipped: skipped
    }

    Jason.encode!(Map.merge(base, extra), pretty: true)
  end

  # --- validation ---------------------------------------------------------------

  defp validate_sizes(sizes) when is_list(sizes) do
    parsed = sizes |> Enum.map(&to_int/1) |> Enum.uniq()

    cond do
      Enum.any?(parsed, &is_nil/1) -> {:error, "sizes must be integers"}
      parsed == [] -> {:error, "sizes must not be empty"}
      Enum.any?(parsed, &(&1 not in Rasterizer.allowed_sizes())) ->
        {:error, "allowed sizes: #{Enum.join(Rasterizer.allowed_sizes(), ", ")}"}
      true -> {:ok, parsed}
    end
  end

  defp validate_sizes(_), do: {:error, "sizes must be a list"}

  defp validate_icons(icons) when is_list(icons) and icons != [] do
    normalized =
      Enum.map(icons, fn
        %{"set" => s, "name" => n, "style" => st}
        when is_binary(s) and is_binary(n) and is_binary(st) ->
          %{"set" => s, "name" => n, "style" => st}

        _ ->
          :invalid
      end)

    if :invalid in normalized do
      {:error, "each icon needs string `set`, `name`, and `style`"}
    else
      {:ok, normalized}
    end
  end

  defp validate_icons(_), do: {:error, "`icons` must be a non-empty list"}

  defp check_units(icons, sizes) do
    units = length(icons) * length(sizes)
    if units <= @max_units, do: :ok, else: {:error, {:too_many_units, units}}
  end

  defp check_icon_count(icons) do
    if length(icons) <= @max_icons, do: :ok, else: {:error, {:too_many_icons, length(icons)}}
  end

  # --- responses ----------------------------------------------------------------

  defp send_zip(conn, zip, filename) do
    conn
    |> put_resp_content_type("application/zip")
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
    |> send_resp(200, zip)
  end

  defp empty_result(conn, icons, models) do
    conn
    |> put_status(422)
    |> json(%{error: "No icons could be exported", requested: length(icons), resolved: length(models)})
  end

  defp bad_request(conn, msg), do: conn |> put_status(400) |> json(%{error: msg})

  defp handle_error(conn, {:rate, {:deny, retry_ms}}) do
    conn
    |> put_resp_header("retry-after", to_string(div(retry_ms, 1000)))
    |> put_status(429)
    |> json(%{error: "Too many export requests", retry_after_seconds: div(retry_ms, 1000)})
  end

  defp handle_error(conn, {:error, {:too_many_units, got}}) do
    conn
    |> put_status(422)
    |> json(%{error: "Batch too large", max_render_units: @max_units, requested_units: got,
              hint: "icons × sizes must be ≤ #{@max_units}"})
  end

  defp handle_error(conn, {:error, {:too_many_icons, got}}) do
    conn
    |> put_status(422)
    |> json(%{error: "Batch too large", max_icons: @max_icons, requested_icons: got})
  end

  defp handle_error(conn, {:error, msg}) when is_binary(msg) do
    conn |> put_status(422) |> json(%{error: msg})
  end

  defp handle_error(conn, {:error, reason}) do
    Logger.error("[icon_export] resolve failed: #{inspect(reason)}")
    conn |> put_status(500) |> json(%{error: "Internal error"})
  end

  # --- helpers ------------------------------------------------------------------

  defp rate(conn), do: RateLimiter.hit("iconzip:#{client_ip(conn)}", @rate_scale, @rate_limit)

  defp safe_base(name) do
    name |> String.downcase() |> String.replace(~r/[^a-z0-9]+/u, "-") |> String.trim("-")
  end

  defp to_int(n) when is_integer(n), do: n

  defp to_int(n) when is_binary(n) do
    case Integer.parse(n) do
      {i, ""} -> i
      _ -> nil
    end
  end

  defp to_int(_), do: nil

  defp client_ip(conn) do
    case Plug.Conn.get_req_header(conn, "x-forwarded-for") do
      [forwarded | _] -> forwarded |> String.split(",") |> hd() |> String.trim()
      [] -> conn.remote_ip |> :inet.ntoa() |> to_string()
    end
  end
end
