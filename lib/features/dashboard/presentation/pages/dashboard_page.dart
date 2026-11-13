import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/auth/auth_service.dart';
import '../../../../core/background/ble_foreground_service.dart';
import '../../../../core/ble/ble_constants.dart';
import '../../../../core/di/dependency_injection.dart';
import '../../../../core/routes/app_routes.dart';
import '../../../../core/widgets/settings_tiles.dart';
import '../../../ble_old/domain/entities/ble_message.dart';
import '../../../ble_old/domain/repositories/ble_repository.dart' as ble;
import '../../../ble_old/presentation/controllers/ble_controller.dart';
import '../../../ble_old/presentation/controllers/messages_controller.dart';
import '../../../history/domain/entities/watch_response.dart';
import '../../../location_tracker/presentation/controllers/location_tracker_controller.dart';
import '../../../../core/theme/app_palette.dart';

/// "Início" tab: greeting, location monitoring, today's activity, last
/// question, optional devices and shortcuts. The watch is an optional extra —
/// it never dominates the screen. Diagnostics only for admins.
class ModernDashboardPage extends StatefulWidget {
  /// Switches the shell to the Mapa tab (provided by MainScreen).
  final VoidCallback? onOpenMap;

  const ModernDashboardPage({super.key, this.onOpenMap});

  @override
  State<ModernDashboardPage> createState() => _ModernDashboardPageState();
}

class _ModernDashboardPageState extends State<ModernDashboardPage>
    with WidgetsBindingObserver {
  late final BleController _bleController;
  late final MessagesController _messagesController;
  late final LocationTrackerController _tracker;
  final BleForegroundServiceManager _foregroundService =
      BleForegroundServiceManager();
  final DependencyInjection _di = DependencyInjection();
  final List<StreamSubscription<dynamic>> _subs = [];

  bool _bluetoothEnabled = true;
  ble.ConnectionState _connectionState = ble.ConnectionState.disconnected;
  bool _keepBleAliveInBackground = true;
  String _deviceName = 'Relógio';

  List<WatchResponse> _responses = const [];
  BleMessage? _lastMessage;
  Timer? _reloadDebounce;

  @override
  void initState() {
    super.initState();
    _bleController = BleController();
    _messagesController = MessagesController();
    _tracker = _di.locationTrackerController;
    _tracker.addListener(_onChanged);
    WidgetsBinding.instance.addObserver(this);
    _setupListeners();
    _loadSettings();
    _loadResponses();
    _bleController.refreshStatus();
  }

  void _setupListeners() {
    _subs.add(_bleController.bluetoothEnabled.listen((enabled) {
      if (mounted) setState(() => _bluetoothEnabled = enabled);
    }));
    _subs.add(_bleController.connectionState.listen((state) {
      if (mounted) setState(() => _connectionState = state);
    }));
    _subs.add(_messagesController.tickStatus.listen((_) => _onChanged()));
    _subs.add(_messagesController.messages.listen((messages) {
      if (!mounted || messages.isEmpty) return;
      setState(() => _lastMessage = messages.last);
      // A watch answer may have just been saved — refresh the cards.
      _reloadDebounce?.cancel();
      _reloadDebounce = Timer(const Duration(milliseconds: 800), _loadResponses);
    }));
  }

  Future<void> _loadSettings() async {
    final settings = (await _di.loadSettings()).valueOrNull;
    if (!mounted) return;
    setState(() {
      _keepBleAliveInBackground = settings?.keepBleAliveInBackground ?? true;
      final name = settings?.preferredDeviceName.trim() ?? '';
      _deviceName = name.isEmpty ? BleConstants.genericDeviceLabel : name;
    });
  }

  Future<void> _loadResponses() async {
    try {
      final all = await _di.watchResponseRepository.getAll();
      if (mounted) setState(() => _responses = all);
    } catch (_) {
      // Informative only.
    }
  }

  Future<void> _refresh() async {
    await Future.wait([_loadSettings(), _loadResponses(), _bleController.refreshStatus()]);
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _messagesController.updateAppLifecycleState(state);

    if (state == AppLifecycleState.resumed) {
      _bleController.refreshStatus();
      _loadResponses();
      return;
    }

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      if (_connectionState == ble.ConnectionState.connected &&
          _keepBleAliveInBackground &&
          !_foregroundService.isRunning()) {
        Future.microtask(() => _startForegroundService(silent: true));
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tracker.removeListener(_onChanged);
    _reloadDebounce?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _bleController.dispose();
    super.dispose();
  }

  // ─── Derived data ────────────────────────────────────────────────────────

  bool _isToday(DateTime t) {
    final now = DateTime.now();
    return t.year == now.year && t.month == now.month && t.day == now.day;
  }

  int get _visitsToday => _tracker.visits.where((v) => _isToday(v.timestamp)).length;

  int get _answeredToday => _responses
      .where((r) => r.questionStatus == QuestionStatus.answered && _isToday(r.timestamp))
      .length;

  int get _pending =>
      _responses.where((r) => r.questionStatus != QuestionStatus.answered).length;

  WatchResponse? get _latest {
    if (_responses.isEmpty) return null;
    return _responses.reduce((a, b) => a.timestamp.isAfter(b.timestamp) ? a : b);
  }

  // ─── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        color: context.palette.accent,
        onRefresh: _refresh,
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 24 + MediaQuery.paddingOf(context).bottom),
          children: [
            _Greeting(now: DateTime.now()),
            const SizedBox(height: 20),
            _MonitoringCard(
              locations: _tracker.locations.length,
              backgroundActive: _foregroundService.isRunning(),
              onOpenMap: widget.onOpenMap,
            ),
            const SizedBox(height: 24),
            _sectionTitle('Hoje'),
            Row(
              children: [
                Expanded(
                  child: _MetricTile(
                    icon: Icons.directions_walk_rounded,
                    color: context.palette.accent,
                    value: _visitsToday,
                    label: 'Visitas',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MetricTile(
                    icon: Icons.task_alt_rounded,
                    color: context.palette.success,
                    value: _answeredToday,
                    label: 'Respondidas',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MetricTile(
                    icon: Icons.pending_actions_rounded,
                    color: _pending > 0 ? context.palette.warning : context.palette.textPrimary.withValues(alpha: 0.38),
                    value: _pending,
                    label: 'Pendentes',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _sectionTitle('Última pergunta'),
            _LastQuestionCard(
              response: _latest,
              onTap: () async {
                await Navigator.pushNamed(context, AppRoutes.history);
                _loadResponses();
              },
            ),
            const SizedBox(height: 24),
            SettingsSection(
              title: 'Dispositivos',
              children: [_buildWatchTile()],
            ),
            SettingsSection(
              title: 'Atalhos',
              children: [
                SettingsTile(
                  icon: Icons.history_rounded,
                  title: 'Histórico de respostas',
                  subtitle: '${_responses.length} registro(s)',
                  onTap: () async {
                    await Navigator.pushNamed(context, AppRoutes.history);
                    _loadResponses();
                  },
                ),
                SettingsTile(
                  icon: Icons.place_outlined,
                  iconColor: context.palette.warning,
                  title: 'Locais cadastrados',
                  subtitle: '${_tracker.locations.length} local(is)',
                  onTap: () => Navigator.pushNamed(context, AppRoutes.catalog),
                ),
              ],
            ),
            ValueListenableBuilder<bool>(
              valueListenable: AuthService().isAuthenticatedNotifier,
              builder: (context, isAuth, _) {
                if (!isAuth) return const SizedBox.shrink();
                return _buildDiagnostics();
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Watch as an optional accessory: neutral when absent, never an alert.
  Widget _buildWatchTile() {
    final p = context.palette;
    void open() => Navigator.pushNamed(context, AppRoutes.connect);

    return switch (_connectionState) {
      ble.ConnectionState.connected => SettingsTile(
          icon: Icons.watch_rounded,
          iconColor: _messagesController.isWatchOnline ? p.success : p.caution,
          title: _deviceName,
          subtitle: _messagesController.isWatchOnline
              ? 'Conectado · recebendo perguntas'
              : 'Conectado · aguardando sinal',
          onTap: open,
        ),
      ble.ConnectionState.connecting || ble.ConnectionState.disconnecting =>
        SettingsTile(
          icon: Icons.watch_rounded,
          iconColor: p.caution,
          title: _deviceName,
          subtitle: _connectionState == ble.ConnectionState.connecting
              ? 'Conectando…'
              : 'Desconectando…',
          onTap: open,
        ),
      ble.ConnectionState.disconnected => SettingsTile(
          icon: Icons.watch_outlined,
          iconColor: p.textMuted,
          title: 'Relógio',
          subtitle: _bluetoothEnabled
              ? 'Opcional · receba as perguntas também no pulso'
              : 'Opcional · Bluetooth desligado',
          value: 'Conectar',
          onTap: open,
        ),
    };
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 6, bottom: 10),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: context.palette.textPrimary.withValues(alpha: 0.45),
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildDiagnostics() {
    final running = _foregroundService.isRunning();
    final msg = _lastMessage;
    return SettingsSection(
      title: 'Diagnóstico',
      footer: 'Visível apenas para administradores.',
      children: [
        SettingsSwitchTile(
          icon: Icons.memory_rounded,
          iconColor: context.palette.info,
          title: 'Serviço em segundo plano',
          subtitle: running
              ? 'Ativo · keep-alive ${_keepBleAliveInBackground ? "ligado" : "desligado"}'
              : 'Parado',
          value: running,
          onChanged: (v) async {
            if (v) {
              await _startForegroundService();
            } else {
              await _foregroundService.stopBleKeepAliveService();
            }
            if (mounted) setState(() {});
          },
        ),
        SettingsTile(
          icon: msg == null
              ? Icons.swap_vert_rounded
              : (msg.isReceived ? Icons.south_west_rounded : Icons.north_east_rounded),
          iconColor: context.palette.info,
          title: msg == null
              ? 'Nenhuma mensagem BLE'
              : '${msg.isReceived ? "RX" : "TX"} · ${_hhmmss(msg.timestamp)}',
          subtitle: msg?.content,
          onTap: () => Navigator.pushNamed(context, AppRoutes.messages),
        ),
      ],
    );
  }

  String _hhmmss(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';

  Future<void> _startForegroundService({bool silent = false}) async {
    final deviceId = _bleController.getConnectedDeviceId();
    if (deviceId == null) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Conecte-se a um dispositivo primeiro'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final settings = (await _di.loadSettings()).valueOrNull;
    if (settings == null) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Configurações BLE inválidas'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    await _foregroundService.startBleKeepAliveService(
      deviceId: deviceId,
      deviceName: settings.preferredDeviceName.isNotEmpty
          ? settings.preferredDeviceName
          : 'Relógio',
      serviceUuid: settings.serviceUuid,
      notifyCharacteristicUuid: settings.notifyCharacteristicUuid,
      serverApiUrl: settings.serverApiUrl,
      keepServiceWhenAppClosed: settings.keepServiceWhenAppClosed,
      backgroundNotifyOnRx: settings.backgroundNotifyOnRx,
      backgroundNotifyFilterEnabled: settings.backgroundNotifyFilterEnabled,
      backgroundNotifyAllowedPatterns: settings.backgroundNotifyAllowedPatterns,
    );

    if (mounted) setState(() {});
  }
}

// ─── Pieces ──────────────────────────────────────────────────────────────────

const _weekdays = [
  'Segunda-feira', 'Terça-feira', 'Quarta-feira', 'Quinta-feira',
  'Sexta-feira', 'Sábado', 'Domingo',
];
const _months = [
  'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho',
  'agosto', 'setembro', 'outubro', 'novembro', 'dezembro',
];

class _Greeting extends StatelessWidget {
  final DateTime now;
  const _Greeting({required this.now});

  @override
  Widget build(BuildContext context) {
    final greeting = now.hour < 12
        ? 'Bom dia'
        : now.hour < 18
            ? 'Boa tarde'
            : 'Boa noite';
    final date = '${_weekdays[now.weekday - 1]}, ${now.day} de ${_months[now.month - 1]}';

    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            date,
            style: TextStyle(
              color: context.palette.textPrimary.withValues(alpha: 0.5),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            greeting,
            style: TextStyle(
              color: context.palette.textPrimary,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Hero card: location monitoring is the app's main job.
class _MonitoringCard extends StatelessWidget {
  final int locations;
  final bool backgroundActive;
  final VoidCallback? onOpenMap;

  const _MonitoringCard({
    required this.locations,
    required this.backgroundActive,
    this.onOpenMap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final hasLocations = locations > 0;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [p.accent.withValues(alpha: 0.14), p.card],
        ),
        border: Border.all(color: p.accent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: p.accent.withValues(alpha: 0.12),
                  border: Border.all(color: p.accent.withValues(alpha: 0.5), width: 1.5),
                ),
                child: Icon(Icons.radar_rounded, color: p.accent, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasLocations
                          ? '$locations ${locations == 1 ? "local monitorado" : "locais monitorados"}'
                          : 'Nenhum local por perto',
                      style: TextStyle(
                        color: p.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hasLocations
                          ? 'Você recebe uma pergunta ao chegar em um deles.'
                          : 'Atualize os locais no mapa para buscar os da sua cidade.',
                      style: TextStyle(color: p.textSecondary, fontSize: 13, height: 1.3),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _Chip(
                icon: backgroundActive ? Icons.shield_moon_outlined : Icons.location_searching_rounded,
                label: backgroundActive ? 'Ativo em segundo plano' : 'Ativo com o app aberto',
                color: backgroundActive ? p.success : p.textMuted,
              ),
              const Spacer(),
              if (onOpenMap != null)
                OutlinedButton.icon(
                  onPressed: onOpenMap,
                  icon: const Icon(Icons.map_outlined, size: 18),
                  label: const Text('Ver mapa'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: p.accent,
                    side: BorderSide(color: p.accent.withValues(alpha: 0.4)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _Chip({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontSize: 12)),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final int value;
  final String label;

  const _MetricTile({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.palette.textPrimary.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 10),
          Text(
            '$value',
            style: TextStyle(
              color: context.palette.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            label,
            style: TextStyle(color: context.palette.textPrimary.withValues(alpha: 0.5), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _LastQuestionCard extends StatelessWidget {
  final WatchResponse? response;
  final VoidCallback onTap;

  const _LastQuestionCard({required this.response, required this.onTap});

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'agora';
    if (d.inMinutes < 60) return 'há ${d.inMinutes} min';
    if (d.inHours < 24) return 'há ${d.inHours} h';
    if (d.inDays == 1) return 'ontem';
    return 'há ${d.inDays} dias';
  }

  @override
  Widget build(BuildContext context) {
    final r = response;
    final decoration = BoxDecoration(
      color: context.palette.card,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: context.palette.textPrimary.withValues(alpha: 0.06)),
    );

    if (r == null) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: decoration,
        child: Row(
          children: [
            Icon(Icons.quiz_outlined, color: context.palette.textPrimary.withValues(alpha: 0.3), size: 32),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'Nenhuma pergunta ainda. Chegue a um local cadastrado para receber a primeira.',
                style: TextStyle(color: context.palette.textPrimary.withValues(alpha: 0.5), fontSize: 13, height: 1.35),
              ),
            ),
          ],
        ),
      );
    }

    final (Color color, String status) = switch (r.questionStatus) {
      QuestionStatus.answered => (context.palette.success, r.answerLabel ?? 'Respondida'),
      QuestionStatus.questionSent => (context.palette.caution, 'Aguardando resposta'),
      QuestionStatus.watchOffline => (context.palette.danger, 'Relógio offline'),
    };

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: decoration,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.place_rounded, size: 16, color: context.palette.warning),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      r.locationName,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: context.palette.warning, fontSize: 13),
                    ),
                  ),
                  Text(
                    _ago(r.timestamp),
                    style: TextStyle(color: context.palette.textPrimary.withValues(alpha: 0.4), fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                r.questionText ?? 'Pergunta ${r.questionId}',
                style: TextStyle(
                  color: context.palette.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _Chip(
                    icon: r.questionStatus == QuestionStatus.answered
                        ? Icons.check_circle_rounded
                        : Icons.schedule_rounded,
                    label: status,
                    color: color,
                  ),
                  const Spacer(),
                  Icon(Icons.chevron_right_rounded, color: context.palette.textPrimary.withValues(alpha: 0.3)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
