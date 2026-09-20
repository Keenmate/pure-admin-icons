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
          Search icons programmatically. All endpoints return JSON. No authentication required.
        </p>

        <%!-- Icons --%>
        <div class="space-y-8">
          <h2 class="text-xl font-bold border-b border-base-300/50 pb-2">Icons</h2>

          <.endpoint
            method="GET"
            path="/api/icons/search"
            description="Search icons by name across all icon sets. Supports full-text search, trigram similarity, and synonym matching."
            params={[
              {"q", "Search query (required)"},
              {"set", "Filter by icon set code, e.g. fluentui, material, phosphor, tabler, lucide, solar (repeatable) — see /api/icon-sets for all codes"},
              {"size", "Filter by size, e.g. 16, 20, 24, 28, 32, 48 (most sets are scalable)"},
              {"style", "Filter by style: outline, filled, thin, light, regular, bold, rounded, sharp, duotone, line-duotone, broken, color, brands (varies by set)"},
              {"limit", "Max results (default: 50, max: 100)"},
              {"format", "Response format: json (default), compact, text"}
            ]}
            example_url="/api/icons/search?q=calendar&set=fluentui&size=24"
          />

          <.endpoint
            method="GET"
            path="/api/icons/:id"
            description="Get a single icon by ID. Returns full metadata including filenames, platform identifiers, categories, phrases, and SVG URLs for all sizes."
            params={[]}
            example_url="/api/icons/5403"
          />
        </div>

        <%!-- Icon Sets --%>
        <div class="space-y-8 mt-10">
          <h2 class="text-xl font-bold border-b border-base-300/50 pb-2">Icon Sets</h2>

          <.endpoint
            method="GET"
            path="/api/icon-sets"
            description="List all available icon sets with metadata: styles, sizes, license, color methods, icon count, plus each set's description and notes (e.g. whether its served SVGs are normalized from upstream)."
            params={[]}
            example_url="/api/icon-sets"
          />
        </div>

        <%!-- Response formats --%>
        <div class="space-y-8 mt-10">
          <h2 class="text-xl font-bold border-b border-base-300/50 pb-2">Response Formats</h2>

          <p class="text-sm text-base-content/80 mb-4">
            The <code class="text-xs font-mono text-primary">format</code> parameter on <code class="text-xs font-mono text-primary">/api/icons/search</code> controls the response shape:
          </p>

          <div class="space-y-4 text-sm text-base-content/85">
            <div class="flex gap-2">
              <code class="text-primary font-mono">json</code>
              <span class="text-base-content/50">&mdash;</span>
              <span>Full response: id, icon_set, name, style, style_color_method, sizes, ios/android identifiers, svg_url</span>
            </div>
            <div class="flex gap-2">
              <code class="text-primary font-mono">compact</code>
              <span class="text-base-content/50">&mdash;</span>
              <span>Minimal JSON: icon_set, name, style, url</span>
            </div>
            <div class="flex gap-2">
              <code class="text-primary font-mono">text</code>
              <span class="text-base-content/50">&mdash;</span>
              <span>Plain text, one icon per line (most token-efficient for AI/LLMs)</span>
            </div>
          </div>
        </div>

        <%!-- Response fields --%>
        <div class="space-y-8 mt-10">
          <h2 class="text-xl font-bold border-b border-base-300/50 pb-2">Response Fields</h2>

          <div class="space-y-4 text-sm">
            <p class="text-base-content/80">Key fields in the JSON response:</p>
            <div class="space-y-2 text-base-content/85">
              <div class="flex gap-2">
                <code class="text-primary font-mono min-w-40">style_color_method</code>
                <span class="text-base-content/50">&mdash;</span>
                <span>How to set icon color via CSS: <code class="text-xs font-mono">"fill"</code>, <code class="text-xs font-mono">"stroke"</code>, or <code class="text-xs font-mono">"multicolor"</code> (not recolorable)</span>
              </div>
              <div class="flex gap-2">
                <code class="text-primary font-mono min-w-40">svg_url</code>
                <span class="text-base-content/50">&mdash;</span>
                <span>Relative URL to the SVG file (e.g., <code class="text-xs font-mono">/icons/fluentui/regular/ic_fluent_calendar_24_regular.svg</code>)</span>
              </div>
              <div class="flex gap-2">
                <code class="text-primary font-mono min-w-40">ios</code>
                <span class="text-base-content/50">&mdash;</span>
                <span>iOS/Swift identifier per size (e.g., <code class="text-xs font-mono" phx-no-curly-interpolation>{"24": "calendar24Solid"}</code>)</span>
              </div>
              <div class="flex gap-2">
                <code class="text-primary font-mono min-w-40">android</code>
                <span class="text-base-content/50">&mdash;</span>
                <span>Android/Kotlin identifier per size (e.g., <code class="text-xs font-mono" phx-no-curly-interpolation>{"24": "ic_heroicons_calendar_24_solid"}</code>)</span>
              </div>
            </div>
          </div>
        </div>

        <%!-- Other endpoints --%>
        <div class="space-y-8 mt-10">
          <h2 class="text-xl font-bold border-b border-base-300/50 pb-2">Other Endpoints</h2>

          <.endpoint
            method="GET"
            path="/api/health"
            description="Health check. Returns icon count and status."
            params={[]}
            example_url="/api/health"
          />

          <.endpoint
            method="GET"
            path="/icons/:icon_set/:style/:filename"
            description="Serve an icon SVG file. Cached for 1 year with immutable header."
            params={[]}
            example_url="/icons/fluentui/regular/ic_fluent_calendar_24_regular.svg"
            response_type="image/svg+xml"
          />

          <.endpoint
            method="POST"
            path="/api/maintenance/:task"
            description="Trigger a maintenance task. Requires X-API-Key header. Rate limited to 5 requests per 5 minutes."
            params={[
              {"task", "Task to run: sync, clean, cube"},
              {"X-API-Key", "API key (header, required)"}
            ]}
            note="Use POST /api/maintenance/sync/:icon_set to sync a specific set (e.g., fontawesome, fluentui)."
          />
        </div>

        <%!-- AI/LLM integration --%>
        <div class="border-t border-base-300/50 mt-10 pt-8">
          <h2 class="text-xl font-bold mb-4">AI / LLM Integration</h2>

          <p class="text-base-content/85 text-sm mb-4">
            For AI assistants and LLMs, use the <code class="text-xs font-mono text-primary">text</code> format for maximum token efficiency.
            We also provide an MCP server for direct integration with Claude Desktop and Claude Code.
          </p>

          <div class="space-y-6">
            <div>
              <h3 class="text-sm font-semibold uppercase tracking-wider text-base-content/80 mb-2">
                MCP Server (Claude Desktop / Claude Code)
              </h3>
              <.code_block code={~s|{\n  "mcpServers": {\n    "pure-admin-icons": {\n      "command": "npx",\n      "args": ["-y", "-p", "@keenmate/pure-admin-icons-mcp", "pure-admin-icons-mcp"]\n    }\n  }\n}|} lang="json" />
            </div>

            <div>
              <h3 class="text-sm font-semibold uppercase tracking-wider text-base-content/80 mb-2">
                LLM-friendly endpoint
              </h3>
              <.code_block code="curl 'https://icons.pureadmin.io/api/icons/search?q=calendar&format=text'" />
            </div>

            <div>
              <h3 class="text-sm font-semibold uppercase tracking-wider text-base-content/80 mb-2">
                Machine-readable docs
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
          <h2 class="text-xl font-bold mb-4">Usage Examples</h2>

          <div class="space-y-6">
            <div>
              <h3 class="text-sm font-semibold uppercase tracking-wider text-base-content/80 mb-2">
                Search icons
              </h3>
              <.code_block code="curl 'https://icons.pureadmin.io/api/icons/search?q=pen&size=24&limit=5'" />
            </div>

            <div>
              <h3 class="text-sm font-semibold uppercase tracking-wider text-base-content/80 mb-2">
                Filter by multiple icon sets
              </h3>
              <.code_block code="curl 'https://icons.pureadmin.io/api/icons/search?q=arrow&set=heroicons&set=lucide&set=fontawesome'" />
            </div>

            <div>
              <h3 class="text-sm font-semibold uppercase tracking-wider text-base-content/80 mb-2">
                Get icon detail
              </h3>
              <.code_block code="curl 'https://icons.pureadmin.io/api/icons/5403'" />
            </div>

            <div>
              <h3 class="text-sm font-semibold uppercase tracking-wider text-base-content/80 mb-2">
                List icon sets
              </h3>
              <.code_block code="curl 'https://icons.pureadmin.io/api/icon-sets'" />
            </div>

            <div>
              <h3 class="text-sm font-semibold uppercase tracking-wider text-base-content/80 mb-2">
                JavaScript
              </h3>
              <.code_block code={~s|const res = await fetch('https://icons.pureadmin.io/api/icons/search?q=calendar&format=compact');\nconst { results } = await res.json();\nconsole.log(results.map(i => `${i.icon_set}/${i.name}`));|} lang="javascript" />
            </div>

            <div>
              <h3 class="text-sm font-semibold uppercase tracking-wider text-base-content/80 mb-2">
                Trigger sync (authenticated)
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
            Parameters
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
          <span class="text-xs text-base-content/40">Try:</span>
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
        <span class="text-xs text-base-content/40">Response: {@response_type}</span>
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
