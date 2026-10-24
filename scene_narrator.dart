import 'spatial_scene.dart';

/// Describes evidence in the current camera view. Never infers a room type,
/// traversable route, exit, or open/closed door from an object label.
class SceneNarrator {
  SpatialScene? _previous;
  List<SpatialFeature> _stable = [];
  final Map<String, int> _announced = {};
  int _lastSpeech = -10000;
  bool _overviewSent = false;
  String reason = 'waiting_for_scene';

  void reset() {
    _previous = null;
    _stable = [];
    _announced.clear();
    _lastSpeech = -10000;
    _overviewSent = false;
    reason = 'waiting_for_scene';
  }

  void observe(SpatialScene scene) {
    if (_previous?.frameId == scene.frameId) return;
    final previous = _previous;
    _stable = previous != null && scene.receivedAtMs >= previous.receivedAtMs &&
        scene.receivedAtMs - previous.receivedAtMs <= 2200
        ? scene.features.where((f) => previous.features.any((old) =>
            old.label == f.label && overlap(old.box, f.box) >= .25)).toList()
        : [];
    _previous = scene;
  }

  List<SpatialFeature> get stable => List.unmodifiable(_stable);

  Narration? next(SpatialScene scene, int now, {String? target}) {
    if (!scene.freshAt(now)) { reason = 'stale_scene'; return null; }
    if (_previous?.frameId != scene.frameId) { reason = 'unobserved_scene'; return null; }
    if (now - _lastSpeech < 6000) { reason = 'speech_interval'; return null; }
    _announced.removeWhere((_, at) => now - at > 60000);
    final candidates = _stable.where((f) => target == null
        ? !const ['wall', 'floor', 'ceiling'].contains(f.label)
        : f.label == target).toList()..sort(_priority);
    if (candidates.isEmpty) { reason = 'no_stable_relevant_features'; return null; }
    final changed = candidates.where((f) => !_announced.containsKey(_key(f))).toList();
    if (changed.isEmpty) { reason = 'scene_unchanged'; return null; }
    final selected = changed.take(!_overviewSent && target == null ? 3 : 2).toList();
    reason = target != null ? 'target_found' : !_overviewSent ? 'initial_overview' : 'scene_change';
    return Narration(describeFeatures(selected,
      prefix: target != null ? 'זוהה בתמונה' : !_overviewSent ? 'סקירה קצרה' : 'עדכון'),
      selected, reason);
  }

  void accepted(Narration narration, int now) {
    _overviewSent = true;
    _lastSpeech = now;
    for (final feature in narration.features) { _announced[_key(feature)] = now; }
  }

  void speechFinished(int now) { _lastSpeech = now; }

  // Quantize only for repeat suppression, never as a measured distance.
  String _key(SpatialFeature f) => '${f.label}:${f.box.cell.split(':').first}:'
      '${f.depth == null ? 'unknown' : (f.depth!.meters / 1.5).floor()}';

  static String overview(SpatialScene scene, {int limit = 4}) {
    final ranked = scene.features.where((f) => f.box.valid).toList()..sort(_priority);
    final selected = <SpatialFeature>[];
    for (final f in ranked) {
      if (selected.any((other) => other.label == f.label &&
          (f.structure && const ['wall', 'floor', 'ceiling'].contains(f.label) ||
            overlap(other.box, f.box) > .6))) continue;
      selected.add(f);
      if (selected.length == limit) break;
    }
    return describeFeatures(selected, prefix: 'בתמונה שלפניך');
  }

  static String describeFeatures(List<SpatialFeature> features, {required String prefix}) {
    if (features.isEmpty) return 'לא זוהו כרגע פרטים ברורים. אין בכך אישור שהדרך פנויה.';
    final phrases = features.map((f) {
      final side = f.box.x < 1/3 ? 'משמאל' : f.box.x > 2/3 ? 'מימין' : 'במרכז';
      final vertical = f.box.y > 2/3 ? ', בחלק התחתון של התמונה'
          : f.box.y < 1/3 ? ', בחלק העליון של התמונה' : '';
      return '${f.spokenLabel} $side$vertical${f.depth == null ? '' : ', ${f.depth!.speech}'}';
    }).join('. ');
    final unknown = features.any((f) => f.depth == null) ? ' לחלק מהפרטים אין אומדן מרחק.' : '';
    return '$prefix: $phrases.$unknown';
  }

  static int _priority(SpatialFeature a, SpatialFeature b) {
    int rank(SpatialFeature f) {
      if (f.label == 'stairs') return 0;
      if (f.label == 'door') return 1;
      if (!f.structure && f.depth != null && f.depth!.meters < 2 && f.box.x > .25 && f.box.x < .75) return 2;
      if (!f.structure) return 3;
      if (f.label == 'window') return 4;
      return 5;
    }
    final order = rank(a).compareTo(rank(b));
    return order != 0 ? order : (a.depth?.meters ?? 100).compareTo(b.depth?.meters ?? 100);
  }
}

class Narration {
  const Narration(this.text, this.features, this.reason);
  final String text, reason;
  final List<SpatialFeature> features;
}

double overlap(ImageBox a, ImageBox b) {
  if (!a.valid || !b.valid) return 0;
  final left = a.left > b.left ? a.left : b.left;
  final top = a.top > b.top ? a.top : b.top;
  final right = a.right < b.right ? a.right : b.right;
  final bottom = a.bottom < b.bottom ? a.bottom : b.bottom;
  if (right <= left || bottom <= top) return 0;
  final intersection = (right - left) * (bottom - top);
  return intersection / ((a.right - a.left) * (a.bottom - a.top) +
      (b.right - b.left) * (b.bottom - b.top) - intersection);
}
