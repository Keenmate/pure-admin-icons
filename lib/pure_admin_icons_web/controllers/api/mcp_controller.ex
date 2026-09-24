defmodule PureAdminIconsWeb.API.McpController do
  use PureAdminIconsWeb, :controller

  alias PureAdminIconsWeb.McpVersion

  @doc """
  MCP client-version contract. The `@keenmate/pure-admin-icons-mcp` server calls
  this once at startup to decide whether to warn the user to upgrade.

  This is the one endpoint we promise to keep stable forever — its shape must
  stay backward-compatible so the "you're outdated" signal survives any churn in
  the feature endpoints.

  ## Example

      GET /api/mcp/version
      {"latest": "1.3.0", "min_supported": "1.0.0",
       "changelog_url": "https://icons.pureadmin.io/docs/mcp"}
  """
  def version(conn, _params) do
    json(conn, McpVersion.payload())
  end
end
