import 'dart:io';

/// Native zlib (RFC 1950) compression for PDF `/FlateDecode` streams. Used on
/// platforms where `dart:io` is available; web falls back to uncompressed.
List<int>? deflate(List<int> data) => ZLibCodec().encode(data);
