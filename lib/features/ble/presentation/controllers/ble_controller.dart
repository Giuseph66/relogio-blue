import 'dart:async';
import '../../../../core/di/dependency_injection.dart';
import '../../../../core/permissions/permission_helper.dart';
import '../../../../core/ble/ble_errors.dart';
import '../../../../core/background/ble_foreground_service.dart';
import '../../domain/entities/ble_device.dart';
import '../../domain/entities/ble_settings.dart';
import '../../domain/repositories/ble_repository.dart';

/// Controller for BLE operations
class BleController {
  final DependencyInjection _di = DependencyInjection();
  final BleForegroundServiceManager _foregroundService = BleForegroundServiceManager();

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
  Timer? _autoReconnectTimer;
  bool _isScanning = false;
  bool _isRefreshingStatus = false;
  ConnectionState _currentConnectionState = ConnectionState.disconnected;
  String? _connectedDeviceId;
  bool _lastBluetoothEnabled = false;
  bool _userInitiatedDisconnect = false;
  bool _autoReconnectInProgress = false;
  int _autoReconnectAttempt = 0;

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
    _attemptAutoReconnectOnStart();
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

    _userInitiatedDisconnect = false;
    _autoReconnectInProgress = false;
    _connectionSubscription?.cancel();
    final connectionStream = await _di.connectToDevice(device.id, settings);
    _connectionSubscription = connectionStream.listen(
      (state) {
        _currentConnectionState = state;
        _connectionStateController.add(state);
        if (state == ConnectionState.connected) {
          _connectedDeviceId = device.id;
          _resetAutoReconnect();
          // Save last device
          _di.preferencesRepository.saveLastDevice(device);
          // Start foreground service if enabled
          _handleConnectionStateChange(state, device, settings);
        } else if (state == ConnectionState.disconnected) {
          _connectedDeviceId = null;
          if (_userInitiatedDisconnect || !settings.keepBleAliveInBackground) {
            _foregroundService.stopBleKeepAliveService();
            _userInitiatedDisconnect = false;
          }
          _scheduleAutoReconnect(settings);
        }
      },
      onError: (error) {
        _currentConnectionState = ConnectionState.disconnected;
        _connectedDeviceId = null;
        _connectionStateController.add(ConnectionState.disconnected);
        if (_userInitiatedDisconnect || !settings.keepBleAliveInBackground) {
          _foregroundService.stopBleKeepAliveService();
          _userInitiatedDisconnect = false;
        }
        _scheduleAutoReconnect(settings);
      },
    );
  }

  /// Handle connection state change and manage foreground service
  Future<void> _handleConnectionStateChange(
    ConnectionState state,
    BleDevice device,
    BleSettings settings,
  ) async {
    if (state == ConnectionState.connected && settings.keepBleAliveInBackground) {
      final title = settings.backgroundServiceTitle ?? device.name;
      final text = settings.backgroundServiceText ?? 'Conectado e recebendo mensagens';

      await _foregroundService.startBleKeepAliveService(
        deviceId: device.id,
        deviceName: device.name,
        serviceUuid: settings.serviceUuid,
        notifyCharacteristicUuid: settings.notifyCharacteristicUuid,
        serverApiUrl: settings.serverApiUrl,
        keepServiceWhenAppClosed: settings.keepServiceWhenAppClosed,
      );

      // Update notification with custom title/text if provided
      if (settings.backgroundServiceTitle != null || settings.backgroundServiceText != null) {
        await _foregroundService.updateNotification(
          title: title,
          text: text,
        );
      }
    }
  }

  /// Disconnect
  Future<void> disconnect() async {
    _userInitiatedDisconnect = true;
    _cancelAutoReconnect();
    await _di.disconnectDevice();
    _connectedDeviceId = null;
    // Stop foreground service
    await _foregroundService.stopBleKeepAliveService();
  }

  /// Get connected device ID
  String? getConnectedDeviceId() => _connectedDeviceId ?? _di.bleRepository.getConnectedDeviceId();

  /// Dispose
  void dispose() {
    _scanSubscription?.cancel();
    _connectionSubscription?.cancel();
    _bluetoothSubscription?.cancel();
    _statusTimer?.cancel();
    _autoReconnectTimer?.cancel();
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

  Future<void> _attemptAutoReconnectOnStart() async {
    try {
      final settingsResult = await _di.loadSettings();
      final settings = settingsResult.valueOrNull;
      if (settings == null || !settings.autoReconnect) {
        return;
      }

      final lastDevice = await _di.preferencesRepository.getLastDevice();
      if (lastDevice == null) {
        return;
      }

      if (_currentConnectionState != ConnectionState.disconnected) {
        return;
      }

      _scheduleAutoReconnect(settings);
    } catch (_) {
      // Ignore auto reconnect errors at startup
    }
  }

  void _scheduleAutoReconnect(BleSettings settings) {
    if (!settings.autoReconnect || _userInitiatedDisconnect) return;
    if (_autoReconnectTimer?.isActive ?? false) return;
    if (_autoReconnectInProgress) return;

    final nextAttempt = _autoReconnectAttempt + 1;
    _autoReconnectAttempt = nextAttempt > 5 ? 5 : nextAttempt;
    final delaySeconds = _autoReconnectAttempt <= 1
        ? 2
        : _autoReconnectAttempt <= 2
            ? 4
            : _autoReconnectAttempt <= 3
                ? 6
                : 8;

    _autoReconnectTimer = Timer(Duration(seconds: delaySeconds), () async {
      if (_userInitiatedDisconnect) return;
      if (_currentConnectionState != ConnectionState.disconnected) return;

      final hasPermissions = await PermissionHelper.checkBlePermissions();
      if (!hasPermissions) return;

      final bluetoothEnabled = await _di.bleRepository.isBluetoothEnabled();
      if (!bluetoothEnabled) return;

      final lastDevice = await _di.preferencesRepository.getLastDevice();
      if (lastDevice == null) return;

      _autoReconnectInProgress = true;
      await connectToDevice(lastDevice);
      _autoReconnectInProgress = false;
    });
  }

  void _resetAutoReconnect() {
    _autoReconnectAttempt = 0;
    _autoReconnectInProgress = false;
    _autoReconnectTimer?.cancel();
    _autoReconnectTimer = null;
  }

  void _cancelAutoReconnect() {
    _autoReconnectTimer?.cancel();
    _autoReconnectTimer = null;
    _autoReconnectInProgress = false;
    _autoReconnectAttempt = 0;
  }
}
