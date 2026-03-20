import 'dart:async';

import '../../../../core/ble/ble_question_protocol.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/logger/app_logger.dart';
import '../../../../features/history/data/repositories/watch_response_repository.dart';
import '../../../../features/history/domain/entities/watch_response.dart';
import '../../../../features/ble_old/presentation/controllers/messages_controller.dart';
import '../../../../features/ble_old/domain/entities/ble_message.dart';
import '../../data/datasources/remote_location_data_source.dart';
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
  bool _wasOnline = false;

  VisitQuestionOrchestrator({
    required WatchResponseRepository responseRepository,
    required MessagesController messagesController,
  })  : _responseRepository = responseRepository,
        _messagesController = messagesController {
    _startListeningMessages();
    _startListeningTick();
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

      // The questionId in the QANS is already the sanitized (≤18 char) version
      // because that's what was transmitted in the QST command.
      final pending = _pending.remove(result.questionId);
      AppLogger.info(
        'VisitQuestionOrchestrator: pending lookup for "${result.questionId}" → ${pending != null ? "FOUND" : "NOT FOUND"}',
      );
      if (pending == null) return;

      pending.timeoutTimer?.cancel();

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

  /// Called when a geofence visit is detected.
  Future<bool> handleVisit(
    TrackedLocation location, {
    double? latitude,
    double? longitude,
    String? city,
  }) async {
    try {
      final dataSource = RemoteLocationDataSource(baseUrl: AppConfig.serverApiUrl);
      final questions = await dataSource.fetchQuestionsForVisit(
        latitude: latitude ?? location.latitude,
        longitude: longitude ?? location.longitude,
        city: city,
      );

      if (questions.isEmpty) {
        AppLogger.info('VisitQuestionOrchestrator: no questions for ${location.name}');
        return false;
      }

      final question = questions.firstWhere(
        (q) => q.locationId == location.id,
        orElse: () => questions.first,
      );

      final prompt = BleQuestionPrompt(
        questionId: question.id,
        question: question.prompt,
        options: question.options
            .map((o) => BleQuestionOption(id: o.id, label: o.label))
            .toList(),
      );

      if (prompt.options.length < bleQuestionMinOptions) return false;

      final command = buildBleQuestionCommand(prompt);

      // ── Extract the sanitized questionId that was actually put in the
      // command — this is what the watch will echo back in the QANS.
      final safeQuestionId = _extractCommandId(command);

      // Skip if we're already waiting for an answer to this question.
      if (_pending.containsKey(safeQuestionId)) return false;

      // ── Check connection ────────────────────────────────────────────────
      // Accept: watch is actively ticking (online) OR BLE is connected.
      final watchAvailable =
          _messagesController.isWatchOnline || _messagesController.isWatchConnected;

      if (!watchAvailable) {
        AppLogger.info('VisitQuestionOrchestrator: watch offline for ${location.name}');
        await _responseRepository.saveWatchOffline(
          locationId: location.id,
          locationName: location.name,
          questionId: safeQuestionId,
          questionCommand: command,
        );
        return true;
      }

      // ── Send question ───────────────────────────────────────────────────
      final sent = await _messagesController.sendMessage(command);
      if (!sent) return false;

      AppLogger.info('VisitQuestionOrchestrator: question sent for ${location.name}');

      final record = await _responseRepository.saveQuestionSent(
        locationId: location.id,
        locationName: location.name,
        questionId: safeQuestionId,
        questionCommand: command,
      );

      _registerPending(safeQuestionId, record.id, location.id, location.name);
      return true;
    } catch (e) {
      AppLogger.warning('VisitQuestionOrchestrator: handleVisit error: $e');
      return false;
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
  }
}

enum ResendResult {
  sent,
  watchOffline,
  noCommand,
  alreadyPending,
  sendFailed,
}
