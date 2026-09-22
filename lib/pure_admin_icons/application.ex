defmodule PureAdminIcons.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      PureAdminIcons.Repo,
      PureAdminIconsWeb.Telemetry,
      {Phoenix.PubSub, name: PureAdminIcons.PubSub},
      {PureAdminIcons.RateLimiter, clean_period: :timer.minutes(1)},
      PureAdminIcons.SearchMetricsCollector,
      PureAdminIcons.Scheduler,
      {DNSCluster, query: Application.get_env(:pure_admin_icons, :dns_cluster_query) || :ignore},
      PureAdminIconsWeb.Endpoint,
      {Task, &maybe_initial_sync/0}
    ]

    opts = [strategy: :one_for_one, name: PureAdminIcons.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp maybe_initial_sync do
    require Logger

    PureAdminIcons.Sync.SvgDownloader.log_extraction_tools()
    Process.sleep(2000)

    db_empty = PureAdminIcons.Icons.count() == 0
    files_empty = not PureAdminIcons.Sync.SvgDownloader.icons_downloaded?()

    cond do
      db_empty and files_empty ->
        Logger.info("DB and files empty, starting full sync...")
        PureAdminIcons.Sync.Worker.sync_all()

      db_empty ->
        Logger.info("DB empty (files present), starting full sync...")
        PureAdminIcons.Sync.Worker.sync_all()

      files_empty ->
        Logger.info("Files empty (DB present), starting full sync...")
        PureAdminIcons.Sync.Worker.sync_all()

      true ->
        Logger.info("DB and files present, skipping initial sync")
        # v1.11 introduced mv_icon / mv_icon_phrase. If we skipped the sync
        # but those MVs are empty (e.g. fresh migration), search returns
        # nothing. Cheap to call — concurrent refresh, no-op when current.
        case PureAdminIcons.Repo.query("SELECT internal.refresh_icon_caches()", []) do
          {:ok, _} -> Logger.info("Refreshed mv_icon / mv_icon_phrase at startup")
          {:error, reason} -> Logger.warning("startup refresh_icon_caches failed: #{inspect(reason)}")
        end
    end

    :ok
  end

  @impl true
  def config_change(changed, _new, removed) do
    PureAdminIconsWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
