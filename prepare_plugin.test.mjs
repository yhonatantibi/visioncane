import test from 'node:test';
import assert from 'node:assert/strict';
import {patchAndroid, patchApple} from './prepare_plugin.mjs';

test('Android rotates exported pixels by the exact captured camera angle and attests dimensions', () => {
  const source = 'result.copy(originalImage = bitmap)  // Reuse bitmap from ImageProxy conversion\n' +
    'enhancedStreamData["imageHeight"] = resultWithOriginalImage.origShape.height';
  const patched = patchAndroid(source);
  assert.match(patched, /postRotate\(rotationDegrees.toFloat\(\)\)/);
  assert.match(patched, /originalImage = upright/);
  assert.match(patched, /originalImage\?\.width == orientedWidth/);
  assert.equal(patchAndroid(patched), patched);
});
test('Apple normalizes UIImage and verifies dimensions before asserting alignment', () => {
  const patched = patchApple('if let imageData = originalImage.jpegData(compressionQuality: 0.9) {\nmap["originalImage"] = imageData');
  assert.match(patched, /originalImage.draw/);
  assert.match(patched, /upright.jpegData/);
  assert.match(patched, /result.orig_shape.height/);
  assert.equal(patchApple(patched), patched);
});
test('changed native code fails closed instead of silently losing alignment fix', () => {
  assert.throws(() => patchAndroid('new upstream'), /Pinned plugin changed/);
  assert.throws(() => patchApple('new upstream'), /Pinned plugin changed/);
});
