import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:visioncane_app/domain/benchmark.dart';

void main() {
  BenchmarkRun createRun() => BenchmarkRun(startedAt: DateTime.utc(2026, 10, 20));

  void add(BenchmarkRun run, int elapsed, double ms, {double fps = 30}) {
    run.addPerformance(elapsedMs: elapsed, processingMs: ms, reportedFps: fps);
  }

  Map<String, Object?> report(BenchmarkRun run) => run.report(
    platform: 'ios', deviceLabel: 'iPhone 13', requestedGpu: true,
  );

  test('excludes warmup and late samples with exact window boundaries', () {
    final run = createRun();
    add(run, 4999, 1000);
    add(run, 5000, 10);
    add(run, 64999, 20);
    add(run, 65000, 1000);
    run.finish(65000);
    expect(run.sampleCount, 2);
    expect(report(run)['sdk_processing_ms_p50'], 10);
    expect(report(run)['sdk_processing_ms_p95'], 20);
  });

  test('invalid metrics do not contaminate percentiles or JSON', () {
    final run = createRun();
    add(run, 6000, double.nan);
    add(run, 6000, double.infinity);
    add(run, 6000, -1);
    add(run, 6000, 0);
    add(run, 6000, 10, fps: double.infinity);
    add(run, 6000, 10, fps: -1);
    add(run, 6000, 15, fps: 0);
    expect(run.invalidSamples, 6);
    expect(run.sampleCount, 1);
    expect(() => jsonEncode(report(run)), returnsNormally);
  });

  test('interrupted run freezes data and preserves original stop reason', () {
    final run = createRun();
    add(run, 6000, 18);
    run.finish(7000, reason: 'app_backgrounded');
    add(run, 8000, 1);
    run.finish(65000);
    expect(report(run)['actual_measurement_ms'], 2000);
    expect(report(run)['stop_reason'], 'app_backgrounded');
    expect(run.sampleCount, 1);
  });

  test('empty or warmup-only run never invents measurements', () {
    final run = createRun();
    run.finish(1000, reason: 'user_stopped_benchmark');
    final data = report(run);
    expect(data['actual_measurement_ms'], 0);
    expect(data['sdk_processing_ms_p50'], isNull);
    expect(data['sdk_processing_ms_p95'], isNull);
    expect(data['sdk_reported_fps_p50'], isNull);
    expect(data['frame_drop_count'], isNull);
    expect(data['accuracy_measured'], false);
  });

  test('class counts describe appearances and exclude warmup and finished data', () {
    final run = createRun();
    run.addDetections(1000, ['car']);
    run.addDetections(6000, ['person', 'person', 'car']);
    run.finish(8000);
    run.addDetections(9000, ['car']);
    expect(report(run)['detection_appearances_by_class'], {'person': 2, 'car': 1});
  });

  test('caps raw samples and reports truncation', () {
    final run = createRun();
    for (var i = 0; i < BenchmarkRun.maxSamples + 1; i++) {
      add(run, 6000, 10);
    }
    expect(run.sampleCount, BenchmarkRun.maxSamples);
    expect(run.truncated, true);
  });

  test('nearest rank p95 handles tail latency', () {
    expect(percentile(List.generate(100, (i) => (i + 1).toDouble()), 0.95), 95);
    expect(percentile([12], 0.95), 12);
    expect(percentile([], 0.5), isNull);
  });

  test('short report excludes raw samples without dropping performance summary', () {
    final run = createRun();
    add(run, 6000, 70);
    run.finish(65000);
    final summary = report(run);
    expect(summary.containsKey('samples'), false);
    expect(summary['raw_samples_included'], false);
    expect(summary['sdk_processing_ms_p50'], 70);
    final full = run.report(platform: 'android', deviceLabel: 'SM-X510',
        requestedGpu: true, includeSamples: true);
    expect(full['samples'], hasLength(1));
  });

  test('report identifies experimental depth and the settings used in that run', () {
    final run = BenchmarkRun(startedAt: DateTime.utc(2026, 10, 20),
      model: 'depth-test-model', mode: 'depth_experiment',
      confidenceThreshold: 0.55, speechEnabled: false);
    final data = report(run);
    expect(data['model'], 'depth-test-model');
    expect(data['mode'], 'depth_experiment');
    expect(data['confidence_threshold'], 0.55);
    expect(data['speech_enabled_during_run'], false);
  });
}
