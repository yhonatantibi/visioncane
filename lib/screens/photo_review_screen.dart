import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';
import '../domain/prototype.dart';
import '../domain/spatial_scene.dart';
import '../services/local_speech.dart';
import '../services/report_export.dart';
import '../services/spatial_perception.dart';

/// Explicitly historical image review, never used as a live navigation scene.
class PhotoReviewScreen extends StatefulWidget {
  const PhotoReviewScreen({super.key});
  @override
  State<PhotoReviewScreen> createState() => _PhotoReviewScreenState();
}

class _PhotoReviewScreenState extends State<PhotoReviewScreen> with WidgetsBindingObserver {
  final _spatial = SpatialPerception();
  final _speech = LocalSpeech();
  final _clock = Stopwatch()..start();
  final _notes = TextEditingController();
  YOLO? _detector;
  Uint8List? _image;
  SpatialScene? _scene;
  bool _busy = false, _speaking = false, _foreground = true;
  bool _detectorReady = false;
  String _status = 'בחר תמונת JPEG או PNG מהמכשיר';
  int _run = 0;
  Completer<void>? _idle;

  @override
  void initState() { super.initState(); WidgetsBinding.instance.addObserver(this); }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) unawaited(_speech.stop().catchError((Object _) {}));
  }
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notes.dispose();
    unawaited(_speech.stop().catchError((Object _) {}));
    unawaited(_cleanup());
    super.dispose();
  }
  Future<void> _cleanup() async {
    await _idle?.future;
    await _detector?.dispose();
    await _spatial.dispose();
  }

  Future<void> _choose() async {
    if (_busy || _speaking) return;
    setState(() { _busy = true; });
    try {
      final file = await openFile(acceptedTypeGroups: const [XTypeGroup(
        label: 'תמונות', extensions: ['jpg', 'jpeg', 'png'],
        mimeTypes: ['image/jpeg', 'image/png'],
        uniformTypeIdentifiers: ['public.jpeg', 'public.png'])]);
      if (file == null || !mounted) return;
      if (await file.length() > 15 * 1024 * 1024) throw StateError('התמונה גדולה מ־15 מגה־בייט');
      final bytes = await file.readAsBytes();
      // Decode once and normalize orientation/size before ALL models see it.
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      try {
        if (descriptor.width * descriptor.height > 40000000) throw StateError('רזולוציית התמונה גדולה מדי');
        final scale = 1280 / (descriptor.width > descriptor.height ? descriptor.width : descriptor.height);
        final codec = await descriptor.instantiateCodec(
          targetWidth: scale < 1 ? (descriptor.width * scale).round() : descriptor.width,
          targetHeight: scale < 1 ? (descriptor.height * scale).round() : descriptor.height);
        try {
          final frame = await codec.getNextFrame();
          try {
            final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
            if (png == null) throw StateError('לא ניתן לפענח את התמונה');
            if (mounted) setState(() {
              _image = png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes);
              _scene = null; _notes.clear(); _status = 'התמונה מוכנה. לחץ ניתוח תמונה.';
            });
          } finally { frame.image.dispose(); }
        } finally { codec.dispose(); }
      } finally { descriptor.dispose(); buffer.dispose(); }
    } catch (e) { if (mounted) setState(() { _status = 'פתיחת התמונה נכשלה: $e'; }); }
    finally { if (mounted) setState(() { _busy = false; }); }
  }

  Future<void> _analyse() async {
    if (_busy || _speaking || _image == null) return;
    _idle = Completer<void>();
    setState(() { _busy = true; _scene = null; _status = 'מכין מודלים. בהורדה הראשונה נדרש אינטרנט.'; });
    try {
      _detector ??= YOLO(modelPath: 'yolo26n', task: YOLOTask.detect, useGpu: false, useMultiInstance: true);
      if (!_detectorReady) _detectorReady = await _detector!.loadModel();
      if (!_detectorReady) throw StateError('מודל העצמים לא נטען');
      if (!mounted) return;
      if (!_spatial.prepared) { await _spatial.prepare(useGpu: false); }
      else if (!_spatial.depthReady || !_spatial.structureReady) { await _spatial.retry(useGpu: false); }
      if (!mounted) return;
      setState(() { _status = 'מנתח את התמונה השמורה…'; });
      final received = _clock.elapsedMilliseconds;
      final raw = await _detector!.predict(_image!, confidenceThreshold: .65);
      if (!mounted) return;
      final detections = YOLODetectionResults.fromMap(raw).detections;
      final scene = await _spatial.analyse(jpeg: _image!, detections: detections,
        frameId: ++_run, receivedAtMs: received, now: () => _clock.elapsedMilliseconds);
      if (mounted) setState(() {
        _scene = scene;
        _status = scene == null ? 'לא התקבלה תוצאה' : 'הניתוח הסתיים — תמונה שמורה, לא מצב חי';
      });
    } catch (e) { if (mounted) setState(() { _status = 'הניתוח נכשל: $e'; }); }
    finally { _idle!.complete(); if (mounted) setState(() { _busy = false; }); }
  }

  Future<void> _read() async {
    if (_scene == null || _speaking || !_foreground) return;
    setState(() { _speaking = true; });
    try {
      await _speech.prepare();
      if (!mounted || !_foreground) return;
      await _speech.speak('בתמונה השמורה. ${_scene!.describe()}');
    } catch (e) { if (mounted) setState(() { _status = 'ההקראה נכשלה: $e'; }); }
    finally { if (mounted) setState(() { _speaking = false; }); }
  }

  String get _report => const JsonEncoder.withIndent('  ').convert({
    'app_version': prototypeVersion, 'source': 'saved_image_not_live',
    'run': _run, 'models': ['yolo26n', 'yolo26n-depth', 'yolo26n-sem'],
    'gpu_requested': false, 'spatial': _spatial.diagnostics,
    'processing_ms_excluding_model_loading': _scene == null ? null : _scene!.completedAtMs - _scene!.receivedAtMs,
    'description': _scene?.describe(), 'issues': _scene?.issues,
    'features': _scene?.features.map((f) => {'label': f.label, 'position': f.box.cell,
      'box': [f.box.left, f.box.top, f.box.right, f.box.bottom],
      'estimated_meters': f.depth?.meters, 'structure': f.structure}).toList(),
    'user_notes': _notes.text, 'accuracy_measured': false,
    'image_included': false, 'status': _status,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('בדיקה מתמונה שמורה')),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      const Text('זהו ניתוח תמונה מהעבר. המיקום והמרחק מתייחסים לצילום בלבד. התמונה אינה נשלחת לשרת ואינה נכללת בדוח.'),
      const SizedBox(height: 12),
      Semantics(liveRegion: true, child: Text(_status)),
      OutlinedButton(onPressed: _busy || _speaking ? null : _choose, child: const Text('בחירת תמונה')),
      if (_image != null) Image.memory(_image!, height: 220, semanticLabel: 'התמונה שנבחרה לבדיקה'),
      FilledButton(onPressed: _busy || _speaking || _image == null ? null : _analyse,
        child: Text(_busy ? 'מעבד…' : _run == 0 ? 'ניתוח תמונה' : 'ניתוח חוזר')),
      Text('מרחק: ${_spatial.depthStatus}'), Text('דלתות וקירות: ${_spatial.structureStatus}'),
      if (_scene != null) ...[
        SelectableText(_scene!.describe(), style: const TextStyle(fontSize: 22)),
        for (final issue in _scene!.issues) Text(issue),
        OutlinedButton(onPressed: _speaking ? null : _read, child: const Text('הקראת התיאור')),
        OutlinedButton(onPressed: () => unawaited(_speech.stop()), child: const Text('עצירת הקראה')),
        for (final feature in _scene!.ordered) ListTile(title: Text(feature.spokenLabel), subtitle: Text(feature.phrase)),
      ],
      TextField(controller: _notes, maxLines: 3, decoration: const InputDecoration(labelText: 'מה נכון או חסר בתיאור? למשל: יש דלת שלא זוהתה')),
      OutlinedButton(onPressed: _busy ? null : () => shareReport(context, _report, 'photo-review'),
        child: const Text('שיתוף דוח ללא התמונה')),
    ]),
  );
}
