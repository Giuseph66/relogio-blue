import 'package:flutter/material.dart';
import 'package:app_settings/app_settings.dart';
import '../../../../core/widgets/app_drawer.dart';
import '../../../../core/routes/app_routes.dart';
import '../../../../core/ble/ble_errors.dart';
import '../../../../core/permissions/permission_helper.dart';
import '../controllers/ble_controller.dart';
import '../../domain/entities/ble_device.dart';

class ConnectDevicePage extends StatefulWidget {
  const ConnectDevicePage({super.key});

  @override
  State<ConnectDevicePage> createState() => _ConnectDevicePageState();
}

class _ConnectDevicePageState extends State<ConnectDevicePage> with WidgetsBindingObserver {
  late final BleController _bleController;
  final TextEditingController _filterController = TextEditingController();
  List<BleDevice> _devices = [];
  bool _isScanning = false;
  bool _bluetoothEnabled = false;
  bool _permissionsGranted = false;
  bool _hasPromptedBluetoothOff = false;

  @override
  void initState() {
    super.initState();
    _bleController = BleController();
    WidgetsBinding.instance.addObserver(this);
    _setupListeners();
    _bleController.refreshStatus();
  }

  void _setupListeners() {
    _bleController.scanResults.listen(
      (devices) {
        if (!mounted) return;
        setState(() => _devices = devices);
      },
      onError: _handleScanError,
    );
    _bleController.isScanning.listen((scanning) {
      if (!mounted) return;
      setState(() => _isScanning = scanning);
    });
    _bleController.bluetoothEnabled.listen(_handleBluetoothStatus);
    _bleController.permissionsGranted.listen((granted) {
      if (!mounted) return;
      setState(() => _permissionsGranted = granted);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _bleController.dispose();
    _filterController.dispose();
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
        title: const Text('Conectar Dispositivo'),
        actions: [
          IconButton(
            tooltip: 'Configurações',
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.pushNamed(context, AppRoutes.settings),
          ),
        ],
      ),
      drawer: const AppDrawer(),
      body: Column(
        children: [
          if (!_bluetoothEnabled || !_permissionsGranted)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: _buildStatusAlert(),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _filterController,
              decoration: InputDecoration(
                labelText: 'Filtrar por nome',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _filterController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _filterController.clear();
                          _startScan();
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                filled: true,
                fillColor: Colors.white.withOpacity(0.1),
              ),
              style: const TextStyle(color: Colors.white),
              onChanged: (_) => _startScan(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isScanning ? _stopScan : _startScan,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                    child: Text(_isScanning ? 'Parar Busca' : 'Iniciar Busca'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _devices.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.bluetooth_disabled,
                          size: 64,
                          color: Colors.white.withOpacity(0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _isScanning
                              ? 'Buscando dispositivos...'
                              : 'Nenhum dispositivo encontrado',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _devices.length,
                    itemBuilder: (context, index) {
                      final device = _devices[index];
                      return _buildDeviceItem(device);
                    },
                  ),
          ),
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

  Widget _buildDeviceItem(BleDevice device) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.white.withOpacity(0.1),
      child: ListTile(
        leading: Icon(
          Icons.bluetooth,
          color: device.isPreferred ? Colors.green : Colors.white,
        ),
        title: Text(
          device.name,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ID: ${device.id}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
            if (device.rssi != null)
              Text('RSSI: ${device.rssi} dBm', style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
        trailing: ElevatedButton(
          onPressed: () => _connectToDevice(device),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
          ),
          child: const Text('Conectar'),
        ),
      ),
    );
  }

  void _startScan() {
    final filter = _filterController.text.trim();
    _bleController.startScan(filterByName: filter.isEmpty ? null : filter);
  }

  void _stopScan() {
    _bleController.stopScan();
  }

  void _connectToDevice(BleDevice device) {
    _bleController.connectToDevice(device);
    Navigator.pushNamed(context, AppRoutes.messages);
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

  void _handleScanError(Object error) {
    if (!mounted) return;
    if (error is BluetoothDisabledError) {
      _showBluetoothDisabledDialog();
      return;
    }

    final message = error is BleError ? error.message : 'Erro ao buscar dispositivos';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  Future<void> _showBluetoothDisabledDialog() async {
    final openSettings = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bluetooth desligado'),
        content: const Text('Para buscar dispositivos, ative o Bluetooth.'),
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
}
