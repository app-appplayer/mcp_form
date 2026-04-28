import 'package:mcp_bundle/mcp_bundle.dart';

/// Extension providing computed layout dimensions for [FormLayoutPolicy].
///
/// All dimension values are in millimeters unless noted otherwise.
extension FormLayoutPolicyDimensions on FormLayoutPolicy {
  /// Whether the orientation is landscape.
  bool get isLandscape =>
      pageSize.orientation.toLowerCase() == 'landscape';

  /// Effective page width in mm, considering orientation.
  double get effectivePageWidth {
    return isLandscape ? pageSize.height : pageSize.width;
  }

  /// Effective page height in mm, considering orientation.
  double get effectivePageHeight {
    return isLandscape ? pageSize.width : pageSize.height;
  }

  /// Available content width in mm (page width minus horizontal margins).
  double get contentWidth =>
      effectivePageWidth - margins.left - margins.right;

  /// Available content height in mm (page height minus vertical margins).
  double get contentHeight =>
      effectivePageHeight - margins.top - margins.bottom;

  /// Width of a single grid column in mm.
  double get columnWidth => contentWidth / gridColumns;
}

/// Extension providing heading size calculations for [FormFontPolicy].
extension FormFontPolicyScale on FormFontPolicy {
  /// Returns the font size for a given heading level (1-6).
  ///
  /// Scale: h1=1.5x, h2=1.25x, h3=1.0x, h4=0.875x, h5=0.75x, h6=0.625x.
  /// Levels outside 1-6 are clamped.
  double headingSizeForLevel(int level) {
    const scales = <int, double>{
      1: 1.5,
      2: 1.25,
      3: 1.0,
      4: 0.875,
      5: 0.75,
      6: 0.625,
    };
    final scale = scales[level.clamp(1, 6)] ?? 1.0;
    return headingSize * scale;
  }
}
