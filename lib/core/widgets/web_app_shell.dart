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
  bool _enablingNotifications = false;
  Map<String, dynamic> _notificationStatus = {};
  Map<String, dynamic> _pushStatus = {};
  bool _testingPush = false;
  String? _requestedQuestionId;
  String? _message;

  @override
  void initState() {
    super.initState();
    AuthService().isAuthenticatedNotifier.addListener(_authChanged);
    AuthService().isGuestNotifier.addListener(_authChanged);
    GeofenceService().status.addListener(_gpsChanged);
    _requestedQuestionId = Uri.base.queryParameters['question'];
    _events = BrowserBridge.events.listen((event) {
      if (event['type'] == 'visibility') {
        if (event['visible'] == true) {
          if (_monitoring) GeofenceService().start(pollImmediately: true);
          unawaited(_sync());
          unawaited(_loadNotificationStatus());
        } else {
          GeofenceService().stop();
        }
      } else if (event['type'] == 'update') {
        if (mounted) setState(() {});
      } else if (event['type'] == 'online') {
        unawaited(_sync());
      } else if (event['type'] == 'notification.error') {
        if (mounted) setState(() => _message = event['message'] as String?);
      } else if (event['type'] == 'question.open') {
        _requestedQuestionId = event['recordId'] as String?;
        if (_requestedQuestionId != null) {
          QuestionNotificationService.focusQuestion(_requestedQuestionId!);
          unawaited(_sync());
        }
      }
    });
    unawaited(_sync());
    unawaited(_loadNotificationStatus());
  }

  void _gpsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadNotificationStatus() async {
    try {
      final status = await BrowserBridge.call('notifications.status');
      var push = <String, dynamic>{};
      if (AuthService().hasAppSession) {
        try {
          push = Map<String, dynamic>.from(
            await BrowserBridge.call('push.status') as Map,
          );
        } catch (_) {
          /* Local visit notifications remain usable offline. */
        }
      }
      if (mounted) {
        setState(() {
          _notificationStatus = Map<String, dynamic>.from(status as Map);
          _pushStatus = push;
        });
      }
    } catch (_) {
      /* Native widget tests do not load the browser adapter. */
    }
  }

  Future<void> _enableNotifications() async {
    // Call before any await: iOS requires the direct button gesture.
    final request = BrowserBridge.call('notifications.request');
    setState(() => _enablingNotifications = true);
    try {
      final permission = await request;
      Map<String, dynamic>? push;
      String? pushError;
      if (permission == 'granted') {
        try {
          push = Map<String, dynamic>.from(
            await BrowserBridge.call('push.enable') as Map,
          );
        } catch (error) {
          pushError = error.toString().replaceFirst('Bad state: ', '');
        }
      }
      await _loadNotificationStatus();
      if (!mounted) return;
      setState(
        () => _message = switch (permission) {
          'granted' =>
            pushError != null
                ? 'Avisos locais ativados. Web Push não ativado: $pushError'
                : push?['subscribed'] == true
                ? 'Avisos ativados, inclusive enviados pelo servidor com o app fechado.'
                : 'Avisos de visitas ativados com o app aberto. Avisos com o app fechado indisponíveis neste servidor ou navegador.',
          'install-required' =>
            'No iPhone, adicione o GeoNexo à Tela de Início e abra pelo ícone para ativar os avisos.',
          'denied' =>
            'Avisos bloqueados. Libere as notificações do GeoNexo nos ajustes do celular.',
          'unavailable' =>
            'Notificações indisponíveis. Confira HTTPS e a versão do sistema. No iPhone, use iOS 16.4 ou posterior.',
          _ =>
            'Permissão não concedida. As perguntas continuam disponíveis no aplicativo.',
        },
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'Não foi possível ativar os avisos. Reabra a PWA instalada e tente novamente.',
        );
      }
    } finally {
      if (mounted) setState(() => _enablingNotifications = false);
    }
  }

  Future<void> _testPush() async {
    setState(() => _testingPush = true);
    try {
      final result = await BrowserBridge.call('push.test') as Map;
      if (!mounted) return;
      setState(
        () => _message = switch (result['status']) {
          'accepted' =>
            'O serviço de push aceitou o aviso. Confira as notificações do celular.',
          'expired' => 'Inscrição expirada. Ative os avisos novamente.',
          _ =>
            'O serviço de push não aceitou o aviso. Tente novamente mais tarde.',
        },
      );
      if (result['status'] == 'expired') {
        await BrowserBridge.call('push.disable');
        await _loadNotificationStatus();
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _message = error.toString().replaceFirst('Bad state: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _testingPush = false);
    }
  }

  Future<void> _disablePush() async {
    try {
      await BrowserBridge.call('push.disable');
      await _loadNotificationStatus();
      if (mounted) {
        setState(
          () => _message =
              'Avisos do servidor desativados neste celular. Avisos locais de visitas continuam disponíveis.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'Não foi possível atualizar os avisos no servidor. Confira a conexão e tente novamente.',
        );
      }
    }
  }

  Future<void> _testNotification() async {
    try {
      final shown = await BrowserBridge.call('notify', {
        'title': 'GeoNexo',
        'body': 'Avisos de visitas ativados neste celular.',
        'tag': 'geonexo-test',
      });
      if (mounted) {
        setState(
          () => _message = shown == true
              ? 'Aviso de teste enviado. Confira a Central de Notificações do celular.'
              : 'Ative os avisos na PWA instalada antes de testar.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'O aviso não foi enviado. Reabra o aplicativo instalado e confira as permissões.',
        );
      }
    }
  }

  String get _gpsLabel => !_monitoring
      ? 'GeoNexo • GPS pausado'
      : switch (GeofenceService().status.value) {
          GpsMonitoringStatus.active => 'GPS ativo • app aberto',
          GpsMonitoringStatus.unavailable => 'GPS indisponível',
          _ => 'Buscando localização...',
        };

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
          notify: false,
        );
      }
      if (_requestedQuestionId != null) {
        QuestionNotificationService.focusQuestion(_requestedQuestionId!);
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
      unawaited(_loadNotificationStatus());
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
    GeofenceService().status.removeListener(_gpsChanged);
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
                        label: Text(_gpsLabel),
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
                                : 'Ativar GPS',
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
                        TextButton.icon(
                          icon: const Icon(
                            Icons.notifications_outlined,
                            size: 18,
                          ),
                          onPressed: _enablingNotifications
                              ? null
                              : _enableNotifications,
                          label: Text(
                            _enablingNotifications
                                ? 'Aguarde...'
                                : _notificationStatus['permission'] == 'granted'
                                ? _pushStatus['enabled'] == true &&
                                          _pushStatus['subscribed'] != true
                                      ? 'Ativar Web Push'
                                      : 'Avisos ativados'
                                : 'Ativar avisos',
                          ),
                        ),
                      if (authenticated &&
                          _notificationStatus['permission'] == 'granted')
                        TextButton(
                          onPressed: _testNotification,
                          child: const Text('Testar aviso'),
                        ),
                      if (authenticated && _pushStatus['subscribed'] == true)
                        TextButton(
                          onPressed: _testingPush ? null : _testPush,
                          child: Text(
                            _testingPush ? 'Enviando...' : 'Testar Web Push',
                          ),
                        ),
                      if (authenticated &&
                          _pushStatus['hasSubscription'] == true)
                        TextButton(
                          onPressed: _disablePush,
                          child: const Text('Desativar Web Push'),
                        ),
                    ],
                  ),
                  if (_details)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Ative GPS e avisos para receber perguntas de visitas no próprio celular, sem relógio. '
                        'Mantenha a PWA aberta. No iPhone, instale na Tela de Início e abra pelo ícone para permitir notificações.',
                      ),
                    ),
                  if (_notificationStatus['needsInstallation'] == true)
                    const Text(
                      'iPhone: Compartilhar → Adicionar à Tela de Início. Abra pelo ícone para ativar os avisos.',
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
