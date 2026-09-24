defmodule PureAdminIconsWeb.McpVersion do
  @moduledoc """
  Single source of truth for the MCP client-version contract the API advertises
  to `@keenmate/pure-admin-icons-mcp`.

  Values come from application config (`:pure_admin_icons, :mcp_version`) so the
  floor can be bumped per environment without a code change:

    * `latest` — newest published MCP version (drives the soft "upgrade
      available" nudge).
    * `min_supported` — hard floor; below this the API may reject/misbehave
      (drives the "must upgrade" warning, and any future `426` enforcement).

  Advertised two ways so an outdated client always gets the signal:

    * `X-MCP-Latest` / `X-MCP-Min-Supported` headers on every response — stamped
      at the endpoint (see `PureAdminIconsWeb.Plugs.McpVersionHeaders`); unmatched
      `/api/*` paths fall through to `API.FallbackController` so even a
      renamed/removed endpoint's `404` still carries them.
    * The richer JSON at `GET /api/mcp/version` — the one endpoint we promise to
      keep stable forever, so the "you're outdated" signal never depends on which
      feature endpoints still exist.
  """

  @doc "Newest published MCP version."
  def latest, do: cfg(:latest, "0.0.0")

  @doc "Hard floor MCP version; below this the API may reject/misbehave."
  def min_supported, do: cfg(:min_supported, "0.0.0")

  @doc "Optional human-readable deprecation note, or nil."
  def message, do: cfg(:message, nil)

  @doc "Optional ISO-8601 sunset date for the hard cutoff, or nil."
  def sunset, do: cfg(:sunset, nil)

  @doc "Optional changelog/docs URL, or nil."
  def changelog_url, do: cfg(:changelog_url, nil)

  @doc "Full payload for GET /api/mcp/version (nils dropped)."
  def payload do
    %{
      latest: latest(),
      min_supported: min_supported(),
      message: message(),
      sunset: sunset(),
      changelog_url: changelog_url()
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp cfg(key, default) do
    :pure_admin_icons
    |> Application.get_env(:mcp_version, [])
    |> Keyword.get(key, default)
  end
end
