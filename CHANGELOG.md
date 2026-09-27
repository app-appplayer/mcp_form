## [0.2.1] - 2026-09-27

### Fixed — tool arguments are checked before they are read
- Every `form.*` call is checked against its tool's `inputSchema` before a
  handler reads an argument. A missing or mistyped argument used to reach a
  cast and come back as its text (`type 'Null' is not a subtype of type
  'String' in type cast`). It now answers `INVALID_PARAMS` with
  `data.path` and every problem in `data.issues` (`{path, message}`), e.g.
  `template.layoutPolicy.fontPolicy is required`.
- `form.save_template` checks the template against a FormTemplate schema
  written from the model's own parser — the nine block types, blocks nested
  in `repeatable` and `conditional`, an unknown block type checked as the
  text block it reads as. Its answer carries `formErrorCode:
  template.invalid_schema`. The tool's `inputSchema` now publishes that
  schema, so a host can check a template before calling.
- `template.invalid_schema` from a port maps to `INVALID_PARAMS`; it fell
  through to `INTERNAL_ERROR`.
- `form.create_document` declared `data` as required while its description,
  its test and its handler treat it as optional; the schema now matches, so
  a document can be created with no initial data.

### Added
- `validateArgument` (`lib/src/feat/mcp/argument_validator.dart`) and
  `formTemplateJsonSchema` (`lib/src/feat/mcp/form_template_json_schema.dart`).

## [0.2.0] - 2026-06-30 - Document rendering engine

A landmark, fully additive release: mcp_form grows from form port adapters into a
complete document rendering engine. Every change is backward-compatible — new
files, new optional `RenderOptions` flags, new block `style` keys, and new
`FormTheme` fields. No existing public API changed. Consumers should bump to
`^0.2.0`. The core (`mcp_bundle`) is untouched; all new capability rides on the
existing carriers (`FormBlock.style`, `FormTextBlock.content`/`format`, and a
render-time `FormStyleSheet` on `RenderContext`).

### Added — pure-Dart image renderer, backgrounds, page frame, page breaks
- **`ImageRenderer` (6th renderer, format `image`/`png`).** Rasterizes a document to PNG in pure Dart — no browser, no platform canvas. Text is drawn by rasterizing the injected TrueType font's own glyph outlines (`TrueTypeFont.glyphContours` → quadratic-bezier flatten → even-odd scanline fill), so multilingual output (CJK) renders correctly given `context.embeddedFont`. Covers headings, text, **fields** (`fieldName: value` from the document data), **tables** (header + data rows, cell borders, per-column `width` as proportional weights and `alignment` left/center/right — matching the PDF renderer), images, **`style.placement`** (image + text, absolute page anchors, `z:'back'`/`fit`/full-bleed backgrounds) and page background. Paged output is the **full page box** (A4/A3/card at its real aspect, not content-cropped); continuous grows to content. Enough for business cards, invoices, quotes at any page size (card / invitation / A4 / A3 / landscape); charts / math / columns are a follow-up. `form.render`/`export` gain `image` in the format enum; registered in `standardRendererRegistry`.
- **Background / cover images** via `style.placement`: `z: 'back'` draws behind the flow, `fit: 'cover'|'contain'` scales within the box, `width/height: 'full'` fills the page (full-bleed). PDF (behind-layer draw, page clips overflow) + HTML (`z-index:-1; object-fit; 100%`).
- **`RenderOptions.pageBorder`** (+ `pageBorderColor` / `pageBorderWidth` / `pageBorderRadius`) — an opt-in page frame (official-document / certificate outline), drawn on every page. HTML `border` on the page box, PDF stroked rectangle.
- **`style.pageBreak: 'before'` (PDF also `'after'`)** — explicit page breaks (paged mode) for report structure: a cover page, a TOC page, the body, a back page. PDF forces a new page; HTML emits a print page-break.

### Fixed — placement rendering fidelity (real-render re-verify, sbuilder)
- **HTML placement anchored to the page, not the content height.** The `position: relative` page box had no height, so a `bottom`-anchored seal on a short document sat just below the content instead of at the paper bottom. The body box now sets `box-sizing: border-box` + `min-height: <pageHeight>mm`, so bottom-anchored placement lands at the paper bottom (matching the PDF).
- **`style.placement` now applies to any block type, not just images.** A text block (e.g. a bottom-centre company name) with `style.placement` was rendered in flow instead of at its anchor. HTML now pulls any placed block out of flow and renders it through the normal path inside the absolute container; PDF places image **and** text blocks (text via a computed absolute baseline — the reported footer/company-name case). Added `top-center` / `bottom-center` anchors. (PDF placement of table/chart blocks remains a follow-up; HTML handles all types.)

### Fixed / Added — Form Builder dogfood round 2 (sbuilder)
- **Recipe font seam** — `formCapabilityTools` gains a `rendererRegistry` parameter so a host can inject `standardRendererRegistry(embeddedFont: …, fallbackFonts: […])`. Without it, non-Latin text (e.g. Korean) rendered as `?` in PDF because the default registry embeds no fonts. (Recipe change in `capability_tools`; the engine seam already existed.)
- **PDF image `maxWidth`** — `renderImage` ignored `block.maxWidth` and drew every image at full content width (an 80px stamp filled the page and pushed to a second page). Now capped to `maxWidth` (px → pt at 96→72 dpi), matching the HTML renderer.
- **`style.placement` — absolute page placement (PDF + HTML).** A block with `style.placement {anchor: top-left|top-right|bottom-left|bottom-right|center, x, y (mm), width? (mm), repeat?}` is pulled out of the flow and drawn at page coordinates measured from the paper corner (margins ignored), overlaid on the flow — for seals/stamps/logos. Default is the last page; `repeat: true` repeats on every page. PDF draws it as an artifact; HTML emits an absolute-positioned element in the (now `position: relative`) page box.
- **`uiDsl` Image node** now serializes `maxWidth` / `aspectRatio` / `style` (previously `src`/`alt` only), so a UI DSL runtime renders images at their intended size and alignment instead of stretching to full width.
- **`form.get_document {documentId}`** — returns the full typed document (`FormDocument.toJson`, patches applied) so a publication snapshot can be frozen / re-rendered without going through a render format. (Surface 14 verbs.)

### Fixed — tool-path rendering reachability (Form Builder audit, sbuilder)
- **`form.render` / `form.export` no longer dead.** The default assembly built an empty `RendererRegistry()`, so every format returned `render.unsupported_format`. New `standardRendererRegistry({styleSheet, embeddedFont, fallbackFonts})` registers the five bundled renderers (PDF/HTML/DOCX/Markdown/UI DSL); it is the intended default for the `form.*` capability.
- **`RenderOptions.fromJson`** — the `form.render` `options` object mapped only 3 keys (`includeMetadata`/`applyWatermark`/`watermarkText`), silently dropping the entire 0.2.0 surface (multi-column, continuous flow, header/footer, page numbers, watermark styling, compress, `fillableFields`, `pdfA`, `taggedPdf`). Now every key maps through, so those features are reachable from the tool path.
- **Font / stylesheet injection seam** — `RendererRegistry` gains optional `styleSheet` / `embeddedFont` / `fallbackFonts`, threaded into every `RenderContext`. Previously only tests could supply fonts, so multilingual PDF (TrueType embedding, glyph fallback) and global styling were unreachable through `form.*`. Font loading stays the host's job — the registry only carries the built objects.

### Added — LLM-fill entry points (C1/C2 verbs)
- `form.template_schema {templateId, version?, withCapacity?}` → Template→JSON Schema (draft 2020-12; folds capacity as `maxLength` by default) so an external LLM fills constrained to the template.
- `form.capacity {templateId, version?, fieldId?}` → per-field text capacity report (copy-fit feed-forward).

### Added — template management on the MCP tool surface
- `FormToolHandler` now exposes the full template lifecycle (7 → 11 tools):
  `form.save_template` (create/update, rejects duplicate templateId+version),
  `form.get_template` (by id + optional version), `form.delete_template`, and
  `form.get_template_versions` (version history) — alongside the existing
  `list_templates` / `render` / `validate` / `patch` / `export` /
  `create_document` / `get_status`. This completes the surface a host built-in
  (e.g. a Studio Form Builder app) needs to create/manage templates, publish
  documents, and show history through the `form.*` capability. Ports were
  already present on `FormTemplatePort`; only the tool verbs were missing.

### Added — rich styling & copy-fit (`lib/src/style/`)
- Style layer: rich inline runs (`FormRichText` + markdown/HTML inline parsers),
  per-block/per-run styling, named-style + theme resolution with a defined
  precedence (layout → theme → named → block → run), real Helvetica-metric text
  measurement, and copy-fit (`grow` / `shrinkToFit` / `clip` / `summarize` /
  `split`) driven by a box's fixed `height`.
- Boxes & borders that split cleanly across page breaks (résumé frames).
- Pagination: `paged` vs `continuous` flow; break quality (`keepTogether`,
  `orphans`, `widows`).
- Multi-column newspaper flow (`RenderOptions.columnCount` / `columnGap`) and
  per-block 12-column grid placement (`style.colSpan`).
- Native charts — format-independent geometry drawn as PDF vectors and HTML SVG
  (`chart.dart`).
- Tables as real grids (column widths, cell borders, header fill + repeat, cell
  wrapping, per-column alignment, row height policies).
- Lists (`style.listStyle` / `numberFormat`) with shared markers across renderers.

### Added — international text (PDF)
- TrueType embedding (Type0/CIDFontType2) with **font subsetting** (glyph
  renumbering + `CIDToGIDMap`; e.g. AppleGothic 14.5 MB → ~10 KB).
- Multi-font fallback (per-codepoint routing across a primary + fallback fonts).
- Complex-script shaping & BiDi (`bidi.dart` UAX #9, Arabic contextual joining,
  Hebrew RTL, N0 bracket pairing, L4 mirroring) and Devanagari pre-base matra
  reordering. No external dependencies.
- FlateDecode stream compression (`RenderOptions.compress`).

### Added — document structure
- Automatic heading numbering (`FormHeadingBlock.numbering` → `1.2.3`).
- Cross-references: inline `[ref:label]` resolves to a heading / caption number.
- Table of contents (`style.toc`) with HTML/Markdown anchor links and real,
  single-pass PDF page numbers.
- Auto-numbered figure / table captions (`style.caption` / `captionKind` /
  `captionPrefix`).
- Footnotes: inline `[fn:…]` → `[N]` marker collected as endnotes.
  (`document_numbering.dart` + `FootnoteCollector`.)
- Repeatable data binding — a `FormRepeatableBlock` expands its template over the
  array at `itemsBinding` (dotted path, `minItems` padding / `maxItems`
  truncation). (`repeatable_binding.dart`.)
- Conditional blocks — safe expression evaluation of `condition` → then/else
  (`condition_evaluator.dart`).

### Added — theme & branding
- `FormTheme` colour tokens, body/heading fonts, `baseFontSize` (now consumed as
  a render-time body-size override), and a letterhead `logo` / `logoWidth`.

### Added — math, codes, and edit tracking
- Math: display equations (`style.math`, a LaTeX-subset parser + a PDF
  box-layout engine + MathML for HTML + `$$` for Markdown) and inline `$…$`
  math (inline MathML in HTML, native `$…$` in Markdown, a Unicode
  approximation elsewhere).
- Code 128 barcodes (`src: barcode:DATA`) and QR codes (`src: qr:DATA`, a
  self-contained GF(256) + Reed–Solomon encoder), drawn as PDF rectangles / HTML
  SVG.
- Version redline (`style.change` = `inserted` / `deleted`), rendered with
  `<ins>`/`<del>`, `~~…~~`, DOCX run marks, or PDF run styling.

### Added — LLM-native authoring
- Template → JSON Schema export (draft 2020-12) to constrain LLM structured
  output to the template (`json_schema_export.dart`).
- Capacity feed-forward — fixed-box character estimates injected as `maxLength`
  so an LLM writes to fit (`capacity.dart`).

### Added — PDF forms & compliance (`RenderOptions`)
- `fillableFields` — interactive AcroForm text-field widgets per
  `FormFieldBlock` (`/FT /Tx`, bound value in `/V`, `/NeedAppearances`).
- `pdfA` — archival metadata (XMP `pdfaid`, deterministic `/ID`, `/MarkInfo`).
- `taggedPdf` — a tagged PDF (PDF/UA) logical structure tree
  (`Document → H1…H6 / P / L › LI / Table › TR › TH·TD / Figure` with `/Alt`),
  marked content (BDC/EMC + MCID), `/ParentTree`, page `/StructParents`,
  `/Artifact` page furniture, and an XMP `pdfuaid:part 1` declaration.

### Changed
- HTML headings now carry an `id` anchor (for TOC links) and, when auto-numbered,
  a `heading-number` span. Rendered output only — no API change.

### Dependencies
- Added `image ^4.0.0` (decode PNG / GIF / WebP for PDF image embedding; JPEG
  passes through).

### Notes
- Honest boundaries (documented in `doc/design/styling-and-copyfit.md`): OpenType
  GSUB/GPOS, inline-flow math, matrices, full PDF/A ICC + font-embedding, and a
  validated PDF/UA (veraPDF) pass remain out of scope; non-Latin math symbols and
  full compliance require a host-provided embedded font.

## [0.1.1] - 2026-05-23 - mcp_bundle 0.4.0 cascade

### Changed (cascade)
- `mcp_bundle` caret bumped from `^0.3.0` to `^0.4.0`. mcp_form does not touch `UiSection.pages` directly, so this release is a caret-only cascade. Consumers should bump to `^0.1.1`.

## [0.1.0] - 2026-04-28 - Initial Release

### Added
- Template subsystem — field types, layout extensions, schema validator, defaults, summary, version compatibility and validator.
- Document subsystem — factory, extensions, summary.
- Validator subsystem — form / layout / schema validators with autofix engine.
- Binding engine for runtime template-to-document data binding.
- Standard port adapters implementing `mcp_bundle` form Contract Layer (`FormPort`, `FormRendererPort`, `FormTemplatePort`).
