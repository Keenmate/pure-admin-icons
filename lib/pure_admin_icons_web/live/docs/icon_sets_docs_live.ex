defmodule PureAdminIconsWeb.Docs.IconSetsDocsLive do
  use PureAdminIconsWeb, :live_view

  import PureAdminIcons.Translations, only: [t: 1, t: 2]

  alias PureAdminIcons.Icons
  alias PureAdminIcons.IconSets

  # Sets whose served SVGs are normalized during sync (hardcoded colors rewritten
  # to currentColor for theming), so the served files are not byte-identical to
  # upstream. Kept in sync with the adapters that transform SVGs on copy.
  @svg_normalized_sets ~w(material carbon simpleicons solar mingcute)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, t("iconSets.headers.pageTitle"))
     |> assign(:icon_sets, Icons.list_icon_sets())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.site_nav />
    <div class="max-w-5xl mx-auto px-4 py-10">
      <div class="rounded-box bg-base-200 overflow-hidden border border-base-300 p-8 mb-6">
        <h1 class="text-3xl font-bold mb-2">{t("iconSets.headers.pageTitle")}</h1>
        <p class="text-base-content/80 mb-1">
          {t("iconSets.messages.summary", %{count: length(@icon_sets)})}
        </p>
        <p class="text-base-content/50 text-sm">
          {t("iconSets.messages.helpText")}
        </p>
      </div>

      <div class="space-y-4">
        <%= for set <- @icon_sets do %>
          <.set_card set={set} />
        <% end %>
      </div>

      <footer class="text-center text-base-content/50 text-xs py-8">
        icons.pureadmin.io &middot; {t("common.labels.by")}
        <a href="https://keenmate.com" class="hover:text-primary">KeenMate</a>
      </footer>
    </div>
    """
  end

  attr :set, :any, required: true

  defp set_card(assigns) do
    ~H"""
    <article class="rounded-xl border border-base-300 bg-base-100 overflow-hidden">
      <div
        class="h-2"
        style={IconSets.Color.bar_style(@set.code)}
      >
      </div>
      <div class="p-6">
        <div class="flex flex-wrap items-start justify-between gap-3 mb-3">
          <div>
            <div class="flex items-center gap-2 mb-1">
              <h2 class="text-xl font-semibold">
                {@set.display_title || @set.title}
              </h2>
              <span
                class="badge badge-sm font-mono"
                style={IconSets.Color.badge_style(@set.code)}
              >
                {@set.code}
              </span>
              <%= if svg_normalized?(@set.code) do %>
                <span
                  class="badge badge-sm badge-warning badge-outline gap-1"
                  title={t("iconSets.tooltips.normalizedSvg")}
                >
                  <.icon name="hero-information-circle" class="size-3" />
                  {t("iconSets.labels.normalizedSvg")}
                </span>
              <% end %>
            </div>
            <%= if @set.description && @set.description != "" do %>
              <p class="text-sm text-base-content/85">{@set.description}</p>
            <% end %>
          </div>
          <div class="text-right shrink-0">
            <div class="text-2xl font-bold tabular-nums">{format_count(@set.icon_count)}</div>
            <div class="text-xs text-base-content/50 uppercase tracking-wide">
              {t("iconSets.labels.iconsSuffix")}
            </div>
          </div>
        </div>

        <dl class="grid gap-3 sm:grid-cols-2 mb-4">
          <.info_row label={t("iconSets.labels.license")} value={@set.license} />
          <.info_row label={t("iconSets.labels.defaultSize")} value={"#{@set.default_size} px"} />
          <.info_row label={t("iconSets.labels.sizes")}>
            <%= cond do %>
              <% @set.has_single_source -> %>
                <span class="text-base-content/85">{t("common.labels.scalable")}</span>
              <% @set.sizes && @set.sizes != [] -> %>
                <span class="font-mono">{Enum.join(@set.sizes, ", ")} px</span>
              <% true -> %>
                <span class="text-base-content/50">—</span>
            <% end %>
          </.info_row>
          <.info_row label={t("iconSets.labels.vectorRaster")}>
            <%= if @set.is_scalable do %>
              <span class="text-success">{t("iconSets.messages.vector")}</span>
            <% else %>
              <span class="text-warning">{t("iconSets.messages.raster")}</span>
            <% end %>
          </.info_row>
          <.info_row label={t("iconSets.labels.lastSynced")}>
            <%= if @set.last_synced_at do %>
              <span
                class="text-base-content/85"
                title={Calendar.strftime(@set.last_synced_at, "%Y-%m-%d %H:%M:%S UTC")}
              >
                {format_sync_time(@set.last_synced_at)}
              </span>
            <% else %>
              <span class="text-base-content/50">—</span>
            <% end %>
          </.info_row>
        </dl>

        <div class="mb-4">
          <div class="text-xs font-semibold text-base-content/80 uppercase tracking-wide mb-1.5">
            {t("iconSets.headers.styles")}
          </div>
          <div class="flex flex-wrap gap-1.5">
            <%= for style <- @set.styles || [] do %>
              <span
                class="badge badge-sm badge-outline font-mono"
                title={style_title(@set, style)}
              >
                {style}
                <%= if native = native_name(@set, style) do %>
                  <span class="opacity-60 ml-1">({native})</span>
                <% end %>
              </span>
            <% end %>
          </div>
        </div>

        <div class="flex flex-wrap gap-2 mb-4">
          <%= if @set.homepage_url && @set.homepage_url != "" do %>
            <a
              href={@set.homepage_url}
              target="_blank"
              rel="noreferrer"
              class="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-sm font-medium bg-base-200 hover:bg-base-300 transition-colors"
            >
              <.icon name="hero-globe-alt" class="size-4" /> {t("common.buttons.homepage")}
            </a>
          <% end %>
          <%= if @set.github_url && @set.github_url != "" do %>
            <a
              href={@set.github_url}
              target="_blank"
              rel="noreferrer"
              class="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-sm font-medium bg-base-200 hover:bg-base-300 transition-colors"
            >
              <.icon name="hero-code-bracket" class="size-4" /> {t("common.buttons.github")}
            </a>
          <% end %>
          <a
            href={"/?set=#{@set.code}"}
            class="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-sm font-medium bg-primary/10 text-primary hover:bg-primary/20 transition-colors"
          >
            <.icon name="hero-magnifying-glass" class="size-4" /> {t("iconSets.buttons.browseIcons")}
          </a>
        </div>

        <%= if @set.notes && String.trim(@set.notes) != "" do %>
          <div class="border-l-4 border-warning/60 bg-warning/5 rounded-r-lg p-3">
            <div class="flex items-center gap-1.5 text-xs font-semibold text-warning uppercase tracking-wide mb-1.5">
              <.icon name="hero-information-circle" class="size-4" /> {t("iconSets.headers.notes")}
            </div>
            <div class="text-sm text-base-content/80 whitespace-pre-wrap">{@set.notes}</div>
          </div>
        <% end %>
      </div>
    </article>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, default: nil
  slot :inner_block

  defp info_row(assigns) do
    ~H"""
    <div>
      <dt class="text-xs font-semibold text-base-content/80 uppercase tracking-wide">{@label}</dt>
      <dd class="text-sm mt-0.5">
        <%= if @inner_block != [] do %>
          {render_slot(@inner_block)}
        <% else %>
          {@value}
        <% end %>
      </dd>
    </div>
    """
  end

  defp svg_normalized?(code), do: code in @svg_normalized_sets

  # Returns the native-source name for a canonical style, if it differs.
  defp native_name(%{native_style_names: nsn}, style) when is_map(nsn) do
    case Map.get(nsn, style) do
      n when is_binary(n) and n != "" and n != style -> n
      _ -> nil
    end
  end

  defp native_name(_, _), do: nil

  defp style_title(set, style) do
    color_method = Map.get(set.style_color_methods || %{}, style)
    native = native_name(set, style)

    [
      if(native, do: t("iconSets.tooltips.nativeName", %{native: native})),
      if(color_method, do: t("iconSets.tooltips.colorMethod", %{method: color_method}))
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  # Format a sync timestamp as friendly relative time, falling back to an
  # absolute UTC date for anything older than a week.
  defp format_sync_time(%DateTime{} = dt) do
    diff_seconds = DateTime.diff(DateTime.utc_now(), dt, :second)

    cond do
      diff_seconds < 60 -> t("common.time.justNow")
      diff_seconds < 3600 -> t("common.time.minutesAgo", %{count: div(diff_seconds, 60)})
      diff_seconds < 86_400 -> t("common.time.hoursAgo", %{count: div(diff_seconds, 3600)})
      diff_seconds < 604_800 -> t("common.time.daysAgo", %{count: div(diff_seconds, 86_400)})
      true -> Calendar.strftime(dt, "%Y-%m-%d %H:%M UTC")
    end
  end

  defp format_count(nil), do: "0"

  defp format_count(n) when is_integer(n) and n >= 1_000 do
    "#{Float.round(n / 1_000, 1)}k"
  end

  defp format_count(n), do: to_string(n)
end
