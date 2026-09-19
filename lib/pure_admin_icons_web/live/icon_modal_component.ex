defmodule PureAdminIconsWeb.IconModalComponent do
  @moduledoc """
  LiveComponent for the icon detail modal.

  Extracted from IconSearchLive to isolate its render cycle — opening/closing
  the modal no longer triggers a re-render of the icon grid/list.
  Events (close_modal, toggle_platform, track_download, track_copy) bubble
  up to the parent LiveView which handles them.
  """
  use PureAdminIconsWeb, :live_component

  alias PureAdminIcons.Icons.Icon
  alias PureAdminIcons.IconSets.Formatter

  import PureAdminIconsWeb.Components.PlatformIcons
  import PureAdminIconsWeb.Components.DownloadDesigner, only: [download_designer: 1]
  import PureAdminIcons.Translations, only: [t: 1]

  alias PureAdminIconsWeb.PreviewPresets

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      class="fixed inset-0 z-50 overflow-y-auto xl:static xl:z-auto xl:overflow-visible"
      aria-labelledby="modal-title"
      role="dialog"
      aria-modal="true"
      phx-window-keydown="close_modal"
      phx-key="Escape"
    >
      <!-- Backdrop (overlay only — hidden in the inline master/detail layout) -->
      <div class="fixed inset-0 bg-black/60 transition-opacity xl:hidden" phx-click="close_modal">
      </div>

      <!-- Modal / inline panel -->
      <div class="flex min-h-full items-center justify-center p-4 xl:block xl:p-0">
        <div class="relative bg-base-200 rounded-xl shadow-2xl max-w-2xl w-full max-h-[90vh] overflow-y-auto xl:max-w-none xl:sticky xl:top-6 xl:max-h-[calc(100vh-3rem)] xl:shadow-lg">
          <!-- Close button -->
          <button
            phx-click="close_modal"
            class="absolute top-4 right-4 text-base-content/50 hover:text-base-content/70 z-10"
          >
            <svg class="h-6 w-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M6 18L18 6M6 6l12 12"
              />
            </svg>
          </button>

          <div class="p-6">
            <!-- Header -->
            <div class="text-center mb-6">
              <h2 class="text-2xl font-bold text-base-content" id="modal-title">{@icon.name}</h2>
              <div class="flex justify-center gap-2 mt-2">
                <span
                  class="inline-block px-2.5 py-1 rounded text-sm font-medium"
                  style={PureAdminIcons.IconSets.Color.badge_style(@icon.icon_set_code)}
                >{@icon.icon_set_code}</span>
                <span class="inline-block px-2.5 py-1 rounded text-sm font-medium badge-style capitalize">{@icon.style_code}</span>
              </div>

              <!-- Stats -->
              <% copies = Map.get(@metrics, "copy", 0) %>
              <% downloads = Map.get(@metrics, "download", 0) %>
              <% total = copies + downloads %>
              <%= if total > 0 do %>
                <div class="flex justify-center gap-3 mt-3">
                  <div class="px-3 py-1.5 bg-base-200 rounded-lg text-center">
                    <div class="text-lg font-semibold text-primary">{format_number(copies)}</div>
                    <div class="text-xs text-primary">{t("iconDetail.labels.copies")}</div>
                  </div>
                  <div class="px-3 py-1.5 bg-base-200 rounded-lg text-center">
                    <div class="text-lg font-semibold text-success">{format_number(downloads)}</div>
                    <div class="text-xs text-success">{t("iconDetail.labels.downloads")}</div>
                  </div>
                  <div class="px-3 py-1.5 bg-base-200 rounded-lg text-center">
                    <div class="text-lg font-semibold text-base-content">{format_number(total)}</div>
                    <div class="text-xs text-base-content/70">{t("iconDetail.labels.total")}</div>
                  </div>
                </div>
              <% end %>
            </div>

            <!-- Preview Presets & Custom Color -->
            <div
              class="mb-4"
              id={"color-picker-#{@icon.icon_id}"}
              phx-hook="ColorPicker"
              data-update-trigger={:erlang.phash2(@platform_prefs)}
              data-presets={Jason.encode!(PreviewPresets.all())}
              data-color-method={@icon.style_color_method || "fill"}
              data-icon-set={@icon.icon_set_code}
            >
              <%= if @icon.style_color_method == "multicolor" do %>
                <div class="flex items-center gap-3">
                  <label class="text-sm font-medium text-base-content">{t("iconDetail.labels.preview")}</label>
                  <span class="text-sm text-base-content/50 italic">{t(
                    "iconDetail.messages.multicolorNotRecolorable"
                  )}</span>
                </div>
              <% else %>
                <div class="flex flex-wrap items-center gap-2 mb-2">
                  <label class="text-sm font-medium text-base-content">{t("iconDetail.labels.colors")}</label>
                  <div class="relative preview-preset-combo">
                    <button
                      type="button"
                      class="preview-preset-trigger inline-flex items-center gap-2 px-3 py-1.5 rounded text-sm font-medium cursor-pointer border border-base-300 hover:bg-base-200"
                    >
                      <span
                        class="preview-preset-swatch w-4 h-4 rounded-sm border border-base-content/20"
                        style="background: linear-gradient(135deg, #ffffff 50%, #212121 50%);"
                      ></span>
                      <span class="preview-preset-label">Classic Light</span>
                      <svg
                        class="w-3 h-3 text-base-content/50"
                        fill="none"
                        stroke="currentColor"
                        viewBox="0 0 24 24"
                      ><path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M19 9l-7 7-7-7"
                      /></svg>
                    </button>
                    <div class="preview-preset-dropdown hidden absolute top-full left-0 mt-1 py-1 rounded-lg bg-base-100 border border-base-content/20 shadow-xl z-50 min-w-44 max-h-64 overflow-y-auto">
                      <%= for preset <- PreviewPresets.all() do %>
                        <button
                          type="button"
                          data-preset={preset["key"]}
                          data-label={preset["label"]}
                          class="preview-preset w-full text-left px-3 py-1.5 text-sm cursor-pointer hover:opacity-80"
                          style={PreviewPresets.button_style(preset)}
                        >{preset["label"]}</button>
                      <% end %>
                      <div class="custom-presets-container"></div>
                    </div>
                  </div>
                  <button
                    type="button"
                    class="custom-preset-new px-3 py-1.5 rounded text-sm font-medium cursor-pointer border border-base-300 hover:bg-base-200 inline-flex items-center gap-1.5"
                    title={t("iconDetail.tooltips.newPreset")}
                  >
                    <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M12 4v16m8-8H4"
                    /></svg>
                    {t("iconDetail.buttons.new")}
                  </button>
                  <button
                    type="button"
                    class="preview-copy-css px-3 py-1.5 rounded text-sm font-medium cursor-pointer border border-base-300 hover:bg-base-200 inline-flex items-center gap-1.5"
                    title={t("iconDetail.tooltips.copyCss")}
                  >
                    <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z"
                    /></svg>
                    {t("iconDetail.buttons.copyCss")}
                  </button>
                  <button
                    type="button"
                    class="preview-import-css px-3 py-1.5 rounded text-sm font-medium cursor-pointer border border-base-300 hover:bg-base-200 inline-flex items-center gap-1.5"
                    title={t("iconDetail.tooltips.importCss")}
                  >
                    <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-8l-4-4m0 0L8 8m4-4v12"
                    /></svg>
                    {t("iconDetail.buttons.importCss")}
                  </button>
                </div>
                <div
                  class="preview-import-area space-y-2 p-3 rounded-lg bg-base-200/50 border border-base-300 mb-2"
                  style="display: none;"
                >
                  <label class="text-sm font-medium text-base-content">{t(
                    "iconDetail.labels.pasteCss"
                  )}</label>
                  <textarea
                    class="preview-import-textarea w-full h-32 px-3 py-2 text-xs font-mono border border-base-300 rounded bg-base-100 text-base-content"
                    placeholder="/* Preset — My Theme [color: #ffffff, background: #000000] */\n.my-class {\n  background-color: #000000;\n  color: #ffffff;\n}"
                  ></textarea>
                  <div class="flex items-center gap-2">
                    <button
                      type="button"
                      class="preview-import-submit px-3 py-1 rounded text-xs font-medium cursor-pointer bg-primary text-primary-content hover:opacity-80"
                    >
                      {t("iconDetail.buttons.importAsPreset")}
                    </button>
                    <button
                      type="button"
                      class="preview-import-cancel px-3 py-1 rounded text-xs font-medium cursor-pointer border border-base-300 hover:bg-base-200"
                    >
                      {t("common.buttons.cancel")}
                    </button>
                    <span class="preview-import-status text-xs text-base-content/60"></span>
                  </div>
                </div>
                <div
                  class="preview-custom-area space-y-2 p-3 rounded-lg bg-base-200/50 border border-base-300"
                  style="display: none;"
                >
                  <div class="flex flex-wrap items-center gap-3">
                    <div class="flex items-center gap-2">
                      <span class="text-xs text-base-content/50">{t("iconDetail.labels.iconColor")}</span>
                      <input
                        type="color"
                        value="#212121"
                        class="color-input w-8 h-8 rounded cursor-pointer border border-base-300"
                      />
                      <input
                        type="text"
                        value="#212121"
                        class="color-text w-20 px-2 py-1 text-xs font-mono border border-base-300 rounded"
                        maxlength="7"
                        placeholder="#000000"
                      />
                    </div>
                    <div class="flex items-center gap-2">
                      <span class="text-xs text-base-content/50">{t("iconDetail.labels.bgColor")}</span>
                      <input
                        type="color"
                        value="#ffffff"
                        class="bg-color-input w-8 h-8 rounded cursor-pointer border border-base-300"
                      />
                      <input
                        type="text"
                        value="#ffffff"
                        class="bg-color-text w-20 px-2 py-1 text-xs font-mono border border-base-300 rounded"
                        maxlength="7"
                        placeholder="#ffffff"
                      />
                      <button
                        type="button"
                        class="bg-transparent-toggle w-8 h-8 rounded cursor-pointer border border-base-300 hover:border-primary text-xs leading-none"
                        style="background-image: repeating-conic-gradient(#d1d5db 0% 25%, #fff 0% 50%); background-size: 6px 6px;"
                        title={t("iconDetail.tooltips.transparentBg")}
                      ></button>
                    </div>
                    <span class={[
                      "text-xs px-2 py-0.5 rounded",
                      color_method_class(@icon.style_color_method)
                    ]}>
                      {color_method_label(@icon.style_color_method)}
                    </span>
                  </div>
                  <div class="flex items-center gap-2">
                    <input
                      type="text"
                      class="custom-preset-name w-40 px-2 py-1 text-xs border border-base-300 rounded"
                      placeholder={t("iconDetail.placeholders.presetName")}
                      maxlength="20"
                    />
                    <button
                      type="button"
                      class="custom-preset-save px-3 py-1 rounded text-xs font-medium cursor-pointer bg-primary text-primary-content hover:opacity-80"
                    >
                      {t("iconDetail.buttons.saveAsPreset")}
                    </button>
                    <button
                      type="button"
                      class="custom-preset-delete px-3 py-1 rounded text-xs font-medium cursor-pointer border border-error text-error hover:bg-error/10"
                    >
                      {t("common.buttons.delete")}
                    </button>
                  </div>
                </div>
              <% end %>
            </div>

            <!-- Icon Sizes Preview with Download -->
            <div
              class="mb-6"
              id={"download-naming-#{@icon.icon_id}"}
              phx-hook="DownloadNaming"
              data-name={@icon.name}
              data-style={@icon.style_code}
            >
              <div class="flex items-center justify-between mb-3">
                <h3 class="text-sm font-medium text-base-content">
                  <%= if Map.get(@icon, :has_single_source, false) do %>
                    {t("iconDetail.headers.preview")}
                    <span class="text-base-content/50">{t("iconDetail.messages.previewScalableSuffix")}</span>
                  <% else %>
                    {t("iconDetail.headers.availableSizes")}
                  <% end %>
                </h3>
                <label class="flex items-center gap-2 text-xs text-base-content/70">
                  <span>{t("iconDetail.labels.filename")}</span>
                  <select class="download-naming-select select select-xs select-bordered">
                    <option value="original">{t("iconDetail.labels.filenameOriginal")}</option>
                    <option value="kebab">kebab-case</option>
                    <option value="snake">snake_case</option>
                    <option value="pascal">PascalCase</option>
                  </select>
                </label>
              </div>
              <%= if Map.get(@icon, :has_single_source, false) do %>
                <div
                  class="flex justify-center"
                  id={"icon-preview-#{@icon.icon_id}"}
                  phx-hook="InlineSvg"
                  data-color="#212121"
                  data-urls={Jason.encode!([Icon.svg_url(@icon, 0)])}
                >
                  <div class="flex flex-col items-center">
                    <div
                      class="svg-container bg-white rounded-lg p-3 border border-base-300 flex items-center justify-center"
                      data-size="64"
                      style="width: 96px; height: 96px;"
                    >
                    </div>
                    <span class="text-3xl font-bold text-base-content/70 mt-1 leading-none">&#8734;</span>
                    <a
                      href={Icon.svg_url(@icon, 0)}
                      download={Icon.svg_filename(@icon, 0)}
                      data-original-filename={Icon.svg_filename(@icon, 0)}
                      phx-click="track_download"
                      phx-value-icon-id={@icon.icon_id}
                      phx-value-size="0"
                      title={t("iconDetail.tooltips.downloadSvg")}
                      class="download-link mt-1 p-1.5 text-primary hover:text-primary hover:bg-base-200 rounded-md transition-colors"
                    >
                      <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          stroke-width="2"
                          d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4"
                        />
                      </svg>
                    </a>
                  </div>
                </div>
              <% else %>
                <div
                  class="flex flex-wrap gap-4 justify-center items-end"
                  id={"icon-preview-#{@icon.icon_id}"}
                  phx-hook="InlineSvg"
                  data-color="#212121"
                  data-urls={Jason.encode!(Enum.map(@icon.sizes, &Icon.svg_url(@icon, &1)))}
                >
                  <%= for size <- @icon.sizes do %>
                    <div class="flex flex-col items-center">
                      <div
                        class="svg-container bg-white rounded-lg p-3 border border-base-300 flex items-center justify-center"
                        data-size={size}
                        style={"width: #{min(size + 24, 96)}px; height: #{min(size + 24, 96)}px;"}
                      >
                      </div>
                      <span class="text-xs text-base-content/70 mt-1">{size}px</span>
                      <a
                        href={Icon.svg_url(@icon, size)}
                        download={Icon.svg_filename(@icon, size)}
                        data-original-filename={Icon.svg_filename(@icon, size)}
                        data-size={size}
                        phx-click="track_download"
                        phx-value-icon-id={@icon.icon_id}
                        phx-value-size={size}
                        title={t("iconDetail.tooltips.downloadSvg")}
                        class="download-link mt-1 p-1.5 text-primary hover:text-primary hover:bg-base-200 rounded-md transition-colors"
                      >
                        <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path
                            stroke-linecap="round"
                            stroke-linejoin="round"
                            stroke-width="2"
                            d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4"
                          />
                        </svg>
                      </a>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>

            <!-- Download Designer -->
            <.download_designer
              variant={:modal}
              id={"download-designer-#{@icon.icon_id}"}
              name={@icon.name}
              svg_url={
                if Map.get(@icon, :has_single_source, false),
                  do: Icon.svg_url(@icon, 0),
                  else: Icon.svg_url(@icon, List.first(@icon.sizes))
              }
            />

            <!-- Platform Identifiers -->
            <div class="space-y-4">
              <div class="flex items-center justify-between">
                <h3 class="text-sm font-medium text-base-content">
                  {t("iconDetail.headers.platformIdentifiers")}
                </h3>
              </div>

              <!-- Platform Toggle Checkboxes -->
              <div
                class="flex flex-wrap gap-4 pb-4 border-b border-base-300"
                id="platform-prefs"
                phx-hook="PlatformPrefs"
              >
                <% {ios_pkg, _} = ios_package(@icon) %>
                <% {android_pkg, _} = android_package(@icon) %>
                <% {react_pkg, _} = react_package(@icon) %>
                <% {vue_pkg, _} = vue_package(@icon) %>
                <% {svelte_pkg, _} = svelte_package(@icon) %>
                <%= if ios_pkg do %>
                  <label class="flex items-center gap-2 cursor-pointer">
                    <input
                      type="checkbox"
                      checked={@platform_prefs.ios}
                      phx-click="toggle_platform"
                      phx-value-platform="ios"
                      class="w-4 h-4 rounded border-base-300 focus:ring-primary"
                    />
                    <.platform_icon name="ios" class="w-4 h-4 text-base-content/70" />
                    <span class="text-sm text-base-content/70">iOS</span>
                  </label>
                <% end %>
                <%= if android_pkg do %>
                  <label class="flex items-center gap-2 cursor-pointer">
                    <input
                      type="checkbox"
                      checked={@platform_prefs.android}
                      phx-click="toggle_platform"
                      phx-value-platform="android"
                      class="w-4 h-4 rounded border-base-300 focus:ring-primary"
                    />
                    <.platform_icon name="android" class="w-4 h-4 text-base-content/70" />
                    <span class="text-sm text-base-content/70">Android</span>
                  </label>
                <% end %>
                <%= if react_pkg do %>
                  <label class="flex items-center gap-2 cursor-pointer">
                    <input
                      type="checkbox"
                      checked={@platform_prefs.react}
                      phx-click="toggle_platform"
                      phx-value-platform="react"
                      class="w-4 h-4 rounded border-base-300 focus:ring-primary"
                    />
                    <.platform_icon name="react" class="w-4 h-4 text-base-content/70" />
                    <span class="text-sm text-base-content/70">React</span>
                  </label>
                <% end %>
                <%= if vue_pkg do %>
                  <label class="flex items-center gap-2 cursor-pointer">
                    <input
                      type="checkbox"
                      checked={@platform_prefs.vue}
                      phx-click="toggle_platform"
                      phx-value-platform="vue"
                      class="w-4 h-4 rounded border-base-300 focus:ring-primary"
                    />
                    <.platform_icon name="vue" class="w-4 h-4 text-base-content/70" />
                    <span class="text-sm text-base-content/70">Vue</span>
                  </label>
                <% end %>
                <%= if svelte_pkg do %>
                  <label class="flex items-center gap-2 cursor-pointer">
                    <input
                      type="checkbox"
                      checked={@platform_prefs.svelte}
                      phx-click="toggle_platform"
                      phx-value-platform="svelte"
                      class="w-4 h-4 rounded border-base-300 focus:ring-primary"
                    />
                    <.platform_icon name="svelte" class="w-4 h-4 text-base-content/70" />
                    <span class="text-sm text-base-content/70">Svelte</span>
                  </label>
                <% end %>
                <label class="flex items-center gap-2 cursor-pointer">
                  <input
                    type="checkbox"
                    checked={@platform_prefs.filename}
                    phx-click="toggle_platform"
                    phx-value-platform="filename"
                    class="w-4 h-4 rounded border-base-300 focus:ring-primary"
                  />
                  <.platform_icon name="filename" class="w-4 h-4 text-base-content/70" />
                  <span class="text-sm text-base-content/70">{t("iconDetail.platforms.filename")}</span>
                </label>
                <% {cssclass_pkg, _} = cssclass_package(@icon) %>
                <%= if cssclass_pkg do %>
                  <label class="flex items-center gap-2 cursor-pointer">
                    <input
                      type="checkbox"
                      checked={@platform_prefs.cssclass}
                      phx-click="toggle_platform"
                      phx-value-platform="cssclass"
                      class="w-4 h-4 rounded border-base-300 focus:ring-primary"
                    />
                    <.platform_icon name="cssclass" class="w-4 h-4 text-base-content/70" />
                    <span class="text-sm text-base-content/70">{t("iconDetail.platforms.cssClass")}</span>
                  </label>
                  <label class="flex items-center gap-2 cursor-pointer">
                    <input
                      type="checkbox"
                      checked={@platform_prefs.htmltag}
                      phx-click="toggle_platform"
                      phx-value-platform="htmltag"
                      class="w-4 h-4 rounded border-base-300 focus:ring-primary"
                    />
                    <.platform_icon name="htmltag" class="w-4 h-4 text-base-content/70" />
                    <span class="text-sm text-base-content/70">{t("iconDetail.platforms.htmlTag")}</span>
                  </label>
                <% end %>
              </div>

              <!-- iOS -->
              <%= if @platform_prefs.ios do %>
                <% {ios_pkg_name, ios_pkg_url} = ios_package(@icon) %>
                <%= if ios_pkg_name do %>
                  <.platform_section
                    icon={@icon}
                    platform="ios"
                    pkg_name={ios_pkg_name}
                    pkg_url={ios_pkg_url}
                    color="text-primary"
                    identifiers={Icon.platform_ids(@icon, "ios")}
                  />
                <% end %>
              <% end %>

              <!-- Android -->
              <%= if @platform_prefs.android do %>
                <% {android_pkg_name, android_pkg_url} = android_package(@icon) %>
                <%= if android_pkg_name do %>
                  <.platform_section
                    icon={@icon}
                    platform="android"
                    pkg_name={android_pkg_name}
                    pkg_url={android_pkg_url}
                    color="text-success"
                    identifiers={Icon.platform_ids(@icon, "android")}
                  />
                <% end %>
              <% end %>

              <!-- React -->
              <%= if @platform_prefs.react do %>
                <% {react_pkg_name, react_pkg_url} = react_package(@icon) %>
                <%= if react_pkg_name do %>
                  <.identifier_section
                    icon={@icon}
                    platform="react"
                    pkg_name={react_pkg_name}
                    pkg_url={react_pkg_url}
                    color="text-purple-600"
                    sizes={Formatter.react_identifier_sizes(@icon)}
                    identifier_fn={&Formatter.react_identifier(@icon, &1)}
                  />
                <% end %>
              <% end %>

              <!-- Vue -->
              <%= if @platform_prefs.vue do %>
                <% {vue_pkg_name, vue_pkg_url} = vue_package(@icon) %>
                <%= if vue_pkg_name do %>
                  <.identifier_section
                    icon={@icon}
                    platform="vue"
                    pkg_name={vue_pkg_name}
                    pkg_url={vue_pkg_url}
                    color="text-emerald-600"
                    sizes={Formatter.vue_identifier_sizes(@icon)}
                    identifier_fn={&Formatter.vue_identifier(@icon, &1)}
                  />
                <% end %>
              <% end %>

              <!-- Svelte -->
              <%= if @platform_prefs.svelte do %>
                <% {svelte_pkg_name, svelte_pkg_url} = svelte_package(@icon) %>
                <%= if svelte_pkg_name do %>
                  <div
                    class="bg-base-100 rounded-lg p-4"
                    id={"svelte-section-#{@icon.icon_id}"}
                    phx-hook="SvelteColor"
                    data-name={@icon.name |> String.downcase() |> String.replace(" ", "_")}
                    data-style={@icon.style_code}
                    data-icon-set={@icon.icon_set_code}
                    data-sizes={Jason.encode!(Formatter.svelte_identifier_sizes(@icon))}
                  >
                    <div class="flex items-center justify-between mb-2">
                      <span class="text-sm font-medium text-base-content/70 flex items-center gap-1.5">
                        <.platform_icon name="svelte" class="w-4 h-4" />
                        Svelte (<%= if svelte_pkg_url do %>
                          <a
                            href={svelte_pkg_url}
                            target="_blank"
                            rel="noreferrer"
                            referrerpolicy="unsafe-url"
                            class="text-primary hover:underline"
                          >{svelte_pkg_name}</a>
                        <% else %>
                          {svelte_pkg_name}
                        <% end %>)
                      </span>
                      <%= if @icon.icon_set_code == "fluentui" do %>
                        <label class="flex items-center gap-1.5 text-xs text-base-content/70 cursor-pointer">
                          <input
                            type="checkbox"
                            class="svelte-include-color w-3.5 h-3.5 rounded border-base-300"
                          /> Include color
                        </label>
                      <% end %>
                    </div>
                    <div class="space-y-1 svelte-code-list">
                      <%= for size <- Formatter.svelte_identifier_sizes(@icon) do %>
                        <div class="flex items-center justify-between bg-base-200 rounded px-3 py-2 border border-base-300">
                          <code
                            id={"svelte-#{@icon.icon_id}-#{size}"}
                            class="text-sm text-orange-600 whitespace-pre-line"
                            data-size={size}
                          >{Formatter.svelte_identifier(@icon, size)}</code>
                          <button
                            type="button"
                            phx-click={
                              Phoenix.LiveView.JS.dispatch("phx:copy",
                                to: "#svelte-#{@icon.icon_id}-#{size}"
                              )
                            }
                            class="text-xs text-base-content/70 hover:text-base-content px-2 py-1 rounded hover:bg-base-200 cursor-pointer"
                          >{t("common.buttons.copy")}</button>
                        </div>
                      <% end %>
                    </div>
                  </div>
                <% end %>
              <% end %>

              <!-- CSS Class -->
              <%= if @platform_prefs.cssclass do %>
                <% {cssclass_pkg_name, cssclass_pkg_url} = cssclass_package(@icon) %>
                <%= if cssclass_pkg_name do %>
                  <.identifier_section
                    icon={@icon}
                    platform="cssclass"
                    pkg_name={cssclass_pkg_name}
                    pkg_url={cssclass_pkg_url}
                    color="text-pink-600"
                    sizes={Formatter.cssclass_identifier_sizes(@icon)}
                    identifier_fn={&Formatter.cssclass_identifier(@icon, &1)}
                  />
                <% end %>
              <% end %>

              <!-- HTML Tag -->
              <%= if @platform_prefs.htmltag do %>
                <% {htmltag_pkg_name, htmltag_pkg_url} = Formatter.htmltag_package(@icon) %>
                <%= if htmltag_pkg_name do %>
                  <.identifier_section
                    icon={@icon}
                    platform="htmltag"
                    pkg_name={htmltag_pkg_name}
                    pkg_url={htmltag_pkg_url}
                    color="text-fuchsia-600"
                    sizes={Formatter.htmltag_identifier_sizes(@icon)}
                    identifier_fn={&Formatter.htmltag_identifier(@icon, &1)}
                  />
                <% end %>
              <% end %>

              <!-- Filename -->
              <%= if @platform_prefs.filename do %>
                <div
                  class="bg-base-100 rounded-lg p-4"
                  id={"filename-section-#{@icon.icon_id}"}
                  phx-hook="FilenameTemplate"
                  phx-update="ignore"
                  data-name={@icon.name}
                  data-style={@icon.style_code}
                  data-sizes={
                    Jason.encode!(
                      if Map.get(@icon, :has_single_source, false), do: [0], else: @icon.sizes
                    )
                  }
                  data-filenames={Jason.encode!(@icon.filenames || %{})}
                >
                  <div class="flex items-center justify-between mb-2">
                    <span class="text-sm font-medium text-base-content/70 flex items-center gap-1.5">
                      <.platform_icon name="filename" class="w-4 h-4" />
                      {t("iconDetail.headers.filenameLocalCopy")}
                    </span>
                  </div>
                  <div class="mb-1 text-xs text-base-content/70">
                    <span class="font-medium">{t("iconDetail.labels.placeholders")}</span>
                    <code class="bg-base-300 px-1 rounded">{"{filename}"}</code>
                    <code class="bg-base-300 px-1 rounded">{"{name}"}</code>
                    <code class="bg-base-300 px-1 rounded">{"{name_snake}"}</code>
                    <code class="bg-base-300 px-1 rounded">{"{name_pascal}"}</code>
                    <code class="bg-base-300 px-1 rounded">{"{name_kebab}"}</code>
                    <code class="bg-base-300 px-1 rounded">{"{size}"}</code>
                    <code class="bg-base-300 px-1 rounded">{"{style}"}</code>
                  </div>
                  <div class="mb-3">
                    <input
                      type="text"
                      id={"filename-template-input-#{@icon.icon_id}"}
                      class="w-full px-3 py-2 text-sm border border-base-300 rounded search-glow"
                      placeholder="/my/assets/{filename}"
                    />
                  </div>
                  <div id={"filename-results-#{@icon.icon_id}"} class="space-y-1"></div>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ---- Sub-components for repeated platform sections ----

  defp platform_section(assigns) do
    ~H"""
    <div class="bg-base-100 rounded-lg p-4">
      <div class="flex items-center justify-between mb-2">
        <span class="text-sm font-medium text-base-content/70 flex items-center gap-1.5">
          <.platform_icon name={@platform} class="w-4 h-4" />
          {String.capitalize(@platform)} (<%= if @pkg_url do %>
            <a href={@pkg_url} target="_blank" rel="noreferrer" class="text-primary hover:underline">{@pkg_name}</a>
          <% else %>
            {@pkg_name}
          <% end %>)
        </span>
      </div>
      <div class="space-y-1">
        <%= for {size, id} <- @identifiers do %>
          <div class="flex items-center justify-between bg-base-200 rounded px-3 py-2 border border-base-300">
            <code class={["text-sm", @color]}>{id}</code>
            <button
              type="button"
              phx-click={
                Phoenix.LiveView.JS.dispatch("phx:copy", to: "##{@platform}-#{@icon.icon_id}-#{size}")
              }
              class="text-xs text-base-content/70 hover:text-base-content px-2 py-1 rounded hover:bg-base-200 cursor-pointer"
            >{t("common.buttons.copy")}</button>
            <span id={"#{@platform}-#{@icon.icon_id}-#{size}"} class="hidden">{id}</span>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp identifier_section(assigns) do
    ~H"""
    <div class="bg-base-100 rounded-lg p-4">
      <div class="flex items-center justify-between mb-2">
        <span class="text-sm font-medium text-base-content/70 flex items-center gap-1.5">
          <.platform_icon name={@platform} class="w-4 h-4" />
          {platform_label(@platform)} (<%= if @pkg_url do %>
            <a href={@pkg_url} target="_blank" rel="noreferrer" class="text-primary hover:underline">{@pkg_name}</a>
          <% else %>
            {@pkg_name}
          <% end %>)
        </span>
      </div>
      <div class="space-y-1">
        <%= for size <- @sizes do %>
          <div class="flex items-center justify-between bg-base-200 rounded px-3 py-2 border border-base-300">
            <code
              id={"#{@platform}-#{@icon.icon_id}-#{size}"}
              class={["text-sm whitespace-pre-line", @color]}
            >{@identifier_fn.(size)}</code>
            <button
              type="button"
              phx-click={
                Phoenix.LiveView.JS.dispatch("phx:copy", to: "##{@platform}-#{@icon.icon_id}-#{size}")
              }
              class="text-xs text-base-content/70 hover:text-base-content px-2 py-1 rounded hover:bg-base-200 cursor-pointer"
            >{t("common.buttons.copy")}</button>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # ---- Helpers ----

  defp ios_package(icon), do: Formatter.ios_package(icon)
  defp android_package(icon), do: Formatter.android_package(icon)
  defp react_package(icon), do: Formatter.react_package(icon)
  defp vue_package(icon), do: Formatter.vue_package(icon)
  defp svelte_package(icon), do: Formatter.svelte_package(icon)
  defp cssclass_package(icon), do: Formatter.cssclass_package(icon)

  defp color_method_label("fill"), do: "CSS: fill / color"
  defp color_method_label("stroke"), do: "CSS: stroke / color"
  defp color_method_label("multicolor"), do: "Multicolor"
  defp color_method_label(_), do: ""

  defp color_method_class("fill"), do: "bg-blue-100 text-blue-700"
  defp color_method_class("stroke"), do: "bg-emerald-100 text-emerald-700"
  defp color_method_class("multicolor"), do: "bg-amber-100 text-amber-700"
  defp color_method_class(_), do: "bg-base-200 text-base-content/70"

  defp platform_label("react"), do: "React"
  defp platform_label("vue"), do: "Vue"
  defp platform_label("svelte"), do: "Svelte"
  defp platform_label("cssclass"), do: "CSS Class"
  defp platform_label("htmltag"), do: "HTML Tag"
  defp platform_label(p), do: String.capitalize(p)

  defp format_number(n) when n >= 1_000_000 do
    "#{Float.round(n / 1_000_000, 1)}M"
  end

  defp format_number(n) when n >= 1_000 do
    "#{Float.round(n / 1_000, 1)}K"
  end

  defp format_number(n), do: to_string(n)
end
