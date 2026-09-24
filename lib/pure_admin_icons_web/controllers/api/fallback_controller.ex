defmodule PureAdminIconsWeb.API.FallbackController do
  use PureAdminIconsWeb, :controller

  @doc """
  Catch-all for unmatched `/api/*` routes.

  Returns a normal `404` rather than letting the router raise `NoRouteError`.
  That distinction matters: Phoenix renders a raised `NoRouteError` on the
  endpoint-entry conn, *before* `PureAdminIconsWeb.Plugs.McpVersionHeaders`
  registered its `before_send`, so those responses carry no `X-MCP-*` headers.
  Routing unmatched paths here produces an ordinary response instead, so the
  version headers ride along — which is what lets an old MCP client that calls a
  renamed/removed endpoint still receive the upgrade signal.
  """
  def not_found(conn, _params) do
    conn
    |> put_status(:not_found)
    |> json(%{
      error: "Not found",
      hint:
        "This API endpoint does not exist. If your client is outdated, see GET /api/mcp/version."
    })
  end
end
