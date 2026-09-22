defmodule PureAdminIconsWeb.API.MaintenanceController do
  @moduledoc """
  Controller for maintenance API endpoints.
  Allows triggering maintenance tasks remotely via authenticated HTTP requests.

  Protected by:
  - API key authentication via X-API-Key header (MAINTENANCE_API_KEY env var)
  - Rate limiting (5 attempts per 5 minutes per IP)
  - Timing-safe comparison to prevent timing attacks

  Usage:
    curl -X POST -H "X-API-Key: your-key" https://example.com/api/maintenance/sync
  """
  use PureAdminIconsWeb, :controller

  # 5 attempts per 5 minutes per IP
  @rate_limit 5
  @rate_scale :timer.minutes(5)

  def run(conn, %{"task" => task}) do
    ip = get_client_ip(conn)
    api_key = get_api_key(conn)
    configured_key = Application.get_env(:pure_admin_icons, :maintenance_api_key)

    case PureAdminIcons.RateLimiter.hit("maintenance:#{ip}", @rate_scale, @rate_limit) do
      {:deny, retry_after} ->
        conn
        |> put_resp_header("retry-after", to_string(div(retry_after, 1000)))
        |> put_status(429)
        |> json(%{error: "Too many attempts", retry_after_seconds: div(retry_after, 1000)})

      {:allow, _count} ->
        cond do
          is_nil(configured_key) or configured_key == "" ->
            conn |> put_status(503) |> json(%{error: "Maintenance API not configured"})

          is_nil(api_key) or api_key == "" ->
            conn |> put_status(401) |> json(%{error: "Missing X-API-Key header"})

          not Plug.Crypto.secure_compare(api_key, configured_key) ->
            conn |> put_status(401) |> json(%{error: "Invalid API key"})

          true ->
            execute_task(conn, task)
        end
    end
  end

  defp get_api_key(conn) do
    case Plug.Conn.get_req_header(conn, "x-api-key") do
      [key | _] -> key
      [] -> nil
    end
  end

  defp get_client_ip(conn) do
    # Check X-Forwarded-For for proxied requests (Traefik)
    case Plug.Conn.get_req_header(conn, "x-forwarded-for") do
      [forwarded | _] -> forwarded |> String.split(",") |> hd() |> String.trim()
      [] -> conn.remote_ip |> :inet.ntoa() |> to_string()
    end
  end

  # Task execution (async - returns immediately)
  defp execute_task(conn, "sync") do
    icon_set = conn.params["icon_set"]

    if icon_set do
      available = PureAdminIcons.Sync.Adapter.available_icon_sets()

      if icon_set in available do
        Task.start(fn -> PureAdminIcons.Sync.Worker.sync_icon_set(icon_set) end)
        json(conn, %{status: "started", task: "sync", icon_set: icon_set})
      else
        conn
        |> put_status(400)
        |> json(%{error: "Unknown icon set", icon_set: icon_set, available: available})
      end
    else
      Task.start(fn -> PureAdminIcons.Sync.Worker.sync_all() end)
      json(conn, %{status: "started", task: "sync"})
    end
  end

  defp execute_task(conn, "clean") do
    Task.start(fn ->
      PureAdminIcons.Repo.query!("TRUNCATE public.icon CASCADE")
    end)
    json(conn, %{status: "started", task: "clean"})
  end

  defp execute_task(conn, unknown) do
    conn
    |> put_status(400)
    |> json(%{error: "Unknown task", task: unknown, available: ["sync", "sync/:icon_set", "clean"]})
  end
end
