import 'dart:async';
import '../../../../core/di/dependency_injection.dart';
import '../../../../core/permissions/permission_helper.dart';
import '../../../../core/ble/ble_errors.dart';
import '../../domain/entities/ble_device.dart';
import '../../domain/repositories/ble_repository.dart';
import '../../domain/usecases/start_ble_scan.dart';
import '../../domain/usecases/stop_ble_scan.dart';
import '../../domain/usecases/connect_to_device.dart';
import '../../domain/usecases/disconnect_device.dart';
import '../../domain/usecases/load_settings.dart';

/// Controller for BLE operations
class BleController {
  final DependencyInjection _di = DependencyInjection();

  // Streams
  final _scanResultsController = StreamController<List<BleDevice>>.broadcast();
  final _connectionStateController = StreamController<ConnectionState>.broadcast();
  final _isScanningController = StreamController<bool>.broadcast();
  final _bluetoothEnabledController = StreamController<bool>.broadcast();
  final _permissionsGrantedController = StreamController<bool>.broadcast();

  Stream<List<BleDevice>> get scanResults => _scanResultsController.stream;
  Stream<ConnectionState> get connectionState => _connectionStateController.stream;
  Stream<bool> get isScanning => _isScanningController.stream;
  Stream<bool> get bluetoothEnabled => _bluetoothEnabledController.stream;
  Stream<bool> get permissionsGranted => _permissionsGrantedController.stream;

  List<BleDevice> _devices = [];
  StreamSubscription<BleDevice>? _scanSubscription;
  StreamSubscription<ConnectionState>? _connectionSubscription;
  StreamSubscription<bool>? _bluetoothSubscription;
  Timer? _statusTimer;
  bool _isScanning = false;
  bool _isRefreshingStatus = false;
  ConnectionState _currentConnectionState = ConnectionState.disconnected;
  String? _connectedDeviceId;
  bool _lastBluetoothEnabled = false;

  BleController() {
    _initialize();
  }

  Future<void> _initialize() async {
    // Check permissions
    final hasPermissions = await PermissionHelper.checkBlePermissions();
    _permissionsGrantedController.add(hasPermissions);

    // Check Bluetooth
    final isEnabled = await _di.bleRepository.isBluetoothEnabled();
    _bluetoothEnabledController.add(isEnabled);

    _bluetoothSubscription = _di.bleRepository.getBluetoothStatusStream().listen(
      (enabled) {
        _lastBluetoothEnabled = enabled;
        _bluetoothEnabledController.add(enabled);
      },
      onError: (_) {
        _bluetoothEnabledController.add(false);
      },
    );

    // Listen to connection state
    _connectionSubscription = _di.bleRepository.getConnectionState().listen(
      (state) {
        _currentConnectionState = state;
        _connectionStateController.add(state);
      },
    );

    _startStatusTimer();
  }

  /// Request permissions
  Future<bool> requestPermissions() async {
    final granted = await PermissionHelper.requestBlePermissions();
    _permissionsGrantedController.add(granted);
    return granted;
  }

  /// Refresh Bluetooth and permission status
  Future<void> refreshStatus() async {
    if (_isRefreshingStatus) return;
    _isRefreshingStatus = true;

    try {
      final hasPermissions = await PermissionHelper.checkBlePermissions();
      _permissionsGrantedController.add(hasPermissions);

      final isEnabled = await _di.bleRepository.isBluetoothEnabled();
      _lastBluetoothEnabled = isEnabled;
      _bluetoothEnabledController.add(isEnabled);
    } finally {
      _isRefreshingStatus = false;
    }
  }

  /// Start scanning
  Future<void> startScan({String? filterByName}) async {
    if (_isScanning) return;

    final hasPermissions = await PermissionHelper.checkBlePermissions();
    if (!hasPermissions) {
      final granted = await requestPermissions();
      if (!granted) {
        _scanResultsController.addError(PermissionsNotGrantedError());
        _isScanningController.add(false);
        return;
      }
    }

    await refreshStatus();
    if (!_lastBluetoothEnabled) {
      _scanResultsController.addError(BluetoothDisabledError());
      _isScanningController.add(false);
      return;
    }

    _isScanning = true;
    _isScanningController.add(true);
    _devices.clear();
    _scanResultsController.add(_devices);

    _scanSubscription = _di.startBleScan(
      filterByName: filterByName,
    ).listen(
      (device) {
        // Avoid duplicates
        final index = _devices.indexWhere((d) => d.id == device.id);
        if (index >= 0) {
          _devices[index] = device;
        } else {
          _devices.add(device);
        }
        _scanResultsController.add(List.unmodifiable(_devices));
      },
      onError: (error) {
        _isScanning = false;
        _isScanningController.add(false);
        _scanResultsController.addError(error);
      },
    );
  }

  /// Stop scanning
  Future<void> stopScan() async {
    if (!_isScanning) return;

    await _scanSubscription?.cancel();
    _scanSubscription = null;
    _isScanning = false;
    _isScanningController.add(false);
  }

  /// Connect to device
  Future<void> connectToDevice(BleDevice device) async {
    if (_currentConnectionState == ConnectionState.connected ||
        _currentConnectionState == ConnectionState.connecting) {
      return;
    }

    final settingsResult = await _di.loadSettings();
    final settings = settingsResult.valueOrNull;
    if (settings == null || !settings.isValid) {
      return;
    }

    _connectionSubscription?.cancel();
    final connectionStream = await _di.connectToDevice(device.id, settings);
    _connectionSubscription = connectionStream.listen(
      (state) {
        _currentConnectionState = state;
        _connectionStateController.add(state);
        if (state == ConnectionState.connected) {
          _connectedDeviceId = device.id;
          // Save last device
          _di.preferencesRepository.saveLastDevice(device);
        }
      },
      onError: (error) {
        _currentConnectionState = ConnectionState.disconnected;
        _connectionStateController.add(ConnectionState.disconnected);
      },
    );
  }

  /// Disconnect
  Future<void> disconnect() async {
    await _di.disconnectDevice();
    _connectedDeviceId = null;
  }

  /// Get connected device ID
  String? getConnectedDeviceId() => _connectedDeviceId ?? _di.bleRepository.getConnectedDeviceId();

  /// Dispose
  void dispose() {
    _scanSubscription?.cancel();
    _connectionSubscription?.cancel();
    _bluetoothSubscription?.cancel();
    _statusTimer?.cancel();
    _scanResultsController.close();
    _connectionStateController.close();
    _isScanningController.close();
    _bluetoothEnabledController.close();
    _permissionsGrantedController.close();
  }

  void _startStatusTimer() {
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => refreshStatus(),
    );
  }
}
