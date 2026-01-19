import 'package:flutter/material.dart';
import 'package:app_settings/app_settings.dart';
import '../../../../core/widgets/app_drawer.dart';
import '../../../../core/routes/app_routes.dart';
import '../../../../core/permissions/permission_helper.dart';
import '../controllers/ble_controller.dart';
import '../controllers/messages_controller.dart';
import '../../domain/repositories/ble_repository.dart' as ble;
import '../../domain/entities/ble_message.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> with WidgetsBindingObserver {
  late final BleController _bleController;
  late final MessagesController _messagesController;
  bool _bluetoothEnabled = false;
  bool _permissionsGranted = false;
  ble.ConnectionState _connectionState = ble.ConnectionState.disconnected;
  String? _connectedDeviceId;
  bool _hasPromptedBluetoothOff = false;

  @override
  void initState() {
    super.initState();
    _bleController = BleController();
    _messagesController = MessagesController();
    WidgetsBinding.instance.addObserver(this);
    _setupListeners();
  }

  void _setupListeners() {
    _bleController.bluetoothEnabled.listen(_handleBluetoothStatus);
    _bleController.permissionsGranted.listen((granted) {
      setState(() => _permissionsGranted = granted);
    });
    _bleController.connectionState.listen((state) {
      setState(() => _connectionState = state);
      if (state == ble.ConnectionState.connected) {
        _connectedDeviceId = _bleController.getConnectedDeviceId();
      } else {
        _connectedDeviceId = null;
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _bleController.dispose();
    _messagesController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _bleController.refreshStatus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
      ),
      drawer: const AppDrawer(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Status do Sistema',
              style: TextStyle(
                fontSize: 24,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            if (!_bluetoothEnabled || !_permissionsGranted) ...[
              _buildStatusAlert(),
              const SizedBox(height: 15),
            ],
            _buildStatusCard(
              'Bluetooth',
              _bluetoothEnabled ? 'Ligado' : 'Desligado',
              _bluetoothEnabled ? Colors.green : Colors.red,
              Icons.bluetooth,
            ),
            const SizedBox(height: 15),
            _buildStatusCard(
              'Permissões',
              _permissionsGranted ? 'OK' : 'Pendente',
              _permissionsGranted ? Colors.green : Colors.orange,
              Icons.security,
            ),
            const SizedBox(height: 15),
            _buildStatusCard(
              'Dispositivo',
              _getConnectionStatusText(),
              _getConnectionStatusColor(),
              Icons.devices,
            ),
            if (_connectedDeviceId != null) ...[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Text(
                  'ID: $_connectedDeviceId',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ],
            const SizedBox(height: 30),
            const Text(
              'Ações Rápidas',
              style: TextStyle(
                fontSize: 24,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _buildActionButton(
                    'Conectar',
                    Icons.bluetooth_searching,
                    () => Navigator.pushNamed(context, AppRoutes.connect),
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: _buildActionButton(
                    'Mensagens',
                    Icons.message,
                    () => Navigator.pushNamed(context, AppRoutes.messages),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            _buildActionButton(
              'Configurações',
              Icons.settings,
              () => Navigator.pushNamed(context, AppRoutes.settings),
              fullWidth: true,
            ),
            const SizedBox(height: 30),
            StreamBuilder<List<BleMessage>>(
              stream: _messagesController.messages,
              builder: (context, snapshot) {
                final messages = snapshot.data ?? [];
                if (messages.isEmpty) {
                  return const SizedBox.shrink();
                }
                final lastMessage = messages.last;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Última Mensagem Recebida',
                      style: TextStyle(
                        fontSize: 20,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white.withOpacity(0.2)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                lastMessage.isReceived ? Icons.download : Icons.upload,
                                color: Colors.white,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                lastMessage.isReceived ? 'RX' : 'TX',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                _formatTime(lastMessage.timestamp),
                                style: const TextStyle(
                                  color: Colors.white70,
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
                    ),
                  ],
                );
              },
            ),
          ],
        ),
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
          child: const Text('Abrir configurações do app'),
        ),
    ];

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red, size: 24),
              SizedBox(width: 10),
              Text(
                'Atenção',
                style: TextStyle(
                  color: Colors.red,
                  fontSize: 16,
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
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ),
          if (actions.isNotEmpty)
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: actions,
            ),
        ],
      ),
    );
  }

  Widget _buildStatusCard(String title, String status, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 30),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  status,
                  style: TextStyle(
                    color: color,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _handleBluetoothStatus(bool enabled) {
    if (!mounted) return;
    setState(() => _bluetoothEnabled = enabled);

    if (enabled) {
      _hasPromptedBluetoothOff = false;
      return;
    }

    if (!_hasPromptedBluetoothOff) {
      _hasPromptedBluetoothOff = true;
      _showBluetoothDisabledDialog();
    }
  }

  Future<void> _showBluetoothDisabledDialog() async {
    final openSettings = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bluetooth desligado'),
        content: const Text('Para usar o app, ative o Bluetooth.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Abrir Bluetooth'),
          ),
        ],
      ),
    );

    if (openSettings == true) {
      AppSettings.openAppSettings(type: AppSettingsType.bluetooth);
    }
  }

  Widget _buildActionButton(
    String label,
    IconData icon,
    VoidCallback onPressed, {
    bool fullWidth = false,
  }) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        padding: const EdgeInsets.symmetric(vertical: 20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
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
      ble.ConnectionState.disconnected => Colors.red,
      ble.ConnectionState.connecting => Colors.orange,
      ble.ConnectionState.connected => Colors.green,
      ble.ConnectionState.disconnecting => Colors.orange,
    };
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
  }
}
