import 'package:meta/meta.dart';

/// Vertical alignment of an inline run relative to the baseline.
enum RunBaseline {
  /// Sits on the baseline (default).
  normal,

  /// Raised and rendered smaller (e.g. footnote marks, exponents).
  superscript,

  /// Lowered and rendered smaller (e.g. chemical formulae).
  subscript;

  /// Parse from a `style` map value (`'super'` / `'sub'` / `'normal'`).
  static RunBaseline? fromString(String? v) {
    switch (v) {
      case 'super':
      case 'superscript':
        return RunBaseline.superscript;
      case 'sub':
      case 'subscript':
        return RunBaseline.subscript;
      case 'normal':
        return RunBaseline.normal;
      default:
        return null;
    }
  }

  /// Map-friendly token.
  String get token => switch (this) {
        RunBaseline.superscript => 'super',
        RunBaseline.subscript => 'sub',
        RunBaseline.normal => 'normal',
      };
}

/// Inline ("run-level") text styling — the marks that apply to a span of
/// characters inside a block: weight, slant, decoration, colour, baseline, etc.
///
/// Every field is nullable; a null field means "inherit from the enclosing
/// block / named style / theme". Styles compose with [merge]: the argument
/// overrides any non-null field. This keeps the schema LLM-friendly — an author
/// names only the marks they want to change.
@immutable
class TextRunStyle {
  const TextRunStyle({
    this.fontFamily,
    this.fontSize,
    this.bold,
    this.italic,
    this.underline,
    this.strike,
    this.color,
    this.highlight,
    this.baseline,
    this.link,
    this.letterSpacing,
  });

  /// Parse the inline marks out of a `style` map. Accepts both `font`/`size`
  /// and `fontFamily`/`fontSize` aliases for author convenience.
  factory TextRunStyle.fromMap(Map<String, dynamic>? m) {
    if (m == null || m.isEmpty) return empty;
    double? dbl(String k) => (m[k] as num?)?.toDouble();
    return TextRunStyle(
      fontFamily: (m['fontFamily'] ?? m['font']) as String?,
      fontSize: dbl('fontSize') ?? dbl('size'),
      bold: m['bold'] as bool?,
      italic: m['italic'] as bool?,
      underline: m['underline'] as bool?,
      strike: (m['strike'] ?? m['strikethrough']) as bool?,
      color: m['color'] as String?,
      highlight: (m['highlight'] ?? m['background']) as String?,
      baseline: RunBaseline.fromString(m['baseline'] as String?),
      link: m['link'] as String?,
      letterSpacing: dbl('letterSpacing'),
    );
  }

  /// Font family name (resolved against the renderer's font set).
  final String? fontFamily;

  /// Absolute font size in points (once resolved).
  final double? fontSize;

  /// Bold weight.
  final bool? bold;

  /// Italic / oblique slant.
  final bool? italic;

  /// Underline decoration.
  final bool? underline;

  /// Strike-through decoration.
  final bool? strike;

  /// Foreground colour — `'#RRGGBB'` or a theme colour token.
  final String? color;

  /// Background / highlight colour — `'#RRGGBB'` or a theme colour token.
  final String? highlight;

  /// Baseline shift (super- / subscript).
  final RunBaseline? baseline;

  /// Hyperlink URL for the span.
  final String? link;

  /// Extra spacing between characters in points.
  final double? letterSpacing;

  /// An empty style — inherits everything.
  static const TextRunStyle empty = TextRunStyle();

  /// True when no mark is set.
  bool get isEmpty =>
      fontFamily == null &&
      fontSize == null &&
      bold == null &&
      italic == null &&
      underline == null &&
      strike == null &&
      color == null &&
      highlight == null &&
      baseline == null &&
      link == null &&
      letterSpacing == null;

  /// Return a style where every non-null field of [other] overrides this one.
  TextRunStyle merge(TextRunStyle? other) {
    if (other == null || other.isEmpty) return this;
    return TextRunStyle(
      fontFamily: other.fontFamily ?? fontFamily,
      fontSize: other.fontSize ?? fontSize,
      bold: other.bold ?? bold,
      italic: other.italic ?? italic,
      underline: other.underline ?? underline,
      strike: other.strike ?? strike,
      color: other.color ?? color,
      highlight: other.highlight ?? highlight,
      baseline: other.baseline ?? baseline,
      link: other.link ?? link,
      letterSpacing: other.letterSpacing ?? letterSpacing,
    );
  }

  /// Copy with overrides.
  TextRunStyle copyWith({
    String? fontFamily,
    double? fontSize,
    bool? bold,
    bool? italic,
    bool? underline,
    bool? strike,
    String? color,
    String? highlight,
    RunBaseline? baseline,
    String? link,
    double? letterSpacing,
  }) {
    return TextRunStyle(
      fontFamily: fontFamily ?? this.fontFamily,
      fontSize: fontSize ?? this.fontSize,
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      underline: underline ?? this.underline,
      strike: strike ?? this.strike,
      color: color ?? this.color,
      highlight: highlight ?? this.highlight,
      baseline: baseline ?? this.baseline,
      link: link ?? this.link,
      letterSpacing: letterSpacing ?? this.letterSpacing,
    );
  }

  /// Serialise the set marks back to a map.
  Map<String, dynamic> toMap() => {
        if (fontFamily != null) 'font': fontFamily,
        if (fontSize != null) 'size': fontSize,
        if (bold != null) 'bold': bold,
        if (italic != null) 'italic': italic,
        if (underline != null) 'underline': underline,
        if (strike != null) 'strike': strike,
        if (color != null) 'color': color,
        if (highlight != null) 'highlight': highlight,
        if (baseline != null) 'baseline': baseline!.token,
        if (link != null) 'link': link,
        if (letterSpacing != null) 'letterSpacing': letterSpacing,
      };

  @override
  bool operator ==(Object other) =>
      other is TextRunStyle &&
      other.fontFamily == fontFamily &&
      other.fontSize == fontSize &&
      other.bold == bold &&
      other.italic == italic &&
      other.underline == underline &&
      other.strike == strike &&
      other.color == color &&
      other.highlight == highlight &&
      other.baseline == baseline &&
      other.link == link &&
      other.letterSpacing == letterSpacing;

  @override
  int get hashCode => Object.hash(fontFamily, fontSize, bold, italic, underline,
      strike, color, highlight, baseline, link, letterSpacing);
}
