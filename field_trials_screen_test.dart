import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visioncane_app/domain/field_trial.dart';
import 'package:visioncane_app/screens/field_trials_screen.dart';
import 'package:visioncane_app/services/field_trial_store.dart';

class MemoryTrialStore extends FieldTrialStore {
  List<FieldTrial> records = [];
  @override
  Future<List<FieldTrial>> load() async => List.of(records);
  @override
  Future<void> save(List<FieldTrial> trials) async { records = List.of(trials); }
}

void main() {
  testWidgets('requires an explicit outcome before saving', (tester) async {
    tester.view.physicalSize = const Size(600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = MemoryTrialStore();
    await tester.pumpWidget(MaterialApp(home: FieldTrialsScreen(
      device: 'SM-X510', mode: 'detect', model: 'yolo26n', threshold: 0.4,
      speechEnabled: false, store: store,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('שמירת ניסיון'));
    await tester.pump();
    expect(find.text('בחר תוצאה לפי מה שראית בניסוי.'), findsOneWidget);
    await tester.tap(find.text('החמצה'));
    await tester.pump();
    await tester.tap(find.text('שמירת ניסיון'));
    await tester.pumpAndSettle();
    expect(find.text('ניסיונות שמורים: 1'), findsOneWidget);
    expect(store.records.single.scenario, 'chair');
    expect(store.records.single.outcome, TrialOutcome.missed);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
