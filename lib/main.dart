import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

import 'domain/benchmark.dart';
import 'domain/labels.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const VisionCaneApp());
}

class VisionCaneApp extends StatelessWidget {
  const VisionCaneApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: const Locale('he'),
    supportedLocales: const [Locale('he'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF09121E),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF55E4CE), brightness: Brightness.dark,
      ),
    ),
    home: const DetectionScreen(),
  );
}

class DetectionScreen extends StatefulWidget {
  const DetectionScreen({super.key});

  @override
  State<DetectionScreen> createState() => _DetectionScreenState();
}

class _DetectionScreenState extends State<DetectionScreen>
    with WidgetsBindingObserver {
  final _clock = Stopwatch()..start();
  final _deviceLabel = TextEditingController();
  Timer? _ticker;
  bool _camera = false;
  bool _requesting = false;
  bool _foreground = true;
  bool _ready = false;
  bool _gpu = true;
  int _generation = 0;
  int? _lastResultMs;
  int? _lastMetricsMs;
  int? _cameraStartedMs;
  double? _fps;
  double? _processingMs;
  String? _error;
  List<YOLOResult> _results = [];
  BenchmarkRun? _run;
  String _runDeviceLabel = '';
  bool _runGpu = true;
  int _runStartedMs = 0;
  bool get _supported => Platform.isIOS || Platform.isAndroid;
  bool get _measuring => _run != null && !_run!.finished;
  int get _runElapsed => _clock.elapsedMilliseconds - _runStartedMs;
  bool get _fresh => _lastResultMs != null &&
      _clock.elapsedMilliseconds - _lastResultMs! <= 2000;
  bool get _metricsFresh => _lastMetricsMs != null &&
      _clock.elapsedMilliseconds - _lastMetricsMs! <= 2000;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      if (_measuring && _runElapsed >= _run!.totalMs) {
        _run!.finish(_run!.totalMs, reason: _run!.sampleCount == 0
            ? 'no_valid_metrics' : 'completed');
      } else if (_measuring && !_fresh) {
        _run!.finish(_runElapsed, reason: 'result_stream_stalled');
      }
      setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground && _camera) _stopCamera('app_backgrounded');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _deviceLabel.dispose();
    _clock.stop();
    super.dispose();
  }

  Future<void> _startCamera() async {
    if (_requesting || !_supported || !_foreground) return;
    setState(() { _requesting = true; _error = null; });
    try {
      final status = await Permission.camera.request();
      if (!mounted) return;
      if (!status.isGranted) {
        setState(() {
          _error = status.isPermanentlyDenied || status.isRestricted
              ? 'המצלמה חסומה. יש לאפשר גישה בהגדרות המכשיר.'
              : 'נדרשת הרשאת מצלמה כדי להתחיל.';
        });
        return;
      }
      // A permission dialog can temporarily take the app out of resumed state.
      _foreground = WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
      if (!_foreground) return;
      setState(() {
        _generation++;
        _camera = true;
        _ready = false;
        _results = [];
        _lastResultMs = null;
        _lastMetricsMs = null;
        _fps = null;
        _processingMs = null;
        _cameraStartedMs = _clock.elapsedMilliseconds;
      });
    } catch (error) {
      if (mounted) setState(() { _error = 'לא ניתן לפתוח את המצלמה: $error'; });
    } finally {
      if (mounted) setState(() { _requesting = false; });
    }
  }

  void _stopCamera(String reason) {
    if (_measuring) _run!.finish(_runElapsed, reason: reason);
    setState(() {
      _camera = false;
      _ready = false;
      _generation++; // Ignore callbacks from an older platform view.
      _results = [];
      _lastResultMs = null;
      _lastMetricsMs = null;
      _fps = null;
      _processingMs = null;
    });
  }

  void _onResults(List<YOLOResult> results, int generation) {
    if (!mounted || !_camera || generation != _generation) return;
    _lastResultMs = _clock.elapsedMilliseconds;
    _ready = true;
    _results = List<YOLOResult>.of(results)
      ..sort((a, b) => b.confidence.compareTo(a.confidence));
    if (_measuring) {
      _run!.addDetections(_runElapsed, results.map((r) => r.className));
    }
  }

  void _onMetrics(YOLOPerformanceMetrics metrics, int generation) {
    if (!mounted || !_camera || generation != _generation) return;
    _lastMetricsMs = _clock.elapsedMilliseconds;
    _fps = metrics.fps.isFinite && metrics.fps >= 0 ? metrics.fps : null;
    _processingMs = metrics.processingTimeMs.isFinite && metrics.processingTimeMs > 0
        ? metrics.processingTimeMs : null;
    if (_measuring) {
      _run!.addPerformance(
        elapsedMs: _runElapsed,
        processingMs: metrics.processingTimeMs,
        reportedFps: metrics.fps,
      );
    }
  }

  void _startBenchmark() {
    if (!_camera || !_ready || !_fresh || _measuring) return;
    setState(() {
      _run = BenchmarkRun(startedAt: DateTime.now());
      _runStartedMs = _clock.elapsedMilliseconds;
      _runDeviceLabel = _deviceLabel.text;
      _runGpu = _gpu;
    });
  }

  String get _status {
    if (!_camera) return 'המצלמה כבויה';
    if (_error != null) return 'נדרשת בדיקה';
    if (_fresh) return 'זיהוי מקומי פעיל';
    if (_lastResultMs != null) return 'אין תוצאות עדכניות';
    return 'מכין מצלמה ומודל…';
  }

  @override
  Widget build(BuildContext context) {
    final generation = _generation;
    final visible = _fresh ? _results.take(6).toList() : <YOLOResult>[];
    final loadingLong = _camera && !_ready && _cameraStartedMs != null &&
        _clock.elapsedMilliseconds - _cameraStartedMs! > 30000;
    return Scaffold(
      appBar: AppBar(
        title: const Text('VisionCane'),
        actions: [
          IconButton(
            tooltip: 'מידע על הניסוי',
            onPressed: _showInfo,
            icon: const Icon(Icons.info_outline),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('לראות. למדוד. להתקדם.',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text('ניסוי זיהוי סביבה • עיבוד במכשיר'),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: AspectRatio(
                aspectRatio: 3 / 4,
                child: ColoredBox(
                  color: const Color(0xFF142337),
                  child: _camera
                      ? Stack(fit: StackFit.expand, children: [
                          YOLOView(
                            key: ValueKey(generation),
                            modelPath: 'yolo26n',
                            task: YOLOTask.detect,
                            cameraResolution: '720p',
                            confidenceThreshold: 0.4,
                            useGpu: _gpu,
                            streamingConfig: const YOLOStreamingConfig(
                              includeOriginalImage: false,
                              includeClassifications: false,
                              includeMasks: false,
                              includePoses: false,
                              includeOBB: false,
                            ),
                            onResult: (results) => _onResults(results, generation),
                            onPerformanceMetrics: (metrics) => _onMetrics(metrics, generation),
                            onModelError: (error, path, task) {
                              if (!mounted || generation != _generation) return;
                              _stopCamera('model_error');
                              setState(() { _error = 'טעינת המודל נכשלה: $error'; });
                            },
                          ),
                          if (!_fresh)
                            ColoredBox(
                              color: Colors.black54,
                              child: Center(child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(_lastResultMs == null
                                    ? 'טוען את המודל…\nבהפעלה הראשונה נדרש אינטרנט להורדה.'
                                    : 'הזיהוי אינו מתעדכן. עצור והפעל שוב.',
                                  textAlign: TextAlign.center,
                                ),
                              )),
                            ),
                        ])
                      : const Center(child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.center_focus_strong, size: 64),
                            SizedBox(height: 16),
                            Text('מוכנים לבדיקת המצלמה'),
                            SizedBox(height: 8),
                            Text('אין צילום עד ללחיצה על הפעלה'),
                          ],
                        )),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Semantics(liveRegion: true, child: Text(_status,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              TextButton(onPressed: () async { await openAppSettings(); },
                  child: const Text('פתיחת הגדרות האפליקציה')),
            ],
            if (loadingLong) const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('ההכנה מתארכת. ודא שיש אינטרנט בהפעלה הראשונה ושהרשאת המצלמה אושרה. אפשר לעצור ולנסות שוב.'),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _MetricCard(
                label: 'קצב עיבוד מדווח',
                value: _metricsFresh && _fps != null ? '${_fps!.toStringAsFixed(1)} FPS' : '—',
              )),
              const SizedBox(width: 12),
              Expanded(child: _MetricCard(
                label: 'זמן עיבוד מדווח',
                value: _metricsFresh && _processingMs != null
                    ? '${_processingMs!.toStringAsFixed(1)} ms' : '—',
              )),
            ]),
            const SizedBox(height: 8),
            const Text('הנתונים מגיעים ממנוע הזיהוי. הם אינם מודדים את כל הזמן מהצילום ועד להתרעה, ואינם מוכיחים שכל פריים נותח.',
                style: TextStyle(fontSize: 12, color: Colors.white70)),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _requesting ? null : (_camera
                  ? () => _stopCamera('user_stopped_camera') : _startCamera),
              icon: Icon(_camera ? Icons.stop : Icons.videocam_outlined),
              label: Text(_requesting ? 'מבקש הרשאה…' : _camera ? 'עצירת מצלמה' : 'הפעלת זיהוי'),
            ),
            if (!_supported) const Text('הניסוי זמין באייפון ובאנדרואיד בלבד.'),
            const SizedBox(height: 20),
            const Text('מה מופיע בתמונה?', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (visible.isEmpty)
              Text(!_fresh ? 'ממתין לתוצאות עדכניות.' : 'אין כרגע זיהויים מעל סף הביטחון. אין בכך אישור שהדרך פנויה.'),
            for (final result in visible)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.crop_free),
                title: Text(displayLabel(result.className)),
                subtitle: Text(result.className, textDirection: TextDirection.ltr),
                trailing: Text('${(result.confidence * 100).round()}%'),
              ),
            const Divider(height: 32),
            const Text('בדיקת ביצועים', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('5 שניות חימום ולאחריהן 60 שניות מדידה. הדוח מכיל נתונים מספריים בלבד.'),
            const SizedBox(height: 12),
            TextField(
              controller: _deviceLabel,
              enabled: !_measuring,
              maxLength: 80,
              decoration: const InputDecoration(
                labelText: 'דגם המכשיר (למשל iPhone 13)',
                border: OutlineInputBorder(),
              ),
            ),
            if (Platform.isAndroid) SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('אפשר האצת GPU'),
              subtitle: const Text('שינוי כשהמצלמה כבויה; ייתכן מעבר אוטומטי ל־CPU.'),
              value: _gpu,
              onChanged: _camera ? null : (value) => setState(() { _gpu = value; }),
            ),
            if (_measuring) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: (_runElapsed / _run!.totalMs).clamp(0, 1).toDouble()),
              const SizedBox(height: 8),
              Text(_runElapsed < _run!.warmupMs ? 'חימום המנוע…' : 'מודד… ${((_run!.totalMs - _runElapsed) / 1000).ceil()} שניות נותרו'),
            ],
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _measuring
                  ? () => setState(() { _run!.finish(_runElapsed, reason: 'user_stopped_benchmark'); })
                  : (_camera && _ready && _fresh ? _startBenchmark : null),
              icon: Icon(_measuring ? Icons.stop_circle_outlined : Icons.speed),
              label: Text(_measuring ? 'סיום מדידה מוקדם' : 'התחלת בדיקת 65 שניות'),
            ),
            if (_run?.finished == true)
              TextButton.icon(
                onPressed: _showReport,
                icon: const Icon(Icons.description_outlined),
                label: Text('פתיחת דוח • ${_run!.sampleCount} דגימות'),
              ),
            const SizedBox(height: 16),
            const Text('אב־טיפוס לבדיקה מבוקרת. אינו אמצעי להכוונת הליכה. בשלב זה אין מדידת מרחק או זיהוי של כל סוגי המכשולים.',
                style: TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
      ),
    );
  }

  Future<void> _showReport() async {
    final run = _run;
    if (run == null || !run.finished) return;
    final report = run.report(
      platform: Platform.operatingSystem,
      deviceLabel: _runDeviceLabel,
      requestedGpu: _runGpu,
    );
    final json = const JsonEncoder.withIndent('  ').convert(report);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(child: Padding(
        padding: const EdgeInsets.all(24),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.65,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('דוח בדיקת ביצועים', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text('סיבת סיום: ${run.stopReason}\nדגימות תקינות: ${run.sampleCount}'),
            const SizedBox(height: 12),
            Expanded(child: SingleChildScrollView(child: Directionality(
              textDirection: TextDirection.ltr,
              child: SelectableText(json, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
            ))),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: json));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('הדוח הועתק. אפשר להדביק אותו בשיחה.')));
              },
              icon: const Icon(Icons.copy),
              label: const Text('העתקת הדוח'),
            ),
          ]),
        ),
      )),
    );
  }

  void _showInfo() {
    showDialog<void>(context: context, builder: (context) => AlertDialog(
      title: const Text('על הניסוי'),
      content: const SingleChildScrollView(child: Text(
        'המודל הוא YOLO26n. באייפון הוא רץ דרך Core ML ובאנדרואיד דרך LiteRT.\n\n'
        'בהפעלה הראשונה קובץ המודל יורד מהאינטרנט ונשמר במכשיר. אחר כך יש לבדוק פעולה במצב טיסה.\n\n'
        'קוד הניסוי אינו שומר או מעלה תמונות ואינו מבקש מיקרופון או מיקום. העתקת דוח היא פעולה ידנית.\n\n'
        'המודל מזהה קטגוריות מוכרות. ענפים, בורות, מדרגות וסכנות אחרות אינם מובטחים. ציון ביטחון אינו אחוז הצלחה שנמדד בניסוי.')),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('הבנתי'))],
    ));
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(padding: const EdgeInsets.all(14), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, textDirection: TextDirection.ltr,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF55E4CE))),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    )),
  );
}
