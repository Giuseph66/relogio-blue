import 'dart:async';
import 'package:flutter/foundation.dart';
import '../platform/browser_bridge.dart';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../features/history/data/repositories/watch_response_repository.dart';
import '../ble/ble_question_protocol.dart';
import '../config/app_config.dart';
import '../logger/app_logger.dart';
import 'notification_service.dart';

/// Action id of the "answer" button attached to question notifications.
const String kQuestionAnswerActionId = 'question_answer';

/// Name used to register the main isolate's [SendPort] in [IsolateNameServer],
/// so the background notification isolate can tell the main isolate that a
/// question was answered from the phone.
const String kQuestionAnswerPortName = 'question_answer_port';

/// Android channel for question notifications (high importance → heads-up).
const String kQuestionsChannelId = 'questions_channel';
const String kQuestionsChannelName = 'Perguntas';
const String kQuestionsChannelDescription =
    'Perguntas de visita com opções de resposta rápida';

/// Everything needed to answer a question from the notification, even in a
/// fresh background isolate where no in-memory state exists.
class QuestionNotificationPayload {
  /// Sanitized questionId — the same one sent to the watch in the QST command.
  final String questionId;

  /// Row id in `watch_responses`, when the record was already created.
  final String? recordId;
  final String locationId;
  final String locationName;
  final String prompt;

  /// The BLE QST command (stored with the record so history can show it).
  final String? command;

  /// Option ids are sanitized like in the BLE command (so phone and watch
  /// answers are identical); labels are kept in full for the notification.
  final List<BleQuestionOption> options;

  const QuestionNotificationPayload({
    required this.questionId,
    required this.locationId,
    required this.locationName,
    required this.prompt,
    required this.options,
    this.recordId,
    this.command,
  });

  factory QuestionNotificationPayload.fromPrompt(
    BleQuestionPrompt prompt, {
    required String locationId,
    required String locationName,
    String? recordId,
    String? command,
  }) {
    final cmd = command ?? buildBleQuestionCommand(prompt);
    final parts = cmd.split('|');
    final safeQuestionId = parts.length > 1 ? parts[1] : prompt.questionId;

    return QuestionNotificationPayload(
      questionId: safeQuestionId,
      recordId: recordId,
      locationId: locationId,
      locationName: locationName,
      prompt: prompt.question.trim(),
      command: cmd,
      options: prompt.options
          .take(bleQuestionMaxOptions)
          .map(
            (o) => BleQuestionOption(
              id: sanitizeBleQuestionText(o.id, maxLength: 16),
              label: o.label.trim(),
            ),
          )
          .where((o) => o.id.isNotEmpty && o.label.isNotEmpty)
          .toList(growable: false),
    );
  }

  /// Maps the chip text the user tapped back to the option id.
  String? optionIdForLabel(String label) {
    final wanted = label.trim();
    if (wanted.isEmpty) return null;
    for (final o in options) {
      if (o.label == wanted) return o.id;
    }
    final lower = wanted.toLowerCase();
    for (final o in options) {
      if (o.label.toLowerCase() == lower) return o.id;
    }
    return null;
  }

  String toJson() => jsonEncode({
        'questionId': questionId,
        'recordId': recordId,
        'locationId': locationId,
        'locationName': locationName,
        'prompt': prompt,
        'command': command,
        'options': options.map((o) => {'id': o.id, 'label': o.label}).toList(),
      });

  static QuestionNotificationPayload? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final questionId = map['questionId'] as String? ?? '';
      if (questionId.isEmpty) return null;
      final options = (map['options'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(
            (o) => BleQuestionOption(
              id: o['id'] as String? ?? '',
              label: o['label'] as String? ?? '',
            ),
          )
          .where((o) => o.id.isNotEmpty)
          .toList(growable: false);
      return QuestionNotificationPayload(
        questionId: questionId,
        recordId: map['recordId'] as String?,
        locationId: map['locationId'] as String? ?? questionId,
        locationName: map['locationName'] as String? ?? '',
        prompt: map['prompt'] as String? ?? '',
        command: map['command'] as String?,
        options: options,
      );
    } catch (e) {
      AppLogger.warning('QuestionNotification: invalid payload: $e');
      return null;
    }
  }
}

/// Shows visit questions as phone notifications with quick-reply chips
/// (like WhatsApp smart replies) and handles the chosen answer.
class QuestionNotificationService {
  static final QuestionNotificationService _instance =
      QuestionNotificationService._internal();
  factory QuestionNotificationService() => _instance;
  QuestionNotificationService._internal();

  static final pendingQuestions = ValueNotifier<List<QuestionNotificationPayload>>([]);
  static final _answers = StreamController<String>.broadcast();
  static Stream<String> get answers => _answers.stream;

  static void focusQuestion(String recordId) {
    final questions = pendingQuestions.value;
    final index = questions.indexWhere((question) => question.recordId == recordId);
    if (index <= 0) return;
    pendingQuestions.value = [questions[index], ...questions.take(index), ...questions.skip(index + 1)];
  }

  static String _webTag(QuestionNotificationPayload question) =>
      'geonexo-question:${question.recordId ?? question.questionId}';

  static Future<void> answerFromWeb(QuestionNotificationPayload payload, String answerId) async {
    if (!payload.options.any((option) => option.id == answerId)) return;
    final saved = await WatchResponseRepository().saveAnswerFromPhone(
      recordId: payload.recordId, questionId: payload.questionId, answerId: answerId,
      locationId: payload.locationId, locationName: payload.locationName,
      questionCommand: payload.command, serverUrl: AppConfig.serverApiUrl,
    );
    if (saved == null) throw StateError('A pergunta já foi respondida ou não está disponível.');
    await QuestionNotificationService().cancelQuestion(payload.questionId);
    _answers.add(payload.questionId);
  }

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Stable notification id per question (FNV-1a), identical in every
  /// isolate so any of them can replace or cancel it.
  static int notificationIdFor(String questionId) {
    var hash = 0x811c9dc5;
    for (final unit in questionId.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    // Keep clear of the fixed ids used elsewhere (e.g. RX notification = 42).
    return 10000 + (hash % 900000);
  }

  Future<void> showQuestion(QuestionNotificationPayload payload, {bool notify = true}) async {
    if (payload.options.length < bleQuestionMinOptions) return;
    if (kIsWeb) {
      final alreadyPending = pendingQuestions.value.any((question) =>
          question.questionId == payload.questionId && question.recordId == payload.recordId);
      pendingQuestions.value = [
        ...pendingQuestions.value.where((p) => p.questionId != payload.questionId), payload,
      ];
      if (notify && !alreadyPending) {
        try {
          await BrowserBridge.call('notify', {
            'title': payload.locationName.isEmpty ? 'Nova pergunta' : payload.locationName,
            'body': payload.prompt,
            'tag': _webTag(payload),
            'recordId': payload.recordId,
          });
        } catch (error) {
          AppLogger.warning('QuestionNotification: web notification failed: $error');
        }
      }
      return;
    }

    try {
      await NotificationService().init();

      final labels =
          payload.options.map((o) => o.label).toList(growable: false);

      final androidDetails = AndroidNotificationDetails(
        kQuestionsChannelId,
        kQuestionsChannelName,
        channelDescription: kQuestionsChannelDescription,
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.message,
        styleInformation: BigTextStyleInformation(payload.prompt),
        onlyAlertOnce: true,
        autoCancel: false,
        icon: '@mipmap/ic_launcher',
        actions: <AndroidNotificationAction>[
          AndroidNotificationAction(
            kQuestionAnswerActionId,
            'Responder',
            inputs: <AndroidNotificationActionInput>[
              AndroidNotificationActionInput(
                choices: labels,
                allowFreeFormInput: false,
                label: 'Escolha uma opção',
              ),
            ],
            cancelNotification: true,
          ),
        ],
      );

      final title = payload.locationName.isNotEmpty
          ? payload.locationName
          : 'Nova pergunta';

      await _plugin.show(
        notificationIdFor(payload.questionId),
        title,
        payload.prompt,
        NotificationDetails(android: androidDetails),
        payload: payload.toJson(),
      );
      AppLogger.info(
        'QuestionNotification: shown for ${payload.questionId} (${labels.length} options)',
      );
    } catch (e) {
      AppLogger.error('QuestionNotification: failed to show', e);
    }
  }

  Future<void> cancelQuestion(String questionId) async {
    if (kIsWeb) {
      final removed = pendingQuestions.value.where((p) => p.questionId == questionId).toList();
      pendingQuestions.value = pendingQuestions.value.where((p) => p.questionId != questionId).toList();
      for (final question in removed) {
        try {
          await BrowserBridge.call('notify.cancel', {'tag': _webTag(question)});
        } catch (_) { /* Saving an answer must not depend on notification support. */ }
      }
      return;
    }
    try {
      await _plugin.cancel(notificationIdFor(questionId));
    } catch (e) {
      AppLogger.debug('QuestionNotification: cancel failed: $e');
    }
  }

  /// Handles a tap on a quick-reply chip. Works in any isolate:
  /// persists the answer to SQLite (+ server sync) and then pings the main
  /// isolate, if it is alive, so it can drop the in-memory pending entry.
  static Future<void> handleResponse(NotificationResponse response) async {
    if (response.actionId != kQuestionAnswerActionId) return;

    final payload = QuestionNotificationPayload.tryParse(response.payload);
    if (payload == null) return;

    final answerId = payload.optionIdForLabel(response.input ?? '');
    if (answerId == null) {
      AppLogger.warning(
        'QuestionNotification: no option matches input "${response.input}"',
      );
      return;
    }

    try {
      final saved = await WatchResponseRepository().saveAnswerFromPhone(
        recordId: payload.recordId,
        questionId: payload.questionId,
        answerId: answerId,
        locationId: payload.locationId,
        locationName: payload.locationName,
        questionCommand: payload.command,
        serverUrl: AppConfig.serverApiUrl,
      );
      AppLogger.info(
        'QuestionNotification: answered ${payload.questionId} → $answerId from phone',
      );

      IsolateNameServer.lookupPortByName(kQuestionAnswerPortName)?.send({
        'questionId': payload.questionId,
        'recordId': saved?.id ?? payload.recordId,
        'answerId': answerId,
      });
    } catch (e) {
      AppLogger.error('QuestionNotification: failed to save answer', e);
    }
  }
}

/// Entry point for notification actions handled while the UI isolate is not
/// the receiver (Android runs non-UI actions in a background isolate).
@pragma('vm:entry-point')
void onQuestionNotificationBackgroundResponse(NotificationResponse response) {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  QuestionNotificationService.handleResponse(response);
}
