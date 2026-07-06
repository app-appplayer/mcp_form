/// Code 128 (subset B) barcode encoding — self-contained, no dependencies.
///
/// A document can embed a barcode by using a [FormImageBlock] whose `src` is
/// `barcode:DATA` (e.g. `barcode:INV-2026-0042`). Renderers expand the data into
/// a module bitmap and draw it as vertical bars (PDF rectangles, HTML SVG). Code
/// 128B covers the printable ASCII range (space..`~`), which suits invoice
/// numbers, SKUs, shipping references and the like.
library;

/// The 107 Code 128 symbol patterns (values 0..106), each six module widths
/// (bar, space, bar, space, bar, space) summing to 11 — except the stop pattern
/// (value 106) which is the seven-module `2331112`. Authoritative table from the
/// Code 128 specification.
const List<String> _patterns = [
  '212222', '222122', '222221', '121223', '121322', '131222', '122213',
  '122312', '132212', '221213', '221312', '231212', '112232', '122132',
  '122231', '113222', '123122', '123221', '223211', '221132', '221231',
  '213212', '223112', '312131', '311222', '321122', '321221', '312212',
  '322112', '322211', '212123', '212321', '232121', '111323', '131123',
  '131321', '112313', '132113', '132311', '211313', '231113', '231311',
  '112133', '112331', '132131', '113123', '113321', '133121', '313121',
  '211331', '231131', '213113', '213311', '213131', '311123', '311321',
  '331121', '312113', '312311', '332111', '314111', '221411', '431111',
  '111224', '111422', '121124', '121421', '141122', '141221', '112214',
  '112412', '122114', '122411', '142112', '142211', '241211', '221114',
  '413111', '241112', '134111', '111242', '121142', '121241', '114212',
  '124112', '124211', '411212', '421112', '421211', '212141', '214121',
  '412121', '111143', '111341', '131141', '114113', '114311', '411113',
  '411311', '113141', '114131', '311141', '411131', '211412', '211214',
  '211232', '2331112', // 103 Start A, 104 Start B, 105 Start C, 106 Stop
];

const int _startB = 104;
const int _stop = 106;

/// The result of encoding a string as Code 128B.
class Barcode128 {
  const Barcode128(this.symbolValues, this.modules);

  /// The symbol value sequence: start, data..., checksum, stop.
  final List<int> symbolValues;

  /// The unit-module bitmap, one bool per narrowest bar width; true = dark.
  final List<bool> modules;

  /// The number of unit modules across the symbol (excluding quiet zones).
  int get width => modules.length;
}

/// Encode [data] as Code 128 subset B. Characters outside the printable range
/// (32..126) are replaced with a space so the symbol stays well-formed.
Barcode128 encodeCode128B(String data) {
  final values = <int>[_startB];
  var weightedSum = _startB; // start carries weight 1
  var position = 1;
  for (final rune in data.runes) {
    final cp = (rune < 32 || rune > 126) ? 32 : rune;
    final value = cp - 32; // subset B: value = ASCII - 32
    values.add(value);
    weightedSum += value * position;
    position++;
  }
  final checksum = weightedSum % 103;
  values.add(checksum);
  values.add(_stop);

  final modules = <bool>[];
  for (final v in values) {
    final pattern = _patterns[v];
    var dark = true; // each pattern starts with a bar
    for (final ch in pattern.codeUnits) {
      final runLength = ch - 0x30; // '0'..'9'
      for (var i = 0; i < runLength; i++) {
        modules.add(dark);
      }
      dark = !dark;
    }
  }
  return Barcode128(values, modules);
}

/// True when [src] is a `barcode:...` image source; the payload is everything
/// after the prefix.
bool isBarcodeSrc(String src) => src.startsWith('barcode:');

/// The payload of a `barcode:...` source.
String barcodeData(String src) => src.substring('barcode:'.length);
