/// A self-contained QR Code encoder (byte mode, error-correction level M,
/// versions 1–7). No dependencies. Produces a square module matrix a renderer
/// draws as black/white cells — useful for payment links, ticket / label codes
/// and document URLs.
///
/// Scope: byte (8-bit) mode, EC level M, versions 1–7 (uniform block layout,
/// up to ~122 data bytes). Larger payloads throw. Numeric / alphanumeric / kanji
/// modes and versions 8–40 are out of scope.
library;

/// The encoded QR matrix: `modules[y][x]` is true for a dark cell. Includes the
/// function patterns and the quiet zone is *not* added (renderers add margin).
class QrMatrix {
  QrMatrix(this.size, this.modules);
  final int size;
  final List<List<bool>> modules;
}

// Version table for EC level M: (dataCodewords, ecPerBlock, blockCount).
// Blocks are uniform for versions 1–7.
const List<List<int>> _versionM = [
  [16, 10, 1], // v1
  [28, 16, 1], // v2
  [44, 26, 1], // v3
  [64, 18, 2], // v4  (2 blocks × 32 data)
  [86, 24, 2], // v5  (2 × 43)
  [108, 16, 4], // v6 (4 × 27)
  [124, 18, 4], // v7 (4 × 31)
];

// Alignment-pattern centre coordinates per version (1-based version index).
const List<List<int>> _alignPositions = [
  [], // v1
  [6, 18],
  [6, 22],
  [6, 26],
  [6, 30],
  [6, 34],
  [6, 22, 38], // v7
];

// ---- GF(256) tables (primitive polynomial 0x11D) ----

final List<int> _gfExp = List<int>.filled(512, 0);
final List<int> _gfLog = List<int>.filled(256, 0);
bool _gfReady = false;

void _initGf() {
  if (_gfReady) return;
  var x = 1;
  for (var i = 0; i < 255; i++) {
    _gfExp[i] = x;
    _gfLog[x] = i;
    x <<= 1;
    if (x & 0x100 != 0) x ^= 0x11D;
  }
  for (var i = 255; i < 512; i++) {
    _gfExp[i] = _gfExp[i - 255];
  }
  _gfReady = true;
}

int _gfMul(int a, int b) {
  if (a == 0 || b == 0) return 0;
  return _gfExp[_gfLog[a] + _gfLog[b]];
}

/// Reed–Solomon generator polynomial of degree [n].
List<int> _rsGenerator(int n) {
  var poly = <int>[1];
  for (var i = 0; i < n; i++) {
    final next = List<int>.filled(poly.length + 1, 0);
    for (var j = 0; j < poly.length; j++) {
      next[j] ^= poly[j];
      next[j + 1] ^= _gfMul(poly[j], _gfExp[i]);
    }
    poly = next;
  }
  return poly;
}

/// Reed–Solomon error-correction codewords for [data] over GF(256), the QR
/// field. Exposed for verification against known vectors.
List<int> qrErrorCorrection(List<int> data, int ecCount) {
  _initGf();
  return _rsEncode(data, ecCount);
}

/// EC codewords for one data block.
List<int> _rsEncode(List<int> data, int ecCount) {
  final gen = _rsGenerator(ecCount);
  final res = List<int>.filled(ecCount, 0);
  for (final d in data) {
    final factor = d ^ res[0];
    for (var i = 0; i < ecCount - 1; i++) {
      res[i] = res[i + 1] ^ _gfMul(gen[i + 1], factor);
    }
    res[ecCount - 1] = _gfMul(gen[ecCount], factor);
  }
  return res;
}

/// Encode [text] (UTF-8 bytes) into a [QrMatrix].
QrMatrix encodeQr(String text) {
  _initGf();
  final bytes = _utf8(text);

  // Pick the smallest version that fits (2 bytes of mode/count/terminator
  // overhead in byte mode for versions 1–9).
  var version = -1;
  for (var v = 0; v < _versionM.length; v++) {
    if (bytes.length + 2 <= _versionM[v][0]) {
      version = v + 1;
      break;
    }
  }
  if (version == -1) {
    throw ArgumentError('QR payload too large for versions 1–7 (EC-M): '
        '${bytes.length} bytes');
  }
  final info = _versionM[version - 1];
  final totalData = info[0];
  final ecPerBlock = info[1];
  final blocks = info[2];

  // ---- bit stream: byte mode (0100), 8-bit count, data, terminator, pad ----
  final bits = <int>[];
  void putBits(int value, int len) {
    for (var i = len - 1; i >= 0; i--) {
      bits.add((value >> i) & 1);
    }
  }

  putBits(0x4, 4); // byte mode
  putBits(bytes.length, 8);
  for (final b in bytes) {
    putBits(b, 8);
  }
  // Terminator (up to 4 zero bits) + pad to a byte boundary.
  final capacityBits = totalData * 8;
  for (var i = 0; i < 4 && bits.length < capacityBits; i++) {
    bits.add(0);
  }
  while (bits.length % 8 != 0) {
    bits.add(0);
  }
  final codewords = <int>[];
  for (var i = 0; i < bits.length; i += 8) {
    var b = 0;
    for (var j = 0; j < 8; j++) {
      b = (b << 1) | bits[i + j];
    }
    codewords.add(b);
  }
  // Pad codewords (0xEC, 0x11 alternating).
  var pad = 0xEC;
  while (codewords.length < totalData) {
    codewords.add(pad);
    pad = pad == 0xEC ? 0x11 : 0xEC;
  }

  // ---- split into blocks, compute EC, interleave ----
  final dataBlocks = <List<int>>[];
  final ecBlocks = <List<int>>[];
  final perBlock = totalData ~/ blocks;
  for (var b = 0; b < blocks; b++) {
    final block = codewords.sublist(b * perBlock, (b + 1) * perBlock);
    dataBlocks.add(block);
    ecBlocks.add(_rsEncode(block, ecPerBlock));
  }
  final finalCodewords = <int>[];
  for (var i = 0; i < perBlock; i++) {
    for (final block in dataBlocks) {
      finalCodewords.add(block[i]);
    }
  }
  for (var i = 0; i < ecPerBlock; i++) {
    for (final block in ecBlocks) {
      finalCodewords.add(block[i]);
    }
  }

  // ---- module matrix ----
  return _buildMatrix(version, finalCodewords);
}

QrMatrix _buildMatrix(int version, List<int> codewords) {
  final size = 17 + version * 4;
  // null = unset, so data placement can skip function modules.
  final grid = List.generate(size, (_) => List<bool?>.filled(size, null));
  final reserved = List.generate(size, (_) => List<bool>.filled(size, false));

  void set(int x, int y, bool v) {
    grid[y][x] = v;
    reserved[y][x] = true;
  }

  void placeFinder(int ox, int oy) {
    for (var dy = -1; dy <= 7; dy++) {
      for (var dx = -1; dx <= 7; dx++) {
        final x = ox + dx, y = oy + dy;
        if (x < 0 || x >= size || y < 0 || y >= size) continue;
        final onBorder = dx == 0 || dx == 6 || dy == 0 || dy == 6;
        final inCore = dx >= 2 && dx <= 4 && dy >= 2 && dy <= 4;
        final dark = (dx >= 0 && dx <= 6 && dy >= 0 && dy <= 6) &&
            (onBorder || inCore);
        set(x, y, dark);
      }
    }
  }

  placeFinder(0, 0);
  placeFinder(size - 7, 0);
  placeFinder(0, size - 7);

  // Timing patterns.
  for (var i = 8; i < size - 8; i++) {
    if (!reserved[6][i]) set(i, 6, i.isEven);
    if (!reserved[i][6]) set(6, i, i.isEven);
  }

  // Alignment patterns.
  final centers = _alignPositions[version - 1];
  for (final cy in centers) {
    for (final cx in centers) {
      if (reserved[cy][cx]) continue; // skip overlaps with finders
      for (var dy = -2; dy <= 2; dy++) {
        for (var dx = -2; dx <= 2; dx++) {
          final ring = dx.abs() == 2 || dy.abs() == 2;
          final center = dx == 0 && dy == 0;
          set(cx + dx, cy + dy, ring || center);
        }
      }
    }
  }

  // Dark module + reserve format-info areas.
  set(8, size - 8, true);
  for (var i = 0; i < 9; i++) {
    if (!reserved[8][i]) reserved[8][i] = true;
    if (!reserved[i][8]) reserved[i][8] = true;
  }
  for (var i = 0; i < 8; i++) {
    reserved[8][size - 1 - i] = true;
    reserved[size - 1 - i][8] = true;
  }

  // ---- data placement (zigzag, upward/downward columns) ----
  var bitIndex = 0;
  final totalBits = codewords.length * 8;
  bool nextBit() {
    if (bitIndex >= totalBits) return false;
    final cw = codewords[bitIndex ~/ 8];
    final bit = (cw >> (7 - (bitIndex % 8))) & 1;
    bitIndex++;
    return bit == 1;
  }

  var upward = true;
  for (var col = size - 1; col > 0; col -= 2) {
    if (col == 6) col = 5; // skip the timing column
    for (var i = 0; i < size; i++) {
      final y = upward ? size - 1 - i : i;
      for (var c = 0; c < 2; c++) {
        final x = col - c;
        if (reserved[y][x]) continue;
        grid[y][x] = nextBit();
      }
    }
    upward = !upward;
  }

  // ---- masking: score all 8 masks, keep the best ----
  var bestScore = 1 << 30;
  List<List<bool>>? bestGrid;
  for (var mask = 0; mask < 8; mask++) {
    final trial = List.generate(
        size, (y) => List<bool>.generate(size, (x) => grid[y][x] ?? false));
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        if (reserved[y][x]) continue;
        if (_maskAt(mask, x, y)) trial[y][x] = !trial[y][x];
      }
    }
    _writeFormat(trial, reserved, size, mask);
    final score = _penalty(trial, size);
    if (score < bestScore) {
      bestScore = score;
      bestGrid = trial;
    }
  }
  // bestGrid already carries its format bits.
  return QrMatrix(size, bestGrid ?? _flatten(grid, size));
}

bool _maskAt(int mask, int x, int y) {
  switch (mask) {
    case 0:
      return (x + y) % 2 == 0;
    case 1:
      return y % 2 == 0;
    case 2:
      return x % 3 == 0;
    case 3:
      return (x + y) % 3 == 0;
    case 4:
      return (y ~/ 2 + x ~/ 3) % 2 == 0;
    case 5:
      return (x * y) % 2 + (x * y) % 3 == 0;
    case 6:
      return ((x * y) % 2 + (x * y) % 3) % 2 == 0;
    default:
      return ((x + y) % 2 + (x * y) % 3) % 2 == 0;
  }
}

// Format info: EC level M (0b00) + mask → 15-bit BCH with mask XOR.
void _writeFormat(List<List<bool>> g, List<List<bool>> reserved, int size,
    int mask) {
  const ecM = 0; // level M
  final data = (ecM << 3) | mask; // 5 bits
  var rem = data;
  for (var i = 0; i < 10; i++) {
    rem = (rem << 1) ^ (((rem >> 9) & 1) == 1 ? 0x537 : 0);
  }
  final bits = ((data << 10) | (rem & 0x3FF)) ^ 0x5412;

  for (var i = 0; i < 15; i++) {
    final bit = ((bits >> i) & 1) == 1;
    // Around the top-left finder.
    if (i < 6) {
      g[i][8] = bit;
    } else if (i < 8) {
      g[i + 1][8] = bit;
    } else {
      g[8][15 - i - 1] = bit;
    }
    // The mirrored copy.
    if (i < 8) {
      g[8][size - 1 - i] = bit;
    } else {
      g[size - 15 + i][8] = bit;
    }
  }
  g[size - 8][8] = true; // dark module
}

int _penalty(List<List<bool>> g, int size) {
  var score = 0;
  // Rule 1: runs of 5+ same-colour in rows and columns.
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      // horizontal
      if (x <= size - 5) {
        var run = 1;
        while (x + run < size && g[y][x + run] == g[y][x]) {
          run++;
        }
        if (run >= 5) {
          score += 3 + (run - 5);
          x += run - 1;
        }
      }
    }
  }
  for (var x = 0; x < size; x++) {
    var y = 0;
    while (y < size) {
      var run = 1;
      while (y + run < size && g[y + run][x] == g[y][x]) {
        run++;
      }
      if (run >= 5) score += 3 + (run - 5);
      y += run;
    }
  }
  // Rule 2: 2x2 blocks of the same colour.
  for (var y = 0; y < size - 1; y++) {
    for (var x = 0; x < size - 1; x++) {
      final c = g[y][x];
      if (g[y][x + 1] == c && g[y + 1][x] == c && g[y + 1][x + 1] == c) {
        score += 3;
      }
    }
  }
  return score;
}

List<List<bool>> _flatten(List<List<bool?>> g, int size) => List.generate(
    size, (y) => List<bool>.generate(size, (x) => g[y][x] ?? false));

// ---- helpers ----

/// True when [src] is a `qr:...` image source.
bool isQrSrc(String src) => src.startsWith('qr:');

/// The payload of a `qr:...` source.
String qrData(String src) => src.substring('qr:'.length);

List<int> _utf8(String s) {
  final out = <int>[];
  for (final rune in s.runes) {
    if (rune < 0x80) {
      out.add(rune);
    } else if (rune < 0x800) {
      out.add(0xC0 | (rune >> 6));
      out.add(0x80 | (rune & 0x3F));
    } else if (rune < 0x10000) {
      out.add(0xE0 | (rune >> 12));
      out.add(0x80 | ((rune >> 6) & 0x3F));
      out.add(0x80 | (rune & 0x3F));
    } else {
      out.add(0xF0 | (rune >> 18));
      out.add(0x80 | ((rune >> 12) & 0x3F));
      out.add(0x80 | ((rune >> 6) & 0x3F));
      out.add(0x80 | (rune & 0x3F));
    }
  }
  return out;
}
