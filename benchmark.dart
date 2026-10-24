import 'dart:math' as math;

import 'prototype.dart';

/// These are SDK processing samples, NOT capture-to-alert measurements.
class PerformanceSample {
  const PerformanceSample({
    required this.elapsedMs,
    required this.processingMs,
    required this.reportedFps,
  });

  final int elapsedMs;
  final double processingMs;
  final double reportedFps;

  Map<String, Object> toJson() => {
    'elapsed_ms': elapsedMs,
    'sdk_processing_ms': processingMs,
    'sdk_reported_fps': reportedFps,
  };
}

class BenchmarkRun {
  BenchmarkRun({
    required this.startedAt,
    this.model = 'yolo26n',
    this.mode = 'detect',
    this.confidenceThreshold = 0.4,
    this.speechEnabled = false,
    this.warmupMs = 5000,
    this.measurementMs = 60000,
  });

  final DateTime startedAt;
  final String model;
  final String mode;
  final double confidenceThreshold;
  final bool speechEnabled;
  final int warmupMs;
  final int measurementMs;
  final List<PerformanceSample> _samples = [];
  final Map<String, int> _detectionsByClass = {};
  static const maxSamples = 10000;
  bool finished = false;
  bool truncated = false;
  int? endedElapsedMs;
  String? stopReason;
  int invalidSamples = 0;

  int get sampleCount => _samples.length;
  int get totalMs => warmupMs + measurementMs;
  bool _inWindow(int elapsedMs) =>
      !finished && elapsedMs >= warmupMs && elapsedMs < totalMs;

  void addPerformance({
    required int elapsedMs,
    required double processingMs,
    required double reportedFps,
  }) {
    if (!_inWindow(elapsedMs)) return;
    if (!processingMs.isFinite || processingMs <= 0 ||
        !reportedFps.isFinite || reportedFps < 0) {
      invalidSamples++;
      return;
    }
    if (_samples.length >= maxSamples) {
      truncated = true;
      return;
    }
    _samples.add(PerformanceSample(
      elapsedMs: elapsedMs,
      processingMs: processingMs,
      reportedFps: reportedFps,
    ));
  }

  /// Counts detection appearances in callbacks, not unique tracked objects.
  void addDetections(int elapsedMs, Iterable<String> classes) {
    if (!_inWindow(elapsedMs)) return;
    for (final name in classes) {
      _detectionsByClass.update(name, (value) => value + 1, ifAbsent: () => 1);
    }
  }

  void finish(int elapsedMs, {String reason = 'completed'}) {
    if (finished) return;
    finished = true;
    endedElapsedMs = elapsedMs;
    stopReason = reason;
  }

  Map<String, Object?> report({
    required String platform,
    required String deviceLabel,
    required bool requestedGpu,
    bool includeSamples = false,
  }) {
    final processing = _samples.map((s) => s.processingMs).toList()..sort();
    final fps = _samples.map((s) => s.reportedFps).toList()..sort();
    return {
      'schema_version': 2,
      'app_version': prototypeVersion,
      'model': model,
      'mode': mode,
      'speech_enabled_during_run': speechEnabled,
      'plugin': 'ultralytics_yolo 0.6.16',
      'platform': platform,
      'device_label_user_supplied': deviceLabel.trim(),
      'requested_android_gpu': platform == 'android' ? requestedGpu : null,
      'actual_accelerator': 'not_verified_check_native_device_logs',
      'camera_resolution_requested': '720p',
      'confidence_threshold': confidenceThreshold,
      'started_at': startedAt.toUtc().toIso8601String(),
      'warmup_ms': warmupMs,
      'planned_measurement_ms': measurementMs,
      'actual_measurement_ms': endedElapsedMs == null ? null :
          math.max(0, math.min(measurementMs, endedElapsedMs! - warmupMs)),
      'finished': finished,
      'stop_reason': stopReason,
      'sample_count': sampleCount,
      'invalid_samples': invalidSamples,
      'samples_truncated': truncated,
      'sdk_processing_ms_p50': percentile(processing, 0.5),
      'sdk_processing_ms_p95': percentile(processing, 0.95),
      'sdk_processing_ms_max': processing.isEmpty ? null : processing.last,
      'sdk_reported_fps_p50': percentile(fps, 0.5),
      'detection_appearances_by_class': Map<String, int>.of(_detectionsByClass),
      'metric_scope': 'SDK-reported processing time and FPS. Not camera FPS, '
          'not end-to-end latency, not verified every-frame processing.',
      'frame_drop_count': null,
      'accuracy_measured': false,
      'thermal_and_battery_measured': false,
      'raw_samples_included': includeSamples,
      if (includeSamples) 'samples': _samples.map((s) => s.toJson()).toList(),
    };
  }
}

/// Nearest-rank percentile over a sorted list. Missing data stays missing.
double? percentile(List<double> sorted, double fraction) {
  if (sorted.isEmpty) return null;
  final index = (fraction.clamp(0, 1) * sorted.length).ceil() - 1;
  return sorted[math.max(0, index)];
}
