import 'package:mcp_bundle/mcp_bundle.dart';

import '../../style/style_sheet.dart';
import '../../style/truetype_font.dart';

/// How a paginated renderer (PDF) lays content out.
enum PageFlow {
  /// Fixed-size pages; content splits across pages and bordered boxes split
  /// with the page break. Use for printable, page-form templates (A4, Letter).
  paged,

  /// One continuous page that grows to fit all content — like a web/app page.
  /// No page breaks and bordered boxes never split.
  continuous,
}

/// Options for rendering a document.
class RenderOptions {
  const RenderOptions({
    this.includeMetadata = false,
    this.applyWatermark = false,
    this.watermarkText,
    this.watermarkColor = '#D9D9D9',
    this.watermarkOpacity = 1.0,
    this.watermarkFontSize = 48,
    this.watermarkAngle = 45,
    this.pageFlow = PageFlow.paged,
    this.columnCount = 1,
    this.columnGap = 18,
    this.headerText,
    this.footerText,
    this.showPageNumbers = false,
    this.pageNumberTemplate = '{page} / {total}',
    this.compress = true,
    this.fillableFields = false,
    this.pdfA = false,
    this.taggedPdf = false,
    this.pageBorder = false,
    this.pageBorderColor = '#000000',
    this.pageBorderWidth = 1.0,
    this.pageBorderRadius = 0.0,
  });

  /// Parse render options from an opaque JSON object (the `options` argument of
  /// the `form.render` / `form.export` tools). Every key is optional and falls
  /// back to its default, so all 0.2.0 rendering features — multi-column,
  /// continuous flow, headers/footers, page numbers, watermark styling, PDF/A,
  /// tagged PDF, fillable fields — are reachable through the tool surface.
  factory RenderOptions.fromJson(Map<String, dynamic> json) {
    const defaults = RenderOptions();
    double d(String k, double fallback) =>
        (json[k] as num?)?.toDouble() ?? fallback;
    return RenderOptions(
      includeMetadata: json['includeMetadata'] as bool? ?? defaults.includeMetadata,
      applyWatermark: json['applyWatermark'] as bool? ?? defaults.applyWatermark,
      watermarkText: json['watermarkText'] as String?,
      watermarkColor: json['watermarkColor'] as String? ?? defaults.watermarkColor,
      watermarkOpacity: d('watermarkOpacity', defaults.watermarkOpacity),
      watermarkFontSize: d('watermarkFontSize', defaults.watermarkFontSize),
      watermarkAngle: d('watermarkAngle', defaults.watermarkAngle),
      pageFlow: switch (json['pageFlow'] as String?) {
        'continuous' => PageFlow.continuous,
        'paged' => PageFlow.paged,
        _ => defaults.pageFlow,
      },
      columnCount: (json['columnCount'] as num?)?.toInt() ?? defaults.columnCount,
      columnGap: d('columnGap', defaults.columnGap),
      headerText: json['headerText'] as String?,
      footerText: json['footerText'] as String?,
      showPageNumbers: json['showPageNumbers'] as bool? ?? defaults.showPageNumbers,
      pageNumberTemplate:
          json['pageNumberTemplate'] as String? ?? defaults.pageNumberTemplate,
      compress: json['compress'] as bool? ?? defaults.compress,
      fillableFields: json['fillableFields'] as bool? ?? defaults.fillableFields,
      pdfA: json['pdfA'] as bool? ?? defaults.pdfA,
      taggedPdf: json['taggedPdf'] as bool? ?? defaults.taggedPdf,
      pageBorder: json['pageBorder'] as bool? ?? defaults.pageBorder,
      pageBorderColor:
          json['pageBorderColor'] as String? ?? defaults.pageBorderColor,
      pageBorderWidth: d('pageBorderWidth', defaults.pageBorderWidth),
      pageBorderRadius: d('pageBorderRadius', defaults.pageBorderRadius),
    );
  }

  final bool includeMetadata;

  /// Diagonal watermark behind the content (PDF / HTML).
  final bool applyWatermark;
  final String? watermarkText;

  /// Watermark colour (`'#RRGGBB'`), opacity (0..1), size (pt) and angle (deg).
  final String watermarkColor;
  final double watermarkOpacity;
  final double watermarkFontSize;
  final double watermarkAngle;

  /// Pagination mode (PDF). Defaults to [PageFlow.paged].
  final PageFlow pageFlow;

  /// Number of newspaper-style text columns per page (PDF, paged mode). Content
  /// flows down one column then into the next on the same page; only the last
  /// column triggers a page break. Defaults to 1 (single column). Clamped to
  /// 1..8 and ignored in continuous flow.
  final int columnCount;

  /// Gap between columns in points when [columnCount] > 1.
  final double columnGap;

  /// Optional running header / footer text drawn in the page margins (PDF).
  final String? headerText;
  final String? footerText;

  /// Draw a page number in the footer area. `{page}` / `{total}` are
  /// substituted in [pageNumberTemplate].
  final bool showPageNumbers;
  final String pageNumberTemplate;

  /// Compress PDF streams with `/FlateDecode` where the platform supports zlib
  /// (native). Web embeds uncompressed regardless.
  final bool compress;

  /// Emit interactive AcroForm text fields for `FormFieldBlock`s (PDF) instead
  /// of static "name: value" text, so the output is a fillable form.
  final bool fillableFields;

  /// Add PDF/A archival metadata (XMP packet + document `/ID` + `/MarkInfo`).
  /// Full PDF/A-2b conformance additionally requires all fonts embedded (a
  /// host-provided `embeddedFont` covering every glyph) and an ICC OutputIntent.
  final bool pdfA;

  /// Emit a tagged PDF (PDF/UA logical structure tree) so screen readers can
  /// navigate the content: headings, paragraphs, figures and tables become
  /// structure elements, page furniture becomes artifacts.
  final bool taggedPdf;

  /// Draw a frame around the page (an official-document / certificate border).
  /// Opt-in; [pageBorderColor] (`'#RRGGBB'`), [pageBorderWidth] (pt) and
  /// [pageBorderRadius] (pt, rounded corners — HTML only) style it. In paged
  /// output the frame is drawn on every page.
  final bool pageBorder;
  final String pageBorderColor;
  final double pageBorderWidth;
  final double pageBorderRadius;
}

/// Context passed to renderers during rendering.
class RenderContext {
  const RenderContext({
    required this.document,
    required this.layoutPolicy,
    required this.template,
    this.options = const RenderOptions(),
    this.styleSheet,
    this.embeddedFont,
    this.fallbackFonts = const [],
  });

  final FormDocument document;
  final FormLayoutPolicy layoutPolicy;
  final FormTemplate template;
  final RenderOptions options;

  /// Optional render-time theme + named styles (host/Studio-provided). The
  /// template itself stays a plain data model; styling resolves against this.
  final FormStyleSheet? styleSheet;

  /// Optional embedded TrueType font for multilingual PDF output. When present
  /// the PDF renderer embeds it as a Type0 font and encodes text as glyph ids,
  /// so any script the font covers (CJK, Hangul, Cyrillic, Arabic, …) renders.
  /// When absent, PDF falls back to the built-in Helvetica (Latin / WinAnsi).
  final TrueTypeFont? embeddedFont;

  /// Optional fallback fonts, tried in order when [embeddedFont] has no glyph
  /// for a code point (e.g. a Latin face primary + a CJK face fallback). The
  /// PDF renderer embeds each used font as its own Type0 program and routes
  /// every character to the first font that covers it. Ignored when
  /// [embeddedFont] is null.
  final List<TrueTypeFont> fallbackFonts;

  String? get effectiveWatermark =>
      options.applyWatermark ? options.watermarkText : null;
}
