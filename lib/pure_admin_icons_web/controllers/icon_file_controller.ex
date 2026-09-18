defmodule PureAdminIconsWeb.IconFileController do
  @moduledoc """
  Serves icon SVG files directly without directory scanning.
  Uses runtime configuration for icons path.

  Supports two URL patterns:
  - New: /icons/:icon_set/:style/:filename (e.g., /icons/fluentui/regular/add.svg)
  - Legacy: /icons/:style/:filename (defaults to fluentui for backwards compatibility)
  """
  use PureAdminIconsWeb, :controller

  alias PureAdminIcons.Sync.Adapter

  defp icons_dir do
    Application.get_env(:pure_admin_icons, :icons_path)
  end

  @doc """
  Serve icon SVG files.

  Supports two URL patterns:
  - New: /icons/:icon_set/:style/:filename (e.g., /icons/fluentui/regular/add.svg)
  - Legacy: /icons/:style/:filename (defaults to fluentui for backwards compatibility)
  """
  def show(conn, %{"icon_set" => icon_set, "style" => style, "filename" => filename}) do
    serve_icon(conn, icon_set, style, filename)
  end

  def show(conn, %{"style" => style, "filename" => filename}) do
    serve_icon(conn, "fluentui", style, filename)
  end

  defp serve_icon(conn, icon_set, style, filename) do
    case icons_dir() do
      nil ->
        send_resp(conn, 404, "Icons not available locally")

      dir ->
        # Validate icon_set exists
        valid_icon_sets = Adapter.available_icon_sets()

        # Get valid styles for this icon set
        valid_styles = get_valid_styles(icon_set)

        cond do
          icon_set not in valid_icon_sets ->
            send_resp(conn, 404, "Unknown icon set: #{icon_set}")

          style not in valid_styles ->
            send_resp(conn, 404, "Invalid style for #{icon_set}: #{style}")

          not String.ends_with?(filename, ".svg") ->
            send_resp(conn, 400, "Invalid file type")

          true ->
            path = Path.join([dir, icon_set, style, filename])

            if File.exists?(path) do
              serve_svg(conn, path)
            else
              # For FluentUI, redirect to GitHub as fallback
              case github_fallback_url(icon_set, style, filename) do
                nil ->
                  send_resp(conn, 404, "Not found - run 'mix icons.download #{icon_set}' to sync icons")

                url ->
                  conn
                  |> put_resp_header("cache-control", "public, max-age=3600")
                  |> redirect(external: url)
              end
            end
        end
    end
  end

  # Send the SVG with a strong ETag (size + mtime) so browsers revalidate cheaply.
  # max-age is one day — the icon import cadence — so a cached icon stays fresh for
  # at most one import cycle, then the ETag revalidation (304, or 200 when a re-sync
  # rewrote the file) picks up any changes. A longer TTL would hold stale SVGs past
  # an import; the ETag can't help while the entry is still "fresh".
  defp serve_svg(conn, path) do
    etag = file_etag(path)

    conn =
      conn
      |> put_resp_content_type("image/svg+xml")
      |> put_resp_header("cache-control", "public, max-age=86400")
      |> put_resp_header("etag", etag)

    case Plug.Conn.get_req_header(conn, "if-none-match") do
      [^etag] -> send_resp(conn, 304, "")
      _ -> send_file(conn, 200, path)
    end
  end

  defp file_etag(path) do
    %File.Stat{size: size, mtime: mtime} = File.stat!(path, time: :posix)
    # Strong ETag — changes when content replaces (sync rewrites the file).
    "\"" <> Integer.to_string(size, 16) <> "-" <> Integer.to_string(mtime, 16) <> "\""
  end

  defp github_fallback_url("fluentui", style, filename) do
    # Parse filename: ic_fluent_{name}_{size}_{style}.svg
    case Regex.run(~r/ic_fluent_(.+)_(\d+)_(\w+)\.svg/, filename) do
      [_, slug, size, _style] ->
        # Convert slug back to name (best effort)
        name = slug |> String.split("_") |> Enum.map(&String.capitalize/1) |> Enum.join(" ")
        encoded_name = URI.encode(name)
        "https://raw.githubusercontent.com/microsoft/fluentui-system-icons/main/assets/#{encoded_name}/SVG/ic_fluent_#{slug}_#{size}_#{style}.svg"

      _ ->
        nil
    end
  end

  defp github_fallback_url(_icon_set, _style, _filename), do: nil

  defp get_valid_styles(icon_set) do
    case Adapter.get_adapter(icon_set) do
      nil -> []
      adapter -> adapter.styles()
    end
  end
end
