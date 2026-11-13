import 'package:flutter/material.dart';
import 'package:app_settings/app_settings.dart';
import '../../../../core/routes/app_routes.dart';
import '../../../../core/permissions/permission_helper.dart';
import '../../../../core/ble/ble_errors.dart';
import '../../../ble_old/presentation/controllers/ble_controller.dart';
import '../../../ble_old/domain/entities/ble_device.dart';
import '../../../../core/theme/app_palette.dart';

class ModernConnectDevicePage extends StatefulWidget {
  const ModernConnectDevicePage({super.key});

  @override
  State<ModernConnectDevicePage> createState() => _ModernConnectDevicePageState();
}

class _ModernConnectDevicePageState extends State<ModernConnectDevicePage> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final BleController _bleController;
  late AnimationController _radarController;
  final TextEditingController _filterController = TextEditingController();
  List<BleDevice> _devices = [];
  bool _isScanning = false;
  bool _bluetoothEnabled = false;
  bool _permissionsGranted = false;

  @override
  void initState() {
    super.initState();
    _bleController = BleController();
    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    
    WidgetsBinding.instance.addObserver(this);
    _setupListeners();
    _bleController.refreshStatus();
  }

  void _setupListeners() {
    _bleController.scanResults.listen(
      (devices) {
        if (!mounted) return;
        final filteredDevices = devices.where((device) {
          final name = device.name.trim();
          return name.isNotEmpty &&
              name.toLowerCase() != 'unknown' &&
              name.toLowerCase() != 'unknow';
        }).toList();
        setState(() => _devices = filteredDevices);
      },
      onError: _handleScanError,
    );

    _bleController.isScanning.listen((scanning) {
      if (!mounted) return;
      setState(() {
        _isScanning = scanning;
        if (scanning) {
          _radarController.repeat();
        } else {
          _radarController.stop();
        }
      });
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
    _radarController.dispose();
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
        title: const Text('Dispositivos'),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: Column(
        children: [
          if (!_bluetoothEnabled || !_permissionsGranted)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: _buildStatusAlert(),
            ),
          _buildRadarSection(),
          _buildSearchField(),
          Expanded(child: _buildDeviceList()),
        ],
      ),
    );
  }

  Widget _buildRadarSection() {
    return Container(
      height: 200,
      width: double.infinity,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _radarController,
            builder: (context, child) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  for (int i = 0; i < 3; i++)
                    Container(
                      width: 100 + (100 * ((_radarController.value + (i / 3)) % 1.0)),
                      height: 100 + (100 * ((_radarController.value + (i / 3)) % 1.0)),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: context.palette.accent.withOpacity(1.0 - ((_radarController.value + (i / 3)) % 1.0)),
                          width: 2,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          IconButton(
            iconSize: 64,
            icon: Icon(
              _isScanning ? Icons.stop_circle : Icons.play_circle_fill,
              color: context.palette.accent,
            ),
            onPressed: _isScanning ? _stopScan : _startScan,
          ),
          Positioned(
            bottom: 10,
            child: Text(
              _isScanning ? 'Procurando...' : 'Iniciar Busca',
              style: TextStyle(color: context.palette.textPrimary.withValues(alpha: 0.7), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: TextField(
        controller: _filterController,
        onChanged: (_) => _startScan(),
        style: TextStyle(color: context.palette.textPrimary),
        decoration: InputDecoration(
          hintText: 'Filtrar dispositivos...',
          hintStyle: TextStyle(color: context.palette.textPrimary.withValues(alpha: 0.38)),
          prefixIcon: Icon(Icons.search, color: context.palette.textPrimary.withValues(alpha: 0.54)),
          filled: true,
          fillColor: context.palette.textPrimary.withValues(alpha: 0.05),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
        ),
      ),
    );
  }

  Widget _buildDeviceList() {
    if (_devices.isEmpty && !_isScanning) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bluetooth_disabled, size: 48, color: context.palette.textPrimary.withValues(alpha: 0.24)),
            const SizedBox(height: 16),
            Text('Nenhum dispositivo encontrado', style: TextStyle(color: context.palette.textPrimary.withValues(alpha: 0.54))),
            TextButton(onPressed: _startScan, child: const Text('Tentar novamente')),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      itemCount: _devices.length,
      itemBuilder: (context, index) {
        final device = _devices[index];
        return _buildDeviceTile(device);
      },
    );
  }

  Widget _buildDeviceTile(BleDevice device) {
    final rssi = device.rssi ?? -100;
    Color signalColor = Colors.red;
    if (rssi > -60) signalColor = context.palette.success;
    else if (rssi > -85) signalColor = context.palette.warning;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: context.palette.textPrimary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: device.isPreferred ? context.palette.accent.withValues(alpha: 0.3) : context.palette.textPrimary.withValues(alpha: 0.1),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: signalColor.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.bluetooth, color: signalColor),
        ),
        title: Text(
          device.name,
          style: TextStyle(color: context.palette.textPrimary, fontWeight: FontWeight.bold),
        ),
        subtitle: Text('ID: ${device.id}', style: TextStyle(color: context.palette.textPrimary.withValues(alpha: 0.38), fontSize: 10)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${rssi}dBm', style: TextStyle(color: signalColor, fontSize: 10)),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () => _connectToDevice(device),
              style: ElevatedButton.styleFrom(
                backgroundColor: context.palette.textPrimary,
                foregroundColor: context.palette.onAccent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: const Text('Conectar', style: TextStyle(fontSize: 12)),
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
            foregroundColor: context.palette.textPrimary,
            side: BorderSide(color: context.palette.textPrimary.withValues(alpha: 0.6)),
          ),
          child: const Text('Abrir Bluetooth'),
        ),
      if (!_permissionsGranted)
        OutlinedButton(
          onPressed: () => _bleController.requestPermissions(),
          style: OutlinedButton.styleFrom(
            foregroundColor: context.palette.textPrimary,
            side: BorderSide(color: context.palette.textPrimary.withValues(alpha: 0.6)),
          ),
          child: const Text('Solicitar permissões'),
        ),
      if (!_permissionsGranted)
        TextButton(
          onPressed: () => PermissionHelper.openAppSettings(),
          style: TextButton.styleFrom(foregroundColor: context.palette.textPrimary.withValues(alpha: 0.7)),
          child: const Text('Abrir config do app'),
        ),
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.red.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: context.palette.danger),
              SizedBox(width: 8),
              Text(
                'Atenção',
                style: TextStyle(
                  color: context.palette.danger,
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
                style: TextStyle(color: context.palette.textPrimary.withValues(alpha: 0.7), fontSize: 13),
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

  void _startScan() {
    _bleController.startScan(
      filterByName: _filterController.text.isEmpty ? null : _filterController.text,
    );
  }

  void _stopScan() {
    _bleController.stopScan();
  }

  void _connectToDevice(BleDevice device) {
    _bleController.connectToDevice(device);
    Navigator.of(context).pushNamed(AppRoutes.messages);
  }

  void _handleBluetoothStatus(bool enabled) {
    if (!mounted) return;
    setState(() => _bluetoothEnabled = enabled);
  }

  void _handleScanError(Object error) {
    if (!mounted) return;
    if (error is BluetoothDisabledError) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ative o Bluetooth para buscar dispositivos.'),
          backgroundColor: Colors.orange,
        ),
      );
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
}
