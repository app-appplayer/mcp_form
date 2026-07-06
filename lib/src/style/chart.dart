/// Format-agnostic chart geometry.
///
/// [FormChartBlock] data is turned into primitive shapes laid out in a
/// top-left origin, y-down coordinate box (SVG-native). The PDF renderer
/// flips y; the HTML renderer emits the primitives verbatim as SVG. Keeping
/// the geometry separate from output makes it unit-testable and shared.
library;

import 'dart:math' as math;

import 'package:mcp_bundle/mcp_bundle.dart';

import 'color_utils.dart';
import 'font_metrics.dart';

/// A normalised RGB colour (0..1 components).
typedef RgbColor = ({double r, double g, double b});

/// Default series palette used when a series declares no colour.
const List<String> kChartPalette = [
  '#4E79A7',
  '#F28E2B',
  '#59A14F',
  '#E15759',
  '#B07AA1',
  '#76B7B2',
  '#EDC948',
  '#FF9DA7',
];

RgbColor _paletteColor(int i) =>
    hexToRgb(kChartPalette[i % kChartPalette.length])!;

/// A single (category, value) datum.
class ChartPoint {
  ChartPoint(this.x, this.y);

  /// Category / x-axis label.
  final String x;

  /// Numeric value.
  final double y;
}

/// A named series of points with a colour.
class ChartSeries {
  ChartSeries(this.label, this.color, this.points);

  final String label;
  final RgbColor color;
  final List<ChartPoint> points;
}

/// Normalise [block].data into typed series.
///
/// Accepts two shapes per entry:
/// 1. A series map: `{label, color, points:[{x,y}, ...]}`.
/// 2. A bare point map (`{x|label, y|value}`) — collected into one default
///    series. This is the common shape for pie charts (one slice per entry).
List<ChartSeries> normaliseSeries(FormChartBlock block) {
  final out = <ChartSeries>[];
  final loosePoints = <ChartPoint>[];

  double num2(Object? v) =>
      v is num ? v.toDouble() : (double.tryParse('$v') ?? 0.0);

  ChartPoint pointOf(Map<dynamic, dynamic> m) {
    final x = (m['x'] ?? m['label'] ?? m['name'] ?? '').toString();
    final y = num2(m['y'] ?? m['value'] ?? m['count']);
    return ChartPoint(x, y);
  }

  for (final entry in block.data) {
    if (entry is Map && entry['points'] is List) {
      final pts = [
        for (final p in (entry['points'] as List))
          if (p is Map) pointOf(p),
      ];
      final color = hexToRgb(entry['color'] as String?) ?? _paletteColor(out.length);
      out.add(ChartSeries(
        (entry['label'] ?? 'Series ${out.length + 1}').toString(),
        color,
        pts,
      ));
    } else if (entry is Map) {
      loosePoints.add(pointOf(entry));
    }
  }

  if (loosePoints.isNotEmpty) {
    out.add(ChartSeries(block.title ?? 'Series', _paletteColor(out.length), loosePoints));
  }
  return out;
}

/// A filled rectangle (bar).
class ChartRect {
  ChartRect(this.x, this.y, this.w, this.h, this.color);
  final double x, y, w, h;
  final RgbColor color;
}

/// A connected poly-line (line series).
class ChartPolyline {
  ChartPolyline(this.color, this.points, this.width);
  final RgbColor color;
  final List<({double x, double y})> points;
  final double width;
}

/// A pie wedge. Angles in radians, 0 = 3 o'clock, sweeping clockwise.
class ChartWedge {
  ChartWedge(this.cx, this.cy, this.r, this.startRad, this.sweepRad, this.color);
  final double cx, cy, r, startRad, sweepRad;
  final RgbColor color;
}

/// A straight stroke (axis / gridline).
class ChartSegment {
  ChartSegment(this.x1, this.y1, this.x2, this.y2, this.color, this.width);
  final double x1, y1, x2, y2;
  final RgbColor color;
  final double width;
}

/// Horizontal anchoring for chart text.
enum ChartAnchor { start, middle, end }

/// A text label inside the chart box.
class ChartText {
  ChartText(this.x, this.y, this.text, this.size, this.anchor, this.color);
  final double x, y;
  final String text;
  final double size;
  final ChartAnchor anchor;
  final RgbColor color;
}

/// The full set of drawable primitives for one chart, in a [width] x [height]
/// box with top-left origin and y growing downward.
class ChartGeometry {
  ChartGeometry(this.width, this.height);
  final double width;
  final double height;
  final List<ChartRect> rects = [];
  final List<ChartPolyline> polylines = [];
  final List<ChartWedge> wedges = [];
  final List<ChartSegment> segments = [];
  final List<ChartText> texts = [];
}

const RgbColor _axisColor = (r: 0.4, g: 0.4, b: 0.4);
const RgbColor _inkColor = (r: 0.13, g: 0.13, b: 0.13);

/// Build geometry for [block] inside a [width] x [height] point box.
///
/// bar/line draw axes with min/max y ticks and category x labels; pie draws
/// proportional wedges with slice labels. A title (when present) and a legend
/// for multi-series bar/line charts are included.
ChartGeometry buildChartGeometry(
  FormChartBlock block, {
  required double width,
  required double height,
  FontMetrics metrics = defaultMetrics,
}) {
  final geo = ChartGeometry(width, height);
  final series = normaliseSeries(block);
  final type = block.chartType.toLowerCase();

  const titleSize = 11.0;
  const labelSize = 8.0;
  var top = 0.0;

  if (block.title != null && block.title!.isNotEmpty) {
    geo.texts.add(ChartText(
        width / 2, titleSize, block.title!, titleSize, ChartAnchor.middle, _inkColor));
    top = titleSize + 8;
  }

  if (series.isEmpty) {
    geo.texts.add(ChartText(width / 2, height / 2, 'No data', labelSize,
        ChartAnchor.middle, _axisColor));
    return geo;
  }

  if (type == 'pie') {
    _buildPie(geo, series, top, labelSize, metrics);
  } else {
    _buildAxisChart(geo, block, series, type, top, labelSize, metrics);
  }
  return geo;
}

void _buildPie(ChartGeometry geo, List<ChartSeries> series, double top,
    double labelSize, FontMetrics metrics) {
  // Flatten every point into a slice.
  final slices = <ChartPoint>[
    for (final s in series) ...s.points,
  ];
  final total = slices.fold<double>(0, (a, p) => a + p.y.abs());
  if (total <= 0) {
    geo.texts.add(ChartText(geo.width / 2, geo.height / 2, 'No data', labelSize,
        ChartAnchor.middle, _axisColor));
    return;
  }
  final cx = geo.width / 2;
  final cy = top + (geo.height - top) / 2;
  final r = math.min(geo.width, geo.height - top) / 2 * 0.7;

  var angle = -math.pi / 2; // start at 12 o'clock
  for (var i = 0; i < slices.length; i++) {
    final frac = slices[i].y.abs() / total;
    final sweep = frac * 2 * math.pi;
    final color = _paletteColor(i);
    geo.wedges.add(ChartWedge(cx, cy, r, angle, sweep, color));
    // Label at the wedge mid-angle, just outside the radius.
    final mid = angle + sweep / 2;
    final lx = cx + math.cos(mid) * (r + 6);
    final ly = cy + math.sin(mid) * (r + 6);
    final pct = (frac * 100).round();
    final anchor = math.cos(mid) >= 0 ? ChartAnchor.start : ChartAnchor.end;
    geo.texts.add(ChartText(
        lx, ly, '${slices[i].x} $pct%', labelSize, anchor, _inkColor));
    angle += sweep;
  }
}

void _buildAxisChart(
    ChartGeometry geo,
    FormChartBlock block,
    List<ChartSeries> series,
    String type,
    double top,
    double labelSize,
    FontMetrics metrics) {
  // Category axis = union of x labels in first-seen order.
  final categories = <String>[];
  for (final s in series) {
    for (final p in s.points) {
      if (!categories.contains(p.x)) categories.add(p.x);
    }
  }
  if (categories.isEmpty) return;

  // Value range.
  var maxY = block.yAxis?.max ?? double.negativeInfinity;
  var minY = block.yAxis?.min ?? double.infinity;
  for (final s in series) {
    for (final p in s.points) {
      if (p.y > maxY) maxY = p.y;
      if (p.y < minY) minY = p.y;
    }
  }
  if (!maxY.isFinite) maxY = 1;
  if (!minY.isFinite) minY = 0;
  if (minY > 0) minY = 0; // bars/lines baseline at zero
  if (maxY <= minY) maxY = minY + 1;

  // Reserve gutters: left for y ticks, bottom for x labels, top legend.
  final hasLegend = series.length > 1;
  final legendH = hasLegend ? labelSize + 6 : 0.0;
  final plotTop = top + legendH;
  const leftGutter = 34.0;
  const bottomGutter = 16.0;
  const plotLeft = leftGutter;
  final plotRight = geo.width - 6;
  final plotBottom = geo.height - bottomGutter;
  final plotW = plotRight - plotLeft;
  final plotH = plotBottom - plotTop;
  if (plotW <= 0 || plotH <= 0) return;

  double yToPx(double v) => plotBottom - (v - minY) / (maxY - minY) * plotH;

  // Axes.
  geo.segments
    ..add(ChartSegment(plotLeft, plotTop, plotLeft, plotBottom, _axisColor, 0.7))
    ..add(ChartSegment(
        plotLeft, plotBottom, plotRight, plotBottom, _axisColor, 0.7));

  // Y min / max tick labels.
  geo.texts
    ..add(ChartText(plotLeft - 4, yToPx(maxY) + labelSize * 0.35,
        _fmt(maxY), labelSize, ChartAnchor.end, _axisColor))
    ..add(ChartText(plotLeft - 4, yToPx(minY) + labelSize * 0.35,
        _fmt(minY), labelSize, ChartAnchor.end, _axisColor));

  // Category slot width.
  final slot = plotW / categories.length;

  // X category labels.
  for (var c = 0; c < categories.length; c++) {
    final cxLabel = plotLeft + slot * (c + 0.5);
    geo.texts.add(ChartText(cxLabel, plotBottom + labelSize + 2, categories[c],
        labelSize, ChartAnchor.middle, _axisColor));
  }

  if (type == 'line') {
    for (final s in series) {
      final pts = <({double x, double y})>[];
      for (final p in s.points) {
        final ci = categories.indexOf(p.x);
        if (ci < 0) continue;
        pts.add((x: plotLeft + slot * (ci + 0.5), y: yToPx(p.y)));
      }
      if (pts.isNotEmpty) geo.polylines.add(ChartPolyline(s.color, pts, 1.4));
    }
  } else {
    // Bar (default). Cluster bars within each category slot.
    final n = series.length;
    final groupW = slot * 0.7;
    final barW = groupW / n;
    final groupStart = (slot - groupW) / 2;
    for (var c = 0; c < categories.length; c++) {
      for (var si = 0; si < n; si++) {
        final p = series[si].points.where((p) => p.x == categories[c]);
        if (p.isEmpty) continue;
        final v = p.first.y;
        final x = plotLeft + slot * c + groupStart + barW * si;
        final yTop = yToPx(v.clamp(minY, maxY).toDouble());
        final yBase = yToPx(0 < minY ? minY : 0);
        geo.rects.add(ChartRect(
            x, math.min(yTop, yBase), barW * 0.9, (yBase - yTop).abs(),
            series[si].color));
      }
    }
  }

  // Legend (multi-series).
  if (hasLegend) {
    var lx = plotLeft;
    final ly = top + labelSize;
    for (final s in series) {
      geo.rects.add(ChartRect(lx, ly - labelSize * 0.7, labelSize * 0.8,
          labelSize * 0.8, s.color));
      geo.texts.add(ChartText(lx + labelSize, ly, s.label, labelSize,
          ChartAnchor.start, _axisColor));
      lx += labelSize + 6 + _approxWidth(s.label, labelSize, metrics) + 10;
    }
  }
}

double _approxWidth(String text, double size, FontMetrics metrics) =>
    measureText(text, size, metrics: metrics);

/// Compact numeric label: drop a trailing `.0`, otherwise one decimal.
String _fmt(double v) {
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  return v.toStringAsFixed(1);
}
