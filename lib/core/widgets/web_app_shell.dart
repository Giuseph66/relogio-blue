import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'settings_tiles.dart';
import '../auth/auth_service.dart';
import '../device/device_identity.dart';
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
  static final navigatorKey = GlobalKey<NavigatorState>();

  /// Reuses the shell's platform state inside the existing settings screen.
  static Widget preferences(BuildContext context) =>
      context
          .findAncestorStateOfType<_WebAppShellState>()
          ?._buildPreferences() ??
      const SizedBox.shrink();

  @override
  State<WebAppShell> createState() => _WebAppShellState();
}

class _WebAppShellState extends State<WebAppShell> {
  StreamSubscription<Map<String, dynamic>>? _events;
  bool _monitoring = false;
  bool _syncing = false;
  bool _requesting = false;
  bool _answering = false;
  final _preferencesChanged = ValueNotifier<int>(0);
  Timer? _hintTimer;
  bool _hintOffered = false;
  bool _restoringMonitoring = false;
  bool _enablingNotifications = false;
  Map<String, dynamic> _notificationStatus = {};
  Map<String, dynamic> _pushStatus = {};
  bool _testingPush = false;
  String? _requestedQuestionId;
  String? _requestedAnswerId;
  final _dismissedQuestionIds = <String>{};
  String? _message;

  void _refresh(VoidCallback change) {
    if (!mounted) return;
    setState(change);
    _preferencesChanged.value++;
    final message = _message;
    _message = null;
    if (message != null) _toast(message);
  }

  void _toast(String message, {String? action, VoidCallback? onAction}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = WebAppShell.navigatorKey.currentState?.overlay?.context;
      if (target == null) return;
      final colors = Theme.of(target).colorScheme;
      final messenger = ScaffoldMessenger.maybeOf(target);
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(
        SnackBar(
          content: Text(message, style: TextStyle(color: colors.onSurface)),
          backgroundColor: colors.surfaceContainerHigh,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 8),
          showCloseIcon: true,
          closeIconColor: colors.onSurfaceVariant,
          action: action != null && onAction != null
              ? SnackBarAction(
                  label: action,
                  textColor: colors.primary,
                  onPressed: onAction,
                )
              : null,
        ),
      );
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _openSettings() =>
      WebAppShell.navigatorKey.currentState?.pushNamed('/settings');

  Future<void> _offerSetupHint() async {
    if (!kIsWeb || _hintOffered) return;
    try {
      final app = await BrowserBridge.call('app.status') as Map;
      if (!mounted || _hintOffered) return;
      final installed = app['installed'] == true;
      if (!installed && app['installHintDismissed'] != true) {
        _hintOffered = true;
        await BrowserBridge.call('app.dismissInstallHint');
        if (!mounted) return;
        _toast(
          'Instale o GeoNexo no celular. GPS e avisos ficam em Ajustes.',
          action: 'Instalar',
          onAction: () => unawaited(_install()),
        );
      } else if (AuthService().hasAppSession &&
          (!_monitoring ||
              _notificationStatus['permission'] != 'granted' ||
              (_pushStatus['enabled'] == true &&
                  _pushStatus['subscribed'] != true))) {
        _hintOffered = true;
        _toast(
          'Configure localização e avisos para receber perguntas de visitas.',
          action: 'Configurar',
          onAction: _openSettings,
        );
      }
    } catch (_) {
      /* Installation hints are optional when offline. */
    }
  }

  Future<void> _restoreMonitoring() async {
    if (!kIsWeb || _restoringMonitoring || !AuthService().hasAppSession) return;
    _restoringMonitoring = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool('web_monitoring_enabled') ?? true;
      final permission = await Geolocator.checkPermission();
      if (!mounted || !AuthService().hasAppSession || _requesting || !enabled) {
        return;
      }
      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        _refresh(() => _monitoring = true);
        if (BrowserBridge.isVisible) {
          GeofenceService().start(pollImmediately: true);
        }
      }
    } catch (_) {
      /* The user can grant access from settings. */
    } finally {
      _restoringMonitoring = false;
    }
  }

  Future<void> _saveMonitoring(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('web_monitoring_enabled', enabled);
    } catch (_) {
      /* Monitoring remains usable without persistent preferences. */
    }
  }

  @override
  void initState() {
    super.initState();
    AuthService().isAuthenticatedNotifier.addListener(_authChanged);
    AuthService().isGuestNotifier.addListener(_authChanged);
    AuthService().accountNotifier.addListener(_authChanged);
    GeofenceService().status.addListener(_gpsChanged);
    _requestedQuestionId = Uri.base.queryParameters['question'];
    _requestedAnswerId = Uri.base.queryParameters['answer'];
    _events = BrowserBridge.events.listen((event) {
      if (event['type'] == 'visibility') {
        if (event['visible'] == true) {
          if (_monitoring) GeofenceService().start(pollImmediately: true);
          unawaited(_sync());
          unawaited(_loadNotificationStatus());
          unawaited(_restoreMonitoring());
        } else {
          GeofenceService().stop();
        }
      } else if (event['type'] == 'update') {
        if (mounted) _refresh(() {});
        _toast(
          'Uma nova versão do GeoNexo está pronta.',
          action: 'Atualizar',
          onAction: () => unawaited(BrowserBridge.call('update')),
        );
      } else if (event['type'] == 'installed') {
        unawaited(_loadNotificationStatus());
      } else if (event['type'] == 'online') {
        unawaited(_sync());
      } else if (event['type'] == 'notification.error') {
        if (mounted) _refresh(() => _message = event['message'] as String?);
      } else if (event['type'] == 'question.open') {
        _requestedQuestionId = event['recordId'] as String?;
        _requestedAnswerId = event['answerId'] as String?;
        if (_requestedQuestionId != null) {
          _refresh(() => _dismissedQuestionIds.remove(_requestedQuestionId));
          QuestionNotificationService.focusQuestion(_requestedQuestionId!);
          unawaited(_sync());
        }
      }
    });
    unawaited(_sync());
    unawaited(_loadNotificationStatus());
    unawaited(_restoreMonitoring());
    if (kIsWeb) {
      _hintTimer = Timer(
        const Duration(seconds: 2),
        () => unawaited(_offerSetupHint()),
      );
    }
  }

  void _gpsChanged() {
    if (mounted) _refresh(() {});
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
        _refresh(() {
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
    _refresh(() => _enablingNotifications = true);
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
      _refresh(
        () => _message = switch (permission) {
          'granted' =>
            pushError != null
                ? 'Avisos locais ativados. Avisos do servidor não ativados: $pushError'
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
        _refresh(
          () => _message =
              'Não foi possível ativar os avisos. Reabra a PWA instalada e tente novamente.',
        );
      }
    } finally {
      if (mounted) _refresh(() => _enablingNotifications = false);
    }
  }

  Future<void> _testPush() async {
    _refresh(() => _testingPush = true);
    try {
      final result = await BrowserBridge.call('push.test') as Map;
      if (!mounted) return;
      _refresh(
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
        _refresh(
          () => _message = error.toString().replaceFirst('Bad state: ', ''),
        );
      }
    } finally {
      if (mounted) _refresh(() => _testingPush = false);
    }
  }

  Future<void> _disablePush() async {
    try {
      await BrowserBridge.call('push.disable');
      await _loadNotificationStatus();
      if (mounted) {
        _refresh(
          () => _message =
              'Avisos do servidor desativados neste celular. Avisos locais de visitas continuam disponíveis.',
        );
      }
    } catch (_) {
      if (mounted) {
        _refresh(
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
        _refresh(
          () => _message = shown == true
              ? 'Aviso de teste enviado. Confira a Central de Notificações do celular.'
              : 'Ative os avisos na PWA instalada antes de testar.',
        );
      }
    } catch (_) {
      if (mounted) {
        _refresh(
          () => _message =
              'O aviso não foi enviado. Reabra o aplicativo instalado e confira as permissões.',
        );
      }
    }
  }

  String get _gpsLabel => !_monitoring
      ? 'GPS pausado'
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
        if (await WatchResponseRepository().isAnswerBlocked(row.questionId)) continue;
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
      final answerId = _requestedAnswerId;
      _requestedAnswerId = null;
      if (answerId != null) {
        for (final question in QuestionNotificationService.pendingQuestions.value) {
          if (question.recordId == _requestedQuestionId &&
              question.options.any((option) => option.id == answerId)) {
            await _answer(question, answerId);
            break;
          }
        }
      }
      await DependencyInjection().syncService.syncNow();
      await OfflineQuestionCache().refresh();
    } catch (_) {
      if (_requestedAnswerId != null) {
        _requestedAnswerId = null;
        _toast('Não foi possível salvar a resposta. Abra a pergunta e tente novamente.');
      }
      /* Pending data stays local for the next retry. */
    } finally {
      _syncing = false;
      if (_requestedAnswerId != null && mounted) unawaited(_sync());
    }
  }

  void _authChanged() {
    if (!AuthService().hasAppSession) {
      GeofenceService().stop();
      _monitoring = false;
    } else {
      unawaited(_sync());
      unawaited(_loadNotificationStatus());
      unawaited(_restoreMonitoring());
      if (kIsWeb) {
        _hintTimer?.cancel();
        _hintTimer = Timer(
          const Duration(seconds: 2),
          () => unawaited(_offerSetupHint()),
        );
      }
    }
    if (mounted) _refresh(() {});
  }

  Future<void> _toggleMonitoring() async {
    if (_monitoring) {
      GeofenceService().stop();
      _refresh(() => _monitoring = false);
      unawaited(_saveMonitoring(false));
      return;
    }
    _refresh(() {
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
      unawaited(_saveMonitoring(true));
      GeofenceService().start(pollImmediately: true);
      unawaited(BrowserBridge.call('storage.persist').catchError((_) => false));
    } catch (_) {
      _message =
          'Localização indisponível. Confira a permissão deste site, o GPS e a conexão HTTPS.';
    } finally {
      if (mounted) _refresh(() => _requesting = false);
    }
  }

  Future<void> _install() async {
    final installed = await BrowserBridge.call('install') == true;
    if (!mounted) return;
    _refresh(
      () => _message = installed
          ? 'GeoNexo instalado.'
          : 'No menu do navegador, escolha Instalar aplicativo ou Adicionar à Tela de Início.',
    );
  }

  Future<void> _answer(
    QuestionNotificationPayload question,
    String answer,
  ) async {
    if (!DeviceIdentity.canAnswer) {
      _refresh(() => _message = 'Para responder, abra o GeoNexo pelo ícone na tela inicial.');
      return;
    }
    _refresh(() {
      _answering = true;
      _message = null;
    });
    try {
      await QuestionNotificationService.answerFromWeb(question, answer);
    } catch (_) {
      _message = 'Não foi possível salvar a resposta. Tente novamente.';
    } finally {
      if (mounted) _refresh(() => _answering = false);
    }
  }

  @override
  void dispose() {
    AuthService().isAuthenticatedNotifier.removeListener(_authChanged);
    AuthService().isGuestNotifier.removeListener(_authChanged);
    AuthService().accountNotifier.removeListener(_authChanged);
    GeofenceService().status.removeListener(_gpsChanged);
    _events?.cancel();
    _hintTimer?.cancel();
    _preferencesChanged.dispose();
    GeofenceService().stop();
    super.dispose();
  }

  Widget _buildPreferences() => ValueListenableBuilder<int>(
    valueListenable: _preferencesChanged,
    builder: (context, _, child) => SettingsSection(
      title: 'Neste dispositivo',
      footer: 'A detecção de visitas usa o GPS com o aplicativo aberto.',
      children: [
        if (AuthService().hasAppSession) ...[
          SettingsSwitchTile(
            icon: Icons.location_on_outlined,
            title: 'Detectar visitas',
            subtitle: _requesting ? 'Solicitando localização...' : _gpsLabel,
            value: _monitoring,
            onChanged: _requesting ? null : (_) => _toggleMonitoring(),
          ),
          SettingsTile(
            icon: Icons.notifications_outlined,
            title: 'Permitir notificações',
            subtitle: _notificationStatus['needsInstallation'] == true
                ? 'No iPhone, instale e abra pela Tela de Início'
                : _notificationStatus['permission'] == 'granted'
                ? 'Permissão concedida neste dispositivo'
                : 'Receba perguntas e avisos no celular',
            value: _enablingNotifications ? 'Aguarde...' : null,
            onTap: _enablingNotifications ? null : _enableNotifications,
          ),
          if (_pushStatus['enabled'] == true)
            SettingsSwitchTile(
              icon: Icons.mark_chat_unread_outlined,
              title: 'Avisos com o app fechado',
              subtitle: 'Comunicados enviados pelo servidor',
              value: _pushStatus['subscribed'] == true,
              onChanged: _enablingNotifications
                  ? null
                  : (enabled) =>
                        enabled ? _enableNotifications() : _disablePush(),
            ),
        ],
        if (_notificationStatus['installed'] != true)
          SettingsTile(
            icon: Icons.install_mobile_outlined,
            title: 'Instalar no dispositivo',
            subtitle: 'Abra o GeoNexo pelo ícone na Tela de Início',
            onTap: _install,
          ),
        if (BrowserBridge.updateAvailable)
          SettingsTile(
            icon: Icons.system_update_alt,
            title: 'Atualizar aplicativo',
            onTap: () => BrowserBridge.call('update'),
          ),
        if (AuthService().hasAppSession &&
            _notificationStatus['permission'] == 'granted')
          ExpansionTile(
            leading: const Icon(Icons.troubleshoot_outlined),
            title: const Text('Verificar notificações'),
            children: [
              ListTile(
                title: const Text('Testar aviso local'),
                onTap: _testNotification,
              ),
              if (_pushStatus['subscribed'] == true)
                ListTile(
                  title: Text(
                    _testingPush ? 'Enviando...' : 'Testar aviso do servidor',
                  ),
                  onTap: _testingPush ? null : _testPush,
                ),
            ],
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final authenticated = AuthService().hasAppSession;
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(child: widget.child),
        if (authenticated)
          ValueListenableBuilder<List<QuestionNotificationPayload>>(
            valueListenable: QuestionNotificationService.pendingQuestions,
            builder: (context, questions, _) {
              final visibleQuestions = questions.where((question) =>
                  !_dismissedQuestionIds.contains(question.recordId ?? question.questionId)).toList();
              if (visibleQuestions.isEmpty) return const SizedBox.shrink();
              final question = visibleQuestions.first;
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
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    question.locationName,
                                    style: Theme.of(context).textTheme.titleMedium,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Fechar pergunta',
                                  icon: const Icon(Icons.close),
                                  onPressed: () => setState(() {
                                    _dismissedQuestionIds.addAll(visibleQuestions.map(
                                      (item) => item.recordId ?? item.questionId,
                                    ));
                                  }),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(question.prompt),
                            const SizedBox(height: 12),
                            if (kIsWeb && !DeviceIdentity.canAnswer) ...[
                              const Text(
                                'Para responder, instale o GeoNexo e abra pelo ícone na tela inicial. '
                                'Se já instalou, abra por lá.',
                              ),
                              const SizedBox(height: 12),
                              FilledButton.icon(
                                onPressed: _install,
                                icon: const Icon(Icons.install_mobile_outlined),
                                label: const Text('Instalar aplicativo'),
                              ),
                            ] else for (final option in question.options)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: FilledButton(
                                  onPressed: _answering
                                      ? null
                                      : () => _answer(question, option.id),
                                  child: Text(option.label),
                                ),
                              ),
                            if (visibleQuestions.length > 1)
                              Text('${visibleQuestions.length} perguntas pendentes'),
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
    );
  }
}
