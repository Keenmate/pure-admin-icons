import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

let Hooks = {}

// ══════════════════════════════════════════════════════════
// PresetManager — single source of truth for color presets.
// Built-in presets come from the server (embedded in the
// #quick-presets element's data-presets attribute at page load).
// Custom presets live in localStorage.
// Both hooks (ColorPicker in modal, QuickPresets in results bar)
// call these functions instead of each maintaining their own logic.
// ══════════════════════════════════════════════════════════
const PresetManager = {
  _builtins: null,

  /** Parse built-in presets once from the DOM (cached). */
  getBuiltins() {
    if (this._builtins) return this._builtins
    try {
      const el = document.getElementById('quick-presets')
      const arr = JSON.parse(el?.dataset?.presets || '[]')
      this._builtins = {}
      for (const p of arr) this._builtins[p.key] = { color: p.color, bg: p.bg, label: p.label }
    } catch { this._builtins = {} }
    return this._builtins
  },

  /** Get custom presets from localStorage. */
  getCustoms() {
    try { return JSON.parse(localStorage.getItem('icon_custom_presets') || '{}') } catch { return {} }
  },

  /** Save custom presets to localStorage. */
  saveCustoms(presets) {
    localStorage.setItem('icon_custom_presets', JSON.stringify(presets))
  },

  /** All presets as a key→{color, bg, label} map (built-in + custom). */
  getAll() {
    return { ...this.getBuiltins(), ...this.getCustoms() }
  },

  /** All presets as a sorted array of {key, color, bg, label}. */
  getSorted() {
    const all = this.getAll()
    return Object.entries(all)
      .map(([key, p]) => ({ key, color: p.color, bg: p.bg, label: p.label || key }))
      .sort((a, b) => a.label.localeCompare(b.label))
  },

  /** Is the given key a custom (user-created) preset? */
  isCustom(key) {
    return key && !!this.getCustoms()[key]
  },

  /** Get the currently active preset key from localStorage (or null). */
  activeKey() {
    return localStorage.getItem('icon_preview_preset') || null
  },

  /** Get the currently active preset object, or null if custom colors. */
  active() {
    const key = this.activeKey()
    return key ? (this.getAll()[key] || null) : null
  },

  /** Render sorted preset buttons into a dropdown container.
   *  Clears previous sorted items, hides server-rendered originals. */
  renderDropdown(dropdown) {
    if (!dropdown) return
    // Remove old sorted items
    dropdown.querySelectorAll('.preset-sorted').forEach(el => el.remove())
    // Hide ALL non-sorted children (server-rendered originals, custom containers, etc.)
    Array.from(dropdown.children).forEach(el => {
      if (!el.classList.contains('preset-sorted')) el.classList.add('hidden')
    })

    for (const p of this.getSorted()) {
      const btn = document.createElement('button')
      btn.type = 'button'
      btn.dataset.preset = p.key
      btn.dataset.color = p.color
      btn.dataset.bg = p.bg
      btn.dataset.label = p.label
      btn.className = 'preset-sorted w-full text-left px-3 py-1.5 text-sm cursor-pointer hover:opacity-80'
      const bgCss = p.bg === 'checker' ? '#e5e7eb' : p.bg
      btn.style.cssText = `background-color: ${bgCss}; color: ${p.color};`
      btn.textContent = p.label
      dropdown.appendChild(btn)
    }
  },

  /** Update a combo trigger (swatch + label) to reflect the active preset. */
  syncTrigger(swatch, label) {
    if (!swatch || !label) return
    const preset = this.active()
    if (preset) {
      const bgCss = preset.bg === 'checker' ? '#e5e7eb' : preset.bg
      swatch.style.background = `linear-gradient(135deg, ${bgCss} 50%, ${preset.color} 50%)`
      label.textContent = preset.label
    } else {
      const color = localStorage.getItem('icon_preview_color') || '#212121'
      let bg = '#ffffff'
      try { bg = JSON.parse(localStorage.getItem('icon_preview_bg') || '"#ffffff"') } catch { bg = localStorage.getItem('icon_preview_bg') || '#ffffff' }
      const bgCss = bg === 'checker' ? '#e5e7eb' : bg
      swatch.style.background = `linear-gradient(135deg, ${bgCss} 50%, ${color} 50%)`
      label.textContent = 'Custom'
    }
  }
}

// ══════════════════════════════════════════════════════════
// Debug helper — pulls every fill=".." and stroke=".." from an SVG string
// so we can see what colors the SVG actually carries before/after colorize.
function extractFillStroke(svgText) {
  const fills = [...svgText.matchAll(/fill="([^"]*)"/g)].map(m => m[1])
  const strokes = [...svgText.matchAll(/stroke="([^"]*)"/g)].map(m => m[1])
  return { fills, strokes }
}

// Recolours a LIVE DOM SVG element. Updates any `fill`/`stroke` on the
// root + every child shape element, unless the attribute is `none` (kept
// transparent) or absent (paths without fill rely on SVG inheritance from
// the root, which works in DOM rendering).
//
// This is the single source of truth for the grid (IconColorFilter), the
// modal preview's first load (InlineSvg), and preset changes
// (ColorPicker.updateSvgColors). The designer canvas uses a different
// function because it has to serialize + rasterize via `<img src=blob>`,
// where DOM-level inheritance isn't honored.
function colorizeLiveSvg(svg, color) {
  const update = (el) => {
    const fill = el.getAttribute('fill')
    if (fill && fill !== 'none') el.setAttribute('fill', color)
    const stroke = el.getAttribute('stroke')
    if (stroke && stroke !== 'none') el.setAttribute('stroke', color)
  }
  update(svg)
  svg.querySelectorAll('path, circle, rect, line, polyline, polygon, ellipse, g').forEach(update)
}

// DesignerExport — shared export logic for Download Designer.
// Used by DownloadDesigner hook (modal) and FloatingPopover
// (quick download button in grid/list).
// Reads settings from localStorage so it works without the
// DownloadDesigner hook being mounted.
// ══════════════════════════════════════════════════════════
const DesignerExport = {
  getSettings() {
    const includeColors = localStorage.getItem('designer_include_colors') !== 'false'
    const padding = parseInt(localStorage.getItem('designer_padding') || '10') / 100
    const radius = parseInt(localStorage.getItem('designer_radius') || '20') / 100
    const color = includeColors ? (localStorage.getItem('icon_preview_color') || '#212121') : null
    let bg = null
    if (includeColors) {
      try { bg = JSON.parse(localStorage.getItem('icon_preview_bg') || '"#ffffff"') } catch { bg = localStorage.getItem('icon_preview_bg') || '#ffffff' }
      if (bg === 'checker') bg = null
    }
    return { includeColors, padding, radius, color, bg }
  },

  getSizes() {
    let sizes = [32, 64, 128, 256, 512, 1024]
    const saved = localStorage.getItem('designer_sizes')
    if (saved) {
      try { sizes = JSON.parse(saved) } catch {}
    }
    const custom = parseInt(localStorage.getItem('designer_custom_size'))
    if (custom > 0 && custom <= 4096) sizes.push(custom)
    return [...new Set(sizes)].sort((a, b) => a - b)
  },

  /** Returns true if the user has ever used the designer (settings exist in localStorage). */
  hasSettings() {
    return localStorage.getItem('designer_padding') !== null
  },

  // Rewrites every fill/stroke reference in an SVG to `color`, AND also
  // stamps `fill="${color}"` onto child paths that have no explicit fill,
  // but only when the root's fill is being colored (i.e. a fill-based icon
  // set, not a stroke-only set like Lucide).
  //
  // Why the extra stamping: the live DOM preview uses inline SVG + CSS,
  // where SVG fill inheritance from the root works transparently. The
  // canvas designer rasterizes the SVG via `<img src=blob>`, and in that
  // context root-to-path fill inheritance is unreliable — Material icons
  // specifically leave paths without any fill attribute, so the canvas
  // painted nothing (or default black) for those paths. Setting fill
  // explicitly on each path avoids the inheritance path entirely.
  colorizeSvg(svgText, color) {
    if (!color) return svgText
    const parser = new DOMParser()
    const doc = parser.parseFromString(svgText, 'image/svg+xml')
    const svg = doc.querySelector('svg')
    if (!svg) return svgText

    // Replace any existing coloured fill/stroke on the root or any child.
    const setIfColored = (el, attr) => {
      const v = el.getAttribute(attr)
      if (v && v !== 'none') el.setAttribute(attr, color)
    }
    setIfColored(svg, 'fill')
    setIfColored(svg, 'stroke')
    svg.querySelectorAll('path, circle, rect, line, polyline, polygon, ellipse, g')
      .forEach((el) => {
        setIfColored(el, 'fill')
        setIfColored(el, 'stroke')
      })

    // Stamp fill on paths that would otherwise rely on root inheritance.
    // Only when the root actively uses fill — skip stroke-only sets like
    // Lucide where root fill="none" and the icon lives on strokes.
    const rootFill = svg.getAttribute('fill')
    const fillActive = rootFill && rootFill !== 'none'
    if (fillActive) {
      svg.querySelectorAll('path, circle, rect, polygon, ellipse').forEach((el) => {
        if (!el.hasAttribute('fill') && !el.hasAttribute('stroke')) {
          el.setAttribute('fill', color)
        }
      })
    }

    const out = new XMLSerializer().serializeToString(doc)
    console.group(`[DesignerExport.colorizeSvg] color=${color}`)
    console.log('before fill/stroke attrs:', extractFillStroke(svgText))
    console.log('after  fill/stroke attrs:', extractFillStroke(out))
    console.groupEnd()
    return out
  },

  // Apply the current designer settings to an SVG string: recolor fills/strokes,
  // then wrap the artwork with padding, a background rect, and rounded corners.
  // Returns SVG text. Shared by the single-icon designer download and the basket
  // bulk SVG export so both honour identical settings.
  designSvg(rawSvg, settings) {
    const { color, bg, padding, radius } = settings || this.getSettings()
    const parser = new DOMParser()
    const doc = parser.parseFromString(rawSvg, 'image/svg+xml')
    const svg = doc.querySelector('svg')
    if (!svg) return rawSvg

    const vb = svg.getAttribute('viewBox')?.split(/\s+/).map(Number) || [0, 0, 24, 24]
    const [, , vw, vh] = vb

    if (color) {
      const colorize = (el) => {
        const fill = el.getAttribute('fill')
        if (fill && fill !== 'none') el.setAttribute('fill', color)
        const stroke = el.getAttribute('stroke')
        if (stroke && stroke !== 'none') el.setAttribute('stroke', color)
      }
      colorize(svg)
      svg.querySelectorAll('path, circle, rect, line, polyline, polygon, ellipse, g').forEach(colorize)
    }

    if (bg || padding > 0 || radius > 0) {
      const pad = padding * Math.max(vw, vh)
      const newW = vw + pad * 2
      const newH = vh + pad * 2
      const r = radius * Math.max(newW, newH) / 2

      const g = doc.createElementNS('http://www.w3.org/2000/svg', 'g')
      g.setAttribute('transform', `translate(${pad}, ${pad})`)
      while (svg.firstChild) g.appendChild(svg.firstChild)

      svg.setAttribute('viewBox', `0 0 ${newW} ${newH}`)

      if (bg) {
        const rect = doc.createElementNS('http://www.w3.org/2000/svg', 'rect')
        rect.setAttribute('width', newW)
        rect.setAttribute('height', newH)
        rect.setAttribute('rx', r)
        rect.setAttribute('ry', r)
        rect.setAttribute('fill', bg)
        svg.appendChild(rect)
      }
      svg.appendChild(g)
    }

    return new XMLSerializer().serializeToString(doc)
  },

  // Intrinsic aspect ratio (w/h) of an SVG string, from its viewBox
  // (falling back to width/height, then 1:1). Canvas drawImage stretches to
  // the destination rect, so non-square icons (e.g. FontAwesome's narrow
  // glyphs) come out distorted unless we fit them preserving aspect ratio.
  svgAspect(svgText) {
    const vb = /viewBox\s*=\s*["']([^"']+)["']/.exec(svgText)
    if (vb) {
      const p = vb[1].trim().split(/[\s,]+/).map(Number)
      if (p.length === 4 && p[2] > 0 && p[3] > 0) return p[2] / p[3]
    }
    const w = /\bwidth\s*=\s*["']([\d.]+)/.exec(svgText)
    const h = /\bheight\s*=\s*["']([\d.]+)/.exec(svgText)
    if (w && h && +h[1] > 0) return +w[1] / +h[1]
    return 1
  },

  // Fit a box of the given aspect ratio inside dest rect (x,y,w,h),
  // centered ("contain"). Returns the drawImage destination rect.
  fitContain(aspect, x, y, w, h) {
    let dw = w, dh = h
    if (aspect > w / h) dh = w / aspect
    else dw = h * aspect
    return { dx: x + (w - dw) / 2, dy: y + (h - dh) / 2, dw, dh }
  },

  renderToCanvas(svgText, size, settings) {
    const { color, bg, padding, radius } = settings || this.getSettings()
    return new Promise((resolve) => {
      const canvas = document.createElement('canvas')
      canvas.width = size
      canvas.height = size
      const ctx = canvas.getContext('2d')
      const r = radius * size / 2

      ctx.beginPath()
      ctx.roundRect(0, 0, size, size, r)
      ctx.clip()

      if (bg) {
        ctx.fillStyle = bg
        ctx.fillRect(0, 0, size, size)
      }

      const colorized = color ? this.colorizeSvg(svgText, color) : svgText
      const aspect = this.svgAspect(colorized)
      const blob = new Blob([colorized], { type: 'image/svg+xml' })
      const url = URL.createObjectURL(blob)
      const img = new Image()
      img.onload = () => {
        const pad = padding * size
        const { dx, dy, dw, dh } = this.fitContain(aspect, pad, pad, size - pad * 2, size - pad * 2)
        ctx.drawImage(img, dx, dy, dw, dh)
        URL.revokeObjectURL(url)
        canvas.toBlob(blob => resolve(blob), 'image/png')
      }
      img.src = url
    })
  },

  async downloadPngZip(svgUrl, baseName, sizes) {
    if (!window.JSZip) return
    sizes = sizes || this.getSizes()
    if (sizes.length === 0) return

    const resp = await fetch(svgUrl)
    const rawSvg = await resp.text()
    const settings = this.getSettings()

    const zip = new JSZip()
    for (const size of sizes) {
      const blob = await this.renderToCanvas(rawSvg, size, settings)
      zip.file(`${baseName}-${size}.png`, blob)
    }

    // Manifest
    const manifest = {
      generator: 'icons.pureadmin.io — Download Designer',
      url: window.location.origin,
      icon: baseName,
      source_svg: window.location.origin + svgUrl,
      created: new Date().toISOString(),
      settings: {
        include_colors: settings.includeColors,
        icon_color: settings.color || 'original',
        background: settings.bg || 'transparent',
        padding_percent: Math.round(settings.padding * 100),
        corner_radius_percent: Math.round(settings.radius * 100),
        preset_name: PresetManager.active()?.label || 'Custom',
        preset_key: PresetManager.activeKey()
      },
      files: sizes.map(s => ({ filename: `${baseName}-${s}.png`, size: s, format: 'png' }))
    }
    zip.file('manifest.json', JSON.stringify(manifest, null, 2))

    // Readme
    const sep = '='.repeat(60)
    const readme = [
      `${baseName} - PNG Icon Pack`, sep, '',
      `Generated by icons.pureadmin.io Download Designer`,
      window.location.origin, '', '',
      `ICON`, '-'.repeat(40),
      `Name:       ${baseName}`,
      `Source SVG: ${window.location.origin}${svgUrl}`,
      `Created:    ${new Date().toLocaleString()}`, '', '',
      `SETTINGS`, '-'.repeat(40),
      `Colors:        ${manifest.settings.include_colors ? 'Yes' : 'No (original)'}`,
      manifest.settings.include_colors ? `Icon color:    ${manifest.settings.icon_color}` : null,
      manifest.settings.include_colors ? `Background:    ${manifest.settings.background}` : null,
      manifest.settings.include_colors ? `Preset:        ${manifest.settings.preset_name}` : null,
      `Padding:       ${manifest.settings.padding_percent}%`,
      `Corner radius: ${manifest.settings.corner_radius_percent}%`, '', '',
      `FILES`, '-'.repeat(40),
      ...sizes.map(s => `  ${baseName}-${s}.png  (${s} x ${s} px)`), '', '',
      `RE-IMPORTING THESE SETTINGS`, '-'.repeat(40),
      `To recreate these icons with the same settings:`, '',
      `  1. Go to ${window.location.origin}`,
      `  2. Open any icon's detail dialog`,
      `  3. In the Download Designer section, click "Import Settings"`,
      `  4. Select the manifest.json file from this ZIP`, '',
      `All settings (colors, padding, corners, sizes) will be restored.`, '', '',
      `LICENSE`, '-'.repeat(40),
      `The icon SVG retains its original license from the source icon set.`,
      `Colors and formatting applied by icons.pureadmin.io are not subject`,
      `to additional licensing.`, ''
    ].filter(Boolean).join('\n')
    zip.file('readme.txt', readme)

    const zipBlob = await zip.generateAsync({ type: 'blob' })
    const a = document.createElement('a')
    a.href = URL.createObjectURL(zipBlob)
    a.download = `${baseName}-pngs.zip`
    document.body.appendChild(a)
    a.click()
    document.body.removeChild(a)
    URL.revokeObjectURL(a.href)

    return sizes
  },

  // Trigger a browser download for a Blob.
  _saveBlob(blob, filename) {
    const a = document.createElement('a')
    a.href = URL.createObjectURL(blob)
    a.download = filename
    document.body.appendChild(a)
    a.click()
    document.body.removeChild(a)
    URL.revokeObjectURL(a.href)
  },

  // Build a collision-free base filename for a basket item ("{set}__{name}").
  _basketBaseName(item) {
    const safe = s => String(s || '').trim().replace(/[^a-z0-9._-]+/gi, '-').replace(/^-+|-+$/g, '')
    return `${safe(item.set)}__${safe(item.name)}`
  },

  // Bulk-download the SVGs for every basket item as a single zip, applying the
  // current designer settings (color/background/padding/corners) to each — the
  // same transform the single-icon designer uses. With "include colors" off and
  // no padding/radius, this is the plain original SVG.
  async downloadSvgZip(items) {
    if (!window.JSZip || !items || items.length === 0) return
    const settings = this.getSettings()
    const designed = !!(settings.color || settings.bg || settings.padding > 0 || settings.radius > 0)
    const zip = new JSZip()
    const seen = {}
    const manifestFiles = []

    for (const item of items) {
      if (!item.url) continue
      try {
        const resp = await fetch(item.url)
        const rawSvg = await resp.text()
        const svg = designed ? this.designSvg(rawSvg, settings) : rawSvg
        let base = this._basketBaseName(item)
        // De-dupe identical base names within the zip.
        if (seen[base] != null) { seen[base] += 1; base = `${base}-${seen[base]}` }
        else { seen[base] = 0 }
        const filename = `${base}.svg`
        zip.file(filename, svg)
        manifestFiles.push({ filename, name: item.name, set: item.set, style: item.style, source_svg: window.location.origin + item.url })
      } catch (err) {
        console.error('[BasketExport] SVG fetch failed:', item.url, err)
      }
    }

    zip.file('manifest.json', JSON.stringify({
      generator: 'icons.pureadmin.io — Basket',
      url: window.location.origin,
      created: new Date().toISOString(),
      designed,
      settings: designed ? {
        include_colors: settings.includeColors,
        icon_color: settings.color || 'original',
        background: settings.bg || 'transparent',
        padding_percent: Math.round(settings.padding * 100),
        corner_radius_percent: Math.round(settings.radius * 100)
      } : null,
      count: manifestFiles.length,
      files: manifestFiles
    }, null, 2))

    const blob = await zip.generateAsync({ type: 'blob' })
    this._saveBlob(blob, 'pure-admin-icons-svgs.zip')
  },

  // Bulk-download PNGs for every basket item (all designer sizes) as one zip.
  async downloadPngZipBatch(items) {
    if (!window.JSZip || !items || items.length === 0) return
    const sizes = this.getSizes()
    if (sizes.length === 0) return
    const settings = this.getSettings()

    const zip = new JSZip()
    const seen = {}
    const manifestFiles = []

    for (const item of items) {
      if (!item.url) continue
      try {
        const resp = await fetch(item.url)
        const rawSvg = await resp.text()
        let base = this._basketBaseName(item)
        if (seen[base] != null) { seen[base] += 1; base = `${base}-${seen[base]}` }
        else { seen[base] = 0 }
        for (const size of sizes) {
          const blob = await this.renderToCanvas(rawSvg, size, settings)
          const filename = `${base}-${size}.png`
          zip.file(filename, blob)
          manifestFiles.push({ filename, name: item.name, set: item.set, size, format: 'png' })
        }
      } catch (err) {
        console.error('[BasketExport] PNG render failed:', item.url, err)
      }
    }

    zip.file('manifest.json', JSON.stringify({
      generator: 'icons.pureadmin.io — Basket',
      url: window.location.origin,
      created: new Date().toISOString(),
      settings: {
        include_colors: settings.includeColors,
        icon_color: settings.color || 'original',
        background: settings.bg || 'transparent',
        padding_percent: Math.round(settings.padding * 100),
        corner_radius_percent: Math.round(settings.radius * 100)
      },
      sizes,
      count: items.length,
      files: manifestFiles
    }, null, 2))

    const blob = await zip.generateAsync({ type: 'blob' })
    this._saveBlob(blob, 'pure-admin-icons-pngs.zip')
  }
}

// Inline SVG loader with lazy loading, caching, and color support
Hooks.IconColorFilter = {
  mounted() {
    console.time('[hook] IconColorFilter.mounted')
    this.svgCache = new Map()
    this.applyPreviewBg()
    this.loadAllSvgs()
    console.timeEnd('[hook] IconColorFilter.mounted')
    window.addEventListener('iconColorChanged', () => {
      this.updateAllColors()
      this.applyPreviewBg()
    })
  },
  updated() {
    // Every LiveView update: eagerly load any icon container that's in
    // the DOM but missing its <svg>. We used to rely on the intersection
    // observer alone + a signature guard, but morphdom can replace icon
    // containers across filter toggles and the new empty spans never got
    // observed. Eager loading is cheap (30 icons per page, browser-cached
    // SVGs), robust, and always leaves every visible icon coloured.
    this.loadAllSvgs()
    this.updateAllColors()
    this.applyPreviewBg()
  },
  applyPreviewBg() {
    let bg = '#ffffff'
    try { bg = JSON.parse(localStorage.getItem('icon_preview_bg') || '"#ffffff"') } catch { bg = localStorage.getItem('icon_preview_bg') || '#ffffff' }
    this.el.querySelectorAll('.icon-preview-bg').forEach(el => {
      el.style.removeProperty('background-image')
      el.style.removeProperty('background-size')
      if (bg === 'checker') {
        el.style.backgroundImage = 'repeating-conic-gradient(#d1d5db 0% 25%, #fff 0% 50%)'
        el.style.backgroundSize = '8px 8px'
        el.style.backgroundColor = ''
      } else {
        el.style.backgroundColor = bg
      }
    })
  },
  async loadAllSvgs() {
    // Eagerly load every empty container. Pages cap at 30 icons, SVGs are
    // browser-cached with ETags (served from /icons/*), and the fetch is
    // cheap compared to guarding with IntersectionObserver which turned
    // out to miss spans that morphdom created across filter toggles.
    this.el.querySelectorAll('.inline-svg-icon').forEach(icon => {
      if (!icon.querySelector('svg')) {
        this.loadSvg(icon)
      }
    })
  },
  async loadSvg(container) {
    const color = localStorage.getItem('icon_preview_color') || '#212121'
    const url = container.dataset.svgUrl
    if (!url) return
    try {
      let svgText
      if (this.svgCache.has(url)) {
        svgText = this.svgCache.get(url)
      } else {
        const response = await fetch(url)
        svgText = await response.text()
        this.svgCache.set(url, svgText)
      }
      container.innerHTML = svgText
      const svg = container.querySelector('svg')
      if (svg) {
        svg.style.width = '100%'
        svg.style.height = '100%'
        this.colorizeSvg(svg, color, url)
      }
      container.dataset.loaded = 'true'
    } catch (err) {
      console.error('[IconColorFilter] Failed to load SVG:', url, err)
    }
  },
  // Thin wrapper — the logic lives in the shared colorizeLiveSvg helper so
  // the grid, modal preview, and preset-change updater all use the same
  // rules. `debugUrl` preserved for the log that flagged icons with no
  // fill/stroke attrs.
  colorizeSvg(svg, color, debugUrl) {
    const hasAny =
      svg.getAttribute('fill') || svg.getAttribute('stroke') ||
      svg.querySelector('[fill], [stroke]')
    colorizeLiveSvg(svg, color)
    if (!hasAny) {
      console.warn('[IconColorFilter] No fill/stroke attributes found in SVG, icon may render with default color:', debugUrl)
    }
  },
  updateAllColors() {
    const color = localStorage.getItem('icon_preview_color') || '#212121'
    let count = 0
    this.el.querySelectorAll('.inline-svg-icon').forEach(icon => {
      const svg = icon.querySelector('svg')
      if (svg) {
        this.colorizeSvg(svg, color, icon.dataset.svgUrl)
        count++
      }
    })
    console.log(`[IconColorFilter] updateAllColors recolored ${count} icons to ${color}`)
  }
}

// Metrics tracker — exposes pushEvent for JS + filter persistence
Hooks.MetricsTracker = {
  mounted() {
    this.el._pushEvent = (event, params) => {
      this.pushEvent(event, params)
    }
    this.handleEvent("save_filters", ({styles, sizes, icon_sets}) => {
      localStorage.setItem("icon_filter_styles", JSON.stringify(styles))
      localStorage.setItem("icon_filter_sizes", JSON.stringify(sizes))
      localStorage.setItem("icon_filter_icon_sets", JSON.stringify(icon_sets))
    })
    // Basket persistence — the server pushes the full basket after every change.
    this.handleEvent("save_basket", ({basket}) => {
      localStorage.setItem("icon_basket", JSON.stringify(basket || []))
    })
  }
}

// View mode persistence
Hooks.ViewMode = {
  mounted() {
    this.handleEvent("save_view_mode", ({mode}) => {
      localStorage.setItem("icon_view_mode", mode)
      document.documentElement.setAttribute('data-view-mode', mode)
    })
  }
}

// Basket bulk actions — SVG/PNG zip downloads (client-side) and the
// server-pushed "copy all identifiers" clipboard write. The basket item list
// (name/set/url) is passed in via the element's data-basket attribute.
Hooks.BasketActions = {
  items() {
    try { return JSON.parse(this.el.dataset.basket || '[]') } catch { return [] }
  },
  flash(btn) {
    if (!btn) return
    const svg = btn.querySelector('svg')
    if (svg) { svg.style.color = '#22c55e'; setTimeout(() => svg.style.color = '', 1200) }
  },
  mounted() {
    this.onClick = async (e) => {
      const btn = e.target.closest('[data-basket-action]')
      if (!btn || btn.disabled) return
      const action = btn.dataset.basketAction
      const items = this.items()
      if (items.length === 0) return
      btn.disabled = true
      try {
        if (action === 'svg-zip') await DesignerExport.downloadSvgZip(items)
        else if (action === 'png-zip') await DesignerExport.downloadPngZipBatch(items)
        this.flash(btn)
      } catch (err) {
        console.error('[BasketActions] export failed:', err)
      } finally {
        btn.disabled = false
      }
    }
    this.el.addEventListener('click', this.onClick)

    this.handleEvent('copy_all_ids', ({text}) => {
      if (!text) return
      navigator.clipboard.writeText(text).then(() => {
        const tip = document.createElement('div')
        tip.textContent = 'Copied!'
        tip.className = 'fixed z-[100] px-2 py-1 text-xs font-medium rounded bg-success text-success-content shadow-lg pointer-events-none'
        const rect = this.el.getBoundingClientRect()
        tip.style.left = `${rect.left + rect.width / 2}px`
        tip.style.top = `${rect.top}px`
        tip.style.transform = 'translateX(-50%)'
        document.body.appendChild(tip)
        setTimeout(() => tip.remove(), 1200)
      }).catch(err => console.error('[BasketActions] copy failed:', err))
    })
  },
  destroyed() {
    this.el.removeEventListener('click', this.onClick)
  }
}

// Platform preferences persistence
Hooks.PlatformPrefs = {
  mounted() {
    this.handleEvent("save_platform_prefs", (prefs) => {
      localStorage.setItem("icon_platform_prefs", JSON.stringify(prefs))
    })
  }
}

// ColorPicker hook — modal icon color preview with presets
Hooks.ColorPicker = {
  mounted() {
    this.colorInput = this.el.querySelector('.color-input')
    this.textInput = this.el.querySelector('.color-text')
    this.bgColorInput = this.el.querySelector('.bg-color-input')
    this.bgColorText = this.el.querySelector('.bg-color-text')
    this.renderCustomPresets()
    this.bindPresetButtons()
    this.applySaved()

    // Sync when colors change externally (e.g. DownloadDesigner import, QuickPresets)
    window.addEventListener('iconColorChanged', () => {
      this.rebuildDropdown()
      this.syncComboTrigger()
      // Update inputs + modal preview (no re-dispatch since updateSvgColors is now pure)
      const color = localStorage.getItem('icon_preview_color') || '#212121'
      let bg = '#ffffff'
      try { bg = JSON.parse(localStorage.getItem('icon_preview_bg') || '"#ffffff"') } catch { bg = localStorage.getItem('icon_preview_bg') || '#ffffff' }
      if (this.colorInput) this.colorInput.value = color
      if (this.textInput) this.textInput.value = color
      if (this.bgColorInput && bg !== 'checker') this.bgColorInput.value = bg
      if (this.bgColorText) this.bgColorText.value = bg === 'checker' ? 'transparent' : bg
      this.applyBg(bg)
      this.updateSvgColors(color)
    })

    // Preset combo dropdown
    const comboTrigger = this.el.querySelector('.preview-preset-trigger')
    const comboDropdown = this.el.querySelector('.preview-preset-dropdown')
    if (comboTrigger && comboDropdown) {
      comboTrigger.addEventListener('click', (e) => {
        e.stopPropagation()
        this.renderCustomPresets()
        this.bindPresetButtons()
        this.rebuildDropdown()
        comboDropdown.classList.toggle('hidden')
      })
      this._comboOutsideClick = (e) => {
        if (!this.el.querySelector('.preview-preset-combo')?.contains(e.target))
          comboDropdown.classList.add('hidden')
      }
      document.addEventListener('click', this._comboOutsideClick)
    }

    // Custom icon color inputs
    if (this.colorInput) {
      this.colorInput.addEventListener('input', (e) => {
        if (this.textInput) this.textInput.value = e.target.value
        localStorage.removeItem('icon_preview_preset')
        this.highlightPreset(null)
        this.syncComboTrigger()
        this.updateSvgColors(e.target.value)
        window.dispatchEvent(new CustomEvent('iconColorChanged'))
      })
    }
    if (this.textInput) {
      this.textInput.addEventListener('input', (e) => {
        let color = e.target.value
        if (color && !color.startsWith('#')) { color = '#' + color; this.textInput.value = color }
        if (/^#[0-9A-Fa-f]{6}$/.test(color)) {
          if (this.colorInput) this.colorInput.value = color
          localStorage.removeItem('icon_preview_preset')
          this.highlightPreset(null)
        this.syncComboTrigger()
          this.updateSvgColors(color)
          window.dispatchEvent(new CustomEvent('iconColorChanged'))
        }
      })
    }

    // Custom background color inputs
    if (this.bgColorInput) {
      this.bgColorInput.addEventListener('input', (e) => {
        if (this.bgColorText) this.bgColorText.value = e.target.value
        localStorage.setItem('icon_preview_bg', JSON.stringify(e.target.value))
        localStorage.removeItem('icon_preview_preset')
        this.highlightPreset(null)
        this.syncComboTrigger()
        this.applyBg(e.target.value)
      })
    }
    if (this.bgColorText) {
      this.bgColorText.addEventListener('input', (e) => {
        let bg = e.target.value
        if (bg && !bg.startsWith('#')) { bg = '#' + bg; this.bgColorText.value = bg }
        if (/^#[0-9A-Fa-f]{6}$/.test(bg)) {
          if (this.bgColorInput) this.bgColorInput.value = bg
          localStorage.setItem('icon_preview_bg', JSON.stringify(bg))
          localStorage.removeItem('icon_preview_preset')
          this.highlightPreset(null)
          this.syncComboTrigger()
          this.applyBg(bg)
        }
      })
    }
    // Transparent background toggle (checker pattern)
    const transparentBtn = this.el.querySelector('.bg-transparent-toggle')
    if (transparentBtn) {
      transparentBtn.addEventListener('click', () => {
        localStorage.setItem('icon_preview_bg', JSON.stringify('checker'))
        localStorage.removeItem('icon_preview_preset')
        if (this.bgColorText) this.bgColorText.value = 'transparent'
        this.highlightPreset(null)
        this.syncComboTrigger()
        this.applyBg('checker')
      })
    }

    // Copy CSS button
    const copyCssBtn = this.el.querySelector('.preview-copy-css')
    if (copyCssBtn) {
      copyCssBtn.addEventListener('click', () => {
        const css = this.generateCss()
        navigator.clipboard.writeText(css).then(() => {
          const orig = copyCssBtn.innerHTML
          copyCssBtn.innerHTML = '<svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/></svg> Copied!'
          setTimeout(() => { copyCssBtn.innerHTML = orig }, 1500)
        })
      })
    }

    // Import CSS button + dialog
    const importBtn = this.el.querySelector('.preview-import-css')
    const importArea = this.el.querySelector('.preview-import-area')
    const importTextarea = this.el.querySelector('.preview-import-textarea')
    const importSubmit = this.el.querySelector('.preview-import-submit')
    const importCancel = this.el.querySelector('.preview-import-cancel')
    const importStatus = this.el.querySelector('.preview-import-status')

    if (importBtn && importArea) {
      importBtn.addEventListener('click', () => {
        importArea.style.display = importArea.style.display === 'none' ? '' : 'none'
        if (importArea.style.display !== 'none') importTextarea?.focus()
      })
    }
    if (importCancel) {
      importCancel.addEventListener('click', () => {
        importArea.style.display = 'none'
        if (importStatus) importStatus.textContent = ''
        if (importTextarea) importTextarea.value = ''
      })
    }
    if (importSubmit) {
      importSubmit.addEventListener('click', () => {
        const css = importTextarea?.value || ''
        const parsed = this.parseImportedCss(css)
        if (!parsed) {
          if (importStatus) {
            importStatus.textContent = 'Could not parse — need either a "Preset — Name [color: #..., background-color: #...]" comment, or at least a CSS rule with color: and background-color: properties.'
            importStatus.className = 'preview-import-status text-xs text-error'
          }
          return
        }
        // Save as custom preset
        const presets = PresetManager.getCustoms()
        const key = `custom-${Date.now()}`
        presets[key] = { color: parsed.color, bg: parsed.bg, label: parsed.label }
        PresetManager.saveCustoms(presets)
        // Activate it
        localStorage.setItem('icon_preview_color', parsed.color)
        localStorage.setItem('icon_preview_bg', JSON.stringify(parsed.bg))
        localStorage.setItem('icon_preview_preset', key)
        this.rebuildDropdown()
        if (this.colorInput) this.colorInput.value = parsed.color
        if (this.textInput) this.textInput.value = parsed.color
        if (this.bgColorInput) this.bgColorInput.value = parsed.bg
        if (this.bgColorText) this.bgColorText.value = parsed.bg
        // Update the custom-preset name input to reflect the just-imported preset
        const nameInput = this.el.querySelector('.custom-preset-name')
        if (nameInput) nameInput.value = parsed.label
        this.applyBg(parsed.bg)
        this.updateSvgColors(parsed.color)
        window.dispatchEvent(new CustomEvent('iconColorChanged'))
        this.highlightPreset(key)
        this.syncComboTrigger()
        // Show custom area so user can see the imported preset's fields
        const customArea = this.el.querySelector('.preview-custom-area')
        if (customArea) customArea.style.display = ''
        if (importStatus) {
          importStatus.textContent = `Imported "${parsed.label}" — selected`
          importStatus.className = 'preview-import-status text-xs text-success'
        }
        if (importTextarea) importTextarea.value = ''
        setTimeout(() => {
          if (importStatus) importStatus.textContent = ''
          if (importArea) importArea.style.display = 'none'
        }, 2000)
      })
    }

    // Save as preset (creates new with timestamp ID, or updates active custom preset)
    const saveBtn = this.el.querySelector('.custom-preset-save')
    const nameInput = this.el.querySelector('.custom-preset-name')
    if (saveBtn && nameInput) {
      saveBtn.addEventListener('click', () => {
        const name = nameInput.value.trim()
        if (!name) {
          nameInput.focus()
          return
        }
        const color = this.colorInput ? this.colorInput.value : '#212121'
        let bg = '#ffffff'
        try { bg = JSON.parse(localStorage.getItem('icon_preview_bg') || '"#ffffff"') } catch { bg = localStorage.getItem('icon_preview_bg') || '#ffffff' }
        const presets = PresetManager.getCustoms()
        const activeKey = localStorage.getItem('icon_preview_preset')
        // If the active preset is a custom one, UPDATE it (keeps its ID).
        // Otherwise, create a new one with a timestamp-based ID.
        const key = (activeKey && presets[activeKey]) ? activeKey : `custom-${Date.now()}`
        presets[key] = { color, bg, label: name }
        PresetManager.saveCustoms(presets)
        // Activate the saved preset
        localStorage.setItem('icon_preview_preset', key)
        localStorage.setItem('icon_preview_color', color)
        localStorage.setItem('icon_preview_bg', JSON.stringify(bg))
        this.rebuildDropdown()
        this.highlightPreset(key)
        this.syncComboTrigger()
        window.dispatchEvent(new CustomEvent('iconColorChanged'))
      })
    }

    // Delete active custom preset
    const deleteBtn = this.el.querySelector('.custom-preset-delete')
    if (deleteBtn) {
      deleteBtn.addEventListener('click', () => {
        const activeKey = localStorage.getItem('icon_preview_preset')
        if (!activeKey) return
        const presets = PresetManager.getCustoms()
        if (!presets[activeKey]) return // can't delete built-in
        delete presets[activeKey]
        PresetManager.saveCustoms(presets)
        localStorage.removeItem('icon_preview_preset')
        this.rebuildDropdown()
        this.highlightPreset(null)
        this.syncComboTrigger()
        // Hide the custom area
        const customArea = this.el.querySelector('.preview-custom-area')
        if (customArea) customArea.style.display = 'none'
        window.dispatchEvent(new CustomEvent('iconColorChanged'))
      })
    }

    // New preset button — show custom area, pre-fill with current colors
    const newBtn = this.el.querySelector('.custom-preset-new')
    if (newBtn) {
      newBtn.addEventListener('click', () => {
        const customArea = this.el.querySelector('.preview-custom-area')
        if (customArea) customArea.style.display = ''
        // Clear name input for fresh preset
        if (nameInput) nameInput.value = ''
        // Pre-fill with current active colors (from selected preset or custom picks)
        const color = localStorage.getItem('icon_preview_color') || '#212121'
        let bg = '#ffffff'
        try { bg = JSON.parse(localStorage.getItem('icon_preview_bg') || '"#ffffff"') } catch { bg = localStorage.getItem('icon_preview_bg') || '#ffffff' }
        if (this.colorInput) this.colorInput.value = color
        if (this.textInput) this.textInput.value = color
        if (this.bgColorInput && bg !== 'checker') this.bgColorInput.value = bg
        if (this.bgColorText) this.bgColorText.value = bg === 'checker' ? 'transparent' : bg
        localStorage.removeItem('icon_preview_preset')
        this.highlightPreset(null)
        this.syncComboTrigger()
        if (nameInput) nameInput.focus()
      })
    }
  },
  renderCustomPresets() { /* no-op — PresetManager.renderDropdown handles everything */ },
  bindPresetButtons() {
    this.el.querySelectorAll('.preset-sorted, .preview-preset').forEach(btn => {
      if (btn.dataset.bound === 'true') return
      btn.dataset.bound = 'true'
      btn.addEventListener('click', () => {
        const preset = PresetManager.getAll()[btn.dataset.preset]
        if (!preset) return
        console.group(`[ColorPicker] preset clicked: ${btn.dataset.preset}`)
        console.log('preset:', preset)
        console.log('  color →', preset.color, '  bg →', preset.bg)
        console.groupEnd()
        localStorage.setItem('icon_preview_color', preset.color)
        localStorage.setItem('icon_preview_bg', JSON.stringify(preset.bg))
        localStorage.setItem('icon_preview_preset', btn.dataset.preset)
        if (this.colorInput) this.colorInput.value = preset.color
        if (this.textInput) this.textInput.value = preset.color
        if (this.bgColorInput && preset.bg !== 'checker') this.bgColorInput.value = preset.bg
        if (this.bgColorText && preset.bg !== 'checker') this.bgColorText.value = preset.bg
        // If this is a custom preset, populate the name input so Save updates it instead of duplicating
        const customs = PresetManager.getCustoms()
        const nameInput = this.el.querySelector('.custom-preset-name')
        if (nameInput) {
          if (customs[btn.dataset.preset]) {
            nameInput.value = preset.label || ''
          } else {
            nameInput.value = ''
          }
        }
        this.applyBg(preset.bg)
        this.updateSvgColors(preset.color)
        window.dispatchEvent(new CustomEvent('iconColorChanged'))
        this.highlightPreset(btn.dataset.preset)
        this.syncComboTrigger()
        const dd = this.el.querySelector('.preview-preset-dropdown')
        if (dd) dd.classList.add('hidden')
        // Show custom area for custom presets so user can edit/delete
        const customArea = this.el.querySelector('.preview-custom-area')
        const isCustom = !!PresetManager.getCustoms()[btn.dataset.preset]
        if (customArea) customArea.style.display = isCustom ? '' : 'none'
      })
    })
  },
  updated() {
    this.colorInput = this.el.querySelector('.color-input')
    this.textInput = this.el.querySelector('.color-text')
    this.bgColorInput = this.el.querySelector('.bg-color-input')
    this.bgColorText = this.el.querySelector('.bg-color-text')
    this.renderCustomPresets()
    this.bindPresetButtons()
    this.applySaved()
  },
  applySaved() {
    const savedColor = localStorage.getItem('icon_preview_color') || '#212121'
    let savedBg = '#ffffff'
    try { savedBg = JSON.parse(localStorage.getItem('icon_preview_bg') || '"#ffffff"') } catch { savedBg = localStorage.getItem('icon_preview_bg') || '#ffffff' }
    const savedPreset = localStorage.getItem('icon_preview_preset')
    requestAnimationFrame(() => {
      if (this.colorInput) this.colorInput.value = savedColor
      if (this.textInput) this.textInput.value = savedColor
      if (this.bgColorInput && savedBg !== 'checker') this.bgColorInput.value = savedBg
      if (this.bgColorText) this.bgColorText.value = savedBg === 'checker' ? 'transparent' : savedBg
      this.applyBg(savedBg)
      this.updateSvgColors(savedColor)
      window.dispatchEvent(new CustomEvent('iconColorChanged'))
      this.highlightPreset(savedPreset)
      this.syncComboTrigger()
      // Show custom area if active preset is a custom one (so user can edit/delete)
      const customArea = this.el.querySelector('.preview-custom-area')
      const isCustom = savedPreset && !!PresetManager.getCustoms()[savedPreset]
      if (customArea) {
        customArea.style.display = isCustom ? '' : 'none'
        // Populate name input for custom presets
        if (isCustom) {
          const nameInput = this.el.querySelector('.custom-preset-name')
          const customs = PresetManager.getCustoms()
          if (nameInput && customs[savedPreset]) nameInput.value = customs[savedPreset].label || ''
        }
      }
    })
  },
  syncComboTrigger() {
    PresetManager.syncTrigger(
      this.el.querySelector('.preview-preset-swatch'),
      this.el.querySelector('.preview-preset-label')
    )
  },
  rebuildDropdown() {
    const dropdown = this.el.querySelector('.preview-preset-dropdown')
    PresetManager.renderDropdown(dropdown)
    this.bindPresetButtons()
  },
  applyBg(bg) {
    // Modal preview boxes
    document.querySelectorAll('.svg-container').forEach(c => {
      c.style.removeProperty('background-image')
      c.style.removeProperty('background-size')
      c.className = c.className.replace(/bg-\S+/g, '')
      c.classList.add('rounded-lg', 'p-3', 'border', 'border-base-300', 'flex', 'items-center', 'justify-center')
      if (bg === 'checker') {
        c.style.backgroundImage = 'repeating-conic-gradient(#d1d5db 0% 25%, #fff 0% 50%)'
        c.style.backgroundSize = '12px 12px'
      } else {
        c.style.backgroundColor = bg
      }
    })
    // Grid / list icon wrappers
    document.querySelectorAll('.icon-preview-bg').forEach(el => {
      el.style.removeProperty('background-image')
      el.style.removeProperty('background-size')
      if (bg === 'checker') {
        el.style.backgroundImage = 'repeating-conic-gradient(#d1d5db 0% 25%, #fff 0% 50%)'
        el.style.backgroundSize = '8px 8px'
        el.style.backgroundColor = ''
      } else {
        el.style.backgroundColor = bg
      }
    })
  },
  // Parse pasted CSS to extract a preset.
  // Strategy 1: look for the "Preset — Name [color: #X, background: #Y]" comment
  // Strategy 2: extract the first background-color + color from any CSS rule
  parseImportedCss(css) {
    if (!css || !css.trim()) return null

    // Strategy 1: parse the preset comment (accepts both background: and background-color:)
    const presetCommentRe = /Preset\s*[—\-]\s*([^\(\[]+?)(?:\s*\([^)]+\))?\s*\[\s*color:\s*(#[0-9a-fA-F]{3,8})\s*,\s*background(?:-color)?:\s*(#[0-9a-fA-F]{3,8}|checker)\s*\]/i
    const m = css.match(presetCommentRe)
    if (m) {
      return {
        label: m[1].trim(),
        color: m[2].toLowerCase(),
        bg: m[3].toLowerCase()
      }
    }

    // Strategy 2: extract first background-color and color values
    const bgMatch = css.match(/background(?:-color)?\s*:\s*(#[0-9a-fA-F]{3,8})/i)
    const colorMatch = css.match(/(?:^|[^-])\bcolor\s*:\s*(#[0-9a-fA-F]{3,8})/i)
    if (bgMatch && colorMatch) {
      return {
        label: 'Imported',
        color: colorMatch[1].toLowerCase(),
        bg: bgMatch[1].toLowerCase()
      }
    }

    return null
  },
  generateCss() {
    const color = localStorage.getItem('icon_preview_color') || '#212121'
    let bg = '#ffffff'
    try { bg = JSON.parse(localStorage.getItem('icon_preview_bg') || '"#ffffff"') } catch { bg = localStorage.getItem('icon_preview_bg') || '#ffffff' }
    const colorMethod = this.el.dataset.colorMethod || 'fill'
    const iconSet = this.el.dataset.iconSet || ''
    const presetKey = localStorage.getItem('icon_preview_preset')
    const presetLabel = presetKey ? (PresetManager.getAll()[presetKey]?.label || presetKey) : 'Custom'

    // CSS class derived from the preset's LABEL (not key) so renaming a custom preset
    // updates the CSS class too. Built-in preset keys already match the slug of their label.
    const cssClass = presetLabel.toLowerCase().replace(/[^a-z0-9]+/g, '-') || 'custom'

    // Selectors per icon set:
    //   scoped  — adds preset class so multiple presets can coexist
    //   global  — applies to ALL icons of this set, no scope
    let scopedSelector, globalSelector, scopedUsage, globalUsage
    if (iconSet === 'fontawesome') {
      scopedSelector = `i.${cssClass}.fa-solid, i.${cssClass}.fa-regular, i.${cssClass}.fa-brands`
      globalSelector = `i.fa-solid, i.fa-regular, i.fa-brands`
      scopedUsage = `<i class="${cssClass} fa-solid fa-arrow-right"></i>`
      globalUsage = `<i class="fa-solid fa-arrow-right"></i>`
    } else if (iconSet === 'tabler') {
      scopedSelector = `i.${cssClass}.ti`
      globalSelector = `i.ti`
      scopedUsage = `<i class="${cssClass} ti ti-arrow-right"></i>`
      globalUsage = `<i class="ti ti-arrow-right"></i>`
    } else {
      scopedSelector = `svg.${cssClass}`
      globalSelector = `svg`
      scopedUsage = `<Calendar className="${cssClass}" />`
      globalUsage = `<Calendar />  /* any icon component renders <svg> */`
    }

    // Header: identifies the preset so users can paste it back into icons.pureadmin.io to recreate it
    const presetHeader = `/* Preset — ${presetLabel} (${iconSet || 'icon'}) [color: ${color}, background-color: ${bg}] */`
    const colorMethodComment = `/* Color method: ${colorMethod} */`

    // Build a CSS rule body for a given selector
    const buildRule = (selector) => {
      const lines = [`${selector} {`]

      if (bg === 'checker') {
        lines.push(
          `  background-image: repeating-conic-gradient(#d1d5db 0% 25%, #fff 0% 50%);`,
          `  background-size: 12px 12px;`
        )
      } else {
        lines.push(`  background-color: ${bg};`)
      }

      if (colorMethod === 'multicolor') {
        lines.push(`  /* Multicolor icon — original SVG colors are preserved */`)
      } else if (colorMethod === 'stroke') {
        lines.push(
          `  color: ${color};`,
          `  stroke: currentColor;`,
          `  fill: none;`
        )
      } else {
        lines.push(
          `  color: ${color};`,
          `  fill: currentColor;`
        )
      }

      lines.push(`}`)
      return lines.join('\n')
    }

    return [
      `/* Generated by icons.pureadmin.io */`,
      presetHeader,
      colorMethodComment,
      ``,
      buildRule(scopedSelector),
      ``,
      `/* Usage: */`,
      `/* ${scopedUsage} */`,
      ``,
      ``,
      `/* ─────────────────────────────────────────────────── */`,
      `/* GLOBAL OVERRIDE — applies to ALL ${iconSet || 'icon'} icons   */`,
      `/* Use this if you want every icon styled the same way  */`,
      `/* ─────────────────────────────────────────────────── */`,
      ``,
      presetHeader,
      colorMethodComment,
      ``,
      buildRule(globalSelector),
      ``,
      `/* Usage: */`,
      `/* ${globalUsage} */`
    ].join('\n')
  },
  highlightPreset(active) {
    this.el.querySelectorAll('.preview-preset').forEach(btn => {
      if (btn.dataset.preset === active) {
        btn.classList.add('ring-2', 'ring-primary', 'ring-offset-1')
      } else {
        btn.classList.remove('ring-2', 'ring-primary', 'ring-offset-1')
      }
    })
  },
  updateSvgColors(color) {
    localStorage.setItem('icon_preview_color', color)
    const svgContainer = document.querySelector('[phx-hook="InlineSvg"]')
    if (svgContainer) {
      svgContainer.dataset.color = color
      // Only the preview <svg>s live inside `.svg-container` — don't sweep
      // the download-arrow <svg> that sits inside each `<a class="download-link">`.
      svgContainer
        .querySelectorAll('.svg-container > svg')
        .forEach(svg => colorizeLiveSvg(svg, color))
    }
    // NOTE: callers are responsible for dispatching iconColorChanged when they
    // intend to notify the grid/other hooks. This function only updates the
    // modal preview SVGs — no event dispatch to avoid re-entry loops.
  }
}

// InlineSvg hook — loads SVGs in modal preview
Hooks.InlineSvg = {
  mounted() { this.loadSvgs() },
  updated() { this.loadSvgs() },
  async loadSvgs() {
    const color = localStorage.getItem('icon_preview_color') || '#212121'
    const urls = JSON.parse(this.el.dataset.urls || '[]')
    const containers = this.el.querySelectorAll('.svg-container')
    for (let i = 0; i < containers.length && i < urls.length; i++) {
      try {
        const response = await fetch(urls[i])
        const svgText = await response.text()
        containers[i].innerHTML = svgText
        const svg = containers[i].querySelector('svg')
        if (svg) {
          svg.style.width = `${containers[i].dataset.size}px`
          svg.style.height = `${containers[i].dataset.size}px`
          colorizeLiveSvg(svg, color)
        }
      } catch (err) { console.error('Failed to load SVG:', err) }
    }
  }
}

// SvelteColor hook — toggles color in generated Svelte code (fluentui only)
Hooks.SvelteColor = {
  mounted() {
    const iconSet = this.el.dataset.iconSet
    const checkbox = this.el.querySelector('.svelte-include-color')
    // Color toggle only applies to fluentui's svelte-fluentui package
    if (!checkbox || iconSet !== 'fluentui') return
    const name = this.el.dataset.name, style = this.el.dataset.style
    const sizes = JSON.parse(this.el.dataset.sizes || '[]')
    const savedPref = localStorage.getItem('svelte_include_color') === 'true'
    checkbox.checked = savedPref
    if (savedPref) this.updateCode(name, style, sizes, true)
    checkbox.addEventListener('change', (e) => {
      localStorage.setItem('svelte_include_color', e.target.checked)
      this.updateCode(name, style, sizes, e.target.checked)
    })
  },
  updateCode(name, style, sizes, includeColor) {
    const codeElements = this.el.querySelectorAll('code[data-size]')
    const color = document.querySelector('.color-input')?.value || localStorage.getItem('icon_preview_color') || '#212121'
    codeElements.forEach(code => {
      const size = code.dataset.size
      code.textContent = includeColor
        ? `<Icon name="${name}" size={${size}} variant="${style}" color="custom" customColor="${color}" />`
        : `<Icon name="${name}" size={${size}} variant="${style}" />`
    })
  }
}

// FloatingPopover hook — uses floating-ui to position copy-button popovers above
// .has-popover triggers (size pills in grid view, size cells in list view).
// The popover element lives inside its trigger as a child with .floating-popover.
// We position it using strategy:'fixed' so ancestor overflow doesn't clip it.
Hooks.FloatingPopover = {
  mounted() {
    this.attach()
    // Quick designer download — delegated click handler for all popovers
    this.el.addEventListener('click', async (e) => {
      const btn = e.target.closest('.quick-designer-download')
      if (!btn || !DesignerExport.hasSettings()) return
      e.stopPropagation()
      e.preventDefault()
      const svgUrl = btn.dataset.svgUrl
      const name = (btn.dataset.name || 'icon').toLowerCase().replace(/\s+/g, '-')
      const iconId = btn.dataset.iconId
      btn.style.opacity = '0.4'
      try {
        const sizes = await DesignerExport.downloadPngZip(svgUrl, name)
        // Track in metrics — mirrors DownloadDesigner's own PNG-ZIP button.
        const metricsEl = document.getElementById('metrics-tracker')
        if (metricsEl?._pushEvent && iconId) {
          metricsEl._pushEvent('track_download', {
            'icon-id': iconId,
            size: (sizes || []).join(','),
            naming: 'popover:png-zip'
          })
        }
      } catch (err) {
        console.error('[FloatingPopover] Quick download failed:', err)
      }
      btn.style.opacity = ''
    })
  },
  updated() {
    this.detach()
    this.attach()
  },
  destroyed() {
    this.detach()
  },
  attach() {
    if (!window.FloatingUIDOM) {
      console.warn('[FloatingPopover] floating-ui-dom global not loaded — popovers disabled')
      return
    }
    this.handlers = []
    this.el.querySelectorAll('.has-popover').forEach(trigger => {
      const popover = trigger.querySelector('.floating-popover')
      if (!popover) return

      let hideTimer = null
      const cancelHide = () => { if (hideTimer) { clearTimeout(hideTimer); hideTimer = null } }
      const scheduleHide = () => {
        cancelHide()
        hideTimer = setTimeout(() => this.hide(popover), 150)
      }
      const onTriggerEnter = () => { cancelHide(); this.show(trigger, popover) }
      const onTriggerLeave = scheduleHide
      const onPopoverEnter = cancelHide
      const onPopoverLeave = scheduleHide

      trigger.addEventListener('mouseenter', onTriggerEnter)
      trigger.addEventListener('mouseleave', onTriggerLeave)
      popover.addEventListener('mouseenter', onPopoverEnter)
      popover.addEventListener('mouseleave', onPopoverLeave)
      this.handlers.push({ trigger, popover, onTriggerEnter, onTriggerLeave, onPopoverEnter, onPopoverLeave })
    })
  },
  detach() {
    if (!this.handlers) return
    this.handlers.forEach(({ trigger, popover, onTriggerEnter, onTriggerLeave, onPopoverEnter, onPopoverLeave }) => {
      trigger.removeEventListener('mouseenter', onTriggerEnter)
      trigger.removeEventListener('mouseleave', onTriggerLeave)
      popover.removeEventListener('mouseenter', onPopoverEnter)
      popover.removeEventListener('mouseleave', onPopoverLeave)
      popover.classList.remove('popover-open')
    })
    this.handlers = []
  },
  show(trigger, popover) {
    popover.classList.add('popover-open')
    const { computePosition, offset, flip, shift } = window.FloatingUIDOM
    computePosition(trigger, popover, {
      strategy: 'fixed',
      placement: 'top',
      middleware: [offset(2), flip(), shift({ padding: 8 })]
    }).then(({ x, y }) => {
      popover.style.left = `${x}px`
      popover.style.top = `${y}px`
    })
  },
  hide(popover) {
    popover.classList.remove('popover-open')
  }
}

// QuickPresets hook — preset dropdown in the results bar
Hooks.QuickPresets = {
  mounted() {
    this.trigger = this.el.querySelector('.quick-preset-trigger')
    this.dropdown = this.el.querySelector('.quick-preset-dropdown')

    // Sync trigger when preset changes elsewhere (e.g. modal ColorPicker)
    window.addEventListener('iconColorChanged', () => this.syncTrigger())
    this.swatch = this.el.querySelector('.quick-preset-swatch')
    this.label = this.el.querySelector('.quick-preset-label')

    // Hide server-rendered presets (kept as data source), build sorted merged list
    this.dropdown.querySelectorAll('.quick-preset').forEach(el => el.classList.add('quick-preset-builtin', 'hidden'))
    this.rebuildDropdown()

    // Restore active preset from localStorage
    this.syncTrigger()

    // Toggle dropdown
    this.trigger.addEventListener('click', (e) => {
      e.stopPropagation()
      this.rebuildDropdown() // refresh in case user added presets in the modal
      this.dropdown.classList.contains('hidden') ? this.openDropdown() : this.closeDropdown()
    })

    // Close on outside click
    this._onOutsideClick = (e) => {
      if (!this.el.contains(e.target)) this.closeDropdown()
    }
    document.addEventListener('click', this._onOutsideClick)

    // Preset selection (delegated — covers sorted items from PresetManager)
    this.dropdown.addEventListener('click', (e) => {
      const btn = e.target.closest('.preset-sorted') || e.target.closest('.quick-preset')
      if (!btn) return
      localStorage.setItem('icon_preview_color', btn.dataset.color)
      localStorage.setItem('icon_preview_bg', JSON.stringify(btn.dataset.bg))
      localStorage.setItem('icon_preview_preset', btn.dataset.preset)
      // Picking a theme means "apply these colours" — turn colours on so the
      // preview + downloads actually reflect the chosen background/colour.
      localStorage.setItem('designer_include_colors', 'true')
      document.querySelectorAll('.designer-include-colors').forEach(cb => { cb.checked = true })
      window.dispatchEvent(new CustomEvent('iconColorChanged'))
      this.syncTrigger()
      this.closeDropdown()
    })
  },
  updated() {
    this.trigger = this.el.querySelector('.quick-preset-trigger')
    this.dropdown = this.el.querySelector('.quick-preset-dropdown')
    this.swatch = this.el.querySelector('.quick-preset-swatch')
    this.label = this.el.querySelector('.quick-preset-label')
    this.rebuildDropdown()
    this.syncTrigger()
  },
  destroyed() {
    if (this._onOutsideClick) document.removeEventListener('click', this._onOutsideClick)
    if (this._cleanupAutoUpdate) this._cleanupAutoUpdate()
  },
  positionDropdown() {
    if (!window.FloatingUIDOM) return
    const { computePosition, offset, flip, shift } = window.FloatingUIDOM
    computePosition(this.trigger, this.dropdown, {
      strategy: 'fixed',
      placement: 'bottom-end',
      middleware: [offset(4), flip({ padding: 8 }), shift({ padding: 8 })]
    }).then(({ x, y }) => {
      this.dropdown.style.left = `${x}px`
      this.dropdown.style.top = `${y}px`
    })
  },
  openDropdown() {
    this.dropdown.classList.remove('hidden')
    this.positionDropdown()
    if (window.FloatingUIDOM && window.FloatingUIDOM.autoUpdate) {
      this._cleanupAutoUpdate = window.FloatingUIDOM.autoUpdate(this.trigger, this.dropdown, () => this.positionDropdown())
    }
  },
  closeDropdown() {
    this.dropdown.classList.add('hidden')
    if (this._cleanupAutoUpdate) { this._cleanupAutoUpdate(); this._cleanupAutoUpdate = null }
  },
  rebuildDropdown() {
    PresetManager.renderDropdown(this.dropdown)
  },
  syncTrigger() {
    PresetManager.syncTrigger(this.swatch, this.label)
  }
}

// IconSizeSlider hook — adjusts icon preview size in list/grid
Hooks.IconSizeSlider = {
  mounted() {
    console.time('[hook] IconSizeSlider.mounted')
    this.range = this.el.querySelector('.icon-size-range')
    this.label = this.el.querySelector('.icon-size-label')
    const saved = parseInt(localStorage.getItem('icon_list_size') || '32', 10)
    this.range.value = saved
    this.apply(saved)
    console.timeEnd('[hook] IconSizeSlider.mounted')
    this.range.addEventListener('input', () => {
      const size = parseInt(this.range.value, 10)
      localStorage.setItem('icon_list_size', size)
      this.apply(size)
    })
  },
  updated() {
    const saved = parseInt(localStorage.getItem('icon_list_size') || '32', 10)
    this.apply(saved)
  },
  apply(size) {
    if (this.label) this.label.textContent = size + 'px'
    // Update list view (desktop table)
    document.querySelectorAll('.icon-list-preview').forEach(el => {
      el.style.width = size + 'px'
      el.style.height = size + 'px'
    })
    // Update list view (mobile cards)
    document.querySelectorAll('.icon-card-preview').forEach(el => {
      el.style.width = (size * 1.5) + 'px'
      el.style.height = (size * 1.5) + 'px'
    })
  }
}

// DownloadDesigner hook — renders a live preview and exports PNGs/SVGs with
// colors, padding, and rounded corners applied.
Hooks.DownloadDesigner = {
  // Push localStorage settings into this instance's controls. Called on mount,
  // on LiveView re-render (updated), on drawer open, and when any other designer
  // instance changes a setting — so the basket + modal designers stay in sync
  // and never lose the user's choices to a re-render.
  syncControls() {
    if (this.colorsCheckbox) this.colorsCheckbox.checked = localStorage.getItem('designer_include_colors') !== 'false'
    if (this.paddingSlider) {
      this.paddingSlider.value = localStorage.getItem('designer_padding') || '10'
      if (this.paddingLabel) this.paddingLabel.textContent = this.paddingSlider.value + '%'
    }
    if (this.radiusSlider) {
      this.radiusSlider.value = localStorage.getItem('designer_radius') || '20'
      if (this.radiusLabel) this.radiusLabel.textContent = this.radiusSlider.value + '%'
    }
    const savedSizes = localStorage.getItem('designer_sizes')
    if (savedSizes) {
      try {
        const checked = new Set(JSON.parse(savedSizes))
        this.el.querySelectorAll('.designer-size').forEach(cb => { cb.checked = checked.has(parseInt(cb.value)) })
      } catch {}
    }
    const customInput = this.el.querySelector('.designer-custom-size')
    const savedCustomSize = localStorage.getItem('designer_custom_size')
    if (customInput && savedCustomSize) customInput.value = savedCustomSize
  },
  mounted() {
    this.canvas = this.el.querySelector('.designer-preview')
    this.ctx = this.canvas?.getContext('2d')
    this.svgUrl = this.el.dataset.svgUrl
    this.baseName = (this.el.dataset.name || 'icon').toLowerCase().replace(/\s+/g, '-')
    this.colorsCheckbox = this.el.querySelector('.designer-include-colors')
    this.paddingSlider = this.el.querySelector('.designer-padding')
    this.paddingLabel = this.el.querySelector('.designer-padding-label')
    this.radiusSlider = this.el.querySelector('.designer-radius')
    this.radiusLabel = this.el.querySelector('.designer-radius-label')

    // Restore saved settings then load the SVG and paint the preview.
    this.syncControls()
    this.loadSvg().then(() => this.renderPreview())

    // Bind controls — persist, repaint, and broadcast so sibling designer
    // instances (basket ↔ modal) re-sync their controls to match.
    const save = () => {
      localStorage.setItem('designer_include_colors', this.colorsCheckbox.checked)
      localStorage.setItem('designer_padding', this.paddingSlider.value)
      localStorage.setItem('designer_radius', this.radiusSlider.value)
      this.saveSizes()
      this.renderPreview()
      window.dispatchEvent(new CustomEvent('designerSettingsChanged', { detail: { from: this.el.id } }))
    }
    this.colorsCheckbox.addEventListener('change', save)
    this.paddingSlider.addEventListener('input', () => { this.paddingLabel.textContent = this.paddingSlider.value + '%'; save() })
    this.radiusSlider.addEventListener('input', () => { this.radiusLabel.textContent = this.radiusSlider.value + '%'; save() })

    // Save sizes on checkbox/input change
    this.el.querySelectorAll('.designer-size').forEach(cb => cb.addEventListener('change', save))
    this.el.querySelector('.designer-custom-size')?.addEventListener('input', save)

    // Listen for color changes from preset combos
    this._onColorChange = () => { this.syncControls(); this.renderPreview() }
    window.addEventListener('iconColorChanged', this._onColorChange)

    // Re-sync when another designer instance changes a setting (skip our own).
    this._onSettingsChanged = (e) => {
      if (e.detail?.from === this.el.id) return
      this.syncControls()
      this.renderPreview()
    }
    window.addEventListener('designerSettingsChanged', this._onSettingsChanged)

    // The basket designer mounts off-screen (drawer closed) at page load, so its
    // canvas can be blank and its controls stale. Re-sync + reload on open.
    this._onBasketOpen = () => {
      this.syncControls()
      this.loadSvg().then(() => this.renderPreview())
    }
    window.addEventListener('phx:basket_drawer_opened', this._onBasketOpen)

    // Download buttons
    this.el.querySelector('.designer-download-png')?.addEventListener('click', () => this.downloadPngZip())
    this.el.querySelector('.designer-download-svg')?.addEventListener('click', () => this.downloadSvg())

    // Import settings from manifest.json
    const importInput = this.el.querySelector('.designer-import-file')
    if (importInput) {
      importInput.addEventListener('change', (e) => {
        const file = e.target.files[0]
        if (!file) return
        const reader = new FileReader()
        reader.onload = () => {
          try {
            const manifest = JSON.parse(reader.result)
            this.importSettings(manifest)
          } catch (err) {
            console.error('[DownloadDesigner] Invalid manifest:', err)
          }
        }
        reader.readAsText(file)
        importInput.value = '' // reset so same file can be re-imported
      })
    }
  },
  destroyed() {
    if (this._onColorChange) window.removeEventListener('iconColorChanged', this._onColorChange)
    if (this._onBasketOpen) window.removeEventListener('phx:basket_drawer_opened', this._onBasketOpen)
    if (this._onSettingsChanged) window.removeEventListener('designerSettingsChanged', this._onSettingsChanged)
  },
  updated() {
    // A LiveView re-render can reset client-set form state — re-apply from
    // localStorage. Reload the SVG when the previewed icon changed (e.g. the
    // first basket item was removed); otherwise just repaint.
    this.syncControls()
    const url = this.el.dataset.svgUrl
    if (url && url !== this.svgUrl) {
      this.svgUrl = url
      this.baseName = (this.el.dataset.name || 'icon').toLowerCase().replace(/\s+/g, '-')
      this.loadSvg().then(() => this.renderPreview())
    } else {
      this.renderPreview()
    }
  },
  async loadSvg() {
    try {
      const resp = await fetch(this.svgUrl)
      this.rawSvg = await resp.text()
    } catch (err) {
      console.error('[DownloadDesigner] Failed to load SVG:', this.svgUrl, err)
    }
  },
  getSettings() {
    return DesignerExport.getSettings()
  },
  renderPreview() {
    if (!this.ctx || !this.rawSvg) return
    // Bump a generation counter so any in-flight img.onload from a previous
    // call sees it's stale and bails. Prevents races where rapid preset
    // clicks interleave async SVG loads and the older render paints on
    // top of the newer one.
    this._renderGen = (this._renderGen || 0) + 1
    const gen = this._renderGen

    const size = 128
    const { color, bg, padding, radius } = this.getSettings()
    const canvas = this.canvas
    canvas.width = size * 2 // 2x for retina
    canvas.height = size * 2
    const ctx = this.ctx
    ctx.clearRect(0, 0, canvas.width, canvas.height)
    const s = size * 2
    const r = radius * s / 2

    // Rounded rect clip
    ctx.beginPath()
    ctx.roundRect(0, 0, s, s, r)
    ctx.clip()

    // Background
    if (bg) {
      ctx.fillStyle = bg
      ctx.fillRect(0, 0, s, s)
    } else {
      // Checker pattern for transparency
      const sq = 8
      for (let y = 0; y < s; y += sq) {
        for (let x = 0; x < s; x += sq) {
          ctx.fillStyle = ((x + y) / sq) % 2 === 0 ? '#e5e7eb' : '#ffffff'
          ctx.fillRect(x, y, sq, sq)
        }
      }
    }

    // Draw SVG with padding
    const svgText = color ? DesignerExport.colorizeSvg(this.rawSvg, color) : this.rawSvg
    const aspect = DesignerExport.svgAspect(svgText)
    const blob = new Blob([svgText], { type: 'image/svg+xml' })
    const url = URL.createObjectURL(blob)
    const img = new Image()
    img.onload = () => {
      URL.revokeObjectURL(url)
      if (gen !== this._renderGen) return
      const pad = padding * s
      const { dx, dy, dw, dh } = DesignerExport.fitContain(aspect, pad, pad, s - pad * 2, s - pad * 2)
      ctx.drawImage(img, dx, dy, dw, dh)
    }
    img.src = url
  },
  renderToCanvas(size) {
    return DesignerExport.renderToCanvas(this.rawSvg, size)
  },
  saveSizes() {
    const checked = []
    this.el.querySelectorAll('.designer-size:checked').forEach(cb => checked.push(parseInt(cb.value)))
    localStorage.setItem('designer_sizes', JSON.stringify(checked))
    const custom = this.el.querySelector('.designer-custom-size')?.value || ''
    localStorage.setItem('designer_custom_size', custom)
  },
  getSelectedSizes() {
    const sizes = []
    this.el.querySelectorAll('.designer-size:checked').forEach(cb => sizes.push(parseInt(cb.value)))
    const custom = parseInt(this.el.querySelector('.designer-custom-size')?.value)
    if (custom > 0 && custom <= 4096) sizes.push(custom)
    return [...new Set(sizes)].sort((a, b) => a - b)
  },
  async downloadPngZip() {
    const sizes = this.getSelectedSizes()
    if (sizes.length === 0) return

    const btn = this.el.querySelector('.designer-download-png')
    const orig = btn.innerHTML
    btn.innerHTML = 'Generating...'
    btn.disabled = true

    try {
      await DesignerExport.downloadPngZip(this.svgUrl, this.baseName, sizes)
      // Track in metrics
      const metricsEl = document.getElementById('metrics-tracker')
      if (metricsEl?._pushEvent) {
        metricsEl._pushEvent('track_download', {
          'icon-id': this.el.id?.replace('download-designer-', '') || '',
          size: sizes.join(','),
          naming: 'designer:png-zip'
        })
      }
    } catch (err) {
      console.error('[DownloadDesigner] PNG ZIP failed:', err)
    } finally {
      btn.innerHTML = orig
      btn.disabled = false
    }
  },
  async downloadSvg() {
    if (!this.rawSvg) return
    const designed = DesignerExport.designSvg(this.rawSvg, this.getSettings())
    const blob = new Blob([designed], { type: 'image/svg+xml' })
    const a = document.createElement('a')
    a.href = URL.createObjectURL(blob)
    a.download = `${this.baseName}-designed.svg`
    document.body.appendChild(a)
    a.click()
    document.body.removeChild(a)
    URL.revokeObjectURL(a.href)

    // Track in metrics
    const metricsEl = document.getElementById('metrics-tracker')
    if (metricsEl?._pushEvent) {
      metricsEl._pushEvent('track_download', {
        'icon-id': this.el.id?.replace('download-designer-', '') || '',
        size: '0',
        naming: 'designer:svg'
      })
    }
  },
  importSettings(manifest) {
    const s = manifest.settings
    if (!s) return

    // Apply designer controls
    if (this.colorsCheckbox) this.colorsCheckbox.checked = !!s.include_colors
    if (this.paddingSlider) { this.paddingSlider.value = s.padding_percent ?? 10; this.paddingLabel.textContent = this.paddingSlider.value + '%' }
    if (this.radiusSlider) { this.radiusSlider.value = s.corner_radius_percent ?? 20; this.radiusLabel.textContent = this.radiusSlider.value + '%' }

    // Apply colors
    if (s.include_colors) {
      if (s.icon_color && s.icon_color !== 'original') localStorage.setItem('icon_preview_color', s.icon_color)
      if (s.background && s.background !== 'transparent') {
        localStorage.setItem('icon_preview_bg', JSON.stringify(s.background))
      } else {
        localStorage.setItem('icon_preview_bg', JSON.stringify('checker'))
      }

      // If a preset name was saved, try to find or create it
      if (s.preset_name && s.preset_name !== 'Custom') {
        const all = PresetManager.getAll()
        const existingKey = Object.entries(all).find(([, p]) => p.label === s.preset_name)?.[0]
        if (existingKey) {
          localStorage.setItem('icon_preview_preset', existingKey)
        } else {
          // Create the preset so user has it for future use
          const key = `custom-${Date.now()}`
          const customs = PresetManager.getCustoms()
          customs[key] = {
            color: s.icon_color || '#212121',
            bg: s.background === 'transparent' ? 'checker' : (s.background || '#ffffff'),
            label: s.preset_name
          }
          PresetManager.saveCustoms(customs)
          localStorage.setItem('icon_preview_preset', key)
        }
      }
      window.dispatchEvent(new CustomEvent('iconColorChanged'))
    }

    // Save to localStorage
    localStorage.setItem('designer_include_colors', s.include_colors)
    localStorage.setItem('designer_padding', s.padding_percent ?? 10)
    localStorage.setItem('designer_radius', s.corner_radius_percent ?? 20)

    // Apply sizes
    if (manifest.files) {
      const importedSizes = new Set(manifest.files.map(f => f.size))
      this.el.querySelectorAll('.designer-size').forEach(cb => {
        cb.checked = importedSizes.has(parseInt(cb.value))
      })
      // Check for custom sizes not in our preset list
      const standardSizes = new Set([32, 64, 128, 256, 512, 1024])
      const customSize = [...importedSizes].find(s => !standardSizes.has(s))
      const customInput = this.el.querySelector('.designer-custom-size')
      if (customInput && customSize) customInput.value = customSize
    }

    this.renderPreview()

    // Show confirmation
    const btn = this.el.querySelector('.designer-download-png')
    if (btn) {
      const label = btn.closest('.flex')?.querySelector('.designer-import-status')
      if (!label) {
        const status = document.createElement('span')
        status.className = 'designer-import-status text-xs text-success'
        status.textContent = `Settings imported${s.preset_name && s.preset_name !== 'Custom' ? ` (preset: ${s.preset_name})` : ''}`
        btn.closest('.flex')?.appendChild(status)
        setTimeout(() => status.remove(), 4000)
      }
    }
  }
}

// DownloadNaming hook — lets users pick a filename convention for SVG downloads
// and optionally bake in preset colors before downloading.
Hooks.DownloadNaming = {
  mounted() {
    this.select = this.el.querySelector('.download-naming-select')
    this.name = this.el.dataset.name
    this.style = this.el.dataset.style
    if (!this.select) return
    const saved = localStorage.getItem('download_naming') || 'original'
    this.select.value = saved
    this.applyNaming(saved)
    this.select.addEventListener('change', () => {
      localStorage.setItem('download_naming', this.select.value)
      this.applyNaming(this.select.value)
    })
    // Intercept download clicks when designer "Include colors" is active
    this.el.addEventListener('click', (e) => {
      const link = e.target.closest('.download-link')
      if (!link) return
      const designerColors = document.querySelector('.designer-include-colors')
      if (!designerColors?.checked) return
      e.preventDefault()
      this.downloadWithColors(link)
    })
  },
  updated() {
    this.select = this.el.querySelector('.download-naming-select')
    this.name = this.el.dataset.name
    this.style = this.el.dataset.style
    if (this.select) this.applyNaming(this.select.value || 'original')
  },
  async downloadWithColors(link) {
    const url = link.getAttribute('href')
    const filename = link.getAttribute('download') || 'icon.svg'
    const color = localStorage.getItem('icon_preview_color') || '#212121'
    let bg = '#ffffff'
    try { bg = JSON.parse(localStorage.getItem('icon_preview_bg') || '"#ffffff"') } catch { bg = localStorage.getItem('icon_preview_bg') || '#ffffff' }

    try {
      const resp = await fetch(url)
      const svgText = await resp.text()
      const parser = new DOMParser()
      const doc = parser.parseFromString(svgText, 'image/svg+xml')
      const svg = doc.querySelector('svg')
      if (!svg) return

      // Apply icon color — same logic as IconColorFilter.colorizeSvg
      const colorize = (el) => {
        const fill = el.getAttribute('fill')
        if (fill && fill !== 'none') el.setAttribute('fill', color)
        const stroke = el.getAttribute('stroke')
        if (stroke && stroke !== 'none') el.setAttribute('stroke', color)
      }
      colorize(svg)
      svg.querySelectorAll('path, circle, rect, line, polyline, polygon, ellipse, g').forEach(colorize)

      // Apply background — insert a rect as first child of svg
      if (bg && bg !== 'checker') {
        const rect = doc.createElementNS('http://www.w3.org/2000/svg', 'rect')
        rect.setAttribute('width', '100%')
        rect.setAttribute('height', '100%')
        rect.setAttribute('fill', bg)
        svg.insertBefore(rect, svg.firstChild)
      }

      // Serialize and download
      const serializer = new XMLSerializer()
      const blob = new Blob([serializer.serializeToString(doc)], { type: 'image/svg+xml' })
      const blobUrl = URL.createObjectURL(blob)
      const a = document.createElement('a')
      a.href = blobUrl
      a.download = filename
      document.body.appendChild(a)
      a.click()
      document.body.removeChild(a)
      URL.revokeObjectURL(blobUrl)
    } catch (err) {
      console.error('[DownloadNaming] Failed to download with colors:', err)
      // Fallback: regular download
      window.location.href = url
    }
  },
  applyNaming(convention) {
    const toSnake = s => s.toLowerCase().replace(/\s+/g, '_')
    const toPascal = s => s.split(/\s+/).map(w => w.charAt(0).toUpperCase() + w.slice(1).toLowerCase()).join('')
    const toKebab = s => s.toLowerCase().replace(/\s+/g, '-')

    this.el.querySelectorAll('.download-link').forEach(link => {
      // Set naming convention so phx-click="track_download" includes it
      link.setAttribute('phx-value-naming', convention)

      const original = link.dataset.originalFilename || ''
      if (!original) return
      const extMatch = original.match(/\.[a-z0-9]+$/i)
      const ext = extMatch ? extMatch[0] : ''
      const size = link.dataset.size

      let baseName
      switch (convention) {
        case 'kebab': baseName = toKebab(this.name); break
        case 'snake': baseName = toSnake(this.name); break
        case 'pascal': baseName = toPascal(this.name); break
        default: link.setAttribute('download', original); return
      }
      // Append size suffix only when the original filename had it (e.g. heroicons "name-24.svg")
      // and we're not in scalable mode
      const hasSizeInOriginal = size && size !== '0' && original.includes(`-${size}`)
      const sizeSuffix = hasSizeInOriginal ? `-${size}` : ''
      link.setAttribute('download', `${baseName}${sizeSuffix}${ext}`)
    })
  }
}

// FilenameTemplate hook — custom filename templating
Hooks.FilenameTemplate = {
  mounted() {
    const input = this.el.querySelector("input[type='text']")
    if (!input) return
    const savedTemplate = localStorage.getItem("filename_template") || "{filename}"
    input.value = savedTemplate
    this.renderFilenames()
    input.addEventListener("input", () => {
      localStorage.setItem("filename_template", input.value)
      this.renderFilenames()
    })
  },
  renderFilenames() {
    const input = this.el.querySelector("input[type='text']")
    if (!input) return
    const template = input.value || "{filename}"
    const name = this.el.dataset.name, style = this.el.dataset.style
    const sizes = JSON.parse(this.el.dataset.sizes || '[]')
    const filenamesMap = JSON.parse(this.el.dataset.filenames || '{}')
    const resultsContainer = this.el.querySelector("[id^='filename-results']")
    if (!resultsContainer) return
    const toSnake = s => s.toLowerCase().replace(/\s+/g, '_')
    const toPascal = s => s.split(/\s+/).map(w => w.charAt(0).toUpperCase() + w.slice(1).toLowerCase()).join('')
    const toKebab = s => s.toLowerCase().replace(/\s+/g, '-')
    // Icon id lives in the hook element's id (e.g. "filename-section-123")
    const iconId = (this.el.id.match(/(\d+)$/) || [])[1]
    resultsContainer.innerHTML = sizes.map(size => {
      // Look up the real filename from the server-provided map (handles all icon sets correctly)
      // Falls back to the first available filename for scalable icons
      const origFilename = filenamesMap[String(size)] || Object.values(filenamesMap)[0] || ''
      // Extract extension from original filename so we can append it when user uses placeholders
      // that don't include it (e.g. {name_kebab})
      const extMatch = origFilename.match(/\.[a-z0-9]+$/i)
      const ext = extMatch ? extMatch[0] : ''
      const usesFilenamePlaceholder = template.includes('{filename}')
      let filename = template.replace(/{filename}/g, origFilename).replace(/{name}/g, name)
        .replace(/{name_snake}/g, toSnake(name)).replace(/{name_pascal}/g, toPascal(name))
        .replace(/{name_kebab}/g, toKebab(name)).replace(/{size}/g, size).replace(/{style}/g, style)
      // Append the extension if the template doesn't already end with one and didn't use {filename}
      if (!usesFilenamePlaceholder && ext && !filename.toLowerCase().endsWith(ext.toLowerCase())) {
        filename += ext
      }
      const escaped = filename.replace(/"/g, '&quot;')
      return `<div class="flex items-center justify-between bg-base-200 rounded px-3 py-2 border border-base-300">
        <code class="text-sm text-base-content">${filename}</code>
        <button type="button" class="copy-filename text-xs text-base-content/60 hover:text-base-content px-2 py-1 rounded hover:bg-base-300" data-text="${escaped}" data-size="${size}">Copy</button>
      </div>`
    }).join("")
    this.el.querySelectorAll(".copy-filename").forEach(btn => {
      btn.onclick = () => navigator.clipboard.writeText(btn.dataset.text).then(() => {
        const orig = btn.textContent; btn.textContent = "Copied!"; setTimeout(() => btn.textContent = orig, 1500)
        // Track in metrics — filename platform, per-size.
        const metricsEl = document.getElementById('metrics-tracker')
        if (metricsEl?._pushEvent && iconId) {
          metricsEl._pushEvent('track_copy', {
            'icon-id': iconId,
            platform: 'filename',
            size: btn.dataset.size || ''
          })
        }
      })
    })
  }
}

// Copy text handler
window.addEventListener("phx:copy_text", (event) => {
  let { text, platform, filename, name, style, size, icon_id } = event.detail
  // For filename platform, apply the saved template
  if (platform === 'filename' && filename) {
    const template = localStorage.getItem('filename_template') || '{filename}'
    const toSnake = s => s.toLowerCase().replace(/\s+/g, '_')
    const toPascal = s => s.split(/\s+/).map(w => w.charAt(0).toUpperCase() + w.slice(1).toLowerCase()).join('')
    const toKebab = s => s.toLowerCase().replace(/\s+/g, '-')
    text = template
      .replace(/{filename}/g, filename)
      .replace(/{name}/g, name)
      .replace(/{name_snake}/g, toSnake(name))
      .replace(/{name_pascal}/g, toPascal(name))
      .replace(/{name_kebab}/g, toKebab(name))
      .replace(/{size}/g, size)
      .replace(/{style}/g, style)
  }
  if (text) {
    navigator.clipboard.writeText(text).then(() => {
      const button = event.target
      if (button) {
        // Flash green
        const origBg = button.style.backgroundColor
        button.style.backgroundColor = 'oklch(65% 0.17 155 / 0.3)'
        const svg = button.querySelector('svg, span')
        if (svg) { svg.style.color = '#22c55e'; setTimeout(() => svg.style.color = '', 1200) }
        setTimeout(() => button.style.backgroundColor = origBg, 1200)
        // Show brief "Copied!" tooltip
        const tip = document.createElement('div')
        tip.textContent = 'Copied!'
        tip.className = 'fixed z-[100] px-2 py-1 text-xs font-medium rounded bg-success text-success-content shadow-lg pointer-events-none'
        const rect = button.getBoundingClientRect()
        tip.style.left = `${rect.left + rect.width / 2}px`
        tip.style.top = `${rect.top - 30}px`
        tip.style.transform = 'translateX(-50%)'
        document.body.appendChild(tip)
        setTimeout(() => tip.remove(), 1200)
      }
      // Track copy on server
      if (icon_id && platform) {
        const metricsEl = document.getElementById('metrics-tracker')
        if (metricsEl && metricsEl._pushEvent) {
          metricsEl._pushEvent("track_copy", { "icon-id": String(icon_id), platform, size: String(size || '') })
        }
      }
    }).catch(err => console.error('Failed to copy:', err))
  }
})

// Copy handler (modal Copy buttons)
window.addEventListener("phx:copy", (event) => {
  const button = event.detail.dispatcher
  if (button) {
    const container = button.closest('.flex')
    const codeEl = container ? container.querySelector('code') : null
    const hiddenSpan = container ? container.querySelector('span.hidden') : null
    const target = hiddenSpan || codeEl
    if (target) {
      navigator.clipboard.writeText(target.textContent).then(() => {
        const orig = button.textContent
        button.textContent = "Copied!"
        setTimeout(() => button.textContent = orig, 1500)
        // Track copy on server
        const metricsEl = document.getElementById('metrics-tracker')
        if (metricsEl && metricsEl._pushEvent && target.id) {
          // target.id is like "ios-1234-24" or "react-1234-16"
          const parts = target.id.split('-')
          if (parts.length >= 3) {
            const platform = parts[0]
            const iconId = parts[1]
            const size = parts[parts.length - 1]
            metricsEl._pushEvent("track_copy", { "icon-id": iconId, platform, size })
          }
        }
      }).catch(err => console.error('Failed to copy:', err))
    }
  }
})

// Copy from button (list view)
window.copyFromButton = function(button) {
  const text = button.dataset.copyText
  if (text) {
    navigator.clipboard.writeText(text).then(() => {
      const svg = button.querySelector('svg')
      if (svg) { svg.style.color = '#22c55e'; setTimeout(() => svg.style.color = '', 1000) }
    }).catch(err => console.error('Failed to copy:', err))
  }
}

console.time('[prefs] LiveSocket init')
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 1500,
  params: {
    _csrf_token: csrfToken,
    view_mode: localStorage.getItem("icon_view_mode") || "grid",
    icon_list_size: parseInt(localStorage.getItem("icon_list_size") || "32", 10),
    platform_prefs: JSON.parse(localStorage.getItem("icon_platform_prefs") || "{}"),
    filter_styles: JSON.parse(localStorage.getItem("icon_filter_styles") || "[]"),
    filter_sizes: JSON.parse(localStorage.getItem("icon_filter_sizes") || "[]"),
    filter_icon_sets: JSON.parse(localStorage.getItem("icon_filter_icon_sets") || "[]"),
    basket: JSON.parse(localStorage.getItem("icon_basket") || "[]")
  },
  hooks: Hooks
})
console.timeEnd('[prefs] LiveSocket init')
console.log('[prefs] connect_params:', {
  view_mode: localStorage.getItem("icon_view_mode"),
  icon_list_size: localStorage.getItem("icon_list_size"),
  filter_icon_sets: localStorage.getItem("icon_filter_icon_sets")
})

topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => { console.time('[phx] page-load'); topbar.show(300) })
window.addEventListener("phx:page-loading-stop", _info => {
  console.timeEnd('[phx] page-load')
  topbar.hide()
  // Hide loader after first LiveView connect
  const loader = document.getElementById('app-loader')
  if (loader) {
    loader.style.opacity = '0'
    setTimeout(() => loader.remove(), 300)
  }
})

liveSocket.connect()
window.liveSocket = liveSocket


// Time-of-day theme manager
import { startAutoUpdate, initThemeEvents, initThemeSwitcherDropdown } from "./theme-manager"
startAutoUpdate()
initThemeEvents()
initThemeSwitcherDropdown()

// Language switcher dropdown
import { initLanguageSwitcherDropdown } from "./language-switcher"
initLanguageSwitcherDropdown()
// Theme transitions disabled — instant switch
// setTimeout(() => document.documentElement.classList.add("theme-transitions"), 100)
