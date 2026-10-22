import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root = fileURLToPath(new URL('../', import.meta.url));
const required = ['pubspec.yaml', 'lib/main.dart', 'lib/domain/benchmark.dart',
  'lib/domain/labels.dart', 'lib/domain/prototype.dart', 'lib/domain/speech_voice.dart',
  'lib/domain/field_trial.dart', 'lib/services/local_speech.dart',
  'lib/services/field_trial_store.dart', 'lib/screens/field_trials_screen.dart',
  'test/speech_voice_test.dart', 'test/local_speech_test.dart',
  'lib/domain/spatial_scene.dart', 'lib/services/spatial_perception.dart',
  'tool/spatial_smoke.dart', 'test/spatial_scene_test.dart',
  'lib/screens/photo_review_screen.dart', 'test/photo_review_screen_test.dart'];
const missing = required.filter(p => !fs.existsSync(path.join(root, p)));
const flattened = fs.readdirSync(root).filter(p => p.endsWith('.dart'));
if (missing.length || flattened.length) {
  console.error('Incorrect upload layout. Preserve lib/domain, lib/services and test folders.');
  if (missing.length) console.error('Missing:', missing.join(', '));
  if (flattened.length) console.error('Misplaced Dart files at root:', flattened.join(', '));
  process.exitCode = 1;
} else console.log('Project layout OK.');
