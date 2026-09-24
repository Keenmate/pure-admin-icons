defmodule PureAdminIconsWeb.Plugs.McpVersionHeaders do
  @moduledoc """
  Stamps the MCP version contract onto every response:

    * `x-mcp-latest` — newest published MCP version
    * `x-mcp-min-supported` — hard floor
    * `sunset` — optional hard-cutoff date (RFC 8594), when configured

  Registered at the endpoint (via `register_before_send/2`) so the headers ride
  every ordinary response — including error responses returned via
  `put_status |> json` from a matched route.

  Note the one gap it does *not* cover on its own: a raised `NoRouteError` is
  rendered by Phoenix on the endpoint-entry conn (before this `before_send` was
  registered), so those responses carry no headers. Unmatched `/api/*` paths are
  therefore routed to `PureAdminIconsWeb.API.FallbackController`, which returns a
  *normal* `404` so the headers ride there too — the renamed/removed-endpoint
  case. See `PureAdminIconsWeb.McpVersion`.
  """
  import Plug.Conn

  alias PureAdminIconsWeb.McpVersion

  def init(opts), do: opts

  def call(conn, _opts) do
    register_before_send(conn, fn conn ->
      conn
      |> put_resp_header("x-mcp-latest", McpVersion.latest())
      |> put_resp_header("x-mcp-min-supported", McpVersion.min_supported())
      |> maybe_put_sunset()
    end)
  end

  defp maybe_put_sunset(conn) do
    case McpVersion.sunset() do
      sunset when is_binary(sunset) and sunset != "" ->
        put_resp_header(conn, "sunset", sunset)

      _ ->
        conn
    end
  end
end
