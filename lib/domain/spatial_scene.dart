import 'dart:math' as math;

class ImageBox {
  const ImageBox(this.left, this.top, this.right, this.bottom);
  final double left, top, right, bottom;
  double get x => (left + right) / 2;
  double get y => (top + bottom) / 2;
  bool get valid => [left, top, right, bottom].every((v) => v.isFinite && v >= 0 && v <= 1)
      && right > left && bottom > top;
  String get cell => '${x < 1/3 ? 'left' : x > 2/3 ? 'right' : 'center'}:'
      '${y < 1/3 ? 'upper' : y > 2/3 ? 'lower' : 'middle'}';
  String get position => '${x < 1/3 ? 'משמאל בתמונה' : x > 2/3 ? 'מימין בתמונה' : 'במרכז התמונה'}, '
      '${y < 1/3 ? 'בחלק העליון' : y > 2/3 ? 'בחלק התחתון' : 'בחלק האמצעי'}';
}

class DepthEstimate {
  const DepthEstimate(this.meters, this.sampleCount, this.spreadMeters);
  final double meters, spreadMeters;
  final int sampleCount;
  String get speech {
    final halves = (meters * 2).round();
    const phrases = {0: 'פחות מחצי מטר', 1: 'חצי מטר', 2: 'מטר',
      3: 'מטר וחצי', 4: 'שני מטרים', 5: 'שניים וחצי מטרים',
      6: 'שלושה מטרים', 7: 'שלושה וחצי מטרים',
      8: 'ארבעה מטרים', 9: 'ארבעה וחצי מטרים',
      10: 'חמישה מטרים', 11: 'חמישה וחצי מטרים',
      12: 'שישה מטרים', 13: 'שישה וחצי מטרים',
      14: 'שבעה מטרים', 15: 'שבעה וחצי מטרים',
      16: 'שמונה מטרים', 17: 'שמונה וחצי מטרים',
      18: 'תשעה מטרים', 19: 'תשעה וחצי מטרים', 20: 'עשרה מטרים'};
    return 'במרחק משוער של ${phrases[halves] ?? 'יותר מעשרה מטרים'}';
  }
}

/// Model estimates in meters, not sensor readings or validated safe distances.
class MetricDepthGrid {
  MetricDepthGrid(this.width, this.height, this.values);
  final int width, height;
  final List<double> values;
  bool get valid => width > 0 && height > 0 && width * height <= 4000000
      && values.length == width * height;

  DepthEstimate? estimate(ImageBox box, {bool Function(double, double)? accepts}) {
    if (!valid || !box.valid) return null;
    final valuesInBox = <double>[];
    final used = <int>{};
    var acceptedLocations = 0;
    // Sample the central 60% to reduce background contamination at box edges.
    for (var row = 0; row < 7; row++) {
      for (var col = 0; col < 7; col++) {
        final x = box.left + (box.right - box.left) * (0.2 + 0.6 * col / 6);
        final y = box.top + (box.bottom - box.top) * (0.2 + 0.6 * row / 6);
        final index = (math.min(height - 1, (y * height).floor()) * width
            + math.min(width - 1, (x * width).floor())).toInt();
        if (!used.add(index) || (accepts != null && !accepts(x, y))) continue;
        acceptedLocations++;
        final value = values[index];
        if (value.isFinite && value >= 0.2 && value <= 30) valuesInBox.add(value);
      }
    }
    if (valuesInBox.length < 9 || valuesInBox.length < acceptedLocations * 0.6) return null;
    valuesInBox.sort();
    final median = valuesInBox[valuesInBox.length ~/ 2];
    final spread = valuesInBox[(valuesInBox.length * .75).floor()]
        - valuesInBox[(valuesInBox.length * .25).floor()];
    if (spread > math.max(0.3, median * 0.4)) return null;
    return DepthEstimate(median, valuesInBox.length, spread);
  }
}

class SpatialFeature {
  const SpatialFeature({required this.label, required this.spokenLabel,
    required this.box, this.depth, this.structure = false});
  final String label, spokenLabel;
  final ImageBox box;
  final DepthEstimate? depth;
  final bool structure;
  String get key => '$label:${box.cell}';
  String get phrase => '$spokenLabel ${box.position}, ${depth?.speech ?? 'המרחק אינו זמין'}';
}

class SpatialScene {
  SpatialScene({required this.frameId, required this.receivedAtMs,
    required this.completedAtMs, required this.features, required this.issues});
  final int frameId, receivedAtMs, completedAtMs;
  final List<SpatialFeature> features;
  final List<String> issues;
  bool freshAt(int nowMs) => nowMs >= receivedAtMs && nowMs - receivedAtMs <= 2500;
  List<SpatialFeature> get ordered => [...features]..sort((a, b) {
    final doorA = a.label == 'door' ? 0 : 1;
    final doorB = b.label == 'door' ? 0 : 1;
    if (doorA != doorB) return doorA.compareTo(doorB);
    if (a.structure != b.structure) return a.structure ? 1 : -1;
    return (a.depth?.meters ?? double.infinity).compareTo(b.depth?.meters ?? double.infinity);
  });
  String describe({int limit = 4}) {
    if (features.isEmpty) return 'אין כרגע פרטים ברורים מספיק לתיאור. אין בכך אישור שהדרך פנויה.';
    final items = ordered;
    final structures = items.where((f) => f.structure).take(1).toList();
    final selection = [...structures, ...items.where((f) => !structures.contains(f))].take(limit);
    final selected = selection.map((f) => f.phrase).join('. ');
    final remaining = items.length > limit ? ' פרטים נוספים מופיעים ברשימה.' : '';
    return '$selected.$remaining';
  }
}

String? structureKind(String label) {
  final names = label.toLowerCase().split(',').map((s) => s.trim());
  for (final name in names) {
    if (name == 'door' || name == 'doorway' || name == 'double door') return 'door';
    if (name == 'wall' || name.startsWith('wall-')) return 'wall';
    if (name == 'floor' || name.startsWith('floor-')) return 'floor';
    if (name == 'ceiling') return 'ceiling';
    if (name == 'stairs' || name == 'stairway' || name == 'staircase') return 'stairs';
    if (name == 'window' || name == 'windowpane') return 'window';
  }
  return null;
}

class _Region {
  _Region(this.kind, this.classIndex);
  final String kind;
  final int classIndex;
  int count = 0, left = 1 << 30, top = 1 << 30, right = 0, bottom = 0;
  void add(int x, int y) {
    count++; left = math.min(left, x); top = math.min(top, y);
    right = math.max(right, x + 1); bottom = math.max(bottom, y + 1);
  }
}

/// Read semantic IDs only through the actual model's metadata, never a guessed ADE mapping.
List<SpatialFeature> extractStructures({required int width, required int height,
  required List<int> classes, required List<String> labels, MetricDepthGrid? depth}) {
  if (width <= 0 || height <= 0 || width * height > 4000000 || classes.length != width * height) return [];
  final regions = <String, _Region>{};
  final kinds = [for (final label in labels) structureKind(label)];
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final index = classes[y * width + x];
      if (index < 0 || index >= kinds.length || kinds[index] == null) continue;
      final kind = kinds[index]!;
      final sector = math.min(2, x * 3 ~/ width);
      final region = regions.putIfAbsent('$index:$sector', () => _Region(kind, index));
      region.add(x, y);
    }
  }
  const hebrew = {'door': 'דלת', 'wall': 'קיר', 'floor': 'רצפה',
    'ceiling': 'תקרה', 'stairs': 'מדרגות', 'window': 'חלון'};
  return regions.values.where((r) => r.count >= math.max(20, width * height * .005)).map((r) {
    final box = ImageBox(r.left / width, r.top / height, r.right / width, r.bottom / height);
    return SpatialFeature(label: r.kind, spokenLabel: hebrew[r.kind]!, box: box, structure: true,
      depth: depth?.estimate(box, accepts: (x, y) =>
        classes[(math.min(height - 1, (y * height).floor()) * width
          + math.min(width - 1, (x * width).floor())).toInt()] == r.classIndex));
  }).toList();
}
