/// Version redline (track-changes) markup. A block carrying `style.change`
/// renders as an edit: `inserted` (underlined, green) or `deleted`
/// (struck-through, red). An upstream diff tool annotates blocks; the renderers
/// only draw the markup, so no diff algorithm lives here.
library;

/// The visual decoration for a redline change, or null when the block is
/// unchanged. `underline` / `strike` reuse the existing run marks and `color`
/// is a hex colour.
({bool underline, bool strike, String color})? redlineDecoration(
    String? change) {
  switch (change) {
    case 'inserted':
      return (underline: true, strike: false, color: '#128A3A'); // green
    case 'deleted':
      return (underline: false, strike: true, color: '#C0392B'); // red
    default:
      return null;
  }
}

/// Merge a block's redline decoration into its style map as inline marks
/// (`underline` / `strike` / `color`), so renderers that read the style map
/// draw the change without special-casing. Unchanged blocks pass through.
Map<String, dynamic>? applyRedlineStyle(Map<String, dynamic>? style) {
  final deco = redlineDecoration(style?['change'] as String?);
  if (deco == null) return style;
  return {
    ...?style,
    if (deco.underline) 'underline': true,
    if (deco.strike) 'strike': true,
    'color': deco.color,
  };
}
