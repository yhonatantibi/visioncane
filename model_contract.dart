/// The legacy Cityscapes model must never silently stand in for indoor parsing.
const indoorModelId = 'yolo26n-sem-ade20k';
const indoorAndroidAsset = 'assets/models/visioncane-indoor-v1.tflite';
const indoorAppleAsset = 'assets/models/visioncane-indoor-v1.mlpackage.zip';

List<String> readModelLabels(Map<Object?, Object?> metadata) {
  final raw = metadata['labels'] ?? metadata['names'];
  if (raw is List<Object?>) return raw.map((v) => v?.toString() ?? '').toList();
  if (raw is Map<Object?, Object?>) {
    final entries = raw.entries.toList()..sort((a, b) =>
      (int.tryParse(a.key.toString()) ?? -1).compareTo(int.tryParse(b.key.toString()) ?? -1));
    if (entries.indexed.every((e) => int.tryParse(e.$2.key.toString()) == e.$1)) {
      return entries.map((e) => e.value.toString()).toList();
    }
  }
  return [];
}

bool supportsIndoorContract(List<String> labels) {
  final names = labels.expand((s) => s.toLowerCase().split(',').map((v) => v.trim())).toSet();
  return labels.length == 150 && names.containsAll(['door', 'wall', 'floor', 'ceiling']);
}
