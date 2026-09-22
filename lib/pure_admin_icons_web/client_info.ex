defmodule PureAdminIconsWeb.ClientInfo do
  @moduledoc """
  Client IP + audit session identity helpers.

  Behind Traefik (prod) the real client IP is the first hop of `x-forwarded-for`;
  fall back to the direct socket/conn peer. There is no country header under
  Traefik — the stored IP is geo-located offline to derive countries. The IP is
  kept on the `audit.session` so abusive traffic is attributable (and blockable).
  """
  alias Plug.Conn

  @doc """
  Client IP for a Plug.Conn (API requests). `RemoteIp.from/2` walks
  `Forwarded` / `X-Forwarded-For` / `X-Real-Ip`, skipping reserved/private proxy
  hops (e.g. the Traefik/docker `10.x` peer); falls back to the raw peer when no
  forwarded header carries a public address.
  """
  def ip(%Conn{} = conn) do
    fmt(RemoteIp.from(conn.req_headers)) || fmt(conn.remote_ip)
  end

  @doc """
  Client IP from LiveView `connect_info`. `x_headers` is the `:x_headers`
  connect_info (the `x-*` request headers of the socket upgrade); `peer_data` is
  the `:peer_data` connect_info. Prefers the real client from the forwarded
  headers, falls back to the socket peer, and is `nil` on the static render.
  """
  def ip_from_connect_info(x_headers, peer_data) do
    fmt(RemoteIp.from(x_headers || [])) ||
      case peer_data do
        %{address: address} when is_tuple(address) -> fmt(address)
        _ -> nil
      end
  end

  defp fmt(nil), do: nil
  defp fmt(address) when is_tuple(address), do: address |> :inet.ntoa() |> to_string()

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
