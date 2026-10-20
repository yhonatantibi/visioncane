import test from 'node:test';
import assert from 'node:assert/strict';
import {patchManifest, patchGradle, patchPlist, patchXcode, podfile} from './native_config.mjs';

test('release manifest gets camera and download permission once', () => {
  const initial = '<manifest xmlns:android="http://schemas.android.com/apk/res/android"><application android:label="visioncane_app"></application></manifest>';
  const result = patchManifest(initial);
  assert.equal(patchManifest(result), result);
  assert.equal(result.match(/android.permission.CAMERA/g).length, 1);
  assert.equal(result.match(/android.permission.INTERNET/g).length, 1);
  assert.match(result, /android:label="VisionCane"/);
  assert.doesNotMatch(result, /RECORD_AUDIO|ACCESS_FINE_LOCATION|usesCleartextTraffic/);
});

test('native Android minimum and target versions are configured idempotently', () => {
  const initial = 'compileSdk = flutter.compileSdkVersion\nminSdk = flutter.minSdkVersion\ntargetSdk = flutter.targetSdkVersion\n';
  const result = patchGradle(initial);
  assert.equal(result, 'compileSdk = maxOf(flutter.compileSdkVersion, 36)\nminSdk = maxOf(flutter.minSdkVersion, 23)\ntargetSdk = maxOf(flutter.targetSdkVersion, 36)\n');
  assert.equal(patchGradle(result), result);
});

test('iOS camera usage description and display name are inserted once', () => {
  const initial = '<plist><dict><key>CFBundleDisplayName</key><string>Old</string></dict></plist>';
  const result = patchPlist(initial);
  assert.equal(patchPlist(result), result);
  assert.equal(result.match(/<key>NSCameraUsageDescription<\/key>/g).length, 1);
  assert.match(result, /<string>VisionCane<\/string>/);
  assert.doesNotMatch(result, /NSMicrophoneUsageDescription|NSLocation/);
});

test('bundle identifier updates keep RunnerTests distinct and reject injection', () => {
  const initial = 'PRODUCT_BUNDLE_IDENTIFIER = dev.old.app;\nPRODUCT_BUNDLE_IDENTIFIER = dev.old.app.RunnerTests;\nIPHONEOS_DEPLOYMENT_TARGET = 13.0;';
  const result = patchXcode(initial, 'app.visioncane.experiment');
  assert.match(result, /app\.visioncane\.experiment;/);
  assert.match(result, /app\.visioncane\.experiment\.RunnerTests;/);
  assert.match(result, /IPHONEOS_DEPLOYMENT_TARGET = 15.0;/);
  assert.equal(patchXcode(result, 'app.visioncane.experiment'), result);
  assert.throws(() => patchXcode(initial, 'invalid; OTHER = value'));
  assert.match(patchXcode(initial), /dev\.old\.app;/);
});

test('camera description is at the plist root even with nested scene configuration', () => {
  const initial = '<plist><dict><key>UIApplicationSceneManifest</key><dict><key>Nested</key><string>value</string></dict></dict></plist>';
  const result = patchPlist(initial);
  assert.match(result, /<string>value<\/string><\/dict>\s*<key>NSCameraUsageDescription/);
  assert.equal(patchPlist(result), result);
});

test('CocoaPods enables only camera permission and preserves inherited flags', () => {
  assert.match(podfile, /PERMISSION_CAMERA=1/);
  assert.match(podfile, /\$\(inherited\)/);
  assert.doesNotMatch(podfile, /PERMISSION_MICROPHONE=1/);
});
