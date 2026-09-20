defmodule PureAdminIconsWeb.Docs.LlmsDocsLive do
  use PureAdminIconsWeb, :live_view

  import PureAdminIcons.Translations, only: [t: 1]

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, t("llmsDocs.headers.pageTitle"))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.site_nav />
    <div class="max-w-4xl mx-auto px-4 py-10">
      <div class="rounded-box bg-base-200 overflow-hidden border border-base-300 p-8">
        <h1 class="text-3xl font-bold mb-2">{t("llmsDocs.headers.pageTitle")}</h1>
        <p class="text-base-content/80 mb-8">
          {t("llmsDocs.messages.intro")}
        </p>

        <div class="space-y-8">
          <div>
            <h2 class="text-xl font-bold border-b border-base-300/50 pb-2 mb-4">{t("llmsDocs.headers.textFormat")}</h2>
            <p class="text-base-content/85 text-sm mb-3">
              {t("llmsDocs.messages.textFormat")}
            </p>
            <pre class="rounded-lg px-4 py-3 text-sm overflow-x-auto bg-base-300/70 border border-base-300 shadow-sm"><code class="hljs">curl 'https://icons.pureadmin.io/api/icons/search?q=calendar&format=text'</code></pre>
          </div>

          <div>
            <h2 class="text-xl font-bold border-b border-base-300/50 pb-2 mb-4">{t("llmsDocs.headers.machineDocs")}</h2>
            <div class="space-y-4 text-sm">
              <div class="flex gap-3">
                <a href="/llms.txt" class="text-primary hover:underline font-mono">/llms.txt</a>
                <span class="text-base-content/50">&mdash;</span>
                <span class="text-base-content/85">{t("llmsDocs.links.llmsTxt")}</span>
              </div>
              <div class="flex gap-3">
                <a href="/.well-known/ai-plugin.json" class="text-primary hover:underline font-mono">/.well-known/ai-plugin.json</a>
                <span class="text-base-content/50">&mdash;</span>
                <span class="text-base-content/85">{t("llmsDocs.links.aiPlugin")}</span>
              </div>
            </div>
          </div>

          <div>
            <h2 class="text-xl font-bold border-b border-base-300/50 pb-2 mb-4">{t("llmsDocs.headers.mcpServer")}</h2>
            <p class="text-base-content/85 text-sm">
              {t("llmsDocs.messages.mcpServer")}
              <a href="/docs/mcp" class="text-primary hover:underline">{t("llmsDocs.links.mcpDocs")}</a>
            </p>
          </div>

          <div>
            <h2 class="text-xl font-bold border-b border-base-300/50 pb-2 mb-4">{t("llmsDocs.headers.tips")}</h2>
            <ul class="text-sm text-base-content/85 space-y-2">
              <li>{t("llmsDocs.tips.textFormat")}</li>
              <li>{t("llmsDocs.tips.limit")}</li>
              <li>{t("llmsDocs.tips.set")}</li>
              <li>{t("llmsDocs.tips.compact")}</li>
            </ul>
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
