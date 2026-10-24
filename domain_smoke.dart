// No Flutter engine, native hooks, compiler discovery or network is needed.
// This is a portable regression check, not a substitute for flutter test.
import 'dart:convert';
import '../lib/domain/speech_voice.dart';
import '../lib/domain/prototype.dart';
import '../lib/domain/benchmark.dart';
import '../lib/domain/field_trial.dart';

void check(bool condition, String label) {
  if (!condition) throw StateError('FAIL: $label');
  print('PASS: $label');
}

void main() {
  check(isLocalVoice('0') && !isLocalVoice('1') && !isLocalVoice(null),
    'actual Android offline metadata and unknown/network rejection');
  check(localHebrewVoices([
    {'name': 'he-local', 'locale': 'he-IL', 'network_required': '0'},
    {'name': 'he-network', 'locale': 'he-IL', 'network_required': '1'},
    {'name': 'english', 'locale': 'en-US', 'network_required': '0'},
  ], android: true).single['name'] == 'he-local', 'mixed real-format voice response');
  final policy = AnnouncementPolicy();
  const chair = SceneItem(label: 'chair', confidence: 0.9, centerX: 0.5);
  for (final ms in [0, 250, 500, 750]) { policy.observe([chair], ms); }
  check(policy.next(750)?.label == 'chair', 'stable object eligible');
  policy.markSpoken(chair, 750);
  check(policy.next(800) == null && policy.next(3000) == null,
    'cooldown and stale observations produce no repeated object');
  check(sectorFor(0.1) == ImageSector.left && sectorFor(0.5) == ImageSector.center &&
    sectorFor(0.9) == ImageSector.right, 'camera sectors');
  final run = BenchmarkRun(startedAt: DateTime.utc(2026, 10, 21));
  for (final ms in [4999, 5000, 64999, 65000]) {
    run.addPerformance(elapsedMs: ms, processingMs: 70, reportedFps: 11.7);
  }
  run.finish(65000);
  final data = run.report(platform: 'android', deviceLabel: 'SM-X510', requestedGpu: true);
  check(run.sampleCount == 2 && data['sdk_processing_ms_p50'] == 70 &&
    data['frame_drop_count'] == null && data['accuracy_measured'] == false,
    'benchmark boundaries and honest metric scope');
  final trial = FieldTrial(at: DateTime.utc(2026, 10, 21), device: 'SM-X510',
    scenario: 'chair', mode: 'detect', model: 'yolo26n', threshold: 0.4,
    speechEnabled: true, outcome: TrialOutcome.missed, lighting: 'bright',
    sector: 'center', offlineConfirmed: false, note: 'manual test');
  final parsed = FieldTrial.fromJson(jsonDecode(jsonEncode(trial.toJson())) as Map<String, dynamic>);
  check(parsed.outcome == TrialOutcome.missed && parsed.distanceMeters == null &&
    !parsed.offlineConfirmed, 'manual data round trip preserves unknowns');
  final report = fieldReport([trial]);
  check(report['total'] == 1 && !report.containsKey('accuracy'),
    'manual observations do not invent automatic accuracy');
}
