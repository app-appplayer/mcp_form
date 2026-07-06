import 'dart:typed_data';

/// A minimal TrueType / OpenType (glyf-based) font reader, enough to embed the
/// font as a PDF Type0 / CIDFontType2 program and to map characters to glyph
/// IDs with their advance widths.
///
/// Only the tables the PDF renderer needs are parsed: `head`, `maxp`, `hhea`,
/// `hmtx`, and `cmap` (formats 4 and 12). CFF/`OTTO` outlines are not handled —
/// pass a glyf-based `.ttf`.
class TrueTypeFont {
  TrueTypeFont._(this.bytes, this._data);

  /// Parse [data]. Throws [FormatException] for unsupported (e.g. CFF) fonts.
  factory TrueTypeFont.parse(List<int> data) {
    final bytes = data is Uint8List ? data : Uint8List.fromList(data);
    final f = TrueTypeFont._(bytes, ByteData.sublistView(bytes));
    f._read();
    return f;
  }

  /// The raw font program (embedded verbatim as `/FontFile2`).
  final Uint8List bytes;
  final ByteData _data;

  int _unitsPerEm = 1000;
  int _numGlyphs = 0;
  int _indexToLocFormat = 0;
  int _numberOfHMetrics = 0;
  int _hmtxOffset = 0;
  int _glyfBase = -1;
  int _locaBase = -1;

  // FontDescriptor metrics, in font units.
  int _xMin = 0, _yMin = 0, _xMax = 1000, _yMax = 1000;
  int _ascent = 800, _descent = -200;

  // cmap format-4 state.
  bool _hasF4 = false;
  late Uint16List _f4End, _f4Start, _f4Delta, _f4RangeOffset;
  late int _f4GlyphArrayOffset; // byte offset of glyphIdArray
  late int _f4SegCount;

  // cmap format-12 groups (start, end, startGid), sorted by start.
  List<List<int>> _f12 = const [];

  int get unitsPerEm => _unitsPerEm;
  int get numGlyphs => _numGlyphs;

  /// 1000-em scaled font bounding box and vertical metrics (PDF glyph space).
  int get bboxXMin => _scale(_xMin);
  int get bboxYMin => _scale(_yMin);
  int get bboxXMax => _scale(_xMax);
  int get bboxYMax => _scale(_yMax);
  int get ascent => _scale(_ascent);
  int get descent => _scale(_descent);

  int _scale(int u) => (u * 1000 / _unitsPerEm).round();

  void _read() {
    final sfnt = _data.getUint32(0);
    if (sfnt == 0x4F54544F) {
      throw const FormatException('CFF (OTTO) fonts are not supported');
    }
    if (sfnt == 0x74746366) {
      throw const FormatException('TrueType Collections (.ttc) are not supported');
    }
    final numTables = _data.getUint16(4);
    final tables = <String, (int, int)>{};
    var p = 12;
    for (var i = 0; i < numTables; i++) {
      final tag = String.fromCharCodes(bytes, p, p + 4);
      final offset = _data.getUint32(p + 8);
      final length = _data.getUint32(p + 12);
      tables[tag] = (offset, length);
      p += 16;
    }

    final head = tables['head']!;
    _unitsPerEm = _data.getUint16(head.$1 + 18);
    _xMin = _data.getInt16(head.$1 + 36);
    _yMin = _data.getInt16(head.$1 + 38);
    _xMax = _data.getInt16(head.$1 + 40);
    _yMax = _data.getInt16(head.$1 + 42);
    _indexToLocFormat = _data.getInt16(head.$1 + 50);

    final maxp = tables['maxp']!;
    _numGlyphs = _data.getUint16(maxp.$1 + 4);

    final hhea = tables['hhea']!;
    _ascent = _data.getInt16(hhea.$1 + 4);
    _descent = _data.getInt16(hhea.$1 + 6);
    _numberOfHMetrics = _data.getUint16(hhea.$1 + 34);

    _hmtxOffset = tables['hmtx']!.$1;
    _glyfBase = tables['glyf']?.$1 ?? -1;
    _locaBase = tables['loca']?.$1 ?? -1;

    _readCmap(tables['cmap']!.$1);
    // Touch indexToLocFormat so the analyzer sees it consumed; loca/glyf are
    // embedded verbatim (no subsetting), so the value is informational here.
    assert(_indexToLocFormat == 0 || _indexToLocFormat == 1);
  }

  void _readCmap(int base) {
    final numTables = _data.getUint16(base + 2);
    int? best4;
    int? best12;
    var p = base + 4;
    for (var i = 0; i < numTables; i++) {
      final platform = _data.getUint16(p);
      final encoding = _data.getUint16(p + 2);
      final off = base + _data.getUint32(p + 4);
      final format = _data.getUint16(off);
      if (format == 12 && (platform == 3 && encoding == 10 || platform == 0)) {
        best12 = off;
      } else if (format == 4 &&
          (platform == 3 && encoding == 1 || platform == 0)) {
        best4 ??= off;
      } else if (format == 4 && platform == 3 && encoding == 0) {
        best4 ??= off;
      }
      p += 8;
    }
    if (best12 != null) _readCmap12(best12);
    if (best4 != null) _readCmap4(best4);
    if (best12 == null && best4 == null) {
      throw const FormatException('No supported cmap subtable (need 4 or 12)');
    }
  }

  void _readCmap4(int off) {
    final segX2 = _data.getUint16(off + 6);
    final segCount = segX2 ~/ 2;
    _f4SegCount = segCount;
    final endOff = off + 14;
    final startOff = endOff + segX2 + 2; // skip reservedPad
    final deltaOff = startOff + segX2;
    final rangeOff = deltaOff + segX2;
    _f4End = Uint16List(segCount);
    _f4Start = Uint16List(segCount);
    _f4Delta = Uint16List(segCount);
    _f4RangeOffset = Uint16List(segCount);
    for (var i = 0; i < segCount; i++) {
      _f4End[i] = _data.getUint16(endOff + i * 2);
      _f4Start[i] = _data.getUint16(startOff + i * 2);
      _f4Delta[i] = _data.getUint16(deltaOff + i * 2);
      _f4RangeOffset[i] = _data.getUint16(rangeOff + i * 2);
    }
    _f4GlyphArrayOffset = rangeOff;
    _hasF4 = true;
  }

  void _readCmap12(int off) {
    final nGroups = _data.getUint32(off + 12);
    final groups = <List<int>>[];
    var p = off + 16;
    for (var i = 0; i < nGroups; i++) {
      groups.add([
        _data.getUint32(p), // startCharCode
        _data.getUint32(p + 4), // endCharCode
        _data.getUint32(p + 8), // startGlyphID
      ]);
      p += 12;
    }
    _f12 = groups;
  }

  /// Glyph id for a Unicode code point, or null if the font has no glyph.
  int? gidFor(int cp) {
    if (_f12.isNotEmpty) {
      // Binary search the sorted groups.
      var lo = 0, hi = _f12.length - 1;
      while (lo <= hi) {
        final mid = (lo + hi) >> 1;
        final g = _f12[mid];
        if (cp < g[0]) {
          hi = mid - 1;
        } else if (cp > g[1]) {
          lo = mid + 1;
        } else {
          return g[2] + (cp - g[0]);
        }
      }
    }
    if (_hasF4 && cp <= 0xFFFF) {
      for (var i = 0; i < _f4SegCount; i++) {
        if (cp <= _f4End[i]) {
          if (cp < _f4Start[i]) return 0;
          final ro = _f4RangeOffset[i];
          if (ro == 0) {
            return (cp + _f4Delta[i]) & 0xFFFF;
          }
          // glyphIdArray index per the TrueType spec.
          final glyphIndexOffset =
              _f4GlyphArrayOffset + i * 2 + ro + (cp - _f4Start[i]) * 2;
          final g = _data.getUint16(glyphIndexOffset);
          if (g == 0) return 0;
          return (g + _f4Delta[i]) & 0xFFFF;
        }
      }
    }
    return null;
  }

  /// Advance width of a glyph in font units.
  int advanceWidthFontUnits(int gid) {
    final idx = gid < _numberOfHMetrics ? gid : _numberOfHMetrics - 1;
    if (idx < 0) return _unitsPerEm;
    return _data.getUint16(_hmtxOffset + idx * 4);
  }

  /// Advance width scaled to PDF 1000-em glyph space.
  int advanceWidth1000(int gid) => _scale(advanceWidthFontUnits(gid));

  /// Decode a glyph's outline into contours of points in font units (y up).
  /// Each point is `(x, y, onCurve)`; off-curve points are quadratic-bezier
  /// control points. Returns an empty list for a space, a missing glyf/loca,
  /// or a composite glyph (composites are a follow-up — they render blank).
  List<List<(double, double, bool)>> glyphContours(int gid) {
    if (_glyfBase < 0 || _locaBase < 0 || gid < 0 || gid >= _numGlyphs) {
      return const [];
    }
    // loca → this glyph's slice within glyf.
    final int start;
    final int end;
    if (_indexToLocFormat == 0) {
      start = _data.getUint16(_locaBase + gid * 2) * 2;
      end = _data.getUint16(_locaBase + (gid + 1) * 2) * 2;
    } else {
      start = _data.getUint32(_locaBase + gid * 4);
      end = _data.getUint32(_locaBase + (gid + 1) * 4);
    }
    if (end <= start) return const []; // empty glyph (e.g. space)

    var p = _glyfBase + start;
    final numContours = _data.getInt16(p);
    if (numContours < 0) return const []; // composite — follow-up
    p += 10; // int16 numContours + 4×int16 bbox

    final endPts = <int>[];
    for (var i = 0; i < numContours; i++) {
      endPts.add(_data.getUint16(p));
      p += 2;
    }
    final numPoints = endPts.isEmpty ? 0 : endPts.last + 1;
    final instrLen = _data.getUint16(p);
    p += 2 + instrLen;

    // Flags (with repeat).
    final flags = <int>[];
    while (flags.length < numPoints) {
      final f = _data.getUint8(p++);
      flags.add(f);
      if (f & 0x08 != 0) {
        var repeat = _data.getUint8(p++);
        while (repeat-- > 0) {
          flags.add(f);
        }
      }
    }

    // X then Y coordinates (delta-encoded per flag bits).
    List<int> readCoords(int shortBit, int sameBit) {
      final coords = <int>[];
      var v = 0;
      for (var i = 0; i < numPoints; i++) {
        final f = flags[i];
        if (f & shortBit != 0) {
          final d = _data.getUint8(p++);
          v += (f & sameBit != 0) ? d : -d;
        } else if (f & sameBit == 0) {
          v += _data.getInt16(p);
          p += 2;
        }
        coords.add(v);
      }
      return coords;
    }

    final xs = readCoords(0x02, 0x10);
    final ys = readCoords(0x04, 0x20);

    final contours = <List<(double, double, bool)>>[];
    var pi = 0;
    for (final endPt in endPts) {
      final contour = <(double, double, bool)>[];
      for (; pi <= endPt; pi++) {
        contour.add((xs[pi].toDouble(), ys[pi].toDouble(), flags[pi] & 0x01 != 0));
      }
      contours.add(contour);
    }
    return contours;
  }
}
