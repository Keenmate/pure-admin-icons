defmodule PureAdminIconsWeb.Components.DownloadDesigner do
  @moduledoc """
  Shared "Download Designer" controls, driven by the `DownloadDesigner` JS hook.

  The hook queries the `.designer-*` element classes defined here (preview canvas,
  include-colors toggle, padding/radius sliders, size checkboxes, custom size,
  import file, and — in the modal — the PNG/SVG download buttons). Keeping the
  markup in one place means that class contract lives in a single file.

  Two variants:

    * `:modal`   — full block with per-icon PNG/SVG download buttons (icon detail
      modal), canvas + controls side by side. The heading + show/hide toggle are
      supplied by the caller (see IconModalComponent).
    * `:compact` — stacked, full-width sliders, no per-icon download buttons
      (basket drawer — bulk SVG/PNG actions live in the drawer header).
  """
  use PureAdminIconsWeb, :html

  import PureAdminIcons.Translations, only: [t: 1]

  attr :id, :string, required: true, doc: "unique id for the hook element"
  attr :name, :string, required: true, doc: "icon display name (data-name)"
  attr :svg_url, :string, required: true, doc: "source SVG url for the preview (data-svg-url)"
  attr :variant, :atom, default: :modal, values: [:modal, :compact]

  def download_designer(%{variant: :modal} = assigns) do
    ~H"""
    <div id={@id} phx-hook="DownloadDesigner" data-name={@name} data-svg-url={@svg_url}>
      <div class="bg-base-100 rounded-lg p-4 space-y-4">
        <div class="flex gap-4">
          <!-- Live preview -->
          <div class="flex-shrink-0">
            <canvas
              class="designer-preview rounded-lg border border-base-300"
              width="128"
              height="128"
              style="width: 128px; height: 128px;"
            ></canvas>
          </div>
          <!-- Controls -->
          <div class="flex-1 space-y-3 text-xs">
            <label
              class="flex items-center gap-2 cursor-pointer text-base-content/70"
              title={t("iconDetail.tooltips.includeColors")}
            >
              <input
                type="checkbox"
                class="designer-include-colors w-3.5 h-3.5 rounded border-base-300"
              />
              <span>{t("iconDetail.labels.includeColors")}</span>
            </label>
            <div class="flex items-center gap-2">
              <span class="text-base-content/70 w-16">{t("iconDetail.labels.padding")}</span>
              <input
                type="range"
                min="0"
                max="40"
                value="10"
                class="designer-padding range range-xs range-primary flex-1"
              />
              <span class="designer-padding-label text-base-content/50 w-8">10%</span>
            </div>
            <div class="flex items-center gap-2">
              <span class="text-base-content/70 w-16">{t("iconDetail.labels.corners")}</span>
              <input
                type="range"
                min="0"
                max="50"
                value="20"
                class="designer-radius range range-xs range-primary flex-1"
              />
              <span class="designer-radius-label text-base-content/50 w-8">20%</span>
            </div>
          </div>
        </div>
        <.size_controls
          custom_class="w-28 text-xs"
          row_class="flex flex-wrap items-center gap-2"
          label_class="text-xs text-base-content/70"
          px_class="text-xs text-base-content/50"
          size_label_class="inline-flex items-center gap-1 cursor-pointer text-xs"
        />
        <div class="flex flex-wrap items-center gap-2">
          <button
            type="button"
            class="designer-download-png px-3 py-1.5 rounded text-xs font-medium cursor-pointer bg-primary text-primary-content hover:opacity-80 inline-flex items-center gap-1.5"
          >
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4"
            /></svg>
            {t("iconDetail.buttons.downloadPngZip")}
          </button>
          <button
            type="button"
            class="designer-download-svg px-3 py-1.5 rounded text-xs font-medium cursor-pointer border border-base-300 hover:bg-base-200 inline-flex items-center gap-1.5"
          >
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4"
            /></svg>
            {t("iconDetail.buttons.downloadSvg")}
          </button>
          <label
            class="px-3 py-1.5 rounded text-xs font-medium cursor-pointer border border-base-300 hover:bg-base-200 inline-flex items-center gap-1.5"
            title={t("iconDetail.tooltips.importSettings")}
          >
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-8l-4-4m0 0L8 8m4-4v12"
            /></svg>
            {t("iconDetail.buttons.importSettings")}
            <input type="file" accept=".json" class="designer-import-file hidden" />
          </label>
        </div>
      </div>
    </div>
    """
  end

  def download_designer(%{variant: :compact} = assigns) do
    ~H"""
    <div id={@id} phx-hook="DownloadDesigner" data-name={@name} data-svg-url={@svg_url}>
      <div class="bg-base-100 rounded-lg p-3 space-y-3">
        <div class="flex items-center gap-3">
          <canvas
            class="designer-preview rounded-lg border border-base-300 flex-shrink-0"
            width="72"
            height="72"
            style="width: 72px; height: 72px;"
          ></canvas>
          <label class="flex-1 flex items-center gap-2 cursor-pointer text-xs text-base-content/70">
            <input
              type="checkbox"
              class="designer-include-colors w-3.5 h-3.5 rounded border-base-300"
            />
            <span>{t("iconDetail.labels.includeColors")}</span>
          </label>
        </div>
        <!-- Sliders full-width (label above) — a narrow drawer squishes
             side-by-side ranges into unusable pills. -->
        <div class="space-y-2 text-xs">
          <div>
            <div class="flex items-center justify-between text-base-content/70 mb-1">
              <span>{t("iconDetail.labels.padding")}</span>
              <span class="designer-padding-label text-base-content/50">10%</span>
            </div>
            <input
              type="range"
              min="0"
              max="40"
              value="10"
              class="designer-padding range range-xs range-primary w-full"
            />
          </div>
          <div>
            <div class="flex items-center justify-between text-base-content/70 mb-1">
              <span>{t("iconDetail.labels.corners")}</span>
              <span class="designer-radius-label text-base-content/50">20%</span>
            </div>
            <input
              type="range"
              min="0"
              max="50"
              value="20"
              class="designer-radius range range-xs range-primary w-full"
            />
          </div>
        </div>
        <label class="flex items-center gap-2 text-xs">
          <span class="text-base-content/70">{t("iconDetail.labels.filename")}</span>
          <select class="designer-naming-select select select-xs select-bordered">
            <option value="original">{t("iconDetail.labels.filenameOriginal")}</option>
            <option value="kebab">kebab-case</option>
            <option value="snake">snake_case</option>
            <option value="pascal">PascalCase</option>
          </select>
        </label>
        <.size_controls
          custom_class="w-16"
          row_class="flex flex-wrap items-center gap-x-3 gap-y-1 text-xs"
          label_class="text-base-content/70"
          px_class="text-base-content/50"
          size_label_class="inline-flex items-center gap-1 cursor-pointer"
        />
        <label
          class="px-3 py-1.5 rounded text-xs font-medium cursor-pointer border border-base-300 hover:bg-base-200 inline-flex items-center gap-1.5"
          title={t("iconDetail.tooltips.importSettings")}
        >
          <.icon name="hero-arrow-up-tray" class="size-4" /> {t("iconDetail.buttons.importSettings")}
          <input type="file" accept=".json" class="designer-import-file hidden" />
        </label>
      </div>
    </div>
    """
  end

  # Size checkboxes + custom size — identical `.designer-*` controls in both
  # variants; only the surrounding spacing/text classes differ.
  attr :row_class, :string, required: true
  attr :label_class, :string, required: true
  attr :size_label_class, :string, required: true
  attr :custom_class, :string, required: true
  attr :px_class, :string, required: true

  defp size_controls(assigns) do
    ~H"""
    <div class={@row_class}>
      <span class={@label_class}>{t("iconDetail.labels.sizes")}</span>
      <%= for size <- [32, 64, 128, 256, 512, 1024] do %>
        <label class={@size_label_class}>
          <input
            type="checkbox"
            checked
            class="designer-size w-3.5 h-3.5 rounded border-base-300"
            value={size}
          />
          <span class="text-base-content/70">{size}</span>
        </label>
      <% end %>
      <div class="flex items-center gap-1">
        <input
          type="number"
          min="1"
          max="4096"
          placeholder={t("iconDetail.placeholders.customSize")}
          class={["designer-custom-size px-2 py-0.5 border border-base-300 rounded", @custom_class]}
        />
        <span class={@px_class}>px</span>
      </div>
    </div>
    """
  end
end
