defmodule PureAdminIcons.Audit do
  @moduledoc """
  Writes usage metrics to the audit event log (`audit.session` / `audit.event`)
  via `Database.DbContext`.

  Every signal — search, copy, download — is an `audit.event`. Icon identity is
  snapshotted server-side (inside the SQL constructors) so metrics survive an icon
  being deleted or re-synced. Events optionally reference an `audit.session` by
  `session_uid`; the link is soft (no FK), so a missing/absent session never blocks
  a write (API/MCP callers may have no session).

  All writers are fire-and-forget from the caller's perspective: they return the
  `DbContext` result (`{:ok, _} | {:error, _}`) but never raise.

  Absent optional values are passed as `nil` (SQL NULL) rather than omitted, so the
  generated positional `$N` placeholders stay aligned — only the trailing
  `_created_by` is left to its DB default.
  """
  require Logger

  alias Database.DbContext

  @doc """
  Register (or touch) a session. `session_uid` may be `nil`, in which case this is
  a no-op (events will simply be ungrouped).

  `opts` may carry `:user_data` and `:request_data` maps (referrer, user agent, utm…).
  """
  def ensure_session(_source, nil, _opts), do: :ok

  def ensure_session(source, session_uid, opts) when is_binary(session_uid) do
    safe(fn ->
      DbContext.audit_ensure_session(source, session_uid, opts[:user_data], opts[:request_data])
    end)
  end

  @doc """
  Record a search event. Callers should only invoke this for *real* searches
  (non-empty, de-duped) — navigation/pagination is not a search.

  `opts`: `:result_count`, `:size`, `:style`, `:icon_set`, `:utm`.
  """
  def track_search(session_uid, source, query, opts \\ []) do
    safe(fn ->
      DbContext.audit_create_search_event(
        session_uid,
        source,
        query,
        opts[:result_count],
        opts[:size],
        opts[:style],
        opts[:icon_set],
        opts[:utm]
      )
    end)
  end

  @doc """
  Record a copy/download event for a single icon. Identity is snapshotted from
  `public.icon` inside the SQL function.

  `action` is `"copy"` or `"download"`. `opts`: `:size`, `:surface`, `:format`,
  `:platform`, `:utm`.
  """
  def track_action(session_uid, source, icon_id, action, opts \\ []) do
    safe(fn ->
      DbContext.audit_create_icon_action_event(
        session_uid,
        source,
        icon_id,
        action,
        opts[:size],
        opts[:surface],
        opts[:format],
        opts[:platform],
        opts[:utm]
      )
    end)
  end

  @doc """
  Record an icon-scoped engagement event (e.g. `"icon_detail_opened"`,
  `"icon_basket_added"`, `"icon_basket_removed"`). Identity is snapshotted from
  `public.icon`. `opts`: `:utm`.
  """
  def track_event(session_uid, source, icon_id, event_type_code, opts \\ []) do
    safe(fn ->
      DbContext.audit_create_icon_event(session_uid, source, icon_id, event_type_code, opts[:utm])
    end)
  end

  @doc """
  Record a session-level event not tied to a single icon (e.g. `"basket_cleared"`),
  via the generic writer. `event_data` is a plain map stored as jsonb. `opts`: `:utm`.
  """
  def track_session_event(session_uid, source, event_type_code, event_data, opts \\ []) do
    safe(fn ->
      DbContext.audit_create_event(session_uid, source, event_type_code, event_data, opts[:utm])
    end)
  end

  # Never let a metrics write crash a request/LiveView path.
  defp safe(fun) do
    try do
      case fun.() do
        {:ok, _} = ok ->
          ok

        {:error, reason} = err ->
          Logger.warning("[audit] write failed: #{inspect(reason)}")
          err

        other ->
          {:ok, other}
      end
    rescue
      e ->
        Logger.warning("[audit] write raised: #{inspect(e)}")
        {:error, e}
    end
  end
end
