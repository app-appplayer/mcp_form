/// Utility for checking engine version compatibility against a range string.
///
/// Parses the compatRange string and checks if the given engine version
/// falls within it. Supports semver range operators: >=, >, <, <=.
///
/// Example range: ">= 1.0.0 < 2.0.0"
bool isCompatibleWithRange(String? compatRange, String engineVersion) {
  if (compatRange == null) return true;

  final parts = compatRange.split(' ');
  String? minVersion;
  String? maxVersion;
  var minInclusive = true;
  var maxInclusive = false;

  for (var i = 0; i < parts.length - 1; i++) {
    final op = parts[i];
    final ver = parts[i + 1];
    if (op == '>=' || op == '>') {
      minVersion = ver;
      minInclusive = (op == '>=');
    } else if (op == '<' || op == '<=') {
      maxVersion = ver;
      maxInclusive = (op == '<=');
    }
  }

  final engine = _parseVersion(engineVersion);
  if (engine == null) return false;

  if (minVersion != null) {
    final min = _parseVersion(minVersion);
    if (min == null) return false;
    final cmp = _compareTo(engine, min);
    if (minInclusive ? cmp < 0 : cmp <= 0) return false;
  }

  if (maxVersion != null) {
    final max = _parseVersion(maxVersion);
    if (max == null) return false;
    final cmp = _compareTo(engine, max);
    if (maxInclusive ? cmp > 0 : cmp >= 0) return false;
  }

  return true;
}

/// Parses a semver string into [major, minor, patch] components.
List<int>? _parseVersion(String version) {
  final parts = version.split('.');
  if (parts.length != 3) return null;
  try {
    return parts.map(int.parse).toList();
  } catch (_) {
    return null;
  }
}

/// Compares two version component lists.
/// Returns negative if a < b, zero if a == b, positive if a > b.
int _compareTo(List<int> a, List<int> b) {
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i] - b[i];
  }
  return 0;
}
