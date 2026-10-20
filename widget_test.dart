import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visioncane_app/main.dart';

void main() {
  testWidgets('camera stays off until explicit start and no metrics are fabricated', (tester) async {
    tester.view.physicalSize = const Size(430, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const VisionCaneApp());
    expect(find.text('המצלמה כבויה'), findsOneWidget);
    expect(find.text('הפעלת זיהוי'), findsOneWidget);
    expect(find.text('—'), findsNWidgets(2));
    // Dispose the observer and periodic UI refresh timer.
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
