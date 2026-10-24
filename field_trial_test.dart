import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:visioncane_app/domain/field_trial.dart';
import 'package:visioncane_app/services/field_trial_store.dart';

FieldTrial trial({String mode = 'detect', String scenario = 'chair',
    TrialOutcome outcome = TrialOutcome.correct, double? distance}) => FieldTrial(
  at: DateTime.utc(2026, 10, 20), device: 'SM-X510', scenario: scenario,
  mode: mode, model: 'test-model', threshold: 0.4, speechEnabled: false,
  outcome: outcome, lighting: 'bright', sector: 'center',
  offlineConfirmed: false, note: 'בדיקה', distanceMeters: distance,
);

void main() {
  test('does not combine depth, detection and control observations', () {
    final report = fieldReport([
      trial(), trial(outcome: TrialOutcome.missed),
      trial(mode: 'depth_experiment'), trial(scenario: 'negative_control'),
    ]);
    final groups = report['groups']! as Map<String, Map<String, int>>;
    expect(groups, hasLength(3));
    expect(groups.values.first['total'], 2);
    expect(groups.values.first['correct'], 1);
    expect(groups.values.first['missed'], 1);
    expect(report.containsKey('accuracy'), false);
  });
  test('unknown observations stay in totals without becoming successes', () {
    final report = fieldReport([trial(outcome: TrialOutcome.inconclusive)]);
    final counts = (report['groups']! as Map<String, Map<String, int>>).values.single;
    expect(counts['total'], 1);
    expect(counts['correct'], 0);
    expect(counts['inconclusive'], 1);
  });
  test('round trip preserves manual provenance and missing distance', () {
    final original = trial();
    final parsed = FieldTrial.fromJson(jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>);
    expect(parsed.toJson(), original.toJson());
    expect(parsed.distanceMeters, isNull);
    expect(parsed.offlineConfirmed, false);
  });
  test('invalid distances and unknown scenarios are rejected', () {
    for (final value in [double.nan, double.infinity, -1.0, 0.0]) {
      expect(() => trial(distance: value), throwsArgumentError);
    }
    expect(() => trial(scenario: 'unknown'), throwsArgumentError);
  });
  test('empty report contains no invented score', () {
    expect(fieldReport([])['total'], 0);
    expect(fieldReport([])['groups'], isEmpty);
    expect(fieldSummary([]), contains('בדיקות ידניות: 0'));
  });
  test('saved trials survive a new store instance and a second save', () async {
    final root = await Directory.systemTemp.createTemp('visioncane-trials-');
    addTearDown(() => root.delete(recursive: true));
    final store = FieldTrialStore(directory: root);
    expect(await store.load(), isEmpty);
    await store.save([trial()]);
    await store.save([trial(), trial(outcome: TrialOutcome.wrong)]);
    final loaded = await FieldTrialStore(directory: root).load();
    expect(loaded, hasLength(2));
    expect(loaded.last.outcome, TrialOutcome.wrong);
  });
  test('corrupt data is reported, not silently treated as an empty log', () async {
    final root = await Directory.systemTemp.createTemp('visioncane-corrupt-');
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/field-trials.json').writeAsString('{broken');
    await expectLater(FieldTrialStore(directory: root).load(), throwsFormatException);
    expect(await File('${root.path}/field-trials.json').readAsString(), '{broken');
  });
}
