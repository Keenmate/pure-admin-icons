defmodule PureAdminIconsWeb.Layouts do
  @moduledoc """
  Layouts and shared UI components for icons.pureadmin.io.
  Mirrors the structure of pureadmin.io's layouts.
  """
  use PureAdminIconsWeb, :html

  import PureAdminIcons.Translations, only: [t: 1]

  embed_templates "layouts/*"

  attr :class, :string, default: "text-lg"

  def logo(assigns) do
    ~H"""
    <a href="/" class="font-bold hover:opacity-80 transition-opacity text-base-content">
      <span class={@class}>icons.</span><span class={["text-primary", @class]}>pure</span><span class={@class}>admin.io</span>
    </a>
    """
  end

  attr :icon_count, :any, default: nil, doc: "total icon count for the nav summary (optional)"
  attr :set_count, :any, default: nil, doc: "icon-set count for the nav summary (optional)"

  attr :basket_count, :any,
    default: nil,
    doc: "number of icons in the basket; when non-nil a basket button is shown (search page only)"

  @doc """
  Shared site navigation bar with burger menu on mobile.

  Pass `icon_count`/`set_count` to render the catalog summary inline (used on the
  search page). Other pages omit them and no summary is shown.
  """
  def site_nav(assigns) do
    ~H"""
    <nav class="relative px-4 sm:px-6 lg:px-8 py-2">
      <%!-- Desktop nav (lg and up) --%>
      <div class="hidden lg:flex items-center justify-between gap-3">
        <div class="flex items-baseline gap-1.5 min-w-0">
          <.logo class="text-lg" />
          <%= if @icon_count do %>
            <span class="text-sm text-base-content/60 whitespace-nowrap">(<span class="font-semibold text-primary">{@icon_count}</span> {t("iconSearch.headers.heroTitleMiddle")} <span class="font-semibold text-primary">{@set_count}</span> {t("iconSearch.headers.heroTitleSuffix")})</span>
          <% end %>
        </div>
        <div class="flex items-center gap-0.5">
          <a
            href="/docs"
            class="inline-flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg text-sm font-medium text-base-content/80 hover:text-primary hover:bg-base-200 transition-colors"
          >
            <.icon name="hero-book-open" class="size-4" /> {t("nav.buttons.docs")}
          </a>
          <a
            href="/docs/icon-sets"
            class="inline-flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg text-sm font-medium text-base-content/80 hover:text-primary hover:bg-base-200 transition-colors"
          >
            <.icon name="hero-squares-2x2" class="size-4" /> {t("nav.buttons.iconSets")}
          </a>
          <a
            href="/docs/api"
            class="inline-flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg text-sm font-medium text-base-content/80 hover:text-primary hover:bg-base-200 transition-colors"
          >
            <.icon name="hero-code-bracket" class="size-4" /> {t("nav.buttons.api")}
          </a>
          <a
            href="/stats"
            class="inline-flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg text-sm font-medium text-base-content/80 hover:text-primary hover:bg-base-200 transition-colors"
          >
            <.icon name="hero-chart-bar" class="size-4" /> {t("nav.buttons.stats")}
          </a>
          <a
            href="https://pureadmin.io"
            target="_blank"
            class="inline-flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg text-sm font-medium text-base-content/80 hover:text-primary hover:bg-base-200 transition-colors"
          >
            <.icon name="hero-swatch" class="size-4" /> {t("nav.buttons.themes")}
          </a>
          <a
            href="https://keenmate.com"
            target="_blank"
            rel="noreferrer"
            class="inline-flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg text-sm font-medium text-base-content/80 hover:text-primary hover:bg-base-200 transition-colors"
          >
            <.icon name="hero-building-office-2" class="size-4" /> {t("nav.buttons.keenmate")}
          </a>
          <.language_switcher />
          <%= if @basket_count != nil do %>
            <.basket_button count={@basket_count} />
          <% end %>
        </div>
      </div>
      <%!-- Mobile / tablet (below lg) --%>
      <div class="flex lg:hidden items-center justify-between gap-2">
        <div class="flex items-baseline gap-1.5 min-w-0">
          <.logo class="text-lg" />
          <%= if @icon_count do %>
            <span class="hidden sm:inline text-sm text-base-content/60 whitespace-nowrap">(<span class="font-semibold text-primary">{@icon_count}</span> {t("iconSearch.headers.heroTitleMiddle")} <span class="font-semibold text-primary">{@set_count}</span> {t("iconSearch.headers.heroTitleSuffix")})</span>
          <% end %>
        </div>
        <div class="flex items-center gap-1">
          <%= if @basket_count != nil do %>
            <.basket_button count={@basket_count} />
          <% end %>
          <button
            type="button"
            onclick="this.closest('nav').querySelector('[data-mobile-nav]').classList.toggle('hidden')"
            class="inline-flex items-center justify-center p-2 rounded-lg text-base-content/80 hover:text-primary hover:bg-base-200 transition-colors"
          >
            <.icon name="hero-bars-3" class="size-6" />
          </button>
        </div>
      </div>
      <div
        data-mobile-nav
        class="hidden lg:hidden mt-2 rounded-xl bg-base-200 border border-base-300 p-2 flex flex-col gap-1"
      >
        <%= if @icon_count do %>
          <div class="sm:hidden px-3 py-2 text-sm text-base-content/60 border-b border-base-300 mb-1">
            {t("iconSearch.headers.heroTitlePrefix")}
            <span class="font-semibold text-primary">{@icon_count}</span>
            {t("iconSearch.headers.heroTitleMiddle")}
            <span class="font-semibold text-primary">{@set_count}</span>
            {t("iconSearch.headers.heroTitleSuffix")}
          </div>
        <% end %>
        <a
          href="/docs"
          class="flex items-center gap-2 px-3 py-2.5 rounded-lg text-sm font-medium text-base-content/80 hover:text-primary hover:bg-base-300 transition-colors"
        >
          <.icon name="hero-book-open" class="size-4" /> {t("nav.buttons.docs")}
        </a>
        <a
          href="/docs/icon-sets"
          class="flex items-center gap-2 px-3 py-2.5 rounded-lg text-sm font-medium text-base-content/80 hover:text-primary hover:bg-base-300 transition-colors"
        >
          <.icon name="hero-squares-2x2" class="size-4" /> {t("nav.buttons.iconSets")}
        </a>
        <a
          href="/docs/api"
          class="flex items-center gap-2 px-3 py-2.5 rounded-lg text-sm font-medium text-base-content/80 hover:text-primary hover:bg-base-300 transition-colors"
        >
          <.icon name="hero-code-bracket" class="size-4" /> {t("nav.buttons.api")}
        </a>
        <a
          href="/stats"
          class="flex items-center gap-2 px-3 py-2.5 rounded-lg text-sm font-medium text-base-content/80 hover:text-primary hover:bg-base-300 transition-colors"
        >
          <.icon name="hero-chart-bar" class="size-4" /> {t("nav.buttons.stats")}
        </a>
        <a
          href="https://pureadmin.io"
          target="_blank"
          class="flex items-center gap-2 px-3 py-2.5 rounded-lg text-sm font-medium text-base-content/80 hover:text-primary hover:bg-base-300 transition-colors"
        >
          <.icon name="hero-swatch" class="size-4" /> {t("nav.buttons.themes")}
        </a>
        <a
          href="https://keenmate.com"
          target="_blank"
          rel="noreferrer"
          class="flex items-center gap-2 px-3 py-2.5 rounded-lg text-sm font-medium text-base-content/80 hover:text-primary hover:bg-base-300 transition-colors"
        >
          <.icon name="hero-building-office-2" class="size-4" /> {t("nav.buttons.keenmate")}
        </a>
        <.language_switcher class="flex items-center gap-2 px-3 py-2.5 rounded-lg text-sm font-medium text-base-content/80 hover:bg-base-300 transition-colors" />
      </div>
    </nav>
    """
  end

  attr :count, :any, required: true, doc: "number of icons currently in the basket"

  @doc """
  Basket toggle button with a live count badge. Clicking dispatches
  `toggle_basket_drawer` to the LiveView, which owns the drawer state.
  """
  def basket_button(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="toggle_basket_drawer"
      title={t("iconSearch.tooltips.openBasket")}
      class="relative inline-flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg text-sm font-medium text-base-content/80 hover:text-primary hover:bg-base-200 transition-colors"
    >
      <.icon name="hero-shopping-bag" class="size-5 lg:size-4" />
      <span class="hidden lg:inline">{t("iconSearch.headers.basket")}</span>
      <%= if @count > 0 do %>
        <span class="absolute -top-1 -right-1 min-w-4 h-4 px-1 rounded-full bg-primary text-primary-content text-[10px] font-bold flex items-center justify-center leading-none">
          {@count}
        </span>
      <% end %>
    </button>
    """
  end

  attr :class, :string,
    default:
      "inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-sm font-medium text-base-content/80 hover:text-primary hover:bg-base-200 transition-colors"

  @doc """
  Language switcher — renders only when more than one locale is in
  `:supported_locales`. Links set `?lang=xx`; the Locale plug stores the
  choice in the session on first hit so subsequent navigation is clean.
  """
  def language_switcher(assigns) do
    supported = Application.get_env(:pure_admin_icons, :supported_locales, ["en"])
    current = PureAdminIcons.Translations.Locale.get()

    assigns =
      assigns
      |> Map.put(:supported, supported)
      |> Map.put(:current, current)
      |> Map.put(:show?, length(supported) > 1)

    ~H"""
    <%= if @show? do %>
      <div data-language-switcher class="relative">
        <button
          type="button"
          data-language-switcher-trigger
          class={@class}
          title={t("nav.tooltips.language")}
        >
          <.icon name="hero-language" class="size-4" />
          <span class="uppercase">{@current}</span>
        </button>
        <div
          data-language-switcher-panel
          class="hidden flex flex-col py-1 rounded-lg bg-base-100 border border-base-300 shadow-lg z-50 min-w-20"
          style="position: fixed; top: 0; left: 0;"
        >
          <%= for code <- @supported do %>
            <a
              href={"?lang=#{code}"}
              class={[
                "px-3 py-1.5 text-sm hover:bg-base-200 uppercase text-center",
                code == @current && "font-semibold text-primary"
              ]}
            >
              {code}
            </a>
          <% end %>
        </div>
      </div>
    <% end %>
    """
  end

  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="navbar px-4 sm:px-6 lg:px-8">
      <div class="flex-1">
        <.logo />
      </div>
      <div class="flex-none">
        <ul class="flex flex-column px-1 space-x-4 items-center">
          <li>
            <a href="/docs" class="btn btn-ghost">
              <.icon name="hero-book-open" class="size-4" /> Docs
            </a>
          </li>
          <li>
            <a href="/docs/api" class="btn btn-ghost">
              <.icon name="hero-code-bracket" class="size-4" /> API
            </a>
          </li>
          <li>
            <a href="https://keenmate.com" target="_blank" rel="noreferrer" class="btn btn-ghost">
              <.icon name="hero-building-office-2" class="size-4" /> Keenmate
            </a>
          </li>
        </ul>
      </div>
    </header>

    <main class="px-4 py-8 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-7xl">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title="We can't find the internet"
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title="Something went wrong!"
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  def theme_toggle(assigns) do
    ~H"""
    <div
      class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full"
      data-theme-toggle
    >
      <div class="theme-toggle-pill absolute w-1/5 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 transition-[left]" />

      <button class="flex p-2 cursor-pointer w-1/5 z-10" phx-click={JS.dispatch("phx:set-theme")} data-phx-theme="auto" title="Auto (time-based)">
        <.icon name="hero-clock-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
      <button class="flex p-2 cursor-pointer w-1/5 z-10" phx-click={JS.dispatch("phx:set-theme")} data-phx-theme="morning" title="Morning">
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
      <button class="flex p-2 cursor-pointer w-1/5 z-10" phx-click={JS.dispatch("phx:set-theme")} data-phx-theme="day" title="Day">
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
      <button class="flex p-2 cursor-pointer w-1/5 z-10" phx-click={JS.dispatch("phx:set-theme")} data-phx-theme="evening" title="Evening">
        <.icon name="hero-cloud-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
      <button class="flex p-2 cursor-pointer w-1/5 z-10" phx-click={JS.dispatch("phx:set-theme")} data-phx-theme="night" title="Night">
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
