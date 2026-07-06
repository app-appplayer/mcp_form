import 'block_style.dart';

/// A document theme — a named colour palette plus default fonts and base size.
/// Colour tokens referenced by styles/runs (e.g. `'primary'`) resolve to hex
/// here; unknown tokens (already `'#RRGGBB'`) pass through unchanged.
class FormTheme {
  const FormTheme({
    this.colors = const {},
    this.bodyFont,
    this.headingFont,
    this.baseFontSize,
    this.logo,
    this.logoWidth,
  });

  factory FormTheme.fromMap(Map<String, dynamic>? m) {
    if (m == null) return empty;
    final raw = m['colors'];
    return FormTheme(
      colors: raw is Map
          ? raw.map((k, v) => MapEntry(k.toString(), v.toString()))
          : const {},
      bodyFont: m['bodyFont'] as String?,
      headingFont: m['headingFont'] as String?,
      baseFontSize: (m['baseFontSize'] as num?)?.toDouble(),
      logo: m['logo'] as String?,
      logoWidth: (m['logoWidth'] as num?)?.toDouble(),
    );
  }

  final Map<String, String> colors;
  final String? bodyFont;
  final String? headingFont;
  final double? baseFontSize;

  /// Optional letterhead logo image source (file path or data URI), drawn at
  /// the top of the document by renderers that support images.
  final String? logo;

  /// Logo display width in points (renderers scale height by aspect ratio);
  /// defaults to 120 when a [logo] is set without a width.
  final double? logoWidth;

  static const FormTheme empty = FormTheme();

  /// Resolve a colour token to hex, or pass through a literal colour.
  String resolveColor(String value) => colors[value] ?? value;

  Map<String, dynamic> toMap() => {
        if (colors.isNotEmpty) 'colors': colors,
        if (bodyFont != null) 'bodyFont': bodyFont,
        if (headingFont != null) 'headingFont': headingFont,
        if (baseFontSize != null) 'baseFontSize': baseFontSize,
        if (logo != null) 'logo': logo,
        if (logoWidth != null) 'logoWidth': logoWidth,
      };
}

/// A render-time stylesheet: a [FormTheme] plus reusable named [BlockStyle]s a
/// block can inherit via `styleRef`. Provided by the host (e.g. the Studio
/// form-builder) on the [RenderContext]; the template stays a plain data model.
class FormStyleSheet {
  const FormStyleSheet({
    this.theme = FormTheme.empty,
    this.styles = const {},
  });

  factory FormStyleSheet.fromMap(Map<String, dynamic>? m) {
    if (m == null) return empty;
    final rawStyles = m['styles'];
    final styles = <String, BlockStyle>{};
    if (rawStyles is Map) {
      rawStyles.forEach((k, v) {
        if (v is Map) {
          styles[k.toString()] = BlockStyle.fromMap(v.cast<String, dynamic>());
        }
      });
    }
    return FormStyleSheet(
      theme: FormTheme.fromMap(m['theme'] as Map<String, dynamic>?),
      styles: styles,
    );
  }

  final FormTheme theme;
  final Map<String, BlockStyle> styles;

  static const FormStyleSheet empty = FormStyleSheet();

  /// Look up a named style.
  BlockStyle? named(String? ref) => ref == null ? null : styles[ref];

  Map<String, dynamic> toMap() => {
        'theme': theme.toMap(),
        if (styles.isNotEmpty)
          'styles': styles.map((k, v) => MapEntry(k, v.toMap())),
      };
}
