import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {configureNative} from './native_config.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
process.chdir(root);
const flutter = process.platform === 'win32' ? 'flutter.bat' : 'flutter';
const run = (args) => {
  const result = spawnSync(flutter, args, {stdio: 'inherit', shell: process.platform === 'win32'});
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`Flutter command failed (${result.status})`);
};

// Let the installed Flutter SDK generate its own matching Gradle/Xcode projects.
// Preserve our implementation even if Flutter changes template overwrite behavior.
const protectedPaths = ['pubspec.yaml', 'README.md', '.gitignore', 'analysis_options.yaml'];
function collect(dir) {
  for (const item of fs.readdirSync(path.join(root, dir), {withFileTypes: true})) {
    const relative = path.join(dir, item.name);
    if (item.isDirectory()) collect(relative);
    else protectedPaths.push(relative);
  }
}
collect('lib');
collect('test');
const saved = new Map(protectedPaths.filter((p) => fs.existsSync(path.join(root, p)))
  .map((p) => [p, fs.readFileSync(path.join(root, p))]));
try {
  if (!fs.existsSync('android/app/build.gradle.kts') || !fs.existsSync('ios/Runner/Info.plist')) {
    run(['create', '--platforms=android,ios', '--org=dev.visioncane',
      '--project-name=visioncane_app', '--no-pub', '.']);
  }
} finally {
  for (const [relative, bytes] of saved) fs.writeFileSync(path.join(root, relative), bytes);
}
configureNative(root, process.env.APP_BUNDLE_ID);
run(['pub', 'get']);
console.log('Native projects configured. Run flutter analyze and flutter test next.');
