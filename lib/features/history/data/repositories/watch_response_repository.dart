import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/logger/app_logger.dart';
import '../../domain/entities/watch_response.dart';
import '../datasources/watch_response_dao.dart';

/// High-level repository for watch responses.
class WatchResponseRepository {
  final WatchResponseDao _dao;
  final Uuid _uuid = const Uuid();

  WatchResponseRepository({
    WatchResponseDao? dao,
  }) : _dao = dao ?? WatchResponseDao();

  // ─── Save scenarios ───────────────────────────────────────────────────────

  /// Watch was offline when the visit was detected – nothing was sent.
  Future<WatchResponse> saveWatchOffline({
    required String locationId,
    required String locationName,
    required String questionId,
    String? questionCommand,
  }) async {
    final response = WatchResponse(
      id: _uuid.v4(),
      locationId: locationId,
      locationName: locationName,
      questionId: questionId,
      answerId: null,
      timestamp: DateTime.now(),
      syncStatus: SyncStatus.pending,
      questionStatus: QuestionStatus.watchOffline,
      questionCommand: questionCommand,
    );
    await _dao.insert(response);
    AppLogger.info('WatchResponseRepository: saved watchOffline for $locationName');
    return response;
  }

  /// Question was sent to the watch – waiting for an answer.
  Future<WatchResponse> saveQuestionSent({
    required String locationId,
    required String locationName,
    required String questionId,
    String? questionCommand,
  }) async {
    final response = WatchResponse(
      id: _uuid.v4(),
      locationId: locationId,
      locationName: locationName,
      questionId: questionId,
      answerId: null,
      timestamp: DateTime.now(),
      syncStatus: SyncStatus.pending,
      questionStatus: QuestionStatus.questionSent,
      questionCommand: questionCommand,
    );
    await _dao.insert(response);
    AppLogger.info('WatchResponseRepository: saved questionSent for $locationName');
    return response;
  }

  /// The watch answered the question – update record and try to sync.
  Future<void> markAnswered({
    required String id,
    required String answerId,
    String? serverUrl,
  }) async {
    await _dao.markAnswered(id, answerId);
    AppLogger.info('WatchResponseRepository: marked $id as answered');

    if (serverUrl != null && serverUrl.isNotEmpty) {
      final updated = await _dao.getById(id);
      if (updated != null) await _trySend(updated, serverUrl);
    }
  }

  // ─── Legacy method (kept for compatibility) ───────────────────────────────

  Future<WatchResponse> saveResponse({
    required String locationId,
    required String locationName,
    required String questionId,
    required String answerId,
    String? serverUrl,
    String? questionCommand,
  }) async {
    final response = WatchResponse(
      id: _uuid.v4(),
      locationId: locationId,
      locationName: locationName,
      questionId: questionId,
      answerId: answerId,
      timestamp: DateTime.now(),
      syncStatus: SyncStatus.pending,
      questionStatus: QuestionStatus.answered,
      questionCommand: questionCommand,
    );
    await _dao.insert(response);
    AppLogger.info('WatchResponseRepository: saved answered response ${response.id}');

    if (serverUrl != null && serverUrl.isNotEmpty) {
      await _trySend(response, serverUrl);
    }
    return response;
  }

  // ─── Queries ──────────────────────────────────────────────────────────────

  Future<List<WatchResponse>> getAll() => _dao.getAll();

  Future<WatchResponse?> getById(String id) => _dao.getById(id);

  // ─── Sync ─────────────────────────────────────────────────────────────────

  /// Retry sync for a single answered record.
  Future<void> retrySingle(String id, String serverUrl) async {
    final r = await _dao.getById(id);
    if (r == null) return;
    if (r.questionStatus != QuestionStatus.answered) return;
    await _trySend(r, serverUrl);
  }

  /// Retry all [SyncStatus.pending] answered responses.
  Future<void> syncPending(String serverUrl) async {
    if (serverUrl.isEmpty) return;
    final pending = await _dao.getPending();
    AppLogger.info('WatchResponseRepository: syncing ${pending.length} pending');
    for (final r in pending) {
      await _trySend(r, serverUrl);
    }
  }

  Future<void> _trySend(WatchResponse response, String serverUrl) async {
    if (response.answerId == null || response.answerId!.isEmpty) return;
    try {
      final base = serverUrl.trim();
      if (base.isEmpty) return;

      final normalized = base.startsWith('http://') || base.startsWith('https://')
          ? base
          : 'https://$base';
      final uri = Uri.parse('$normalized/api/responses');

      final payload = {
        'deviceId': 'mobile-app',
        'questionId': response.questionId,
        'answerId': response.answerId,
        'locationId': response.locationId,
        'locationName': response.locationName,
        'submittedAt': response.timestamp.toIso8601String(),
      };

      final httpResponse = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${AppConfig.appAuthToken}',
        },
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 5));

      if (httpResponse.statusCode >= 200 && httpResponse.statusCode < 300) {
        await _dao.updateStatus(response.id, SyncStatus.synced);
        AppLogger.info('WatchResponseRepository: synced ${response.id}');
      } else {
        await _dao.updateStatus(response.id, SyncStatus.failed);
        AppLogger.warning(
          'WatchResponseRepository: sync failed ${response.id}: ${httpResponse.statusCode} ${httpResponse.body}',
        );
      }
    } catch (e) {
      await _dao.updateStatus(response.id, SyncStatus.failed);
      AppLogger.warning('WatchResponseRepository: failed to sync ${response.id}: $e');
    }
  }
}
