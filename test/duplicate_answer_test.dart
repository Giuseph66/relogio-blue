import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:geonexo_mobile/core/auth/auth_service.dart';
import 'package:geonexo_mobile/core/device/device_identity.dart';
import 'package:geonexo_mobile/features/history/data/datasources/watch_response_dao.dart';
import 'package:geonexo_mobile/features/history/data/repositories/watch_response_repository.dart';
import 'package:geonexo_mobile/features/history/domain/entities/watch_response.dart';
import 'package:geonexo_mobile/features/ble_old/domain/entities/ble_message.dart';
import 'package:geonexo_mobile/features/ble_old/presentation/controllers/messages_controller.dart';
import 'package:geonexo_mobile/features/location_tracker/domain/entities/tracked_location.dart';
import 'package:geonexo_mobile/features/location_tracker/presentation/controllers/visit_question_orchestrator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MemoryDao extends WatchResponseDao {
  final rows = <String, WatchResponse>{};
  @override
  Future<void> insert(WatchResponse r) async => rows[r.id] = r;
  @override
  Future<WatchResponse?> getById(String id) async => rows[id];
  @override
  Future<List<WatchResponse>> getAll() async => rows.values.toList();
  @override
  Future<void> updateStatus(String id, SyncStatus status) async =>
      rows[id] = rows[id]!.copyWith(syncStatus: status);
}

class FakeMessages implements MessagesController {
  @override
  Stream<List<BleMessage>> get messages => const Stream.empty();
  @override
  Stream<TickStatus> get tickStatus => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MemoryDao dao;
  late WatchResponseRepository repository;
  late List<http.Request> sent;

  Future<WatchResponse> answer(int status, {Map<String, Object> prefs = const {
    'device_identity': 'android-abc',
  }}) async {
    SharedPreferences.setMockInitialValues(prefs);
    return http.runWithClient(
      () => repository.saveResponse(
        locationId: 'l', locationName: 'L', questionId: 'q', answerId: 'a',
        serverUrl: 'http://server',
      ),
      () => MockClient((request) async {
        sent.add(request);
        return http.Response('{}', status);
      }),
    ).then((r) => dao.rows[r.id]!);
  }

  setUp(() {
    dao = MemoryDao();
    repository = WatchResponseRepository(dao: dao);
    sent = [];
  });

  test('answers carry the device and a stable id', () async {
    final saved = await answer(201);
    expect(saved.syncStatus, SyncStatus.synced);
    final body = jsonDecode(sent.single.body) as Map;
    expect(body['deviceId'], 'android-abc');
    expect(body['responseId'], saved.id);
    expect(sent.single.headers.containsKey('X-Admin-Session'), isFalse);
  });

  test('refused answers are final; failures stay for retry', () async {
    expect((await answer(409)).syncStatus, SyncStatus.rejected);
    expect((await answer(410)).syncStatus, SyncStatus.rejected);
    for (final status in [401, 426, 500]) {
      expect((await answer(status)).syncStatus, SyncStatus.failed);
    }
  });

  test('answers come from the APK or the installed PWA; admins are exempt', () {
    bool allowed({bool web = true, bool standalone = false, bool admin = false}) =>
        DeviceIdentity.answerAllowed(web: web, standalone: standalone, admin: admin);
    expect(allowed(), isFalse);
    expect(allowed(standalone: true), isTrue);
    expect(allowed(admin: true), isTrue);
    expect(allowed(web: false), isTrue);
  });

  test('only administrators can send a question from the catalog', () async {
    final orchestrator = VisitQuestionOrchestrator(
      responseRepository: repository,
      messagesController: FakeMessages(),
    );
    addTearDown(orchestrator.dispose);
    addTearDown(() => AuthService().isAuthenticatedNotifier.value = false);
    final location = TrackedLocation(
      id: 'l', name: 'L', latitude: 0, longitude: 0, radiusMeters: 50,
      createdAt: DateTime(2026),
    );
    Future<VisitResult> send() => http.runWithClient(
          () => orchestrator.handleVisit(location, resendToPhone: true),
          () => MockClient((_) async => http.Response('{"questions":[]}', 200)),
        );
    expect(await send(), VisitResult.adminOnly);
    AuthService().isAuthenticatedNotifier.value = true;
    expect(await send(), VisitResult.unavailable);
  });

  test('old admin password and the sessions it opened no longer work', () async {
    for (final password in ['admin123', '', ' ']) {
      expect(AuthService.isLocalAdminPassword(password), isFalse);
    }
    SharedPreferences.setMockInitialValues({'auth_is_authenticated': true});
    await AuthService().init();
    expect(AuthService().isAuthenticated, isFalse);
    expect(await AuthService.isStoredAdmin(), isFalse);
  });

  test('nothing is sent before the device is identified', () async {
    expect((await answer(201, prefs: {})).syncStatus, SyncStatus.pending);
    expect(sent, isEmpty);
  });

  test('administrators send the session issued by the server', () async {
    await answer(201, prefs: {
      'device_identity': 'android-abc', 'auth_admin_token': 'token',
    });
    expect(sent.single.headers['X-Admin-Session'], 'token');
  });

  test('an answered question is not asked again, except to administrators', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await repository.isAnswerBlocked('q'), isFalse);
    await answer(201);
    expect(await repository.isAnswerBlocked('q'), isTrue);
    expect(await repository.isAnswerBlocked('other'), isFalse);
    SharedPreferences.setMockInitialValues({'auth_is_authenticated': true});
    expect(await repository.isAnswerBlocked('q'), isFalse);
  });
}
