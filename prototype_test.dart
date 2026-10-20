import 'package:flutter_test/flutter_test.dart';
import 'package:visioncane_app/domain/prototype.dart';

SceneItem item(String name, double x, {double confidence = 0.9}) =>
    SceneItem(label: name, centerX: x, confidence: confidence);

void main() {
  test('image sectors have defined boundaries, independent of body heading', () {
    expect(sectorFor(0.1), ImageSector.left);
    expect(sectorFor(0.35), ImageSector.center);
    expect(sectorFor(0.65), ImageSector.center);
    expect(sectorFor(0.9), ImageSector.right);
    expect(sectorText(ImageSector.center), 'במרכז התמונה');
  });

  test('requires at least 700 ms of consecutive high-confidence detections', () {
    final policy = AnnouncementPolicy();
    for (var now = 0; now <= 600; now += 100) {
      policy.observe([item('chair', 0.5)], now);
      expect(policy.next(now), isNull);
    }
    policy.observe([item('chair', 0.5)], 700);
    expect(policy.next(700)?.label, 'chair');
  });

  test('rejects invalid and low-confidence observations', () {
    final policy = AnnouncementPolicy();
    for (var now = 0; now <= 1000; now += 100) {
      policy.observe([
        item('chair', 0.5, confidence: 0.64),
        item('car', double.nan),
        item('car', -0.5),
        item('car', 0.5, confidence: double.nan),
      ], now);
    }
    expect(policy.next(1000), isNull);
  });

  test('a gap resets stability and stale detections cannot be announced', () {
    final policy = AnnouncementPolicy();
    for (var now = 0; now <= 700; now += 100) policy.observe([item('chair', 0.5)], now);
    expect(policy.next(1051), isNull);
    policy.observe([item('chair', 0.5)], 1200);
    expect(policy.next(1200), isNull);
  });

  test('enforces global and per-category/sector repeat cooldowns', () {
    final policy = AnnouncementPolicy();
    final chair = item('chair', 0.5);
    for (var now = 0; now <= 700; now += 100) policy.observe([chair], now);
    policy.markSpoken(chair, 700);
    for (var now = 800; now <= 12600; now += 100) {
      policy.observe([chair], now);
      expect(policy.next(now), isNull);
    }
    policy.observe([chair], 12700);
    expect(policy.next(12700)?.label, 'chair');
  });

  test('prefers a stable center-image item and does not duplicate same-frame detections', () {
    final policy = AnnouncementPolicy();
    for (var now = 0; now <= 700; now += 100) {
      policy.observe([item('car', 0.1), item('chair', 0.5, confidence: 0.7)], now);
    }
    expect(policy.next(700)?.label, 'chair');
    policy.reset();
    policy.observe(List.generate(100, (_) => item('chair', 0.5)), 0);
    expect(policy.next(700), isNull);
  });

  test('reset discards detections when camera session changes', () {
    final policy = AnnouncementPolicy();
    for (var now = 0; now <= 700; now += 100) policy.observe([item('chair', 0.5)], now);
    policy.reset();
    expect(policy.next(700), isNull);
  });
}
