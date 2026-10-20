import 'dart:io';

import 'package:flutter_tts/flutter_tts.dart';

/// Uses installed system voices. Android network-required voices are rejected.
class LocalSpeech {
  FlutterTts? _engine;
  FlutterTts get _tts => _engine ??= FlutterTts();
  bool _ready = false;
  int _epoch = 0;

  Future<void> prepare() async {
    final epoch = ++_epoch;
    final raw = await _tts.getVoices;
    final voices = raw is List<Object?> ? raw : <Object?>[];
    Map<Object?, Object?>? selected;
    for (final value in voices) {
      if (value is! Map<Object?, Object?>) continue;
      final locale = value['locale']?.toString().toLowerCase() ?? '';
      final hebrew = locale == 'he' || locale == 'iw' ||
          locale.startsWith('he-') || locale.startsWith('he_') ||
          locale.startsWith('iw-') || locale.startsWith('iw_');
      final network = value['network_required'];
      final local = network == false || network == 0 || network == 'false';
      if (hebrew && value['name'] != null && (!Platform.isAndroid || local)) {
        selected = value;
        break;
      }
    }
    if (selected == null) {
      throw StateError('לא נמצא קול עברי מקומי. יש להתקין קול עברי בהגדרות הקראת הטקסט של המכשיר ולנסות שוב.');
    }
    await _tts.setLanguage(selected['locale'].toString());
    await _tts.setVoice({'name': selected['name'].toString(), 'locale': selected['locale'].toString()});
    await _tts.setSpeechRate(0.45);
    await _tts.setVolume(0.8);
    await _tts.awaitSpeakCompletion(true);
    if (Platform.isAndroid) await _tts.setQueueMode(0);
    if (epoch != _epoch) return;
    _ready = true;
  }

  Future<void> speak(String text) async {
    if (!_ready) throw StateError('הקול אינו מוכן');
    await _tts.speak(text);
  }

  Future<void> stop() async {
    _epoch++;
    if (_engine != null) await _tts.stop();
  }
}
