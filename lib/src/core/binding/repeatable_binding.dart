/// Resolve the per-item data scopes a [FormRepeatableBlock] expands over.
///
/// A repeatable block renders its [FormRepeatableBlock.itemTemplate] once per
/// item in the array bound at [FormRepeatableBlock.itemsBinding]. This is a
/// render-time concern owned by mcp_form; the core (mcp_bundle) is unchanged.
/// Static renderers (PDF / HTML / DOCX / Markdown) pre-expand the template here,
/// while the UI DSL renderer hands the template + binding to the runtime to
/// expand interactively.
library;

import 'package:mcp_bundle/mcp_bundle.dart';

/// One data scope per rendered item.
///
/// - `itemsBinding == null` → a single scope equal to the parent [data], i.e.
///   the template renders once with the surrounding data (legacy behaviour).
/// - Otherwise the array at the dotted `itemsBinding` path is read from [data];
///   each element becomes a scope (a Map element is used directly, a scalar is
///   wrapped as `{'value': element}`). The count is clamped to
///   `minItems`..`maxItems`, padding a short array with empty scopes so required
///   rows still render (as unfilled fields).
List<Map<String, dynamic>> resolveRepeatableItems(
  FormRepeatableBlock block,
  Map<String, dynamic> data,
) {
  if (block.itemsBinding == null) return [data];

  final raw = _resolvePath(block.itemsBinding!, data);
  var items = <Map<String, dynamic>>[];
  if (raw is List) {
    items = [
      for (final e in raw)
        if (e is Map)
          e.map((k, v) => MapEntry(k.toString(), v))
        else
          <String, dynamic>{'value': e},
    ];
  }

  final max = block.maxItems;
  if (max != null && items.length > max) {
    items = items.sublist(0, max);
  }
  final min = block.minItems ?? 0;
  while (items.length < min) {
    items.add(<String, dynamic>{});
  }
  return items;
}

/// Navigate a dotted `a.b.c` path into nested maps; null when any hop misses.
dynamic _resolvePath(String path, Map<String, dynamic> data) {
  dynamic current = data;
  for (final part in path.split('.')) {
    if (current is Map && current.containsKey(part)) {
      current = current[part];
    } else {
      return null;
    }
  }
  return current;
}
