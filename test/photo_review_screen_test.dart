import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visioncane_app/screens/photo_review_screen.dart';

void main() {
  testWidgets('saved photo mode starts without models or camera and cannot analyse absent image', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PhotoReviewScreen()));
    expect(find.text('בחירת תמונה'), findsOneWidget);
    expect(find.textContaining('אינה נכללת בדוח'), findsOneWidget);
    final analyse = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'ניתוח תמונה'));
    expect(analyse.onPressed, isNull);
    expect(find.text('הקראת התיאור'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
