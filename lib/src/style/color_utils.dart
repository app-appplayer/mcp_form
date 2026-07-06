/// Parse a `#RGB` / `#RRGGBB` (or bare `RRGGBB`) colour into normalised PDF
/// RGB components (0..1). Returns null for unrecognised input so callers can
/// fall back to the default (black) ink.
({double r, double g, double b})? hexToRgb(String? hex) {
  if (hex == null) return null;
  var h = hex.trim();
  if (h.startsWith('#')) h = h.substring(1);
  if (h.length == 3) {
    h = h.split('').map((c) => '$c$c').join();
  }
  if (h.length != 6) return null;
  final v = int.tryParse(h, radix: 16);
  if (v == null) return null;
  return (
    r: ((v >> 16) & 0xFF) / 255.0,
    g: ((v >> 8) & 0xFF) / 255.0,
    b: (v & 0xFF) / 255.0,
  );
}

/// Format an RGB triple as a PDF colour operand string, e.g. `0.20 0.20 0.20`.
String pdfRgb(({double r, double g, double b}) c) =>
    '${c.r.toStringAsFixed(3)} ${c.g.toStringAsFixed(3)} ${c.b.toStringAsFixed(3)}';
