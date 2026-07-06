// Conditional zlib deflate: native (`dart:io` `ZLibCodec`) where available,
// a null-returning stub on web. PDF streams compress with `/FlateDecode` when
// this returns bytes, and embed whole (uncompressed) when it returns null.
export 'deflate_none.dart' if (dart.library.io) 'deflate_io.dart';
