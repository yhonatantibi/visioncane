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
    expect(find.text('עצירת הכול'), findsOneWidget);
    expect(find.text('הפעלת קול עברי'), findsOneWidget);
    expect(find.text('תאר עכשיו'), findsOneWidget);
    expect(find.ancestor(of: find.text('תאר עכשיו'), matching: find.byType(ListView)), findsNothing);
    expect(find.ancestor(of: find.text('עצירת הכול'), matching: find.byType(ListView)), findsNothing);
    // Dispose the observer and periodic UI refresh timer.
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('demo supports large Hebrew text on a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(const VisionCaneApp());
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(ListView), const Offset(0, -650));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('research tools are separate and switching does not start camera', (tester) async {
    await tester.pumpWidget(const VisionCaneApp());
    await tester.tap(find.text('כלי בדיקה'));
    await tester.pumpAndSettle();
    expect(find.text('ניסוי עומק'), findsOneWidget);
    await tester.tap(find.text('הדגמה'));
    await tester.pumpAndSettle();
    expect(find.text('מה נמצא מולי?'), findsOneWidget);
    expect(find.text('המצלמה כבויה'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
