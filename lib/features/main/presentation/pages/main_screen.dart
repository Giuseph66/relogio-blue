import 'package:flutter/material.dart';
import 'package:app_settings/app_settings.dart';
import '../../../ble_old/presentation/controllers/ble_controller.dart';
import '../../../dashboard/presentation/pages/dashboard_page.dart';
import '../../../ble/presentation/pages/connect_device_page.dart';
import '../../../maps/presentation/pages/map_page.dart';
import '../../../settings/presentation/pages/settings_page.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  late final BleController _bleController;
  bool _isBluetoothDialogShowing = false;

  final List<Widget> _pages = [
    const ModernDashboardPage(),
    const ModernConnectDevicePage(),
    const ModernMapPage(),
    const ModernSettingsPage(),
  ];

  @override
  void initState() {
    super.initState();
    _bleController = BleController();
    _bleController.bluetoothEnabled.listen(_handleBluetoothStatus);
  }

  @override
  void dispose() {
    _bleController.dispose();
    super.dispose();
  }

  void _handleBluetoothStatus(bool enabled) {
    if (!mounted) return;
    if (enabled) {
      if (_isBluetoothDialogShowing) {
        // Automatically hide the dialog if bluetooth is enabled
        Navigator.of(context, rootNavigator: true).pop();
      }
    } else {
      if (!_isBluetoothDialogShowing) {
        _isBluetoothDialogShowing = true;
        _showBluetoothDisabledDialog();
      }
    }
  }

  Future<void> _showBluetoothDisabledDialog() async {
    final openSettings = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Bluetooth desligado'),
        content: const Text('Para usar o app e buscar dispositivos, ative o Bluetooth.'),
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

    _isBluetoothDialogShowing = false;

    if (openSettings == true) {
      AppSettings.openAppSettings(type: AppSettingsType.bluetooth);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_currentIndex != 0) {
          // Nav back to first tab instead of popping this screen
          setState(() => _currentIndex = 0);
        } else {
          // Already at root tab: exit app
          // ignore: deprecated_member_use
        }
      },
      child: Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          children: _pages,
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          type: BottomNavigationBarType.fixed,
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          selectedItemColor: Colors.cyanAccent,
          unselectedItemColor: Colors.white54,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_outlined),
              activeIcon: Icon(Icons.dashboard),
              label: 'Início',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.bluetooth_searching_outlined),
              activeIcon: Icon(Icons.bluetooth_searching),
              label: 'Dispositivo',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.map_outlined),
              activeIcon: Icon(Icons.map),
              label: 'Mapa',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings_outlined),
              activeIcon: Icon(Icons.settings),
              label: 'Ajustes',
            ),
          ],
        ),
      ),
    );
  }
}
