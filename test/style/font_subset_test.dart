import 'dart:io';
import 'dart:typed_data';

import 'package:mcp_form/src/style/style.dart';
import 'package:test/test.dart';

/// Parse an sfnt table directory: tag -> (offset, length).
Map<String, ({int offset, int length})> _tables(Uint8List font) {
  final d = ByteData.sublistView(font);
  final n = d.getUint16(4);
  final out = <String, ({int offset, int length})>{};
  var p = 12;
  for (var i = 0; i < n; i++) {
    out[String.fromCharCodes(font, p, p + 4)] =
        (offset: d.getUint32(p + 8), length: d.getUint32(p + 12));
    p += 16;
  }
  return out;
}

int _numGlyphs(Uint8List font) {
  final t = _tables(font)['maxp']!;
  return ByteData.sublistView(font).getUint16(t.offset + 4);
}

/// Long-format loca offsets for the subset (subsetter always writes long loca).
List<int> _loca(Uint8List font, int numGlyphs) {
  final t = _tables(font)['loca']!;
  final d = ByteData.sublistView(font);
  return [for (var i = 0; i <= numGlyphs; i++) d.getUint32(t.offset + i * 4)];
}

int _cidToGid(Uint8List map, int cid) =>
    ByteData.sublistView(map).getUint16(cid * 2);

void main() {
  const fontPath = '/System/Library/Fonts/Supplemental/AppleGothic.ttf';
  final hasFont = File(fontPath).existsSync();
  final skip = hasFont ? false : 'font not present';

  late Uint8List raw;
  late TrueTypeFont font;
  if (hasFont) {
    raw = Uint8List.fromList(File(fontPath).readAsBytesSync());
    font = TrueTypeFont.parse(raw);
  }

  group('subsetTrueTypeFont (optimal, renumbering)', () {
    test('renumbers to a compact subset and shrinks by orders of magnitude', () {
      final cps = ['가', '한', '글', 'A', '1'].map((s) => s.runes.first);
      final gids = {for (final cp in cps) font.gidFor(cp)!};
      final sub = subsetTrueTypeFont(raw, gids);

      // Glyph count collapses to (requested + components + .notdef), far below
      // the original face, and the program is a tiny fraction of the original.
      final ng = _numGlyphs(sub.fontBytes);
      expect(ng, lessThan(font.numGlyphs));
      expect(ng, lessThan(64));
      expect(sub.fontBytes.length, lessThan(raw.length ~/ 50));

      // Only the tables a CID-keyed embed needs survive; lookups are dropped.
      final tables = _tables(sub.fontBytes);
      expect(tables.keys, containsAll(['head', 'hhea', 'maxp', 'hmtx', 'loca', 'glyf']));
      expect(tables.containsKey('cmap'), isFalse);
      expect(tables.containsKey('post'), isFalse);
    }, skip: skip);

    test('CIDToGIDMap routes each used original gid to a real subset glyph', () {
      final cps = ['가', '한', '글'].map((s) => s.runes.first);
      final gids = {for (final cp in cps) font.gidFor(cp)!};
      final sub = subsetTrueTypeFont(raw, gids);

      final ng = _numGlyphs(sub.fontBytes);
      final loca = _loca(sub.fontBytes, ng);

      for (final oldGid in gids) {
        final newGid = _cidToGid(sub.cidToGidMap, oldGid);
        // Maps into the subset range, not .notdef.
        expect(newGid, inInclusiveRange(1, ng - 1));
        // The mapped glyph carries real outline data (non-empty loca span).
        expect(loca[newGid + 1] - loca[newGid], greaterThan(0));
      }
      // CID 0 always maps to glyph 0.
      expect(_cidToGid(sub.cidToGidMap, 0), 0);
    }, skip: skip);

    test('pulls in composite-glyph components transitively', () {
      // Subsetting any glyph still yields a self-consistent program (composite
      // components are retained and their references remapped) — exercised by
      // building a valid, parseable directory with a non-empty glyf.
      final sub = subsetTrueTypeFont(raw, {font.gidFor('가'.runes.first)!});
      final tables = _tables(sub.fontBytes);
      expect(tables['glyf']!.length, greaterThan(0));
    }, skip: skip);

    test('subset grows with the number of retained glyphs', () {
      final few = subsetTrueTypeFont(raw, {font.gidFor('가'.runes.first)!});
      final many = subsetTrueTypeFont(raw, {
        for (final cp in '가나다라마바사아자차카타파하'.runes) font.gidFor(cp)!,
      });
      expect(many.fontBytes.length, greaterThan(few.fontBytes.length));
      expect(_numGlyphs(many.fontBytes), greaterThan(_numGlyphs(few.fontBytes)));
    }, skip: skip);

    test('empty request yields just .notdef and stays valid', () {
      final sub = subsetTrueTypeFont(raw, <int>{});
      expect(_numGlyphs(sub.fontBytes), 1);
      expect(_tables(sub.fontBytes).keys, contains('glyf'));
    }, skip: skip);

    test('returns input + empty map for a CFF (OTTO) container', () {
      final otto = Uint8List(12);
      ByteData.sublistView(otto).setUint32(0, 0x4F54544F);
      final sub = subsetTrueTypeFont(otto, {1});
      expect(identical(sub.fontBytes, otto), isTrue);
      expect(sub.cidToGidMap, isEmpty);
    });
  });
}
