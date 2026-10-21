import '../lib/domain/spatial_scene.dart';

void verify(bool condition, String name) {
  if (!condition) throw StateError('FAIL: $name');
  print('PASS: $name');
}

void main() {
  const full = ImageBox(0, 0, 1, 1);
  final depth = MetricDepthGrid(30, 30, List.filled(900, 2.0));
  verify(depth.estimate(full)?.meters == 2, 'same-frame constant metric map samples two meters');
  verify(depth.estimate(full)!.speech.contains('שני מטרים'), 'spoken Hebrew distance uses words');
  verify(MetricDepthGrid(30, 30, List.filled(900, double.nan)).estimate(full) == null,
    'invalid depth never becomes a spoken number');
  verify(MetricDepthGrid(30, 30, [1]).estimate(full) == null,
    'mismatched depth shape rejected');
  final mixed = List.generate(900, (i) => i % 30 < 15 ? 1.0 : 9.0);
  verify(MetricDepthGrid(30, 30, mixed).estimate(full) == null,
    'foreground/background disagreement rejected');
  verify(MetricDepthGrid(2, 2, [1, 1, 1, 1]).estimate(full) == null,
    'repeated sample pixels do not pretend to be independent depth evidence');
  verify(const ImageBox(.01, .01, .2, .2).position.contains('בחלק העליון') &&
    const ImageBox(.8, .8, .95, .95).position.contains('מימין'), 'nine-cell image position');
  final structures = extractStructures(width: 30, height: 30, classes: List.filled(900, 0),
    labels: ['door', 'wall'], depth: depth);
  verify(structures.isNotEmpty && structures.every((f) => f.label == 'door' && f.depth?.meters == 2),
    'semantic IDs resolved from model metadata and associated with depth');
  verify(extractStructures(width: 30, height: 30, classes: List.filled(900, 150),
    labels: ['door'], depth: depth).isEmpty, 'unknown semantic IDs are not guessed');
  verify(structureKind('exit') == null && !structures.first.phrase.contains('יציאה'),
    'a door does not become a verified exit');
  final scene = SpatialScene(frameId: 7, receivedAtMs: 100, completedAtMs: 300,
    features: [for (var i = 0; i < 5; i++) const SpatialFeature(label: 'chair',
      spokenLabel: 'כיסא', box: full), structures.first], issues: []);
  verify(scene.freshAt(2600) && !scene.freshAt(2601) && !scene.freshAt(99),
    'freshness uses original event receipt, not inference completion');
  verify(scene.describe().contains('דלת') && scene.describe().contains('המרחק אינו זמין'),
    'description includes structure and explicitly unknown object distance');
  verify(depth.estimate(const ImageBox(-1, 0, 1, 1)) == null,
    'out-of-image box cannot sample unrelated depth');
}
