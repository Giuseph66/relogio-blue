import 'package:flutter/material.dart';
import 'package:app_settings/app_settings.dart';
import '../../../../core/routes/app_routes.dart';
import '../../../../core/permissions/permission_helper.dart';
import '../../../../core/background/ble_foreground_service.dart';
import '../../../../core/di/dependency_injection.dart';
import '../../../ble_old/presentation/controllers/ble_controller.dart';
import '../../../ble_old/presentation/controllers/messages_controller.dart';
import '../../../ble_old/domain/entities/ble_message.dart';
import '../../../ble_old/domain/repositories/ble_repository.dart' as ble;
import '../../../../core/auth/auth_service.dart';
import '../../../auth/presentation/widgets/auth_guard.dart';

class ModernDashboardPage extends StatefulWidget {
  const ModernDashboardPage({super.key});

  @override
  State<ModernDashboardPage> createState() => _ModernDashboardPageState();
}

class _ModernDashboardPageState extends State<ModernDashboardPage>
    with WidgetsBindingObserver {
  late final BleController _bleController;
  late final MessagesController _messagesController;
  final BleForegroundServiceManager _foregroundService =
      BleForegroundServiceManager();
  final DependencyInjection _di = DependencyInjection();

  bool _bluetoothEnabled = false;
  bool _permissionsGranted = false;
  ble.ConnectionState _connectionState = ble.ConnectionState.disconnected;
  String? _connectedDeviceId;
  bool _keepBleAliveInBackground = true;

  @override
  void initState() {
    super.initState();
    _bleController = BleController();
    _messagesController = MessagesController();
    WidgetsBinding.instance.addObserver(this);
    _setupListeners();
    _loadBackgroundSettings();
    _bleController.refreshStatus();
  }

  Future<void> _loadBackgroundSettings() async {
    final settingsResult = await _di.loadSettings();
    final settings = settingsResult.valueOrNull;
    if (!mounted) return;
    setState(() {
      _keepBleAliveInBackground = settings?.keepBleAliveInBackground ?? true;
    });
  }

  void _setupListeners() {
    _bleController.bluetoothEnabled.listen(_handleBluetoothStatus);
    _bleController.permissionsGranted.listen((granted) {
      if (!mounted) return;
      setState(() => _permissionsGranted = granted);
    });
    _bleController.connectionState.listen((state) {
      if (!mounted) return;
      setState(() {
        _connectionState = state;
        _connectedDeviceId = state == ble.ConnectionState.connected
            ? _bleController.getConnectedDeviceId()
            : null;
      });
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _messagesController.updateAppLifecycleState(state);

    if (state == AppLifecycleState.resumed) {
      _bleController.refreshStatus();
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
    _bleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connectionText = _getConnectionStatusText();
    final connectionColor = _getConnectionStatusColor();

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Dashboard'),
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          ValueListenableBuilder<bool>(
            valueListenable: AuthService().isAuthenticatedNotifier,
            builder: (context, isAuth, _) {
              if (isAuth) {
                return IconButton(
                  tooltip: 'Sair (Logout)',
                  icon: const Icon(Icons.logout_rounded),
                  onPressed: () async {
                    await AuthService().logout();
                    if (context.mounted) {
                      Navigator.pushReplacementNamed(context, AppRoutes.login);
                    }
                  },
                );
              }
              return IconButton(
                tooltip: 'Fazer Login',
                icon: const Icon(Icons.login_rounded),
                onPressed: () => Navigator.pushReplacementNamed(context, AppRoutes.login),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Olá!',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const Text(
              'Status do seu relógio hoje',
              style: TextStyle(
                fontSize: 16,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 32),
            if (!_bluetoothEnabled || !_permissionsGranted) ...[
              _buildStatusAlert(),
              const SizedBox(height: 12),
            ],
            _buildQuickStatus(
              bluetoothText: _bluetoothEnabled ? 'Ligado' : 'Desligado',
              bluetoothColor: _bluetoothEnabled ? Colors.greenAccent : Colors.redAccent,
              connectionText: connectionText,
              connectionColor: connectionColor,
              permissionsText: _permissionsGranted ? 'OK' : 'Pendente',
              permissionsColor:
                  _permissionsGranted ? Colors.cyanAccent : Colors.orangeAccent,
            ),
            if (_connectedDeviceId != null) ...[
              const SizedBox(height: 10),
              Text(
                'ID conectado: $_connectedDeviceId',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
            ValueListenableBuilder<bool>(
              valueListenable: AuthService().isAuthenticatedNotifier,
              builder: (context, isAuth, _) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 32),
                    const Text(
                      'Ações',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 2,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      children: [
                        _buildActionCard(
                          context,
                          'Conectar',
                          Icons.bluetooth,
                          Colors.blueAccent,
                          () => Navigator.pushNamed(context, AppRoutes.connect),
                        ),
                        _buildActionCard(
                          context,
                          'Histórico',
                          Icons.history_rounded,
                          Colors.tealAccent,
                          () => Navigator.pushNamed(context, AppRoutes.history),
                        ),
                        if (isAuth)
                          _buildActionCard(
                            context,
                            'Mensagens',
                            Icons.message_rounded,
                            Colors.purpleAccent,
                            () => Navigator.pushNamed(context, AppRoutes.messages),
                          ),
                      ],
                    ),
                    if (isAuth) ...[
                      const SizedBox(height: 24),
                      StreamBuilder<List<BleMessage>>(
                        stream: _messagesController.messages,
                        builder: (context, snapshot) {
                          final messages = snapshot.data ?? [];
                          if (messages.isEmpty) return const SizedBox.shrink();
                          final lastMessage = messages.last;
                          return Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white.withOpacity(0.1)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Última Mensagem',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Icon(
                                      lastMessage.isReceived ? Icons.download : Icons.upload,
                                      size: 14,
                                      color: Colors.white54,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      lastMessage.isReceived ? 'RX' : 'TX',
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      _formatTime(lastMessage.timestamp),
                                      style: const TextStyle(
                                        color: Colors.white54,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  lastMessage.content,
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 24),
                      _buildBackgroundServiceSection(),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickStatus({
    required String bluetoothText,
    required Color bluetoothColor,
    required String connectionText,
    required Color connectionColor,
    required String permissionsText,
    required Color permissionsColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          _buildStatusRow('Bluetooth', bluetoothText, bluetoothColor),
          const Divider(height: 32, color: Colors.white12),
          _buildStatusRow('Relógio', connectionText, connectionColor),
          const Divider(height: 32, color: Colors.white12),
          _buildStatusRow('Permissões', permissionsText, permissionsColor),
        ],
      ),
    );
  }

  Widget _buildStatusAlert() {
    final messages = <String>[
      if (!_bluetoothEnabled) 'Bluetooth desligado. Ative para buscar dispositivos.',
      if (!_permissionsGranted) 'Permissões pendentes. Libere nas configurações do app.',
    ];

    if (messages.isEmpty) {
      return const SizedBox.shrink();
    }

    final actions = <Widget>[
      if (!_bluetoothEnabled)
        OutlinedButton(
          onPressed: () => AppSettings.openAppSettings(type: AppSettingsType.bluetooth),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: BorderSide(color: Colors.white.withOpacity(0.6)),
          ),
          child: const Text('Abrir Bluetooth'),
        ),
      if (!_permissionsGranted)
        OutlinedButton(
          onPressed: () => _bleController.requestPermissions(),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: BorderSide(color: Colors.white.withOpacity(0.6)),
          ),
          child: const Text('Solicitar permissões'),
        ),
      if (!_permissionsGranted)
        TextButton(
          onPressed: () => PermissionHelper.openAppSettings(),
          style: TextButton.styleFrom(foregroundColor: Colors.white70),
          child: const Text('Abrir config do app'),
        ),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
              SizedBox(width: 8),
              Text(
                'Atenção',
                style: TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final message in messages)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                message,
                style: const TextStyle(color: Colors.white70),
              ),
            ),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: actions,
          ),
        ],
      ),
    );
  }

  Widget _buildBackgroundServiceSection() {
    final isRunning = _foregroundService.isRunning();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Background Service',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                isRunning ? Icons.check_circle : Icons.cancel,
                color: isRunning ? Colors.greenAccent : Colors.redAccent,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                isRunning ? 'Ativo' : 'Inativo',
                style: TextStyle(
                  color: isRunning ? Colors.greenAccent : Colors.redAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text(
                'Auto keep-alive: ${_keepBleAliveInBackground ? "Ligado" : "Desligado"}',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: isRunning
                  ? () async {
                      await _foregroundService.stopBleKeepAliveService();
                      if (mounted) {
                        setState(() {});
                      }
                    }
                  : () async => _startForegroundService(),
              style: ElevatedButton.styleFrom(
                backgroundColor: isRunning ? Colors.redAccent : Colors.greenAccent,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: Text(isRunning ? 'Parar Serviço' : 'Iniciar Serviço'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusRow(String title, String status, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: const TextStyle(color: Colors.white70, fontSize: 16)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            status,
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  void _handleBluetoothStatus(bool enabled) {
    if (!mounted) return;
    setState(() => _bluetoothEnabled = enabled);
  }

  String _getConnectionStatusText() {
    return switch (_connectionState) {
      ble.ConnectionState.disconnected => 'Desconectado',
      ble.ConnectionState.connecting => 'Conectando...',
      ble.ConnectionState.connected => 'Conectado',
      ble.ConnectionState.disconnecting => 'Desconectando...',
    };
  }

  Color _getConnectionStatusColor() {
    return switch (_connectionState) {
      ble.ConnectionState.disconnected => Colors.redAccent,
      ble.ConnectionState.connecting => Colors.orangeAccent,
      ble.ConnectionState.connected => Colors.greenAccent,
      ble.ConnectionState.disconnecting => Colors.orangeAccent,
    };
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
  }

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

    final settingsResult = await _di.loadSettings();
    final settings = settingsResult.valueOrNull;
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
          : 'Relógio BLE',
      serviceUuid: settings.serviceUuid,
      notifyCharacteristicUuid: settings.notifyCharacteristicUuid,
      serverApiUrl: settings.serverApiUrl,
      keepServiceWhenAppClosed: settings.keepServiceWhenAppClosed,
      backgroundNotifyOnRx: settings.backgroundNotifyOnRx,
      backgroundNotifyFilterEnabled: settings.backgroundNotifyFilterEnabled,
      backgroundNotifyAllowedPatterns: settings.backgroundNotifyAllowedPatterns,
    );

    if (mounted) {
      setState(() {});
    }
  }

  Widget _buildActionCard(BuildContext context, String title, IconData icon, Color color, VoidCallback onTap) {
    return Material(
      color: Colors.white.withOpacity(0.05),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 40, color: color),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
