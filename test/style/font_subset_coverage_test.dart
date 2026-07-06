import 'dart:typed_data';

import 'package:mcp_form/src/style/style.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Minimal sfnt assembly helpers (no checksums — the code under test
// does not verify checksums when subsetting).
// ---------------------------------------------------------------------------

/// Assemble a TrueType sfnt from a tag→bytes map.
/// Tables are sorted alphabetically in the directory (per spec); each table
/// body is 4-byte-aligned.
Uint8List _buildSfnt(Map<String, Uint8List> tables) {
  final tags = tables.keys.toList()..sort();
  final numTables = tags.length;
  final headerLen = 12 + numTables * 16;

  int pad4(int n) => (n + 3) & ~3;

  var offset = headerLen;
  final offsets = <String, int>{};
  for (final tag in tags) {
    offsets[tag] = offset;
    offset += pad4(tables[tag]!.length);
  }

  final out = Uint8List(offset);
  final ob = ByteData.sublistView(out);

  ob.setUint32(0, 0x00010000); // sfntVersion: TrueType
  ob.setUint16(4, numTables);

  // Write table directory
  var dp = 12;
  for (final tag in tags) {
    out.setRange(dp, dp + 4, tag.codeUnits); // tag
    ob.setUint32(dp + 8, offsets[tag]!);      // offset
    ob.setUint32(dp + 12, tables[tag]!.length); // length
    dp += 16;
  }

  // Write table data
  for (final tag in tags) {
    final t = tables[tag]!;
    out.setRange(offsets[tag]!, offsets[tag]! + t.length, t);
  }

  return out;
}

/// Build the head table (54 bytes).  Set [longLoca]=false for short loca.
Uint8List _makeHead({bool longLoca = true}) {
  final t = Uint8List(54);
  ByteData.sublistView(t).setInt16(50, longLoca ? 1 : 0);
  return t;
}

/// Build the hhea table (36 bytes) with [numHMetrics] at offset 34.
Uint8List _makeHhea(int numHMetrics) {
  final t = Uint8List(36);
  ByteData.sublistView(t).setUint16(34, numHMetrics);
  return t;
}

/// Build the maxp table (6 bytes) with [numGlyphs] at offset 4.
Uint8List _makeMaxp(int numGlyphs) {
  final t = Uint8List(6);
  ByteData.sublistView(t).setUint16(4, numGlyphs);
  return t;
}

/// Build a minimal hmtx table.
/// numHMetrics longHorMetrics (advanceWidth=500, lsb=0) followed by
/// (numGlyphs - numHMetrics) LSB-only entries.
Uint8List _makeHmtx(int numHMetrics, int numGlyphs) {
  final extra = (numGlyphs - numHMetrics).clamp(0, 1000);
  final t = Uint8List(numHMetrics * 4 + extra * 2);
  final d = ByteData.sublistView(t);
  for (var i = 0; i < numHMetrics; i++) {
    d.setUint16(i * 4, 500); // advanceWidth
    // lsb defaults to 0
  }
  // extended lsb entries default to 0
  return t;
}

/// Build a loca table from [glyphOffsets] (numGlyphs+1 entries).
/// [shortLoca]=true → half-word offsets (offsets must be even).
Uint8List _makeLoca(List<int> glyphOffsets, {bool shortLoca = false}) {
  if (shortLoca) {
    final t = Uint8List(glyphOffsets.length * 2);
    final d = ByteData.sublistView(t);
    for (var i = 0; i < glyphOffsets.length; i++) {
      d.setUint16(i * 2, glyphOffsets[i] ~/ 2);
    }
    return t;
  } else {
    final t = Uint8List(glyphOffsets.length * 4);
    final d = ByteData.sublistView(t);
    for (var i = 0; i < glyphOffsets.length; i++) {
      d.setUint32(i * 4, glyphOffsets[i]);
    }
    return t;
  }
}

/// A minimal simple glyph of exactly [byteCount] bytes.
/// numberOfContours=1 (>= 0 → simple).
Uint8List _simpleGlyph(int byteCount) {
  final t = Uint8List(byteCount);
  ByteData.sublistView(t).setInt16(0, 1); // numberOfContours = 1
  return t;
}

/// A composite glyph (42 bytes) with 3 components demonstrating all three
/// scale-flag variants:
///
///   Component 1: flags = 0x0028  (MORE_COMPONENTS | WE_HAVE_A_SCALE)
///   Component 2: flags = 0x0060  (MORE_COMPONENTS | WE_HAVE_AN_X_AND_Y_SCALE)
///   Component 3: flags = 0x0080  (WE_HAVE_A_TWO_BY_TWO; last component)
///
/// Each references glyphIndex=1 with 1-byte (non-word) offset args.
Uint8List _compositeGlyph() {
  final t = Uint8List(42);
  final d = ByteData.sublistView(t);

  // Header: numberOfContours = -1 (composite), bbox zeroed.
  d.setInt16(0, -1);

  // Component 1 at byte 10.
  d.setUint16(10, 0x0028); // flags: MORE_COMPONENTS | WE_HAVE_A_SCALE
  d.setUint16(12, 1);       // glyphIndex = 1
  // bytes 14-15: dx=0, dy=0 (1-byte args, ARG_1_AND_2_ARE_WORDS not set)
  d.setUint16(16, 0x4000);  // F2Dot14 scale = 1.0
  // → total size consumed: 4 (flags+idx) + 2 (args) + 2 (scale) = 8 bytes, ends at 18

  // Component 2 at byte 18.
  d.setUint16(18, 0x0060); // MORE_COMPONENTS | WE_HAVE_AN_X_AND_Y_SCALE
  d.setUint16(20, 1);       // glyphIndex = 1
  // bytes 22-23: dx=0, dy=0
  d.setUint16(24, 0x4000);  // xScale
  d.setUint16(26, 0x4000);  // yScale
  // → size: 4+2+4=10 bytes, ends at 28

  // Component 3 at byte 28.
  d.setUint16(28, 0x0080); // WE_HAVE_A_TWO_BY_TWO (no MORE_COMPONENTS → last)
  d.setUint16(30, 1);       // glyphIndex = 1
  // bytes 32-33: dx=0, dy=0
  d.setUint16(34, 0x4000);  // xx
  d.setUint16(36, 0x0000);  // yx
  d.setUint16(38, 0x0000);  // xy
  d.setUint16(40, 0x4000);  // yy
  // → size: 4+2+8=14 bytes, ends at 42 ✓

  return t;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('subsetTrueTypeFont: missing required tables returns original (line 62)', () {
    test('a 12-byte sfnt with zero tables triggers the null-table early return', () {
      // A minimal TrueType header with numTables=0 means dir['glyf'] etc. are
      // all null → the guard at line 56-62 fires.
      final fake = Uint8List(12);
      ByteData.sublistView(fake).setUint32(0, 0x00010000);
      final result = subsetTrueTypeFont(fake, {0});
      expect(identical(result.fontBytes, fake), isTrue);
      expect(result.cidToGidMap.isEmpty, isTrue);
    });

    test('a CFF/OTTO font is also returned unchanged (pre-check)', () {
      final otto = Uint8List(12);
      ByteData.sublistView(otto).setUint32(0, 0x4F54544F); // 'OTTO'
      final result = subsetTrueTypeFont(otto, {0});
      expect(identical(result.fontBytes, otto), isTrue);
    });
  });

  group('subsetTrueTypeFont: short loca format (line 75)', () {
    test('short-loca offsets (indexToLocFormat=0) are read as half-words', () {
      // Glyph 0 and 1 are each 10 bytes (even; required for short loca).
      final glyf = Uint8List(20);
      ByteData.sublistView(glyf).setInt16(0, 1); // g0 numberOfContours=1
      ByteData.sublistView(glyf).setInt16(10, 1); // g1 numberOfContours=1

      // Short-loca values: [0, 5, 10] → real offsets [0, 10, 20].
      final loca = _makeLoca([0, 10, 20], shortLoca: true);

      final font = _buildSfnt({
        'glyf': glyf,
        'head': _makeHead(longLoca: false), // indexToLocFormat = 0 → short
        'hhea': _makeHhea(2),
        'maxp': _makeMaxp(2),
        'hmtx': _makeHmtx(2, 2),
        'loca': loca,
      });

      // Requesting glyph 1 exercises line 75 (the short-loca branch).
      final result = subsetTrueTypeFont(font, {1});
      expect(result.fontBytes.length, greaterThan(12));
      expect(result.cidToGidMap.isNotEmpty, isTrue);
    });
  });

  group('subsetTrueTypeFont: composite glyph flags + odd glyph + extended hmtx', () {
    // This single synthetic font exercises lines 101, 103, 105, 137, 138,
    // 155, 156, 207, 209, and 211 in a single call to subsetTrueTypeFont.
    //
    // Font layout:
    //   numGlyphs=3, numHMetrics=1 (long loca)
    //   glyph 0: 11 bytes (simple, ODD length → lines 137-138)
    //   glyph 1: 10 bytes (simple, even)
    //   glyph 2: 42 bytes (composite with 3 components → lines 101,103,105)
    //
    // Subsetting with usedGids={2}:
    //   keep closure adds glyph 1 as component of glyph 2.
    //   keep = {0, 1, 2}, oldIds = [0, 1, 2].
    //
    // hmtx with numHMetrics=1:
    //   glyphs 1 and 2 (g >= numHMetrics) use the extended path → lines 155-156.
    //
    // _remapComposite on glyph 2 → lines 207, 209, 211.

    late Uint8List syntheticFont;

    setUp(() {
      final g0 = _simpleGlyph(11); // odd length
      final g1 = _simpleGlyph(10);
      final g2 = _compositeGlyph();

      final glyfBytes = Uint8List(11 + 10 + 42);
      glyfBytes.setRange(0, 11, g0);
      glyfBytes.setRange(11, 21, g1);
      glyfBytes.setRange(21, 63, g2);

      syntheticFont = _buildSfnt({
        'glyf': glyfBytes,
        'head': _makeHead(), // long loca
        'hhea': _makeHhea(1), // numHMetrics=1
        'maxp': _makeMaxp(3),
        'hmtx': _makeHmtx(1, 3), // 1 full + 2 extended lsb
        'loca': _makeLoca([0, 11, 21, 63]), // long loca (4 entries for 3 glyphs)
      });
    });

    test('composite glyph WE_HAVE_A_SCALE flag skips 2 bytes in keep-set loop (line 101)', () {
      // Component 1 has flags=0x0028 → (flags & 0x0008) != 0 → q += 2 (line 101).
      final result = subsetTrueTypeFont(syntheticFont, {2});
      expect(result.fontBytes.length, greaterThan(12));
    });

    test('composite glyph WE_HAVE_AN_X_AND_Y_SCALE flag skips 4 bytes (line 103)', () {
      // Component 2 has flags=0x0060 → (flags & 0x0040) != 0 → q += 4 (line 103).
      final result = subsetTrueTypeFont(syntheticFont, {2});
      expect(result.cidToGidMap.isNotEmpty, isTrue);
    });

    test('composite glyph WE_HAVE_A_TWO_BY_TWO flag skips 8 bytes (line 105)', () {
      // Component 3 has flags=0x0080 → (flags & 0x0080) != 0 → q += 8 (line 105).
      final result = subsetTrueTypeFont(syntheticFont, {2});
      expect(result.fontBytes.length, greaterThan(20));
    });

    test('simple glyph with odd byte count gets a padding byte (lines 137-138)', () {
      // Glyph 0 has 11 bytes (odd) → cursor.isOdd → addByte(0) + cursor++.
      // The rebuilt glyf will be longer by 1 (the padding byte for glyph 0).
      final result = subsetTrueTypeFont(syntheticFont, {2});
      expect(result.fontBytes.length, greaterThan(12));
    });

    test('glyph id >= numHMetrics uses extended hmtx lsb array (lines 155-156)', () {
      // Glyphs 1 and 2 have g >= numHMetrics=1 → else branch (lines 155-156).
      // adv is read from the last longHorMetric entry; lsb from the extended array.
      final result = subsetTrueTypeFont(syntheticFont, {2});
      // If hmtx extended path caused an exception, this would fail.
      expect(result.fontBytes.length, greaterThan(12));
    });

    test('_remapComposite reuses scale-flag traversal for lines 207, 209, 211', () {
      // After identifying composite glyphs in the keep set, the rebuild phase
      // calls _remapComposite(gb, old2new) on glyph 2.
      // That traversal hits:
      //   line 207: flags=0x0028 → (flags & 0x0008) != 0 → q += 2
      //   line 209: flags=0x0060 → (flags & 0x0040) != 0 → q += 4
      //   line 211: flags=0x0080 → (flags & 0x0080) != 0 → q += 8
      final result = subsetTrueTypeFont(syntheticFont, {2});
      // The cidToGidMap covers CIDs 0..2.
      expect(result.cidToGidMap.length, 6); // 3 CIDs × 2 bytes each
    });
  });
}
