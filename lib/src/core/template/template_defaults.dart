import 'package:mcp_bundle/mcp_bundle.dart';

/// Predefined standard page sizes as [FormPageSize] constants.
///
/// Dimensions are in millimeters. These match ISO and US paper standards.
class FormPageSizeDefaults {
  FormPageSizeDefaults._();

  /// ISO A4: 210 x 297 mm
  static const a4 = FormPageSize(
    size: 'A4',
    width: 210,
    height: 297,
  );

  /// ISO A3: 297 x 420 mm
  static const a3 = FormPageSize(
    size: 'A3',
    width: 297,
    height: 420,
  );

  /// ISO A5: 148 x 210 mm
  static const a5 = FormPageSize(
    size: 'A5',
    width: 148,
    height: 210,
  );

  /// US Letter: 215.9 x 279.4 mm
  static const letter = FormPageSize(
    size: 'Letter',
    width: 215.9,
    height: 279.4,
  );

  /// US Legal: 215.9 x 355.6 mm
  static const legal = FormPageSize(
    size: 'Legal',
    width: 215.9,
    height: 355.6,
  );

  /// US Tabloid: 279.4 x 431.8 mm
  static const tabloid = FormPageSize(
    size: 'Tabloid',
    width: 279.4,
    height: 431.8,
  );

  /// Look up a predefined page size by name (case-insensitive).
  ///
  /// Returns null if the name is not a recognized predefined size.
  static FormPageSize? fromName(String name) {
    return switch (name.toLowerCase()) {
      'a4' => a4,
      'a3' => a3,
      'a5' => a5,
      'letter' => letter,
      'legal' => legal,
      'tabloid' => tabloid,
      _ => null,
    };
  }
}

/// Convenience factory methods for creating [FormMargins].
class FormMarginsFactory {
  FormMarginsFactory._();

  /// Create margins with equal values on all sides.
  static FormMargins all(double value) => FormMargins(
        top: value,
        right: value,
        bottom: value,
        left: value,
      );

  /// Create margins with symmetric vertical and horizontal values.
  static FormMargins symmetric({
    double vertical = 0,
    double horizontal = 0,
  }) =>
      FormMargins(
        top: vertical,
        right: horizontal,
        bottom: vertical,
        left: horizontal,
      );

  /// Zero margins on all sides.
  static const zero = FormMargins(
    top: 0,
    right: 0,
    bottom: 0,
    left: 0,
  );
}

/// Predefined standard font policies.
class FormFontPolicyDefaults {
  FormFontPolicyDefaults._();

  /// Standard sans-serif font policy.
  static const standard = FormFontPolicy(
    defaultFont: 'NotoSans',
    defaultSize: 10,
    headingSize: 14,
    bodySize: 10,
    minSize: 6,
  );
}
