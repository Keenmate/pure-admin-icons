defmodule PureAdminIconsWeb.ClientInfo do
  @moduledoc """
  Client IP + audit session identity helpers.

  Behind Traefik (prod) the real client IP is the first hop of `x-forwarded-for`;
  fall back to the direct socket/conn peer. There is no country header under
  Traefik — the stored IP is geo-located offline to derive countries. The IP is
  kept on the `audit.session` so abusive traffic is attributable (and blockable).
  """
  alias Plug.Conn

  @doc "Client IP for a Plug.Conn (API requests)."
  def ip(%Conn{} = conn) do
    case Conn.get_req_header(conn, "x-forwarded-for") do
      [fwd | _] when is_binary(fwd) -> fwd |> String.split(",") |> List.first() |> String.trim()
      _ -> conn.remote_ip |> :inet.ntoa() |> to_string()
    end
  end

  @doc """
  Client IP from LiveView `connect_info` — `x-forwarded-for` first hop if present,
  else the socket peer address. Returns `nil` when neither is available (e.g. the
  static/disconnected render).
  """
  def ip_from_connect_info(x_headers, peer_data) do
    xff =
      Enum.find_value(x_headers || [], fn
        {"x-forwarded-for", v} when is_binary(v) -> v
        _ -> nil
      end)

    cond do
      is_binary(xff) -> xff |> String.split(",") |> List.first() |> String.trim()
      is_map(peer_data) and is_tuple(peer_data[:address]) -> peer_data[:address] |> :inet.ntoa() |> to_string()
      true -> nil
    end
  end

  @doc "Explicit client-supplied session id (`x-session-id` header), or nil."
  def header_session(%Conn{} = conn) do
    case Conn.get_req_header(conn, "x-session-id") do
      [uid | _] when is_binary(uid) and uid != "" -> uid
      _ -> nil
    end
  end

  @doc """
  Resolve the audit session for an API request. Uses the client's `x-session-id`
  when present, otherwise a synthetic `"ip:<addr>"` id so anonymous API traffic
  still groups into a session (and stays attributable for abuse). Returns
  `{session_uid, request_data}` where `request_data` carries the IP.
  """
  def api_session(%Conn{} = conn) do
    ip = ip(conn)
    uid = header_session(conn) || "ip:" <> ip
    {uid, %{"ip" => ip}}
  end
end
