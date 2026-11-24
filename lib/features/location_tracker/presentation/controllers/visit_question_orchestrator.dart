import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import '../../../../core/auth/auth_service.dart';
import '../../../../core/ble/ble_question_protocol.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/device/device_identity.dart';
import '../../../../core/logger/app_logger.dart';
import '../../../../core/notifications/question_notification_service.dart';
import '../../../../core/offline/offline_question_cache.dart';
import '../../../../features/history/data/repositories/watch_response_repository.dart';
import '../../../../features/history/domain/entities/watch_response.dart';
import '../../../../features/ble_old/presentation/controllers/messages_controller.dart';
import '../../../../features/ble_old/domain/entities/ble_message.dart';
import '../../data/datasources/remote_location_data_source.dart';
import '../../domain/entities/location_question.dart';
import '../../domain/entities/tracked_location.dart';

class _PendingQuestion {
  /// Record ID in the watch_responses table.
  final String recordId;
  final String locationId;
  final String locationName;
  Timer? timeoutTimer;

  _PendingQuestion({
    required this.recordId,
    required this.locationId,
    required this.locationName,
  });
}

/// Orchestrates the full flow after a geofence visit is detected:
///
/// 1. Check if watch is connected (tick online OR BLE connected).
/// 2a. Watch **offline** → save [QuestionStatus.watchOffline] record.
/// 2b. Watch **online**  → build BLE command (questionId truncated to 18 chars),
///     send via BLE, save [QuestionStatus.questionSent] record.
/// 3. Listen for QANS reply.
///    - Reply received → update record to [QuestionStatus.answered] + sync.
///    - 3-minute timeout → leave as [QuestionStatus.questionSent] (unanswered).
///
/// When the watch comes back online, pending [watchOffline] records are
/// automatically resent.
class VisitQuestionOrchestrator {
  final WatchResponseRepository _responseRepository;
  final MessagesController _messagesController;

  /// Key: SANITIZED questionId (≤18 chars) as sent to the watch.
  final Map<String, _PendingQuestion> _pending = {};

  StreamSubscription<List<BleMessage>>? _messageSubscription;
  StreamSubscription<TickStatus>? _tickSubscription;
  ReceivePort? _phoneAnswerPort;
  StreamSubscription<String>? _webAnswers;
  bool _wasOnline = false;

  final QuestionNotificationService _questionNotifications =
      QuestionNotificationService();

  VisitQuestionOrchestrator({
    required WatchResponseRepository responseRepository,
    required MessagesController messagesController,
  })  : _responseRepository = responseRepository,
        _messagesController = messagesController {
    _startListeningMessages();
    _startListeningTick();
    _startListeningPhoneAnswers();
  }

  /// Restore pending watch replies after a PWA reload.
  Future<void> restorePendingQuestions() async {
    for (final row in await _responseRepository.getAll()) {
      if (row.questionStatus != QuestionStatus.questionSent || row.questionCommand == null) continue;
      final id = _extractCommandId(row.questionCommand!);
      if (!_pending.containsKey(id)) _registerPending(id, row.id, row.locationId, row.locationName);
    }
  }

  // ─── Listeners ────────────────────────────────────────────────────────────

  void _startListeningMessages() {
    _messageSubscription = _messagesController.messages.listen((messages) {
      if (messages.isEmpty || _pending.isEmpty) return;
      final last = messages.last;
      if (last.direction != MessageDirection.rx) return;

      AppLogger.info(
        'VisitQuestionOrchestrator: RX content="${last.content}" pending=${_pending.keys.toList()}',
      );

      final result = tryParseBleQuestionResult(last.content);
      AppLogger.info(
        'VisitQuestionOrchestrator: parse result=$result isAnswer=${result?.isAnswer} qId=${result?.questionId}',
      );
      if (result == null || !result.isAnswer) return;
      if (!DeviceIdentity.canAnswer) return;

      // The questionId in the QANS is already the sanitized (≤18 char) version
      // because that's what was transmitted in the QST command.
      final pending = _pending.remove(result.questionId);
      AppLogger.info(
        'VisitQuestionOrchestrator: pending lookup for "${result.questionId}" → ${pending != null ? "FOUND" : "NOT FOUND"}',
      );
      if (pending == null) return;

      pending.timeoutTimer?.cancel();
      unawaited(_questionNotifications.cancelQuestion(result.questionId));

      AppLogger.info(
        'VisitQuestionOrchestrator: answer received for ${result.questionId}',
      );
      _responseRepository.markAnswered(
        id: pending.recordId,
        answerId: result.answerId!,
        serverUrl: AppConfig.serverApiUrl,
      );
    });
  }

  void _startListeningTick() {
    _tickSubscription = _messagesController.tickStatus.listen((status) {
      if (status.online && !_wasOnline) {
        AppLogger.info('VisitQuestionOrchestrator: watch came online — auto-resending pending');
        _autoResendWatchOffline();
      }
      _wasOnline = status.online;
    });
  }

  /// Answers chosen from the phone notification are persisted by
  /// [QuestionNotificationService.handleResponse] (possibly in a background
  /// isolate); here we only drop the pending entry so a late watch QANS does
  /// not overwrite it.
  void _startListeningPhoneAnswers() {
    if (kIsWeb) {
      _webAnswers = QuestionNotificationService.answers.listen((id) {
        _pending.remove(id)?.timeoutTimer?.cancel();
      });
      return;
    }
    final port = ReceivePort();
    IsolateNameServer.removePortNameMapping(kQuestionAnswerPortName);
    IsolateNameServer.registerPortWithName(port.sendPort, kQuestionAnswerPortName);
    port.listen((message) {
      if (message is! Map) return;
      final questionId = message['questionId'] as String?;
      if (questionId == null) return;
      final pending = _pending.remove(questionId);
      pending?.timeoutTimer?.cancel();
      AppLogger.info(
        'VisitQuestionOrchestrator: $questionId answered from phone '
        '(pending ${pending != null ? "cleared" : "none"})',
      );
    });
    _phoneAnswerPort = port;
  }

  Future<void> _showPhoneQuestion({
    required BleQuestionPrompt prompt,
    required TrackedLocation location,
    required String recordId,
    required String command,
    bool forceNotify = false,
  }) {
    return _questionNotifications.showQuestion(
      QuestionNotificationPayload.fromPrompt(
        prompt,
        locationId: location.id,
        locationName: location.name,
        recordId: recordId,
        command: command,
      ),
      forceNotify: forceNotify,
    );
  }

  // ─── Auto-resend on reconnect ─────────────────────────────────────────────

  Future<void> _autoResendWatchOffline() async {
    try {
      final allRecords = await _responseRepository.getAll();
      final offline = allRecords
          .where((r) =>
              r.questionStatus == QuestionStatus.watchOffline &&
              r.questionCommand != null &&
              r.questionCommand!.isNotEmpty)
          .toList();

      for (final r in offline) {
        await resend(r);
        // Small gap to avoid flooding BLE
        await Future.delayed(const Duration(milliseconds: 600));
      }
    } catch (e) {
      AppLogger.warning('VisitQuestionOrchestrator: auto-resend error: $e');
    }
  }

  // ─── Public API ───────────────────────────────────────────────────────────

  /// The question that a visit to [location] would trigger (same selection
  /// rule as [handleVisit]). Null when there is none.
  ///
  /// Asks the server first; without network falls back to the offline cache
  /// ([OfflineQuestionCache]), which mirrors the same selection rules.
  Future<LocationQuestion?> resolveQuestionFor(
    TrackedLocation location, {
    double? latitude,
    double? longitude,
    String? city,
  }) async {
    final lat = latitude ?? location.latitude;
    final lng = longitude ?? location.longitude;

    final List<LocationQuestion> questions;
    try {
      final dataSource = RemoteLocationDataSource(baseUrl: AppConfig.serverApiUrl);
      questions = await dataSource.fetchQuestionsForVisit(
        latitude: lat,
        longitude: lng,
        city: city,
      );
    } catch (e) {
      AppLogger.info(
        'VisitQuestionOrchestrator: server unreachable ($e) — using offline cache',
      );
      final cache = OfflineQuestionCache();
      final matched = await cache.locationsAt(lat, lng);
      return cache.questionFor(
        locationId: location.id,
        matchedLocationIds: matched.map((l) => l.id).toList(),
        city: city,
      );
    }

    if (questions.isEmpty) return null;
    return questions.firstWhere(
      (q) => q.locationId == location.id,
      orElse: () => questions.first,
    );
  }

  /// Called when a geofence visit is detected.
  /// Manual catalog sends (administrators only) can alert the phone again using
  /// its unanswered record.
  Future<VisitResult> handleVisit(
    TrackedLocation location, {
    double? latitude,
    double? longitude,
    String? city,
    bool resendToPhone = false,
  }) async {
    if (resendToPhone && !AuthService().isAuthenticated) {
      return VisitResult.adminOnly;
    }
    try {
      final question = await resolveQuestionFor(
        location,
        latitude: latitude,
        longitude: longitude,
        city: city,
      );

      if (question == null) {
        AppLogger.info('VisitQuestionOrchestrator: no questions for ${location.name}');
        return VisitResult.unavailable;
      }

      final prompt = BleQuestionPrompt(
        questionId: question.id,
        question: question.prompt,
        options: question.options
            .map((o) => BleQuestionOption(id: o.id, label: o.label))
            .toList(),
      );

      if (prompt.options.length < bleQuestionMinOptions) {
        return VisitResult.unavailable;
      }

      final command = buildBleQuestionCommand(prompt);

      // ── Extract the sanitized questionId that was actually put in the
      // command — this is what the watch will echo back in the QANS.
      final safeQuestionId = _extractCommandId(command);

      if (await _responseRepository.isAnswerBlocked(safeQuestionId)) {
        return VisitResult.alreadyAnswered;
      }

      if (resendToPhone) {
        for (final record in await _responseRepository.getAll()) {
          if (record.locationId != location.id ||
              record.questionStatus == QuestionStatus.answered ||
              record.questionCommand != command) {
            continue;
          }
          await _showPhoneQuestion(
            prompt: prompt,
            location: location,
            recordId: record.id,
            command: command,
            forceNotify: true,
          );
          return VisitResult.asked;
        }
      }

      // Skip if we're already waiting for an answer to this question.
      if (_pending.containsKey(safeQuestionId)) return VisitResult.unavailable;

      // ── Check connection ────────────────────────────────────────────────
      // Accept: watch is actively ticking (online) OR BLE is connected.
      // A browser tab keeps the question for the installed app.
      final watchAvailable = DeviceIdentity.canAnswer &&
          (_messagesController.isWatchOnline || _messagesController.isWatchConnected);

      if (!watchAvailable) {
        AppLogger.info('VisitQuestionOrchestrator: watch offline for ${location.name}');
        final offlineRecord = await _responseRepository.saveWatchOffline(
          locationId: location.id,
          locationName: location.name,
          questionId: safeQuestionId,
          questionCommand: command,
        );
        await _showPhoneQuestion(
          prompt: prompt,
          location: location,
          recordId: offlineRecord.id,
          command: command,
        );
        return VisitResult.asked;
      }

      // ── Send question ───────────────────────────────────────────────────
      final sent = await _messagesController.sendMessage(command);
      if (!sent) return VisitResult.unavailable;

      AppLogger.info('VisitQuestionOrchestrator: question sent for ${location.name}');

      final record = await _responseRepository.saveQuestionSent(
        locationId: location.id,
        locationName: location.name,
        questionId: safeQuestionId,
        questionCommand: command,
      );

      _registerPending(safeQuestionId, record.id, location.id, location.name);
      await _showPhoneQuestion(
        prompt: prompt,
        location: location,
        recordId: record.id,
        command: command,
      );
      return VisitResult.asked;
    } catch (e) {
      AppLogger.warning('VisitQuestionOrchestrator: handleVisit error: $e');
      return VisitResult.unavailable;
    }
  }

  /// Resend a question from the history screen.
  Future<ResendResult> resend(WatchResponse r) async {
    if (r.questionCommand == null || r.questionCommand!.isEmpty) {
      return ResendResult.noCommand;
    }

    // Normalize old commands (stored with 18-char IDs) to the current 10-char limit
    // so the QANS reply fits in a single 20-byte BLE packet.
    final command = normalizeBleCommandId(r.questionCommand!);
    final safeQuestionId = _extractCommandId(command);

    if (!DeviceIdentity.canAnswer) return ResendResult.installRequired;
    if (await _responseRepository.isAnswerBlocked(r.questionId)) {
      return ResendResult.alreadyAnswered;
    }

    if (_pending.containsKey(safeQuestionId)) {
      return ResendResult.alreadyPending;
    }

    final watchAvailable =
        _messagesController.isWatchOnline || _messagesController.isWatchConnected;
    if (!watchAvailable) return ResendResult.watchOffline;

    final sent = await _messagesController.sendMessage(command);
    if (!sent) return ResendResult.sendFailed;

    _registerPending(safeQuestionId, r.id, r.locationId, r.locationName);

    AppLogger.info('VisitQuestionOrchestrator: resent question $safeQuestionId');
    return ResendResult.sent;
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  /// Extracts the questionId from a built BLE command string
  /// `QST|<id>|<prompt>|...` → `<id>`.
  String _extractCommandId(String command) {
    final parts = command.split('|');
    return parts.length > 1 ? parts[1] : command;
  }

  void _registerPending(
    String safeQuestionId,
    String recordId,
    String locationId,
    String locationName,
  ) {
    final pending = _PendingQuestion(
      recordId: recordId,
      locationId: locationId,
      locationName: locationName,
    );
    pending.timeoutTimer = Timer(const Duration(minutes: 3), () {
      _pending.remove(safeQuestionId);
      AppLogger.info(
        'VisitQuestionOrchestrator: timeout for question $safeQuestionId',
      );
    });
    _pending[safeQuestionId] = pending;
  }

  void dispose() {
    for (final p in _pending.values) {
      p.timeoutTimer?.cancel();
    }
    _pending.clear();
    _messageSubscription?.cancel();
    _tickSubscription?.cancel();
    _webAnswers?.cancel();
    if (!kIsWeb) IsolateNameServer.removePortNameMapping(kQuestionAnswerPortName);
    _phoneAnswerPort?.close();
    _phoneAnswerPort = null;
  }
}

enum ResendResult {
  sent,
  watchOffline,
  noCommand,
  alreadyPending,
  sendFailed,
  alreadyAnswered,
  installRequired,
}

enum VisitResult { asked, alreadyAnswered, adminOnly, unavailable }
