/// Web fallback: no zlib available without `dart:io`, so streams are embedded
/// uncompressed. Returns null to signal "not compressed".
List<int>? deflate(List<int> data) => null;
