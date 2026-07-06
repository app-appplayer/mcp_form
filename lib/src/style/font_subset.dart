import 'dart:typed_data';

/// The result of subsetting a TrueType font for Type0 / CIDFontType2 embedding.
class FontSubset {
  FontSubset(this.fontBytes, this.cidToGidMap);

  /// The compacted font program (embed as `/FontFile2`).
  final Uint8List fontBytes;

  /// `CIDToGIDMap` stream: for every CID (the original glyph id used in the
  /// content stream), two big-endian bytes giving the glyph id inside
  /// [fontBytes]. Dense `0..maxUsedCid`. Empty when the font was not subset
  /// (the caller then uses `/CIDToGIDMap /Identity` with the original program).
  final Uint8List cidToGidMap;
}

/// Optimal TrueType (`glyf`-based) subsetter for CIDFontType2 embedding.
///
/// Only the glyphs actually used (plus the components of any used composite,
/// transitively, plus glyph 0) are retained and **renumbered** into a compact
/// `0..n` range. The `glyf`, `loca`, `hmtx`, `maxp` and `hhea` tables are
/// rebuilt at the subset size, composite-glyph component references are
/// rewritten to the new ids, and grid-fitting tables (`cvt `/`fpgm`/`prep`) are
/// preserved so hinting still works. Lookup tables not needed for embedded CID
/// fonts (`cmap`, `name`, `post`, `OS/2`, `GSUB`/`GPOS`, …) are dropped.
///
/// A [FontSubset.cidToGidMap] maps each original glyph id (used as the CID in
/// Identity-H content) to its new id, so the content stream, `W` array and
/// `ToUnicode` map all stay keyed by the original ids — only the font program
/// shrinks. A 15 MB CJK face collapses to a few KB for a handful of glyphs.
///
/// Falls back to the original bytes with an empty map when the font cannot be
/// subset (CFF/`.ttc` container, or missing `glyf`/`loca`/`head`/`maxp`/`hhea`).
FontSubset subsetTrueTypeFont(Uint8List font, Set<int> usedGids) {
  final data = ByteData.sublistView(font);
  final sfnt = data.getUint32(0);
  if (sfnt == 0x4F54544F || sfnt == 0x74746366) {
    return FontSubset(font, Uint8List(0));
  }

  final numTables = data.getUint16(4);
  final dir = <String, ({int offset, int length})>{};
  var p = 12;
  for (var i = 0; i < numTables; i++) {
    final tag = String.fromCharCodes(font, p, p + 4);
    dir[tag] = (offset: data.getUint32(p + 8), length: data.getUint32(p + 12));
    p += 16;
  }

  final glyf = dir['glyf'];
  final loca = dir['loca'];
  final head = dir['head'];
  final maxp = dir['maxp'];
  final hhea = dir['hhea'];
  final hmtx = dir['hmtx'];
  if (glyf == null ||
      loca == null ||
      head == null ||
      maxp == null ||
      hhea == null ||
      hmtx == null) {
    return FontSubset(font, Uint8List(0));
  }

  final longLoca = data.getInt16(head.offset + 50) == 1;
  final numGlyphs = data.getUint16(maxp.offset + 4);
  final numHMetrics = data.getUint16(hhea.offset + 34);
  if (numGlyphs == 0) return FontSubset(font, Uint8List(0));

  // Original glyph offsets into glyf (numGlyphs + 1 entries).
  final off = List<int>.filled(numGlyphs + 1, 0);
  for (var i = 0; i <= numGlyphs; i++) {
    off[i] = longLoca
        ? data.getUint32(loca.offset + i * 4)
        : data.getUint16(loca.offset + i * 2) * 2;
  }

  // Keep set: glyph 0, the requested glyphs, and composite components (closure).
  final keep = <int>{0};
  var maxCid = 0;
  for (final g in usedGids) {
    if (g >= 0 && g < numGlyphs) {
      keep.add(g);
      if (g > maxCid) maxCid = g;
    }
  }
  final stack = keep.toList();
  while (stack.isNotEmpty) {
    final g = stack.removeLast();
    final start = glyf.offset + off[g];
    final end = glyf.offset + off[g + 1];
    if (end - start < 10 || data.getInt16(start) >= 0) continue;
    var q = start + 10;
    while (q + 4 <= end) {
      final flags = data.getUint16(q);
      final comp = data.getUint16(q + 2);
      if (comp < numGlyphs && keep.add(comp)) stack.add(comp);
      q += 4;
      q += (flags & 0x0001) != 0 ? 4 : 2;
      if ((flags & 0x0008) != 0) {
        q += 2;
      } else if ((flags & 0x0040) != 0) {
        q += 4;
      } else if ((flags & 0x0080) != 0) {
        q += 8;
      }
      if ((flags & 0x0020) == 0) break;
    }
  }

  // Renumber: sorted old ids -> compact new ids (glyph 0 -> 0).
  final oldIds = keep.toList()..sort();
  final newCount = oldIds.length;
  final old2new = <int, int>{};
  for (var n = 0; n < newCount; n++) {
    old2new[oldIds[n]] = n;
  }

  // Rebuild glyf (rewriting composite component ids) + a long loca.
  final newGlyf = BytesBuilder();
  final newLoca = Uint8List((newCount + 1) * 4);
  final locaView = ByteData.sublistView(newLoca);
  var cursor = 0;
  for (var n = 0; n < newCount; n++) {
    locaView.setUint32(n * 4, cursor);
    final g = oldIds[n];
    final len = off[g + 1] - off[g];
    if (len > 0) {
      final gb = Uint8List.sublistView(
          font, glyf.offset + off[g], glyf.offset + off[g] + len);
      if (ByteData.sublistView(gb).getInt16(0) < 0) {
        _remapComposite(gb, old2new);
      }
      newGlyf.add(gb);
      cursor += len;
      if (cursor.isOdd) {
        newGlyf.addByte(0);
        cursor++;
      }
    }
  }
  locaView.setUint32(newCount * 4, cursor);

  // Rebuild hmtx (full longHorMetrics for every retained glyph).
  final newHmtx = Uint8List(newCount * 4);
  final hmtxView = ByteData.sublistView(newHmtx);
  for (var n = 0; n < newCount; n++) {
    final g = oldIds[n];
    final int adv;
    final int lsb;
    if (g < numHMetrics) {
      adv = data.getUint16(hmtx.offset + g * 4);
      lsb = data.getInt16(hmtx.offset + g * 4 + 2);
    } else {
      adv = data.getUint16(hmtx.offset + (numHMetrics - 1) * 4);
      lsb = data.getInt16(hmtx.offset + numHMetrics * 4 + (g - numHMetrics) * 2);
    }
    hmtxView.setUint16(n * 4, adv);
    hmtxView.setInt16(n * 4 + 2, lsb);
  }

  // Patched copies of the structural tables.
  final newHead = _slice(font, head);
  ByteData.sublistView(newHead).setInt16(50, 1); // long loca
  ByteData.sublistView(newHead).setUint32(8, 0); // checkSumAdjustment
  final newHhea = _slice(font, hhea);
  ByteData.sublistView(newHhea).setUint16(34, newCount); // numberOfHMetrics
  final newMaxp = _slice(font, maxp);
  ByteData.sublistView(newMaxp).setUint16(4, newCount); // numGlyphs

  // Final table set: structural + retained outlines + grid-fitting. Everything
  // else (cmap/name/post/OS2/GSUB/…) is unnecessary for a CID-keyed embed.
  final tables = <String, Uint8List>{
    'head': newHead,
    'hhea': newHhea,
    'maxp': newMaxp,
    'hmtx': newHmtx,
    'loca': newLoca,
    'glyf': newGlyf.toBytes(),
  };
  for (final t in const ['cvt ', 'fpgm', 'prep', 'gasp']) {
    final e = dir[t];
    if (e != null) tables[t] = _slice(font, e);
  }

  // CIDToGIDMap: original glyph id (the CID) -> new glyph id, dense 0..maxCid.
  final cidMap = Uint8List((maxCid + 1) * 2);
  final cidView = ByteData.sublistView(cidMap);
  for (final entry in old2new.entries) {
    if (entry.key <= maxCid) cidView.setUint16(entry.key * 2, entry.value);
  }

  return FontSubset(_assembleSfnt(sfnt, tables), cidMap);
}

/// Rewrite composite-glyph component glyph ids in-place using [old2new].
void _remapComposite(Uint8List gb, Map<int, int> old2new) {
  final d = ByteData.sublistView(gb);
  var q = 10;
  while (q + 4 <= gb.length) {
    final flags = d.getUint16(q);
    final comp = d.getUint16(q + 2);
    d.setUint16(q + 2, old2new[comp] ?? 0);
    q += 4;
    q += (flags & 0x0001) != 0 ? 4 : 2;
    if ((flags & 0x0008) != 0) {
      q += 2;
    } else if ((flags & 0x0040) != 0) {
      q += 4;
    } else if ((flags & 0x0080) != 0) {
      q += 8;
    }
    if ((flags & 0x0020) == 0) break;
  }
}

Uint8List _slice(Uint8List font, ({int offset, int length}) t) =>
    Uint8List.fromList(Uint8List.sublistView(font, t.offset, t.offset + t.length));

/// Assemble an sfnt from a tag->bytes map, computing the directory, per-table
/// checksums and the `head` checkSumAdjustment.
Uint8List _assembleSfnt(int sfntVersion, Map<String, Uint8List> tables) {
  final tags = tables.keys.toList()..sort(); // directory sorted by tag (spec)
  final numTables = tags.length;
  int pad4(int n) => (n + 3) & ~3;

  final headerLen = 12 + numTables * 16;
  var offset = headerLen;
  final tableOffset = <String, int>{};
  for (final tag in tags) {
    tableOffset[tag] = offset;
    offset += pad4(tables[tag]!.length);
  }

  final out = Uint8List(offset);
  final ob = ByteData.sublistView(out);

  ob.setUint32(0, sfntVersion);
  ob.setUint16(4, numTables);
  var entrySelector = 0;
  var searchRange = 16;
  while (searchRange * 2 <= numTables * 16) {
    searchRange *= 2;
    entrySelector++;
  }
  ob.setUint16(6, searchRange);
  ob.setUint16(8, entrySelector);
  ob.setUint16(10, numTables * 16 - searchRange);

  for (final tag in tags) {
    out.setRange(
        tableOffset[tag]!, tableOffset[tag]! + tables[tag]!.length, tables[tag]!);
  }

  // head.checkSumAdjustment must be zero before any checksum is computed.
  final headOff = tableOffset['head'];
  if (headOff != null) ob.setUint32(headOff + 8, 0);

  var dp = 12;
  for (final tag in tags) {
    final to = tableOffset[tag]!;
    final len = tables[tag]!.length;
    out.setRange(dp, dp + 4, tag.codeUnits);
    ob.setUint32(dp + 4, _checksum(out, to, len));
    ob.setUint32(dp + 8, to);
    ob.setUint32(dp + 12, len);
    dp += 16;
  }

  if (headOff != null) {
    final whole = _checksum(out, 0, out.length);
    ob.setUint32(headOff + 8, (0xB1B0AFBA - whole) & 0xFFFFFFFF);
  }

  return out;
}

/// TrueType table checksum: sum of big-endian uint32s over [len] bytes from
/// [start], the data treated as zero-padded to a 4-byte boundary.
int _checksum(Uint8List data, int start, int len) {
  final view = ByteData.sublistView(data);
  var sum = 0;
  final end = start + len;
  var i = start;
  while (i + 4 <= end) {
    sum = (sum + view.getUint32(i)) & 0xFFFFFFFF;
    i += 4;
  }
  if (i < end) {
    var last = 0;
    for (var b = 0; b < 4; b++) {
      last = (last << 8) | (i + b < end ? data[i + b] : 0);
    }
    sum = (sum + last) & 0xFFFFFFFF;
  }
  return sum;
}
