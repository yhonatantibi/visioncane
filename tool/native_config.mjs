import fs from 'node:fs';
import path from 'node:path';

export function patchManifest(text) {
  for (const name of ['CAMERA', 'INTERNET']) {
    if (!text.includes(`android.permission.${name}`)) {
      text = text.replace(/<manifest\b[^>]*>/, (tag) =>
        `${tag}\n    <uses-permission android:name="android.permission.${name}" />`);
    }
  }
  if (!text.includes('android.hardware.camera')) {
    text = text.replace(/<application\b/, '<uses-feature android:name="android.hardware.camera" android:required="false" />\n    <application');
  }
  if (!text.includes('android.intent.action.TTS_SERVICE')) {
    if (text.includes('</queries>')) {
      text = text.replace('</queries>', '<intent><action android:name="android.intent.action.TTS_SERVICE" /></intent>\n    </queries>');
    } else {
      text = text.replace('</manifest>', '<queries><intent><action android:name="android.intent.action.TTS_SERVICE" /></intent></queries>\n</manifest>');
    }
  }
  return text.replace(/android:label="[^"]*"/, 'android:label="VisionCane"');
}

export function patchGradle(text) {
  return text
    .replace(/minSdk\s*=\s*[^\r\n]+/, 'minSdk = maxOf(flutter.minSdkVersion, 24)')
    .replace(/compileSdk\s*=\s*[^\r\n]+/, 'compileSdk = maxOf(flutter.compileSdkVersion, 36)')
    .replace(/targetSdk\s*=\s*[^\r\n]+/, 'targetSdk = maxOf(flutter.targetSdkVersion, 36)');
}

export function patchPlist(text) {
  const entries = {
    NSCameraUsageDescription: 'המצלמה משמשת לזיהוי עצמים מקומי במסגרת ניסוי VisionCane.',
    CFBundleDisplayName: 'VisionCane',
  };
  for (const [key, value] of Object.entries(entries)) {
    const pattern = new RegExp(`<key>${key}</key>\\s*<string>[^<]*</string>`);
    const entry = `<key>${key}</key>\n\t<string>${value}</string>`;
    text = pattern.test(text) ? text.replace(pattern, entry) :
      text.replace(/<\/dict>\s*<\/plist>\s*$/, `\t${entry}\n</dict>\n</plist>\n`);
  }
  return text;
}

export function patchXcode(text, bundleId) {
  text = text.replace(/IPHONEOS_DEPLOYMENT_TARGET = [^;]+;/g, 'IPHONEOS_DEPLOYMENT_TARGET = 15.0;');
  if (bundleId) {
    if (!/^[A-Za-z][A-Za-z0-9-]*(\.[A-Za-z][A-Za-z0-9-]*){2,}$/.test(bundleId)) {
      throw new Error('APP_BUNDLE_ID must be a valid reverse-domain identifier');
    }
    text = text.replace(/PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);/g, (_, old) =>
      `PRODUCT_BUNDLE_IDENTIFIER = ${bundleId}${old.includes('RunnerTests') ? '.RunnerTests' : ''};`);
  }
  return text;
}

export const podfile = `platform :ios, '15.0'
ENV['COCOAPODS_DISABLE_STATS'] = 'true'
project 'Runner', { 'Debug' => :debug, 'Profile' => :release, 'Release' => :release }

def flutter_root
  generated = File.expand_path(File.join('..', 'Flutter', 'Generated.xcconfig'), __FILE__)
  raise "Run flutter pub get before pod install" unless File.exist?(generated)
  File.foreach(generated) do |line|
    match = line.match(/FLUTTER_ROOT\\=(.*)/)
    return match[1].strip if match
  end
  raise "FLUTTER_ROOT not found"
end
require File.expand_path(File.join('packages', 'flutter_tools', 'bin', 'podhelper'), flutter_root)
flutter_ios_podfile_setup
target 'Runner' do
  use_frameworks!
  flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))
  target 'RunnerTests' do
    inherit! :search_paths
  end
end
post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
    target.build_configurations.each do |config|
      if config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'].to_f < 15.0
        config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
      end
      config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= ['$(inherited)']
      unless config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'].include?('PERMISSION_CAMERA=1')
        config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] << 'PERMISSION_CAMERA=1'
      end
    end
  end
end
`;

export function configureNative(root, bundleId) {
  const update = (relative, patch) => {
    const file = path.join(root, relative);
    if (!fs.existsSync(file)) throw new Error(`Missing generated platform file: ${relative}`);
    const before = fs.readFileSync(file, 'utf8');
    const after = patch(before);
    fs.writeFileSync(file, after, 'utf8');
  };
  update('android/app/src/main/AndroidManifest.xml', patchManifest);
  update('android/app/build.gradle.kts', patchGradle);
  update('ios/Runner/Info.plist', patchPlist);
  update('ios/Runner.xcodeproj/project.pbxproj', (text) => patchXcode(text, bundleId));
  fs.writeFileSync(path.join(root, 'ios/Podfile'), podfile);
}
