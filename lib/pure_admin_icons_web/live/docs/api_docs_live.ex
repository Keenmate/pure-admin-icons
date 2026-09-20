defmodule PureAdminIconsWeb.Docs.ApiDocsLive do
  use PureAdminIconsWeb, :live_view

  import PureAdminIcons.Translations, only: [t: 1]

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, t("apiDocs.headers.pageTitle"))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.site_nav />
    <div class="max-w-4xl mx-auto px-4 py-10">
      <div class="rounded-box bg-base-200 overflow-hidden border border-base-300 p-8">
        <h1 class="text-3xl font-bold mb-2">{t("apiDocs.headers.pageTitle")}</h1>
        <p class="text-base-content/80 mb-8">
          {t("apiDocs.messages.intro")}
        </p>

        <%!-- Icons --%>
        <div class="space-y-8">
          <h2 class="text-xl font-bold border-b border-base-300/50 pb-2">{t("apiDocs.headers.icons")}</h2>

          <.endpoint
            method="GET"
            path="/api/icons/search"
            description={t("apiDocs.descriptions.search")}
            params={[
              {"q", t("apiDocs.params.q")},
              {"set", t("apiDocs.params.set")},
              {"size", t("apiDocs.params.size")},
              {"style", t("apiDocs.params.style")},
              {"limit", t("apiDocs.params.limit")},
              {"format", t("apiDocs.params.format")}
            ]}
            example_url="/api/icons/search?q=calendar&set=fluentui&size=24"
          />

          <.endpoint
            method="GET"
            path="/api/icons/:id"
            description={t("apiDocs.descriptions.iconDetail")}
            params={[]}
            example_url="/api/icons/5403"
          />
        </div>

        <%!-- Icon Sets --%>
        <div class="space-y-8 mt-10">
          <h2 class="text-xl font-bold border-b border-base-300/50 pb-2">{t("apiDocs.headers.iconSets")}</h2>

          <.endpoint
            method="GET"
            path="/api/icon-sets"
            description={t("apiDocs.descriptions.iconSets")}
            params={[]}
            example_url="/api/icon-sets"
          />
        </div>

        <%!-- Response formats --%>
        <div class="space-y-8 mt-10">
          <h2 class="text-xl font-bold border-b border-base-300/50 pb-2">{t("apiDocs.headers.responseFormats")}</h2>

          <p class="text-sm text-base-content/80 mb-4">
            {t("apiDocs.messages.formatsIntro")}
          </p>

          <div class="space-y-4 text-sm text-base-content/85">
            <div class="flex gap-2">
              <code class="text-primary font-mono">json</code>
              <span class="text-base-content/50">&mdash;</span>
              <span>{t("apiDocs.formats.json")}</span>
            </div>
            <div class="flex gap-2">
              <code class="text-primary font-mono">compact</code>
              <span class="text-base-content/50">&mdash;</span>
              <span>{t("apiDocs.formats.compact")}</span>
            </div>
            <div class="flex gap-2">
              <code class="text-primary font-mono">text</code>
              <span class="text-base-content/50">&mdash;</span>
              <span>{t("apiDocs.formats.text")}</span>
            </div>
          </div>
        </div>

        <%!-- Response fields --%>
        <div class="space-y-8 mt-10">
          <h2 class="text-xl font-bold border-b border-base-300/50 pb-2">{t("apiDocs.headers.responseFields")}</h2>

          <div class="space-y-4 text-sm">
            <p class="text-base-content/80">{t("apiDocs.fields.intro")}</p>
            <div class="space-y-2 text-base-content/85">
              <div class="flex gap-2">
                <code class="text-primary font-mono min-w-40">style_color_method</code>
                <span class="text-base-content/50">&mdash;</span>
                <span>{t("apiDocs.fields.styleColorMethod")}</span>
              </div>
              <div class="flex gap-2">
                <code class="text-primary font-mono min-w-40">svg_url</code>
                <span class="text-base-content/50">&mdash;</span>
                <span>{t("apiDocs.fields.svgUrl")}</span>
              </div>
              <div class="flex gap-2">
                <code class="text-primary font-mono min-w-40">ios</code>
                <span class="text-base-content/50">&mdash;</span>
                <span>{t("apiDocs.fields.ios")}</span>
              </div>
              <div class="flex gap-2">
                <code class="text-primary font-mono min-w-40">android</code>
                <span class="text-base-content/50">&mdash;</span>
                <span>{t("apiDocs.fields.android")}</span>
              </div>
            </div>
          </div>
        </div>

        <%!-- Other endpoints --%>
        <div class="space-y-8 mt-10">
          <h2 class="text-xl font-bold border-b border-base-300/50 pb-2">{t("apiDocs.headers.otherEndpoints")}</h2>

          <.endpoint
            method="GET"
            path="/api/health"
            description={t("apiDocs.descriptions.health")}
            params={[]}
            example_url="/api/health"
          />

          <.endpoint
            method="GET"
            path="/icons/:icon_set/:style/:filename"
            description={t("apiDocs.descriptions.serve")}
            params={[]}
            example_url="/icons/fluentui/regular/ic_fluent_calendar_24_regular.svg"
            response_type="image/svg+xml"
          />

          <.endpoint
            method="POST"
            path="/api/maintenance/:task"
            description={t("apiDocs.descriptions.maintenance")}
            params={[
              {"task", t("apiDocs.params.maintenanceTask")},
              {"X-API-Key", t("apiDocs.params.maintenanceKey")}
            ]}
            note={t("apiDocs.notes.maintenance")}
          />
        </div>

        <%!-- AI/LLM integration --%>
        <div class="border-t border-base-300/50 mt-10 pt-8">
          <h2 class="text-xl font-bold mb-4">{t("apiDocs.headers.aiIntegration")}</h2>

          <p class="text-base-content/85 text-sm mb-4">
            {t("apiDocs.messages.aiIntro")}
          </p>

          <div class="space-y-6">
            <div>
              <h3 class="text-sm font-semibold uppercase tracking-wider text-base-content/80 mb-2">
                {t("apiDocs.headers.mcpServer")}
              </h3>
              <.code_block code={~s|{\n  "mcpServers": {\n    "pure-admin-icons": {\n      "command": "npx",\n      "args": ["-y", "-p", "@keenmate/pure-admin-icons-mcp", "pure-admin-icons-mcp"]\n    }\n  }\n}|} lang="json" />
            </div>

            <div>
              <h3 class="text-sm font-semibold uppercase tracking-wider text-base-content/80 mb-2">
                {t("apiDocs.headers.llmEndpoint")}
              </h3>
              <.code_block code="curl 'https://icons.pureadmin.io/api/icons/search?q=calendar&format=text'" />
            </div>

            <div>
              <h3 class="text-sm font-semibold uppercase tracking-wider text-base-content/80 mb-2">
                {t("apiDocs.headers.machineDocs")}
              </h3>
              <p class="text-base-content/85 text-sm">
                <a href="/llms.txt" class="text-primary hover:underline">/llms.txt</a> &middot;
                <a href="/.well-known/ai-plugin.json" class="text-primary hover:underline">/.well-known/ai-plugin.json</a>
              </p>
            </div>
          </div>
        </div>

        <%!-- Usage examples --%>
        <div class="border-t border-base-300/50 mt-10 pt-8">
          <h2 class="text-xl font-bold mb-4">{t("apiDocs.headers.usageExamples")}</h2>

          <div class="space-y-6">
            <div>
              <h3 class="text-sm font-semibold uppercase tracking-wider text-base-content/80 mb-2">
                {t("apiDocs.examples.search")}
              </h3>
              <.code_block code="curl 'https://icons.pureadmin.io/api/icons/search?q=pen&size=24&limit=5'" />
            </div>

            <div>
              <h3 class="text-sm font-semibold uppercase tracking-wider text-base-content/80 mb-2">
                {t("apiDocs.examples.multiSet")}
              </h3>
              <.code_block code="curl 'https://icons.pureadmin.io/api/icons/search?q=arrow&set=heroicons&set=lucide&set=fontawesome'" />
            </div>

            <div>
              <h3 class="text-sm font-semibold uppercase tracking-wider text-base-content/80 mb-2">
                {t("apiDocs.examples.iconDetail")}
              </h3>
              <.code_block code="curl 'https://icons.pureadmin.io/api/icons/5403'" />
            </div>

            <div>
              <h3 class="text-sm font-semibold uppercase tracking-wider text-base-content/80 mb-2">
                {t("apiDocs.examples.listSets")}
              </h3>
              <.code_block code="curl 'https://icons.pureadmin.io/api/icon-sets'" />
            </div>

            <div>
              <h3 class="text-sm font-semibold uppercase tracking-wider text-base-content/80 mb-2">
                {t("apiDocs.examples.javascript")}
              </h3>
              <.code_block code={~s|const res = await fetch('https://icons.pureadmin.io/api/icons/search?q=calendar&format=compact');\nconst { results } = await res.json();\nconsole.log(results.map(i => `${i.icon_set}/${i.name}`));|} lang="javascript" />
            </div>

            <div>
              <h3 class="text-sm font-semibold uppercase tracking-wider text-base-content/80 mb-2">
                {t("apiDocs.examples.sync")}
              </h3>
              <.code_block code={~s|curl -X POST -H "X-API-Key: your-key" 'https://icons.pureadmin.io/api/maintenance/sync/fontawesome'|} />
            </div>
          </div>
        </div>
      </div>

      <footer class="text-center text-base-content/50 text-xs py-8">
        icons.pureadmin.io &middot; {t("common.labels.by")}
        <a href="https://keenmate.com" class="hover:text-primary">KeenMate</a>
      </footer>
    </div>
    """
  end

  attr :method, :string, required: true
  attr :path, :string, required: true
  attr :description, :string, required: true
  attr :params, :list, default: []
  attr :example_url, :string, default: nil
  attr :response_type, :string, default: "application/json"
  attr :note, :string, default: nil

  defp endpoint(assigns) do
    ~H"""
    <div class="border-b border-base-300/30 pb-6 last:border-0">
      <div class="flex items-center gap-3 mb-2">
        <span class={"px-2 py-0.5 rounded text-xs font-bold #{if @method == "GET", do: "bg-success/20 text-success", else: "bg-warning/20 text-warning"}"}>
          {@method}
        </span>
        <code class="text-sm font-mono text-primary">{@path}</code>
      </div>
      <p class="text-base-content/85 text-sm mb-3">{@description}</p>

      <%= if @note do %>
        <p class="text-xs text-base-content/50 mb-3">{@note}</p>
      <% end %>

      <%= if Enum.any?(@params) do %>
        <div class="mb-3">
          <span class="text-xs font-semibold uppercase tracking-wider text-base-content/50">
            {t("apiDocs.labels.parameters")}
          </span>
          <div class="mt-1 space-y-1">
            <%= for {name, desc} <- @params do %>
              <div class="flex gap-2 text-sm">
                <code class="text-primary font-mono">{name}</code>
                <span class="text-base-content/50">&mdash;</span>
                <span class="text-base-content/80">{desc}</span>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>

      <%= if @example_url do %>
        <div class="flex items-center gap-2">
          <span class="text-xs text-base-content/40">{t("apiDocs.labels.try")}</span>
          <a
            href={@example_url}
            target="_blank"
            class="text-xs font-mono text-primary/70 hover:text-primary"
          >
            {@example_url}
          </a>
        </div>
      <% end %>

      <%= if @response_type != "application/json" do %>
        <span class="text-xs text-base-content/40">{t("apiDocs.labels.response")} {@response_type}</span>
      <% end %>
    </div>
    """
  end

  attr :code, :string, required: true
  attr :lang, :string, default: "bash"

  defp code_block(assigns) do
    ~H"""
    <pre class="rounded-lg px-4 py-3 text-sm overflow-x-auto bg-base-300/70 border border-base-300 shadow-sm"><code class={"language-#{@lang} hljs"}><%= @code %></code></pre>
    """
  end
end
