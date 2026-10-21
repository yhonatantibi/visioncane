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
import 'domain/prototype.dart';
import 'services/local_speech.dart';
import 'services/report_export.dart';
import 'screens/field_trials_screen.dart';

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
  final _speech = LocalSpeech();
  final _announcements = AnnouncementPolicy();
  YOLOViewController? _viewController;
  bool _depthMode = false;
  bool _demoMode = true;
  bool _automaticSpeech = true;
  double _speechRate = 0.45;
  final List<String> _events = [];
  double _threshold = 0.4;
  bool _nativeConfigured = false;
  bool _voiceEnabled = false;
  bool _voicePreparing = false;
  bool _openingTrials = false;
  bool _speaking = false;
  int _utterance = 0;
  String? _voiceError;
  String? _lastSpoken;
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
  bool _staleNotified = false;
  double? _fps;
  double? _processingMs;
  String? _error;
  List<YOLOResult> _results = [];
  BenchmarkRun? _run;
  String _runDeviceLabel = '';
  bool _runGpu = true;
  int _runStartedMs = 0;
  String? get _depthModelId {
    if (!_supported) return null;
    final models = YOLO.officialModels(task: YOLOTask.depth);
    for (final model in models) {
      if (model.contains('26n')) return model;
    }
    return models.isEmpty ? null : models.first;
  }
  String get _modelId => _depthMode ? _depthModelId! : 'yolo26n';
  bool get _supported => Platform.isIOS || Platform.isAndroid;
  bool get _measuring => _run != null && !_run!.finished;
  int get _runElapsed => _clock.elapsedMilliseconds - _runStartedMs;
  bool get _fresh => _lastResultMs != null &&
      _clock.elapsedMilliseconds - _lastResultMs! <= 2000;
  bool get _metricsFresh => _lastMetricsMs != null &&
      _clock.elapsedMilliseconds - _lastMetricsMs! <= 2000;

  void _event(String message) {
    _events.add('${_clock.elapsedMilliseconds}ms $message');
    if (_events.length > 50) _events.removeAt(0);
  }

  void _stopEverything() {
    if (_camera) _stopCamera('stop_all');
    setState(() { _voiceEnabled = false; _speaking = false; _utterance++; });
    _announcements.reset();
    unawaited(_speech.stop().catchError((Object _) {}));
    _event('stop_all');
  }

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
      if (_camera && _lastResultMs != null && !_fresh && !_staleNotified) {
        _staleNotified = true;
        unawaited(_warnStalled(_generation));
      }
      _maybeAnnounce();
      setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _event('lifecycle:${state.name}');
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground && _camera) _stopCamera('app_backgrounded');
    if (!_foreground && !_camera) {
      _voiceEnabled = false;
      _utterance++;
      _speaking = false;
      unawaited(_speech.stop().catchError((Object _) {}));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _deviceLabel.dispose();
    unawaited(_speech.stop().catchError((Object _) {}));
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
        _viewController = YOLOViewController();
        _nativeConfigured = false;
        _announcements.reset();
        _lastSpoken = null;
        _camera = true;
        _ready = false;
        _results = [];
        _lastResultMs = null;
        _lastMetricsMs = null;
        _fps = null;
        _processingMs = null;
        _cameraStartedMs = _clock.elapsedMilliseconds;
        _staleNotified = false;
      });
      _event('camera_start:$_modelId');
    } catch (error) {
      if (mounted) setState(() { _error = 'לא ניתן לפתוח את המצלמה: $error'; });
    } finally {
      if (mounted) setState(() { _requesting = false; });
    }
  }

  void _stopCamera(String reason) {
    _event('camera_stop:$reason');
    if (_measuring) _run!.finish(_runElapsed, reason: reason);
    _utterance++;
    _speaking = false;
    _announcements.reset();
    unawaited(_speech.stop().catchError((Object _) {}));
    setState(() {
      _camera = false;
      _ready = false;
      _nativeConfigured = false;
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
    if (_depthMode) return; // Depth freshness is driven by processing callbacks.
    _lastResultMs = _clock.elapsedMilliseconds;
    _staleNotified = false;
    _ready = true;
    _results = results.where((r) => r.confidence.isFinite &&
        r.confidence >= _threshold && r.confidence <= 1).toList()
      ..sort((a, b) => b.confidence.compareTo(a.confidence));
    _announcements.observe(_sceneItems, _clock.elapsedMilliseconds);
    if (_measuring) {
      _run!.addDetections(_runElapsed, _results.map((r) => r.className));
    }
  }

  void _onMetrics(YOLOPerformanceMetrics metrics, int generation) {
    if (!mounted || !_camera || generation != _generation) return;
    _lastMetricsMs = _clock.elapsedMilliseconds;
    if (_depthMode && metrics.processingTimeMs.isFinite && metrics.processingTimeMs > 0) {
      _lastResultMs = _clock.elapsedMilliseconds;
      _ready = true;
    }
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
      _run = BenchmarkRun(startedAt: DateTime.now(), model: _modelId,
          mode: _depthMode ? 'depth_experiment' : 'detect',
          confidenceThreshold: _threshold, speechEnabled: _voiceEnabled);
      _runStartedMs = _clock.elapsedMilliseconds;
      _runDeviceLabel = _deviceLabel.text;
      _runGpu = _gpu;
    });
  }

  String get _status {
    if (_error != null) return 'נדרשת בדיקה';
    if (!_camera) return 'המצלמה כבויה';
    if (_fresh && !_nativeConfigured) return 'מסנכרן הגדרות תצוגה…';
    if (_fresh) return _depthMode ? 'עיבוד עומק ניסיוני פעיל' : 'זיהוי מקומי פעיל';
    if (_lastResultMs != null) return 'אין תוצאות עדכניות';
    return 'מכין מצלמה ומודל…';
  }

  Iterable<SceneItem> get _sceneItems => _results.map((r) => SceneItem(
    label: r.className,
    confidence: r.confidence,
    centerX: r.normalizedBox.center.dx,
  ));

  Future<void> _configureView(int generation) async {
    try {
      final controller = _viewController;
      if (controller == null) return;
      // The native load callback may arrive just before the view channel is ready.
      for (var attempt = 0; !controller.isInitialized && attempt < 20; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        if (!mounted || !_camera || generation != _generation) return;
      }
      if (!controller.isInitialized) throw StateError('ממשק המצלמה אינו מוכן');
      await controller.setConfidenceThreshold(_threshold);
      if (!mounted || !_camera || generation != _generation) return;
      setState(() { _nativeConfigured = true; });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      _stopCamera('configuration_error');
      setState(() { _error = 'לא ניתן לסנכרן את הגדרות הזיהוי: $error'; });
    }
  }

  Future<void> _toggleVoice(bool enabled) async {
    if (_measuring || _depthMode) return;
    if (!enabled) {
      setState(() { _voiceEnabled = false; _speaking = false; _utterance++; });
      try {
        await _speech.stop();
      } catch (error) {
        if (mounted) setState(() { _voiceError = 'לא ניתן לעצור את מנוע הקול: $error'; });
      }
      return;
    }
    final preparation = ++_utterance;
    setState(() { _voicePreparing = true; _voiceError = null; });
    try {
      await _speech.prepare(rate: _speechRate);
      if (!mounted || !_foreground || preparation != _utterance) return;
      setState(() { _voiceEnabled = true; _announcements.reset(); });
      _event('speech_ready');
      await _speak('הקראה בעברית מוכנה. הכיוונים מתייחסים לתמונת המצלמה.');
    } on SpeechCancelled {
      // Stop, backgrounding or navigation invalidated this preparation.
    } catch (error) {
      _event('speech_prepare_error:$error');
      if (mounted && preparation == _utterance) setState(() { _voiceError = error.toString(); _voiceEnabled = false; });
    } finally {
      if (mounted) setState(() { _voicePreparing = false; });
    }
  }

  String _phrase(SceneItem item) => '${displayLabel(item.label)} ${sectorText(item.sector)}';

  void _maybeAnnounce() {
    if (!_camera || !_fresh || !_nativeConfigured || _depthMode ||
        !_voiceEnabled || !_automaticSpeech || _speaking || !_foreground) return;
    final item = _announcements.next(_clock.elapsedMilliseconds);
    if (item == null) return;
    _announcements.markSpoken(item, _clock.elapsedMilliseconds);
    unawaited(_speak(_phrase(item)));
  }

  Future<void> _speak(String text) async {
    if (!_voiceEnabled || _speaking || !_foreground) return;
    final token = ++_utterance;
    _speaking = true;
    _lastSpoken = text;
    try {
      await _speech.speak(text);
    } catch (error) {
      if (mounted && token == _utterance) {
        _voiceError = 'ההקראה נכשלה: $error';
        _voiceEnabled = false;
        _event('speech_error:$error');
      }
    } finally {
      if (mounted && token == _utterance) setState(() { _speaking = false; });
    }
  }

  Future<void> _warnStalled(int generation) async {
    _event('result_stream_stalled');
    _utterance++;
    _speaking = false;
    _announcements.reset();
    await _speech.stop().catchError((Object _) {});
    if (!mounted || !_camera || generation != _generation || _fresh || !_foreground) return;
    if (_voiceEnabled) await _speak('הזיהוי אינו מתעדכן. עצור והפעל שוב.');
  }

  void _describeNow() {
    if (!_camera || !_fresh || !_nativeConfigured || !_voiceEnabled || _speaking || _depthMode) return;
    final unique = <String, SceneItem>{};
    for (final item in _sceneItems) {
      if (item.valid && item.confidence >= AnnouncementPolicy.minimumConfidence) unique[item.key] = item;
      if (unique.length == 3) break;
    }
    for (final item in unique.values) _announcements.markSpoken(item, _clock.elapsedMilliseconds);
    final text = unique.isEmpty
        ? 'אין כרגע זיהויים בביטחון גבוה. אין בכך אישור שהדרך פנויה.'
        : unique.values.map(_phrase).join('. ');
    unawaited(_speak(text));
  }

  Future<void> _openFieldTrials() async {
    if (_measuring || _requesting || _voicePreparing || _openingTrials) return;
    setState(() { _openingTrials = true; });
    try {
    final mode = _depthMode ? 'depth_experiment' : 'detect';
    final model = _modelId;
    final voice = _voiceEnabled;
    if (_camera) _stopCamera('field_trial_form_opened');
    _voiceEnabled = false;
    _utterance++;
    _speaking = false;
    await _speech.stop().catchError((Object _) {});
    if (!mounted) return;
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => FieldTrialsScreen(
      device: _deviceLabel.text, mode: mode, model: model,
      threshold: _threshold, speechEnabled: voice,
    )));
    } finally {
      if (mounted) setState(() { _openingTrials = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final generation = _generation;
    final visible = _fresh ? _results.take(6).toList() : <YOLOResult>[];
    final loadingLong = _camera && !_ready && _cameraStartedMs != null &&
        _clock.elapsedMilliseconds - _cameraStartedMs! > 30000;
    return Scaffold(
      appBar: AppBar(
        title: const Text('VisionCane • 0.4'),
        actions: [
          IconButton(
            tooltip: 'מידע על הניסוי',
            onPressed: _showInfo,
            icon: const Icon(Icons.info_outline),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _demoMode ? 0 : 1,
        onDestinationSelected: _requesting || _openingTrials ? null : (index) {
          if ((index == 0) == _demoMode) return;
          _stopEverything();
          setState(() { _demoMode = index == 0; if (_demoMode) _depthMode = false; });
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.visibility_outlined), label: 'הדגמה'),
          NavigationDestination(icon: Icon(Icons.science_outlined), label: 'כלי בדיקה'),
        ],
      ),
      body: _demoMode ? _buildDemo(generation) : SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('לראות. למדוד. להתקדם.',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text('ניסוי זיהוי סביבה • עיבוד במכשיר'),
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('זיהוי וקול'), icon: Icon(Icons.visibility_outlined)),
                ButtonSegment(value: true, label: Text('ניסוי עומק'), icon: Icon(Icons.layers_outlined)),
              ],
              selected: {_depthMode},
              onSelectionChanged: _camera || _requesting || _voicePreparing || _measuring
                  ? null : (selection) {
                final depth = selection.first;
                if (depth && _depthModelId == null) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('לא נמצא מודל עומק זמין לפלטפורמה הזאת.')));
                  return;
                }
                setState(() { _depthMode = depth; _voiceEnabled = false; _lastSpoken = null; });
                _announcements.reset();
                unawaited(_speech.stop().catchError((Object _) {}));
              },
            ),
            const SizedBox(height: 8),
            Text(_depthMode
                ? 'מפת עומק ניסיונית. עדיין אינה מודדת מרחק מאומת או קובעת שהדרך פנויה. נדרשת הורדת מודל נפרד בפעם הראשונה.'
                : 'תיאור של עצמים מוכרים וכיוונם בתמונה. כדי להחליף מצב, עצור את המצלמה.'),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: AspectRatio(
                aspectRatio: 3 / 4,
                child: ColoredBox(
                  color: const Color(0xFF142337),
                  child: _camera
                      ? Stack(fit: StackFit.expand, children: [
                          _yoloView(generation),
                          if (!_fresh || !_nativeConfigured)
                            ColoredBox(
                              color: Colors.black54,
                              child: Center(child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(_fresh && !_nativeConfigured ? 'מסנכרן הגדרות…' : _lastResultMs == null
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
            if (!_depthMode) ...[
              const SizedBox(height: 12),
              Text('סף זיהוי: ${(_threshold * 100).round()}%'),
              Slider(
                value: _threshold, min: 0.4, max: 0.8, divisions: 8,
                label: '${(_threshold * 100).round()}%',
                onChanged: _camera || _measuring ? null : (value) => setState(() { _threshold = value; }),
              ),
              const Text('משנים כשהמצלמה כבויה. סף גבוה מצמצם זיהויי שווא אך עלול להגדיל החמצות.', style: TextStyle(fontSize: 12)),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('הקראה מקומית בעברית'),
                subtitle: Text(_voicePreparing ? 'מכין קול…' : 'זיהוי יציב בציון 65% לפחות; אין הוראות ניווט.'),
                value: _voiceEnabled,
                onChanged: _voicePreparing || _measuring ? null : (value) => unawaited(_toggleVoice(value)),
              ),
              if (_voiceError != null) Text(_voiceError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              TextButton.icon(onPressed: _showDiagnostics,
                icon: const Icon(Icons.bug_report_outlined), label: const Text('אבחון והעתקת דוח')),
              Wrap(spacing: 8, children: [
                OutlinedButton.icon(
                  onPressed: _voiceEnabled && !_speaking && !_measuring
                      ? () => unawaited(_speak('בדיקת קול בעברית')) : null,
                  icon: const Icon(Icons.volume_up_outlined), label: const Text('בדיקת קול'),
                ),
                OutlinedButton.icon(
                  onPressed: _voiceEnabled && !_speaking && _fresh && _nativeConfigured ? _describeNow : null,
                  icon: const Icon(Icons.record_voice_over_outlined), label: const Text('תאר עכשיו'),
                ),
              ]),
              if (_lastSpoken != null) Text('הקראה אחרונה: $_lastSpoken'),
              const Text('ימין ושמאל מתייחסים לתמונה של המצלמה האחורית, ולא לכיוון הגוף. נדרש קול עברי מותקן לשימוש בלי רשת.', style: TextStyle(fontSize: 12, color: Colors.white70)),
            ],
            if (!_supported) const Text('הניסוי זמין באייפון ובאנדרואיד בלבד.'),
            const SizedBox(height: 20),
            Text(_depthMode ? 'בדיקת צורת המכשול' : 'מה מופיע בתמונה?', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (_depthMode)
              const Text('בדוק אם קרש הגיהוץ והרגליים שלו נבדלים מהרקע במפת העומק. נבדוק מול מרחקים ידועים לפני הוספת התרעות.')
            else if (visible.isEmpty)
              Text(!_fresh ? 'ממתין לתוצאות עדכניות.' : 'אין כרגע זיהויים מעל סף הביטחון. אין בכך אישור שהדרך פנויה.'),
            for (final result in visible)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.crop_free),
                title: Text(displayLabel(result.className)),
                subtitle: Text('${result.className} • ${sectorText(sectorFor(result.normalizedBox.center.dx))}'),
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
                  : (_camera && _ready && _fresh && _nativeConfigured ? _startBenchmark : null),
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
            OutlinedButton.icon(
              onPressed: _measuring || _requesting || _voicePreparing || _openingTrials ? null : _openFieldTrials,
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('רישום תוצאת ניסוי (עוצר מצלמה)'),
            ),
            const Text('אב־טיפוס לבדיקה מבוקרת. אינו אמצעי להכוונת הליכה. בשלב זה אין מדידת מרחק או זיהוי של כל סוגי המכשולים.',
                style: TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
      ),
    );
  }

  Widget _yoloView(int generation) => ExcludeSemantics(child: YOLOView(
    key: ValueKey(generation), modelPath: _modelId,
    task: _depthMode ? YOLOTask.depth : YOLOTask.detect,
    controller: _viewController, cameraResolution: '720p',
    confidenceThreshold: _threshold, useGpu: _gpu,
    streamingConfig: const YOLOStreamingConfig(
      includeOriginalImage: false, includeClassifications: false,
      includeMasks: false, includePoses: false, includeOBB: false,
    ),
    onResult: (results) => _onResults(results, generation),
    onPerformanceMetrics: (metrics) => _onMetrics(metrics, generation),
    onModelLoad: (path, task) => unawaited(_configureView(generation)),
    onModelError: (error, path, task) {
      if (!mounted || generation != _generation) return;
      _stopCamera('model_error');
      setState(() { _error = 'טעינת המודל נכשלה: $error'; });
    },
  ));

  Widget _buildDemo(int generation) {
    final items = <String, SceneItem>{};
    if (_fresh && _nativeConfigured) {
      for (final item in _sceneItems) {
        if (item.valid && item.confidence >= AnnouncementPolicy.minimumConfidence) {
          items.putIfAbsent(item.key, () => item);
        }
      }
    }
    return SafeArea(child: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Semantics(header: true, child: const Text('מה נמצא מולי?',
          style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold))),
        const SizedBox(height: 8),
        const Text('הדגמת תיאור עצמים במכשיר. מתחילים בישיבה, עם מלווה. המערכת אינה מנחה הליכה ואינה קובעת שהדרך פנויה.'),
        const SizedBox(height: 16),
        Semantics(liveRegion: true, child: Text(_status,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600))),
        const SizedBox(height: 12),
        // Primary controls precede the camera and remain early in TalkBack order.
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(64)),
          onPressed: _requesting || _camera ? null : _startCamera,
          icon: const Icon(Icons.videocam_outlined),
          label: Text(_requesting ? 'מבקש הרשאה…' : 'הפעלת זיהוי', style: const TextStyle(fontSize: 22)),
        ),
        const SizedBox(height: 10),
        FilledButton.tonalIcon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(64)),
          onPressed: _camera || _voiceEnabled || _voicePreparing || _speaking ? _stopEverything : null,
          icon: const Icon(Icons.stop_circle_outlined),
          label: const Text('עצירת הכול', style: TextStyle(fontSize: 22)),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(60)),
          onPressed: _voicePreparing ? null : () => unawaited(_toggleVoice(!_voiceEnabled)),
          icon: Icon(_voiceEnabled ? Icons.volume_off_outlined : Icons.volume_up_outlined),
          label: Text(_voicePreparing ? 'מכין קול עברי…' : _voiceEnabled ? 'כיבוי קול' : 'הפעלת קול עברי',
            style: const TextStyle(fontSize: 20)),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(60)),
          onPressed: _voiceEnabled && !_speaking && _fresh && _nativeConfigured ? _describeNow : null,
          icon: const Icon(Icons.record_voice_over_outlined),
          label: const Text('תאר עכשיו', style: TextStyle(fontSize: 20)),
        ),
        if (_voiceError != null) Semantics(liveRegion: true, child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(_voiceError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        )),
        if (_error != null) ...[
          Semantics(liveRegion: true, child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          TextButton(onPressed: () async { await openAppSettings(); }, child: const Text('פתיחת הגדרות האפליקציה')),
        ],
        SwitchListTile.adaptive(contentPadding: EdgeInsets.zero,
          title: const Text('תיאור אוטומטי'),
          subtitle: const Text('אפשר לכבות ולהשתמש רק ב״תאר עכשיו״, גם לצד קורא מסך.'),
          value: _automaticSpeech,
          onChanged: (v) {
            setState(() { _automaticSpeech = v; _announcements.reset(); });
            if (!v) {
              _utterance++; _speaking = false;
              unawaited(_speech.stop().catchError((Object _) {}));
            }
          },
        ),
        if (_lastSpoken != null) Card(child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('התיאור האחרון: $_lastSpoken', style: const TextStyle(fontSize: 22)),
        )),
        const SizedBox(height: 12),
        SizedBox(height: 240, child: ClipRRect(borderRadius: BorderRadius.circular(20),
          child: ColoredBox(color: const Color(0xFF142337), child: _camera
            ? Stack(fit: StackFit.expand, children: [
                _yoloView(generation),
                if (!_fresh || !_nativeConfigured) ColoredBox(color: Colors.black54,
                  child: Center(child: Padding(padding: const EdgeInsets.all(20),
                    child: Text(_lastResultMs == null
                      ? 'מכין מצלמה ומודל. בפעם הראשונה נדרש אינטרנט להורדה.'
                      : 'אין כרגע זיהוי מעודכן. עצור ונסה שוב.', textAlign: TextAlign.center)))),
              ])
            : const Center(child: Icon(Icons.center_focus_strong, size: 64)),
          ),
        )),
        const SizedBox(height: 16),
        Semantics(header: true, child: const Text('עצמים בתמונה',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold))),
        const Text('שמאל וימין מתייחסים לתמונת המצלמה האחורית, ולא לכיוון הגוף.'),
        if (items.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(!_camera ? 'הפעל זיהוי כדי להתחיל.' : !_fresh || !_nativeConfigured
            ? 'ממתין לתוצאות עדכניות.' : 'אין זיהויים בביטחון גבוה. אין בכך אישור שהדרך פנויה.')),
        for (final item in items.values.take(4)) ListTile(contentPadding: EdgeInsets.zero,
          title: Text(displayLabel(item.label), style: const TextStyle(fontSize: 22)),
          subtitle: Text(sectorText(item.sector), style: const TextStyle(fontSize: 18))),
        ExpansionTile(title: const Text('הכנה, קול ועזרה'), children: [
          const Padding(padding: EdgeInsets.all(12), child: Text(
            '1. בהפעלה הראשונה התחבר לאינטרנט והפעל זיהוי להורדת המודל.\n'
            '2. הפעל קול עברי והקשב למשפט הבדיקה.\n'
            '3. הפעל מצב טיסה, כבה Wi-Fi ופתח מחדש. בדוק זיהוי וקול.\n'
            '4. הדגם כיסא, בקבוק ואדם בישיבה עם מלווה.\n'
            'המצלמה וההקראה נעצרות ביציאה מהאפליקציה. אין שמירת תמונות בקוד האפליקציה.')),
          Text('מהירות הקראה: ${(_speechRate * 100).round()}%'),
          Slider(value: _speechRate, min: 0.25, max: 0.65, divisions: 8,
            label: '${(_speechRate * 100).round()}%',
            onChanged: _voiceEnabled || _voicePreparing ? null : (v) => setState(() { _speechRate = v; })),
          const Text('לשינוי מהירות, כבה את הקול תחילה.'),
          TextButton.icon(onPressed: _voiceEnabled && !_speaking
            ? () => unawaited(_speak('בדיקת קול בעברית. המערכת מתארת עצמים בתמונה.')) : null,
            icon: const Icon(Icons.volume_up), label: const Text('השמעת משפט בדיקה')),
          TextButton.icon(onPressed: _showDiagnostics,
            icon: const Icon(Icons.bug_report_outlined), label: const Text('אבחון והעתקת דוח')),
        ]),
        const SizedBox(height: 16),
      ],
    ));
  }

  Future<void> _showDiagnostics() async {
    final report = const JsonEncoder.withIndent('  ').convert({
      'app_version': prototypeVersion, 'platform': Platform.operatingSystem,
      'os_version': Platform.operatingSystemVersion, 'model': _modelId,
      'camera_running': _camera, 'fresh': _fresh,
      'native_configured': _nativeConfigured, 'gpu_requested': _gpu,
      'gpu_actual': 'not_verified', 'sdk_fps': _fps,
      'sdk_processing_ms': _processingMs, 'camera_error': _error,
      'speech': _speech.diagnostics, 'events': _events,
    });
    await showDialog<void>(context: context, builder: (context) => AlertDialog(
      title: const Text('אבחון המערכת'),
      content: SizedBox(width: 500, child: SingleChildScrollView(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('הדוח כולל הגדרות, מצב מנוע הקול ושגיאות. אין תמונות או הקלטות.'),
          const SizedBox(height: 12),
          Directionality(textDirection: TextDirection.ltr, child: SelectableText(report)),
        ],
      ))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('סגירה')),
        TextButton(onPressed: () => shareReport(context, report, 'diagnostics'), child: const Text('שיתוף קובץ')),
        FilledButton(onPressed: () async {
          try {
            await Clipboard.setData(ClipboardData(text: report));
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('דוח האבחון הועתק')));
          } catch (_) {
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('ההעתקה נכשלה. אפשר לבחור טקסט מהדוח.')));
          }
        }, child: const Text('העתקת דוח')),
      ],
    ));
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
    final fullJson = const JsonEncoder.withIndent('  ').convert(run.report(
      platform: Platform.operatingSystem, deviceLabel: _runDeviceLabel,
      requestedGpu: _runGpu, includeSamples: true,
    ));
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
              label: const Text('העתקת סיכום קצר'),
            ),
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: fullJson));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('הדוח המלא הועתק. הוא ארוך ועלול להיחתך בוואטסאפ.')));
              },
              child: const Text('העתקת דוח מלא עם דגימות'),
            ),
            OutlinedButton.icon(onPressed: () => shareReport(context, fullJson, 'benchmark'),
              icon: const Icon(Icons.share_outlined), label: const Text('שיתוף דוח מלא כקובץ')),
          ]),
        ),
      )),
    );
  }

  void _showInfo() {
    showDialog<void>(context: context, builder: (context) => AlertDialog(
      title: const Text('על הניסוי'),
      content: const SingleChildScrollView(child: Text(
        'גרסה 0.4.0. זיהוי עצמים עם YOLO26n, הקראה בעברית, מצב עומק ניסיוני ורישום בדיקות ידני. באייפון המודלים רצים דרך Core ML ובאנדרואיד דרך LiteRT.\n\n'
        'בהפעלה הראשונה קובץ המודל יורד מהאינטרנט ונשמר במכשיר. אחר כך יש לבדוק פעולה במצב טיסה.\n\n'
        'קוד הניסוי אינו שומר או מעלה תמונות ואינו מבקש מיקרופון או מיקום. תוצאות בדיקה שהזנת נשמרות מקומית. העתקת דוח היא פעולה ידנית.\n\n'
        'המודל מזהה קטגוריות מוכרות. ענפים, בורות, מדרגות וסכנות אחרות אינם מובטחים. ציון ביטחון אינו אחוז הצלחה שנמדד בניסוי.')),
      actions: [
        TextButton(onPressed: () {
          Navigator.pop(context);
          showLicensePage(context: this.context, applicationName: 'VisionCane', applicationVersion: prototypeVersion);
        }, child: const Text('רישיונות רכיבים')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('הבנתי')),
      ],
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
