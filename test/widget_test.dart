import 'package:flutter/material.dart';
import 'package:geonexo_mobile/core/auth/auth_service.dart';
import 'package:geonexo_mobile/core/widgets/web_app_shell.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geonexo_mobile/core/ble/ble_question_protocol.dart';
import 'package:geonexo_mobile/core/offline/offline_question_cache.dart';
import 'package:geonexo_mobile/features/history/domain/entities/watch_response.dart';

void main() {
  testWidgets('PWA keeps content width when login enables question overlay', (
    tester,
  ) async {
    final auth = AuthService();
    auth.isAuthenticatedNotifier.value = false;
    const content = Key('pwa-content');
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => Overlay.wrap(
          child: const WebAppShell(child: SizedBox(key: content)),
        ),
      ),
    );
    expect(tester.getSize(find.byKey(content)).width, 800);
    auth.isAuthenticatedNotifier.value = true;
    await tester.pump();
    expect(tester.getSize(find.byKey(content)).width, 800);
    await tester.pumpWidget(const SizedBox());
    auth.isAuthenticatedNotifier.value = false;
  });

  test(
    'BLE question command preserves answer IDs across the phone/watch flow',
    () {
      final command = buildBleQuestionCommand(
        const BleQuestionPrompt(
          questionId: 'location-question-with-a-long-id',
          question: 'Como está o local?',
          options: [
            BleQuestionOption(id: 'good', label: 'Bom'),
            BleQuestionOption(id: 'bad', label: 'Ruim'),
          ],
        ),
      );
      final id = command.split('|')[1];
      final answer = tryParseBleQuestionResult('QANS|$id|good');
      expect(answer?.isAnswer, isTrue);
      expect(answer?.questionId, id);
      expect(answer?.answerId, 'good');
    },
  );

  test('Browser history format preserves offline sync and question state', () {
    final row = WatchResponse(
      id: 'r1',
      locationId: 'l1',
      locationName: 'Campus',
      questionId: 'q1',
      answerId: 'yes',
      timestamp: DateTime.utc(2026, 11, 17),
      syncStatus: SyncStatus.failed,
      questionStatus: QuestionStatus.answered,
      questionCommand: 'QST|q1|Visitou?|yes:Sim|no:Não',
    );
    final restored = WatchResponse.fromMap(row.toMap());
    expect(restored.syncStatus, SyncStatus.failed);
    expect(restored.questionStatus, QuestionStatus.answered);
    expect(restored.answerLabel, 'Sim');
    expect(restored.timestamp, row.timestamp);
  });

  test('Geofence distance remains usable without native location APIs', () {
    expect(haversineMeters(-15.6, -56.1, -15.6, -56.1), closeTo(0, .001));
    expect(haversineMeters(0, 0, 0, 1), closeTo(111195, 5));
  });
}
