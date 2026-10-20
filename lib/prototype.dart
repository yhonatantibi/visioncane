const prototypeVersion = '0.2.0';

/// Camera-image coordinates only: these are NOT body or navigation directions.
enum ImageSector { left, center, right }

ImageSector sectorFor(double normalizedCenterX) {
  if (normalizedCenterX < 0.35) return ImageSector.left;
  if (normalizedCenterX > 0.65) return ImageSector.right;
  return ImageSector.center;
}

String sectorText(ImageSector sector) => switch (sector) {
  ImageSector.left => 'משמאל בתמונה',
  ImageSector.center => 'במרכז התמונה',
  ImageSector.right => 'מימין בתמונה',
};

class SceneItem {
  const SceneItem({required this.label, required this.confidence, required this.centerX});
  final String label;
  final double confidence;
  final double centerX;
  bool get valid => label.isNotEmpty && confidence.isFinite &&
      confidence >= 0 && confidence <= 1 && centerX.isFinite &&
      centerX >= 0 && centerX <= 1;
  ImageSector get sector => sectorFor(centerX);
  String get key => '$label:${sector.name}';
}

class _Presence {
  _Presence(this.item, this.firstMs, this.lastMs);
  SceneItem item;
  int firstMs;
  int lastMs;
  int hits = 1;
}

/// Conservative announcement smoothing, not multi-object identity tracking.
/// Requires stable high-confidence observations; never infers distance or safety.
class AnnouncementPolicy {
  final Map<String, _Presence> _present = {};
  final Map<String, int> _spokenAt = {};
  int? _lastSpeechMs;
  static const minimumConfidence = 0.65;
  static const stabilityMs = 700;
  static const maxGapMs = 350;
  static const globalCooldownMs = 3500;
  static const repeatCooldownMs = 12000;

  void observe(Iterable<SceneItem> items, int nowMs) {
    _present.removeWhere((_, p) => nowMs - p.lastMs > maxGapMs);
    final unique = <String, SceneItem>{};
    for (final item in items) {
      if (!item.valid || item.confidence < minimumConfidence) continue;
      final old = unique[item.key];
      if (old == null || old.confidence < item.confidence) unique[item.key] = item;
    }
    for (final item in unique.values) {
      final old = _present[item.key];
      if (old == null) {
        _present[item.key] = _Presence(item, nowMs, nowMs);
      } else {
        old.item = item;
        old.lastMs = nowMs;
        old.hits++;
      }
    }
    _spokenAt.removeWhere((_, at) => nowMs - at > 60000);
  }

  SceneItem? next(int nowMs) {
    if (_lastSpeechMs != null && nowMs - _lastSpeechMs! < globalCooldownMs) return null;
    final candidates = _present.values.where((p) =>
      nowMs - p.lastMs <= maxGapMs && p.hits >= 3 &&
      nowMs - p.firstMs >= stabilityMs &&
      (!_spokenAt.containsKey(p.item.key) || nowMs - _spokenAt[p.item.key]! >= repeatCooldownMs)
    ).toList()..sort((a, b) {
      final centerA = a.item.sector == ImageSector.center ? 1 : 0;
      final centerB = b.item.sector == ImageSector.center ? 1 : 0;
      final centerOrder = centerB.compareTo(centerA);
      return centerOrder != 0 ? centerOrder : b.item.confidence.compareTo(a.item.confidence);
    });
    return candidates.isEmpty ? null : candidates.first.item;
  }

  void markSpoken(SceneItem item, int nowMs) {
    _spokenAt[item.key] = nowMs;
    _lastSpeechMs = nowMs;
  }

  void reset() {
    _present.clear();
    _spokenAt.clear();
    _lastSpeechMs = null;
  }
}
