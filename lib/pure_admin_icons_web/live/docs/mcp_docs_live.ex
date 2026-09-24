defmodule PureAdminIconsWeb.Docs.McpDocsLive do
  use PureAdminIconsWeb, :live_view

  import PureAdminIcons.Translations, only: [t: 1]

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, t("mcpDocs.headers.pageTitle"))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.site_nav />
    <div class="max-w-4xl mx-auto px-4 py-10">
      <div class="rounded-box bg-base-200 overflow-hidden border border-base-300 p-8">
        <h1 class="text-3xl font-bold mb-2">{t("mcpDocs.headers.pageTitle")}</h1>
        <p class="text-base-content/80 mb-8">
          {t("mcpDocs.messages.intro")}
        </p>

        <div class="space-y-8">
          <div>
            <h2 class="text-xl font-bold border-b border-base-300/50 pb-2 mb-4">
              {t("mcpDocs.headers.installation")}
            </h2>
            <p class="text-base-content/85 text-sm mb-4">
              {t("mcpDocs.messages.installation")}
            </p>
            <p class="text-base-content/85 text-sm mb-4">
              npm:
              <a
                href="https://www.npmjs.com/package/@keenmate/pure-admin-icons-mcp"
                target="_blank"
                class="text-primary hover:underline"
              >@keenmate/pure-admin-icons-mcp</a>
            </p>
          </div>

          <div>
            <h2 class="text-xl font-bold border-b border-base-300/50 pb-2 mb-4">Claude Desktop</h2>
            <p class="text-base-content/85 text-sm mb-3">
              {t("mcpDocs.messages.claudeDesktop")}
            </p>
            <pre class="rounded-lg px-4 py-3 text-sm overflow-x-auto bg-base-300/70 border border-base-300 shadow-sm"><code class="hljs">{~s|{\n  "mcpServers": {\n    "pure-admin-icons": {\n      "command": "npx",\n      "args": ["-y", "-p", "@keenmate/pure-admin-icons-mcp", "pure-admin-icons-mcp"]\n    }\n  }\n}|}</code></pre>
          </div>

          <div>
            <h2 class="text-xl font-bold border-b border-base-300/50 pb-2 mb-4">Claude Code</h2>
            <p class="text-base-content/85 text-sm mb-3">
              {t("mcpDocs.messages.claudeCode")}
            </p>
            <pre class="rounded-lg px-4 py-3 text-sm overflow-x-auto bg-base-300/70 border border-base-300 shadow-sm"><code class="hljs">claude mcp add pure-admin-icons -- npx -y -p @keenmate/pure-admin-icons-mcp pure-admin-icons-mcp</code></pre>
          </div>

          <div>
            <h2 class="text-xl font-bold border-b border-base-300/50 pb-2 mb-4">
              {t("mcpDocs.headers.updates")}
            </h2>
            <p class="text-base-content/85 text-sm mb-3">
              {t("mcpDocs.messages.updatesCheck")}
            </p>
            <p class="text-base-content/85 text-sm mb-3">
              {t("mcpDocs.messages.updatesRefresh")}
            </p>
            <pre class="rounded-lg px-4 py-3 text-sm overflow-x-auto bg-base-300/70 border border-base-300 shadow-sm"><code class="hljs">npm install -g @keenmate/pure-admin-icons-mcp@latest</code></pre>
          </div>

          <div>
            <h2 class="text-xl font-bold border-b border-base-300/50 pb-2 mb-4">
              {t("mcpDocs.headers.availableTools")}
            </h2>
            <div class="space-y-4 text-sm">
              <div class="border-b border-base-300/30 pb-4">
                <div class="flex items-center gap-3 mb-2">
                  <code class="text-primary font-mono">search_icons</code>
                </div>
                <p class="text-base-content/85">{t("mcpDocs.tools.searchIcons")}</p>
              </div>
              <div class="border-b border-base-300/30 pb-4">
                <div class="flex items-center gap-3 mb-2">
                  <code class="text-primary font-mono">get_icon_svg</code>
                </div>
                <p class="text-base-content/85">{t("mcpDocs.tools.getIconSvg")}</p>
              </div>
            </div>
          </div>

          <div>
            <h2 class="text-xl font-bold border-b border-base-300/50 pb-2 mb-4">
              {t("mcpDocs.headers.usageExample")}
            </h2>
            <p class="text-base-content/85 text-sm mb-3">
              {t("mcpDocs.messages.usageExample")}
            </p>
            <div class="space-y-2 text-sm text-base-content/85">
              <p class="italic">{t("mcpDocs.examples.calendar")}</p>
              <p class="italic">{t("mcpDocs.examples.arrow")}</p>
              <p class="italic">{t("mcpDocs.examples.addSvg")}</p>
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
end
