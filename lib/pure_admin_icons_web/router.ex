defmodule PureAdminIconsWeb.Router do
  use PureAdminIconsWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {PureAdminIconsWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug PureAdminIconsWeb.Plugs.Locale
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Icon SVG files — minimal pipeline, no session/CSRF overhead
  scope "/icons", PureAdminIconsWeb do
    get "/:icon_set/:style/:filename", IconFileController, :show
    get "/:style/:filename", IconFileController, :show
  end

  scope "/", PureAdminIconsWeb do
    pipe_through :browser

    get "/errors/:code", ErrorPreviewController, :show

    live_session :default, on_mount: {PureAdminIconsWeb.Plugs.Locale, :default} do
      live "/", IconSearchLive
      live "/docs", Docs.DocsIndexLive
      live "/docs/api", Docs.ApiDocsLive
      live "/docs/mcp", Docs.McpDocsLive
      live "/docs/llms", Docs.LlmsDocsLive
      live "/docs/icon-sets", Docs.IconSetsDocsLive
      live "/stats", AdminStatsLive
      live "/sync/discrepancies", SyncDiscrepanciesLive
    end
  end

  scope "/api", PureAdminIconsWeb.API do
    pipe_through :api

    get "/icons/search", IconController, :search
    get "/icons/:id", IconController, :show
    get "/icon-sets", IconController, :icon_sets
    get "/download/:icon_set/:style/:filename", DownloadController, :show
    post "/icons/png-zip", IconExportController, :png_zip
    post "/icons/svg-zip", IconExportController, :svg_zip
    get "/health", HealthController, :index
    get "/mcp/version", McpController, :version
    post "/maintenance/:task", MaintenanceController, :run
    post "/maintenance/:task/:icon_set", MaintenanceController, :run

    # Catch-all: turn unmatched /api/* into a normal 404 (not a raised
    # NoRouteError) so the X-MCP-* version headers still ride the response. Must
    # stay last — declared routes above win. See FallbackController.
    match :*, "/*path", FallbackController, :not_found
  end

  # Other scopes may use custom stacks.
  # scope "/api", PureAdminIconsWeb do
  #   pipe_through :api
  # end
end
