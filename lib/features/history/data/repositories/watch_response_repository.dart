import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../../../../core/auth/auth_service.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/device/device_identity.dart';
import '../../../../core/logger/app_logger.dart';
import '../../../../core/platform/browser_bridge.dart';
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

  /// The watch answered (QANS) while only the background service was alive:
  /// updates the latest unanswered record for [questionId].
  Future<bool> markAnsweredByQuestionId({
    required String questionId,
    required String answerId,
    String? serverUrl,
  }) async {
    final target = await _dao.findLatestUnanswered(questionId);
    if (target == null) return false;
    await markAnswered(id: target.id, answerId: answerId, serverUrl: serverUrl);
    return true;
  }

  /// The user answered from the phone notification (quick-reply chip).
  ///
  /// Updates the matching unanswered record ([recordId], or the latest one for
  /// [questionId]). If none exists (e.g. question triggered by the background
  /// service, which does not persist records), a new answered record is created.
  Future<WatchResponse?> saveAnswerFromPhone({
    String? recordId,
    required String questionId,
    required String answerId,
    required String locationId,
    required String locationName,
    String? questionCommand,
    String? serverUrl,
  }) async {
    WatchResponse? target;
    if (recordId != null && recordId.isNotEmpty) {
      target = await _dao.getById(recordId);
    }
    target ??= await _dao.findLatestUnanswered(questionId);

    if (target == null) {
      return saveResponse(
        locationId: locationId,
        locationName: locationName,
        questionId: questionId,
        answerId: answerId,
        serverUrl: serverUrl,
        questionCommand: questionCommand,
      );
    }

    if (target.questionStatus == QuestionStatus.answered) {
      AppLogger.info('WatchResponseRepository: ${target.id} already answered');
      return target;
    }

    await markAnswered(id: target.id, answerId: answerId, serverUrl: serverUrl);
    return _dao.getById(target.id);
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

  /// True when this device already answered [questionId] (as sent to the
  /// watch). Administrators may answer again.
  Future<bool> isAnswerBlocked(String questionId) async {
    if (await AuthService.isStoredAdmin()) return false;
    return (await _dao.getAll()).any((r) =>
        r.questionId == questionId &&
        r.questionStatus == QuestionStatus.answered);
  }

  // ─── Sync ─────────────────────────────────────────────────────────────────

  /// Retry sync for a single answered record.
  Future<void> retrySingle(String id, String serverUrl) async {
    final r = await _dao.getById(id);
    if (r == null) return;
    if (r.questionStatus != QuestionStatus.answered) return;
    if (r.syncStatus == SyncStatus.rejected) return;
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
    // Kept for when the installed app is opened.
    if (!DeviceIdentity.canAnswer) return;
    try {
      final base = serverUrl.trim();
      if (base.isEmpty) return;

      final normalized = base.startsWith('http://') || base.startsWith('https://')
          ? base
          : 'https://$base';
      final uri = Uri.parse('$normalized/api/responses');

      final deviceId = await DeviceIdentity.read();
      if (!kIsWeb && deviceId == null) return; // stays pending
      final adminToken = await AuthService.storedAdminToken();

      final payload = {
        // Same id on every retry: the server stores it only once.
        'responseId': response.id,
        'deviceId': ?deviceId,
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
          if (AppConfig.appAuthToken != '')
            'Authorization': 'Bearer ${AppConfig.appAuthToken}',
          'X-Admin-Session': ?adminToken,
          if (kIsWeb && BrowserBridge.isStandalone) 'X-GeoNexo-App': 'pwa',
        },
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 5));

      if (httpResponse.statusCode >= 200 && httpResponse.statusCode < 300) {
        await _dao.updateStatus(response.id, SyncStatus.synced);
        AppLogger.info('WatchResponseRepository: synced ${response.id}');
      } else if (httpResponse.statusCode == 409 || httpResponse.statusCode == 410) {
        // Already answered from this device, or the question no longer exists.
        await _dao.updateStatus(response.id, SyncStatus.rejected);
        AppLogger.info('WatchResponseRepository: rejected ${response.id}');
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
