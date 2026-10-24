import '../lib/domain/model_contract.dart';
import '../lib/domain/scene_narrator.dart';
import '../lib/domain/spatial_scene.dart';
import '../lib/domain/speech_voice.dart';

void check(bool condition, String name) {
  if (!condition) throw StateError('FAIL: $name');
  print('PASS: $name');
}

SpatialFeature feature(String label, {double left = .4, double top = .3,
    double right = .6, double bottom = .7, bool structure = false, double? meters}) =>
  SpatialFeature(label: label, spokenLabel: label == 'door' ? 'דלת' : label == 'chair' ? 'כיסא' : label,
    box: ImageBox(left, top, right, bottom), structure: structure,
    depth: meters == null ? null : DepthEstimate(meters, 20, .1));
SpatialScene scene(int id, int at, List<SpatialFeature> features) =>
  SpatialScene(frameId: id, receivedAtMs: at, completedAtMs: at + 400, features: features, issues: []);

void main() {
  final door = feature('door', structure:true, meters:2);
  final chair = feature('chair', left:.05, right:.25);
  final narrator = SceneNarrator();
  var s = scene(1, 0, [door, chair]);
  narrator.observe(s);
  check(narrator.next(s, 500) == null, 'single-frame door is not automatically spoken');
  narrator.observe(s);
  check(narrator.stable.isEmpty, 'repeated callback is not independent visual evidence');
  s = scene(2, 1000, [door, chair]);
  narrator.observe(s);
  final first = narrator.next(s, 1500)!;
  check(first.reason == 'initial_overview' && first.text.contains('דלת') && first.text.contains('כיסא'),
    'first stable scene produces a compact overview');
  check(first.text.contains('שני מטרים') && first.text.contains('אין אומדן מרחק'),
    'overview keeps estimated and unknown distances distinct');
  check(!first.text.contains('יציאה') && !first.text.contains('פתוחה'), 'door never implies exit or open state');
  narrator.accepted(first, 1500);
  narrator.speechFinished(4000);
  s = scene(3, 5000, [door, chair]); narrator.observe(s);
  check(narrator.next(s, 5500) == null, 'speech completion starts the quiet interval');
  for (var id = 4; id <= 9; id++) { s = scene(id, id * 1000 + 2000, [door, chair]); narrator.observe(s); }
  check(narrator.next(s, 11500) == null && narrator.reason == 'scene_unchanged', 'unchanged scene is not read repeatedly');
  check(narrator.next(s, 20000) == null && narrator.reason == 'stale_scene', 'old snapshot cannot be narrated');
  narrator.reset();
  s = scene(10, 20000, [door]); narrator.observe(s);
  s = scene(11, 21000, [feature('door', left:.02, right:.15, structure:true)]); narrator.observe(s);
  check(narrator.stable.isEmpty, 'unrelated boxes do not count as one stable door');
  narrator.reset();
  s = scene(12, 22000, [door, chair]); narrator.observe(s);
  s = scene(13, 23000, [door, chair]); narrator.observe(s);
  final found = narrator.next(s, 23500, target:'door')!;
  check(found.features.length == 1 && found.features.single.label == 'door', 'door search does not narrate unrelated objects');
  check(SceneNarrator.overview(scene(1, 0, [])).contains('אין בכך אישור'), 'empty scene is not a clear path');
  final city = List.filled(19, 'wall');
  check(!supportsIndoorContract(city), 'observed legacy 19-class model is rejected');
  final labels = List.generate(150, (i) => 'class$i');
  labels[0] = 'wall'; labels[3] = 'floor'; labels[5] = 'ceiling'; labels[14] = 'door';
  check(supportsIndoorContract(labels), 'actual complete indoor metadata can pass');
  check(readModelLabels({'names': {'0':'wall', '2':'door'}}).isEmpty, 'sparse metadata cannot shift class IDs');
  final voices = localHebrewVoices([
    {'name':'he-il-language', 'locale':'he-IL', 'network_required':'0'},
    {'name':'he-il-x-hee-local', 'locale':'he-IL', 'network_required':'0'},
    {'name':'he-il-x-hec-network', 'locale':'he-IL', 'network_required':'1'},
  ], android:true);
  check(voices.first['name'] == 'he-il-x-hee-local' && voices.length == 2,
    'real diagnostic voices prefer named local voice and reject network voice');
}
