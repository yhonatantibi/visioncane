import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:visioncane_app/services/local_speech.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_tts');
  final calls = <MethodCall>[];
  var active = 'samsung';
  var allNetwork = false;
  var rejectVoice = false;
  Completer<Object?>? delayedVoices;
  setUp(() {
    calls.clear(); active = 'samsung'; allNetwork = false; rejectVoice = false; delayedVoices = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        switch (call.method) {
          case 'getEngines': return ['samsung', 'google'];
          case 'getDefaultEngine': return 'google';
          case 'setEngine': active = call.arguments as String; return 1;
          case 'getVoices':
            if (delayedVoices != null) return delayedVoices!.future;
            return [{ 'name': 'he-local', 'locale': 'he-IL',
              'network_required': allNetwork || active == 'samsung' ? '1' : '0'}];
          case 'setVoice': return rejectVoice ? 0 : 1;
          default: return 1;
        }
      });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
    .setMockMethodCallHandler(channel, null));

  test('switches to installed engine and accepts real Android string metadata', () async {
    final speech = LocalSpeech(engine: FlutterTts(), android: true);
    await speech.prepare();
    expect(speech.ready, isTrue);
    expect(speech.diagnostics['engine'], 'google');
    await speech.speak('שלום');
    expect(calls.where((c) => c.method == 'speak'), hasLength(1));
  });
  test('never uses network Hebrew as a silent fallback', () async {
    allNetwork = true;
    final speech = LocalSpeech(engine: FlutterTts(), android: true);
    await expectLater(speech.prepare(), throwsStateError);
    expect(speech.ready, isFalse);
    expect(calls.where((c) => c.method == 'setVoice'), isEmpty);
    await expectLater(speech.speak('שלום'), throwsStateError);
  });
  test('native rejection is not displayed as ready', () async {
    rejectVoice = true;
    final speech = LocalSpeech(engine: FlutterTts(), android: true);
    await expectLater(speech.prepare(), throwsStateError);
    expect(speech.ready, isFalse);
  });
  test('stop during preparation prevents late readiness and speech', () async {
    delayedVoices = Completer<Object?>();
    final speech = LocalSpeech(engine: FlutterTts(), android: true);
    final preparation = speech.prepare();
    final expectation = expectLater(preparation, throwsA(isA<SpeechCancelled>()));
    while (!calls.any((c) => c.method == 'getVoices')) {
      await Future<void>.delayed(Duration.zero);
    }
    await speech.stop();
    delayedVoices!.complete([{'name': 'he', 'locale': 'he-IL', 'network_required': '0'}]);
    await expectation;
    expect(speech.ready, isFalse);
    expect(calls.where((c) => c.method == 'setVoice'), isEmpty);
  });
}
