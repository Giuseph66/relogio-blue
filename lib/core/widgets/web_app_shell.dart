import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../auth/auth_service.dart';
import '../ble/ble_question_protocol.dart';
import '../../features/history/data/repositories/watch_response_repository.dart';
import '../../features/history/domain/entities/watch_response.dart';
import '../di/dependency_injection.dart';
import '../geofence/geofence_service.dart';
import '../notifications/question_notification_service.dart';
import '../offline/offline_question_cache.dart';
import '../platform/browser_bridge.dart';

/// Browser permissions are optional and requested by a user action, never a
/// gate that prevents opening the app on browsers without Bluetooth.
class WebAppShell extends StatefulWidget {
  final Widget child;
  const WebAppShell({super.key, required this.child});
  @override
  State<WebAppShell> createState() => _WebAppShellState();
}

class _WebAppShellState extends State<WebAppShell> {
  StreamSubscription<Map<String, dynamic>>? _events;
  bool _monitoring = false;
  bool _syncing = false;
  bool _requesting = false;
  bool _answering = false;
  bool _details = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    AuthService().isAuthenticatedNotifier.addListener(_authChanged);
    AuthService().isGuestNotifier.addListener(_authChanged);
    _events = BrowserBridge.events.listen((event) {
      if (event['type'] == 'visibility') {
        if (event['visible'] == true) {
          if (_monitoring) GeofenceService().start(pollImmediately: true);
          unawaited(_sync());
        } else {
          GeofenceService().stop();
        }
      } else if (event['type'] == 'update') {
        if (mounted) setState(() {});
      } else if (event['type'] == 'online') {
        unawaited(_sync());
      }
    });
    unawaited(_sync());
  }

  Future<void> _sync() async {
    if (!AuthService().hasAppSession || _syncing) return;
    _syncing = true;
    try {
      // Reopen unanswered questions after closing/reloading the installed app.
      final rows = await WatchResponseRepository().getAll();
      await DependencyInjection().visitQuestionOrchestrator
          .restorePendingQuestions();
      for (final row in rows.reversed) {
        if (!AuthService().hasAppSession) break;
        if (row.questionStatus == QuestionStatus.answered ||
            row.questionCommand == null) {
          continue;
        }
        final prompt = tryParseBleQuestionCommand(row.questionCommand!);
        if (prompt == null) continue;
        await QuestionNotificationService().showQuestion(
          QuestionNotificationPayload.fromPrompt(
            prompt,
            locationId: row.locationId,
            locationName: row.locationName,
            recordId: row.id,
            command: row.questionCommand,
          ),
        );
      }
      await DependencyInjection().syncService.syncNow();
      await OfflineQuestionCache().refresh();
    } catch (_) {
      /* Pending data stays local for the next retry. */
    } finally {
      _syncing = false;
    }
  }

  void _authChanged() {
    if (!AuthService().hasAppSession) {
      GeofenceService().stop();
      _monitoring = false;
    } else {
      unawaited(_sync());
    }
    if (mounted) setState(() {});
  }

  Future<void> _toggleMonitoring() async {
    if (_monitoring) {
      GeofenceService().stop();
      setState(() => _monitoring = false);
      return;
    }
    setState(() {
      _requesting = true;
      _message = null;
    });
    try {
      final permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw StateError(
          'Permita a localização nas configurações deste site para monitorar visitas.',
        );
      }
      if (!mounted || !AuthService().hasAppSession) return;
      _monitoring = true;
      GeofenceService().start(pollImmediately: true);
      unawaited(BrowserBridge.call('storage.persist').catchError((_) => false));
    } catch (_) {
      _message =
          'Localização indisponível. Confira a permissão deste site, o GPS e a conexão HTTPS.';
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  Future<void> _install() async {
    final installed = await BrowserBridge.call('install') == true;
    if (!mounted) return;
    setState(
      () => _message = installed
          ? 'GeoNexo instalado.'
          : 'No menu do navegador, escolha Instalar aplicativo ou Adicionar à Tela de Início.',
    );
  }

  Future<void> _answer(
    QuestionNotificationPayload question,
    String answer,
  ) async {
    setState(() {
      _answering = true;
      _message = null;
    });
    try {
      await QuestionNotificationService.answerFromWeb(question, answer);
    } catch (_) {
      _message = 'Não foi possível salvar a resposta. Tente novamente.';
    } finally {
      if (mounted) setState(() => _answering = false);
    }
  }

  @override
  void dispose() {
    AuthService().isAuthenticatedNotifier.removeListener(_authChanged);
    AuthService().isGuestNotifier.removeListener(_authChanged);
    _events?.cancel();
    GeofenceService().stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authenticated = AuthService().hasAppSession;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Theme.of(context).colorScheme.surfaceContainer,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.info_outline, size: 18),
                        label: Text(
                          _monitoring
                              ? 'Monitorando com app aberto'
                              : 'GeoNexo Web',
                        ),
                        onPressed: () => setState(() => _details = !_details),
                      ),
                      if (authenticated)
                        TextButton(
                          onPressed: _requesting ? null : _toggleMonitoring,
                          child: Text(
                            _requesting
                                ? 'Aguarde...'
                                : _monitoring
                                ? 'Pausar'
                                : 'Ativar localização',
                          ),
                        ),
                      TextButton(
                        onPressed: _install,
                        child: const Text('Instalar'),
                      ),
                      if (BrowserBridge.updateAvailable)
                        TextButton(
                          onPressed: () => BrowserBridge.call('update'),
                          child: const Text('Atualizar'),
                        ),
                      if (authenticated)
                        IconButton(
                          tooltip: 'Permitir avisos do relógio',
                          icon: const Icon(Icons.notifications_outlined),
                          onPressed: () async {
                            final result = await BrowserBridge.call(
                              'notifications.request',
                            );
                            if (mounted) {
                              setState(
                                () => _message = result == 'granted'
                                    ? 'Avisos permitidos enquanto o app recebe dados do relógio.'
                                    : 'Avisos não permitidos. As perguntas continuam aparecendo no aplicativo.',
                              );
                            }
                          },
                        ),
                    ],
                  ),
                  if (_details)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Mantenha o aplicativo aberto e a tela ligada para monitorar visitas e receber dados do relógio. '
                        'Para Bluetooth, use Chrome no Android. No iPhone, os demais recursos continuam disponíveis.',
                      ),
                    ),
                  if (!BrowserBridge.bluetoothSupported)
                    const Text(
                      'Este navegador não oferece Bluetooth. Use Chrome no Android para conectar o relógio.',
                    ),
                  if (_message != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(_message!, semanticsLabel: _message),
                    ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(child: widget.child),
              if (authenticated)
                ValueListenableBuilder<List<QuestionNotificationPayload>>(
                  valueListenable: QuestionNotificationService.pendingQuestions,
                  builder: (context, questions, _) {
                    if (questions.isEmpty) return const SizedBox.shrink();
                    final question = questions.first;
                    return Align(
                      alignment: Alignment.bottomCenter,
                      child: SafeArea(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: 520,
                            maxHeight: MediaQuery.sizeOf(context).height * .55,
                          ),
                          child: Card(
                            margin: const EdgeInsets.all(12),
                            elevation: 12,
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    question.locationName,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(question.prompt),
                                  const SizedBox(height: 12),
                                  for (final option in question.options)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: FilledButton(
                                        onPressed: _answering
                                            ? null
                                            : () =>
                                                  _answer(question, option.id),
                                        child: Text(option.label),
                                      ),
                                    ),
                                  if (questions.length > 1)
                                    Text(
                                      '${questions.length} perguntas pendentes',
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}
