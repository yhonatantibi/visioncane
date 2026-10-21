import 'prototype.dart';

enum TrialOutcome { correct, missed, wrong, inconclusive }

String outcomeLabel(TrialOutcome value) => switch (value) {
  TrialOutcome.correct => 'הצליח לפי הציפייה',
  TrialOutcome.missed => 'החמצה',
  TrialOutcome.wrong => 'תוצאה שגויה',
  TrialOutcome.inconclusive => 'לא ניתן לקבוע',
};

const trialScenarios = <String, String>{
  'chair': 'כיסא - זיהוי ושיוך לצד בתמונה',
  'couch': 'ספה - זיהוי ושיוך לצד בתמונה',
  'ironing_board': 'קרש גיהוץ - זיהוי או הבחנה בעומק',
  'thin_legs': 'רגליים דקות - הבחנה מהרקע',
  'cable': 'כבל - הבחנה מהרקע',
  'negative_control': 'ביקורת - ללא עצם המטרה',
  'offline_restart': 'פתיחה מחדש בלי רשת',
  'stop_background': 'עצירה ומעבר לרקע',
};

class FieldTrial {
  FieldTrial({required this.at, required this.device, required this.scenario,
    required this.mode, required this.outcome, required this.lighting,
    required this.sector, required this.offlineConfirmed, required this.note,
    required this.model, required this.threshold, required this.speechEnabled,
    this.distanceMeters, this.appVersion = prototypeVersion}) {
    if (device.trim().isEmpty || !trialScenarios.containsKey(scenario) ||
        !const ['detect', 'depth_experiment'].contains(mode) ||
        !threshold.isFinite || threshold < 0 || threshold > 1 ||
        (distanceMeters != null && (!distanceMeters!.isFinite || distanceMeters! <= 0))) {
      throw ArgumentError('Invalid field trial');
    }
  }
  final DateTime at;
  final String device, scenario, mode, lighting, sector, note, model, appVersion;
  final TrialOutcome outcome;
  final bool offlineConfirmed, speechEnabled;
  final double threshold;
  final double? distanceMeters;

  Map<String, Object?> toJson() => {
    'at': at.toUtc().toIso8601String(), 'app_version': appVersion,
    'device_user_supplied': device.trim(), 'scenario': scenario,
    'mode': mode, 'model': model, 'confidence_threshold': threshold,
    'speech_enabled': speechEnabled, 'outcome_user_supplied': outcome.name,
    'lighting_user_supplied': lighting, 'image_sector_user_supplied': sector,
    'distance_meters_user_measured': distanceMeters,
    'offline_restart_user_confirmed': offlineConfirmed, 'note': note.trim(),
  };

  factory FieldTrial.fromJson(Map<String, dynamic> json) => FieldTrial(
    at: DateTime.parse(json['at'] as String),
    appVersion: json['app_version'] as String,
    device: json['device_user_supplied'] as String,
    scenario: json['scenario'] as String, mode: json['mode'] as String,
    model: json['model'] as String, threshold: (json['confidence_threshold'] as num).toDouble(),
    speechEnabled: json['speech_enabled'] as bool,
    outcome: TrialOutcome.values.byName(json['outcome_user_supplied'] as String),
    lighting: json['lighting_user_supplied'] as String,
    sector: json['image_sector_user_supplied'] as String,
    distanceMeters: (json['distance_meters_user_measured'] as num?)?.toDouble(),
    offlineConfirmed: json['offline_restart_user_confirmed'] as bool,
    note: json['note'] as String,
  );
}

Map<String, Object?> fieldReport(List<FieldTrial> trials) {
  final groups = <String, Map<String, int>>{};
  for (final trial in trials) {
    // Never pool depth visibility, lifecycle and detection into one accuracy score.
    final key = '${trial.appVersion}/${trial.mode}/${trial.scenario}';
    final counts = groups.putIfAbsent(key, () => {
      'total': 0, for (final outcome in TrialOutcome.values) outcome.name: 0,
    });
    counts['total'] = counts['total']! + 1;
    counts[trial.outcome.name] = counts[trial.outcome.name]! + 1;
  }
  return {
    'schema_version': 1, 'report_kind': 'manual_field_trials',
    'export_app_version': prototypeVersion, 'total': trials.length,
    'scope': 'User-entered observations; not automated accuracy, distance or network verification.',
    'groups': groups, 'trials': trials.map((t) => t.toJson()).toList(),
  };
}

String fieldSummary(List<FieldTrial> trials) {
  final groups = fieldReport(trials)['groups']! as Map<String, Map<String, int>>;
  return 'VisionCane $prototypeVersion | בדיקות ידניות: ${trials.length}\n'
      '${groups.entries.map((e) => '${e.key}: הצליח ${e.value['correct']}/${e.value['total']}, '
          'החמצה ${e.value['missed']}, שגוי ${e.value['wrong']}, לא ברור ${e.value['inconclusive']}').join('\n')}\n'
      'תצפיות ידניות בלבד; אינן אישור לדיוק או לבטיחות.';
}
