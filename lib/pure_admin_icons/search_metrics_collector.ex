defmodule PureAdminIcons.SearchMetricsCollector do
  @moduledoc """
  Collects search metrics in memory and flushes to database periodically.

  This avoids hitting the database on every API search request.
  Metrics are flushed every 30 seconds or when the buffer reaches 100 entries.
  """
  use GenServer

  require Logger

  alias PureAdminIcons.Audit

  @flush_interval :timer.seconds(30)
  @max_buffer_size 100

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Record a search query metric. This is non-blocking.

  `session_uid` groups the search into an `audit.session` (may be `nil` for
  ungrouped API traffic). `opts`: `:size`, `:style`, `:result_count`,
  `:icon_set`, `:utm`.
  """
  def record(session_uid, source_code, query, opts \\ []) do
    GenServer.cast(__MODULE__, {:record, session_uid, source_code, query, opts})
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    schedule_flush()
    {:ok, []}
  end

  @impl true
  def handle_cast({:record, session_uid, source_code, query, opts}, buffer) do
    entry = %{
      session_uid: session_uid,
      source_code: source_code,
      query: query,
      size: opts[:size],
      style: opts[:style],
      result_count: opts[:result_count],
      icon_set: opts[:icon_set],
      utm: opts[:utm]
    }

    new_buffer = [entry | buffer]

    if length(new_buffer) >= @max_buffer_size do
      flush(new_buffer)
      {:noreply, []}
    else
      {:noreply, new_buffer}
    end
  end

  @impl true
  def handle_info(:flush, buffer) do
    flush(buffer)
    schedule_flush()
    {:noreply, []}
  end

  @impl true
  def terminate(_reason, buffer) do
    # Flush remaining metrics on shutdown
    flush(buffer)
    :ok
  end

  # Private

  defp schedule_flush do
    Process.send_after(self(), :flush, @flush_interval)
  end

  defp flush([]), do: :ok

  defp flush(buffer) do
    {ok_count, errors} =
      Enum.reduce(buffer, {0, []}, fn entry, {ok, errs} ->
        try do
          case Audit.track_search(entry.session_uid, entry.source_code, entry.query,
                 result_count: entry.result_count,
                 size: entry.size,
                 style: entry.style,
                 icon_set: entry.icon_set,
                 utm: entry.utm
               ) do
            {:ok, _} -> {ok + 1, errs}
            {:error, reason} -> {ok, [{entry, reason} | errs]}
          end
        rescue
          e -> {ok, [{entry, e} | errs]}
        end
      end)

    case errors do
      [] ->
        :ok

      _ ->
        Logger.warning(
          "[SearchMetricsCollector] flush dropped #{length(errors)}/#{length(buffer)} entries; " <>
            "first failure: entry=#{inspect(elem(hd(errors), 0))} reason=#{inspect(elem(hd(errors), 1))}"
        )

        Logger.info("[SearchMetricsCollector] flushed #{ok_count} entries successfully")
    end
  end
end
