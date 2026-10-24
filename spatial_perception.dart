import 'dart:typed_data';
import 'dart:async';
import 'dart:io';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';
import '../domain/labels.dart';
import '../domain/spatial_scene.dart';
import '../domain/model_contract.dart';

/// One camera, two additional model instances. Both receive the SAME JPEG as
/// the detections in this stream event. Calls are serialized to limit GPU load;
/// perception is simultaneous at the scene level, not two competing cameras.
class SpatialPerception {
  YOLO? _depth, _semantic;
  List<String> _labels = [];
  Future<void>? _preparing;
  Completer<void>? _idle;
  bool? _gpuAtLoad;
  bool _prepared = false, _busy = false, _closed = false;
  bool depthReady = false, structureReady = false;
  String depthStatus = 'טרם נטען', structureStatus = 'טרם נטען';
  bool get doorSupported => structureReady && _labels.any((s) => structureKind(s) == 'door');
  int processed = 0, droppedBusy = 0;
  final List<String> setupIssues = [];
  bool get prepared => _prepared;
  bool get busy => _busy;
  String get structureAsset => Platform.isIOS ? indoorAppleAsset : indoorAndroidAsset;
  Map<String, Object?> get diagnostics => {
    'depth_model': 'yolo26n-depth', 'structure_model': indoorModelId,
    'structure_asset': structureAsset, 'model_contract': 'ADE20K_150_door_wall_floor_ceiling',
    'depth_ready': depthReady, 'structure_ready': structureReady,
    'depth_status': depthStatus, 'structure_status': structureStatus,
    'door_category_available': doorSupported,
    'structure_categories': _labels.where((s) => structureKind(s) != null).toList(),
    'semantic_label_count': _labels.length, 'processed_scenes': processed,
    'gpu_requested_at_load': _gpuAtLoad,
    'busy_frames_skipped': droppedBusy, 'setup_issues': setupIssues,
    'depth_scope': 'uncalibrated_model_estimate_meters',
    'position_scope': 'upright_camera_image_3_by_3_grid_not_body_bearing',
  };

  Future<void> prepare({required bool useGpu}) => _preparing ??= _prepare(useGpu);
  Future<void> _prepare(bool useGpu) async {
    _gpuAtLoad = useGpu;
    _prepared = true; // Object descriptions remain available during model preparation.
    await Future.wait([_prepareDepth(useGpu), _prepareStructure(useGpu)]);
  }

  Future<void> retry({required bool useGpu}) async {
    if (_closed || _busy) return;
    await _preparing;
    if (_closed || _busy) return;
    setupIssues.clear();
    if (!depthReady) { await _depth?.dispose(); _depth = null; }
    if (!structureReady) { await _semantic?.dispose(); _semantic = null; }
    _preparing = _prepare(useGpu);
    await _preparing;
  }

  Future<void> _prepareDepth(bool useGpu) async {
    if (depthReady || _closed) return;
    depthStatus = 'מוריד או טוען מודל מרחק';
    try {
      _depth = YOLO(modelPath: 'yolo26n-depth', task: YOLOTask.depth,
        useGpu: useGpu, useMultiInstance: true);
      depthReady = await _depth!.loadModel();
      depthStatus = depthReady ? 'מוכן — אומדן לא מכויל' : 'הטעינה נכשלה';
      if (!depthReady) setupIssues.add('מודל המרחק לא נטען');
    } catch (error) { depthStatus = 'הטעינה נכשלה'; setupIssues.add('מודל המרחק: $error'); }
  }

  Future<void> _prepareStructure(bool useGpu) async {
    if (structureReady || _closed) return;
    structureStatus = 'מוריד או טוען מודל דלתות וקירות';
    if (_closed) return;
    try {
      final metadata = await YOLO.inspectModel(structureAsset);
      _labels = readModelLabels(metadata);
      if (!supportsIndoorContract(_labels)) {
        throw StateError('מודל החדר אינו תואם: נדרשות 150 קטגוריות ובהן דלת, קיר, רצפה ותקרה. יש להתקין בנייה הכוללת את מודל החדר.');
      }
      if (_closed) return;
      _semantic = YOLO(modelPath: structureAsset, task: YOLOTask.semantic,
        useGpu: useGpu, useMultiInstance: true);
      structureReady = await _semantic!.loadModel();
      structureStatus = !structureReady ? 'הטעינה נכשלה'
          : doorSupported ? 'מוכן — כולל קטגוריית דלת' : 'מוכן, אך ללא קטגוריית דלת';
      if (!structureReady) setupIssues.add('מודל מבנה המרחב לא נטען');
    } catch (error) { structureStatus = 'הטעינה נכשלה'; setupIssues.add('מודל מבנה המרחב: $error'); }
  }

  Future<SpatialScene?> analyse({required Uint8List jpeg,
    required List<YOLOResult> detections, required int frameId,
    required int receivedAtMs, required int Function() now}) async {
    if (_closed || !_prepared) return null;
    if (_busy) { droppedBusy++; return null; }
    _busy = true;
    _idle = Completer<void>();
    final issues = [...setupIssues];
    try {
      MetricDepthGrid? grid;
      if (depthReady) {
        try {
          final result = await _depth!.predict(jpeg);
          final raw = result['depthMap'];
          if (raw is Map<Object?, Object?>) {
            final map = YOLODepthMap.fromMap(raw);
            final candidate = MetricDepthGrid(map.width, map.height, map.values);
            if (candidate.valid) grid = candidate;
          }
          if (grid == null) issues.add('אין מפת מרחק תקפה לתמונה הזאת');
        } catch (error) { issues.add('אומדן המרחק נכשל: $error'); }
      }
      if (_closed) return null;
      final features = <SpatialFeature>[];
      for (final detection in detections) {
        final b = detection.normalizedBox;
        final box = ImageBox(b.left, b.top, b.right, b.bottom);
        if (!box.valid || !detection.confidence.isFinite || detection.confidence < .65) continue;
        features.add(SpatialFeature(label: detection.className,
          spokenLabel: displayLabel(detection.className), box: box, depth: grid?.estimate(box)));
      }
      if (structureReady) {
        try {
          final result = await _semantic!.predict(jpeg);
          final raw = result['semanticMask'];
          if (raw is Map<Object?, Object?>) {
            final mask = YOLOSemanticMask.fromMap(raw);
            features.addAll(extractStructures(width: mask.width, height: mask.height,
              classes: mask.classMap, labels: _labels, depth: grid));
          } else { issues.add('אין מפת מבנה תקפה לתמונה הזאת'); }
        } catch (error) { issues.add('סיווג המרחב נכשל: $error'); }
      }
      if (_closed) return null;
      processed++;
      return SpatialScene(frameId: frameId, receivedAtMs: receivedAtMs,
        completedAtMs: now(), features: features, issues: issues);
    } finally { _busy = false; _idle?.complete(); }
  }

  Future<void> dispose() async {
    _closed = true;
    await _preparing?.catchError((Object _) {});
    if (_busy) await _idle?.future;
    await _depth?.dispose();
    await _semantic?.dispose();
  }
}
