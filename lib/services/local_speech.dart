import 'dart:async';
import 'dart:io';
import 'package:flutter_tts/flutter_tts.dart';
import '../domain/speech_voice.dart';

class SpeechCancelled implements Exception {}

/// Installed voices only; unknown or network-required Android voices are rejected.
class LocalSpeech {
  LocalSpeech({FlutterTts? engine, bool? android})
      : _engine = engine, _android = android ?? Platform.isAndroid;
  FlutterTts? _engine;
  FlutterTts get _tts => _engine ??= FlutterTts();
  final bool _android;
  bool _ready = false, _preparing = false;
  int _epoch = 0;
  final List<Map<String, Object?>> _probes = [];
  Map<String, String>? _selected;
  String? _selectedEngine, _lastError;
  bool get ready => _ready;
  Map<String, Object?> get diagnostics => {
    'ready': _ready, 'engine': _selectedEngine, 'voice': _selected,
    'offline_status': 'metadata_only_requires_airplane_test',
    'last_error': _lastError, 'probes': List.of(_probes),
  };

  Future<T> _step<T>(Future<T> work, int epoch) async {
    final value = await work.timeout(const Duration(seconds: 10));
    if (epoch != _epoch) throw SpeechCancelled();
    return value;
  }

  Future<void> prepare({double rate = 0.45}) async {
    if (_preparing) throw StateError('הקול עדיין בהכנה');
    _preparing = true;
    _ready = false;
    _selected = null;
    _selectedEngine = null;
    _lastError = null;
    _probes.clear();
    final epoch = ++_epoch;
    try {
      await _step(_tts.stop(), epoch);
      final engines = <String?>[null];
      if (_android) {
        final installed = await _step(_tts.getEngines, epoch);
        final preferred = await _step(_tts.getDefaultEngine, epoch);
        if (preferred is String && preferred.isNotEmpty) engines.add(preferred);
        if (installed is List<Object?>) {
          for (final engine in installed.whereType<String>().take(6)) {
            if (!engines.contains(engine)) engines.add(engine);
          }
        }
      }
      for (final engine in engines) {
        if (engine != null) await _step(_tts.setEngine(engine), epoch);
        final raw = await _step(_tts.getVoices, epoch);
        final candidates = localHebrewVoices(raw, android: _android);
        _probes.add({
          'engine': engine ?? 'current',
          'voice_count': raw is List<Object?> ? raw.length : 0,
          'hebrew': raw is List<Object?> ? raw.whereType<Map<Object?, Object?>>().where((v) => isHebrewLocale(v['locale']))
              .map((v) => {for (final key in ['name', 'locale', 'network_required', 'features'])
                key: v[key]?.toString()}).toList() : [],
        });
        for (final voice in candidates) {
          if (await _step(_tts.setLanguage(voice['locale']!), epoch) != 1) continue;
          if (await _step(_tts.setVoice(voice), epoch) != 1) continue;
          await _step(_tts.setSpeechRate(rate), epoch);
          await _step(_tts.setVolume(0.8), epoch);
          await _step(_tts.awaitSpeakCompletion(true), epoch);
          if (_android) await _step(_tts.setQueueMode(0), epoch);
          _selected = voice;
          _selectedEngine = engine ?? 'current';
          _ready = true;
          return;
        }
      }
      throw StateError('לא נמצא קול עברי מקומי זמין. בחר קול עברי בהגדרות הקראת הטקסט והפעל משפט לדוגמה, ואז נסה שוב כאן. אפשר להעתיק דוח אבחון.');
    } on SpeechCancelled {
      rethrow;
    } catch (error) {
      _lastError = error.toString();
      rethrow;
    } finally {
      _preparing = false;
    }
  }

  Future<void> speak(String text) async {
    if (!_ready) throw StateError('הקול אינו מוכן');
    final epoch = _epoch;
    try {
      final result = await _tts.speak(text).timeout(const Duration(seconds: 20));
      if (epoch == _epoch && result != 1) throw StateError('מנוע ההקראה לא השלים את המשפט');
    } catch (error) {
      if (epoch != _epoch) return;
      _lastError = error.toString();
      _ready = false;
      await _tts.stop().timeout(const Duration(seconds: 3)).catchError((Object _) => 0);
      rethrow;
    }
  }

  Future<void> stop() async {
    _epoch++;
    if (_engine != null) await _tts.stop().timeout(const Duration(seconds: 3));
  }
}
