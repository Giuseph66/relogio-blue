import 'dart:async';
import 'dart:math' as math;
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import '../../../../core/ble/ble_constants.dart';
import '../../../../core/logger/app_logger.dart';
import '../../domain/entities/ble_device.dart';
import '../../domain/entities/ble_settings.dart';
import '../../domain/repositories/ble_repository.dart';
import '../models/ble_device_model.dart';

/// Data source for BLE operations using flutter_reactive_ble
class ReactiveBleDataSource {
  final FlutterReactiveBle _ble;
  final bool _mockMode;
  StreamSubscription<DiscoveredDevice>? _scanSubscription;
  StreamSubscription<ConnectionStateUpdate>? _connectionSubscription;
  StreamSubscription<List<int>>? _notifySubscription;
  StreamController<ConnectionState>? _connectionStateController;
  StreamController<List<int>>? _notifyController;
  String? _connectedDeviceId;
  Timer? _mockTimer;
  int _mockTickCounter = 0;
  BleStatus? _lastBleStatus;

  ReactiveBleDataSource({
    required FlutterReactiveBle ble,
    bool mockMode = false,
  })  : _ble = ble,
        _mockMode = mockMode;

  /// Scan for BLE devices
  Stream<BleDevice> scanForDevices({
    String? filterByName,
    Duration? scanDuration,
  }) {
    if (_mockMode) {
      return _mockScan(filterByName: filterByName);
    }

    final controller = StreamController<BleDevice>();
    final seenDevices = <String>{};

    _scanSubscription = _ble.scanForDevices(
      withServices: [],
      scanMode: ScanMode.lowLatency,
      requireLocationServicesEnabled: false,
    ).listen(
      (device) {
        if (seenDevices.contains(device.id)) {
          return;
        }
        seenDevices.add(device.id);

        final name = device.name.isEmpty ? 'Unknown' : device.name;
        
        if (filterByName != null && filterByName.isNotEmpty) {
          if (!name.toLowerCase().contains(filterByName.toLowerCase())) {
            return;
          }
        }

        final bleDevice = BleDeviceModel(
          id: device.id,
          name: name,
          rssi: device.rssi,
          isPreferred: filterByName != null && name.toLowerCase().contains(filterByName.toLowerCase()),
        );

        controller.add(bleDevice);
        AppLogger.debug('Dispositivo encontrado: $name (${device.id})');
      },
      onError: (error) {
        AppLogger.error('Erro no scan BLE', error);
        controller.addError(error);
      },
    );

    // Auto-stop after scan duration
    if (scanDuration != null) {
      Timer(scanDuration, () {
        stopScan();
      });
    }

    return controller.stream;
  }

  /// Mock scan for testing
  Stream<BleDevice> _mockScan({String? filterByName}) {
    final controller = StreamController<BleDevice>();
    
    Timer.periodic(const Duration(seconds: 2), (timer) {
      final devices = [
        BleDeviceModel(
          id: 'mock-device-1',
          name: 'ESP32',
          rssi: -45,
          isPreferred: filterByName == null || filterByName.toLowerCase().contains('esp32'),
        ),
        BleDeviceModel(
          id: 'mock-device-2',
          name: 'Arduino',
          rssi: -60,
          isPreferred: filterByName == null || filterByName.toLowerCase().contains('arduino'),
        ),
        BleDeviceModel(
          id: 'mock-device-3',
          name: 'BLE Device',
          rssi: -75,
          isPreferred: false,
        ),
      ];

      for (final device in devices) {
        if (filterByName == null || 
            filterByName.isEmpty ||
            device.name.toLowerCase().contains(filterByName.toLowerCase())) {
          controller.add(device);
        }
      }

      if (timer.tick >= 5) {
        timer.cancel();
      }
    });

    return controller.stream;
  }

  /// Stop scanning
  Future<void> stopScan() async {
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    AppLogger.debug('Scan parado');
  }

  /// Connect to a device
  Stream<ConnectionState> connectToDevice(
    String deviceId,
    BleSettings settings,
  ) {
    if (_mockMode) {
      return _mockConnect(deviceId);
    }

    _connectionStateController = StreamController<ConnectionState>.broadcast();
    _connectedDeviceId = deviceId;

    _connectionStateController!.add(ConnectionState.connecting);

    _connectionSubscription = _ble.connectToDevice(
      id: deviceId,
      connectionTimeout: BleConstants.connectionTimeout,
    ).listen(
      (update) {
        final state = _mapConnectionState(update.connectionState);
        _connectionStateController!.add(state);
        AppLogger.info('Estado de conexão: $state');

        if (state == ConnectionState.connected) {
          _subscribeToNotifications(settings);
        }
      },
      onError: (error) {
        AppLogger.error('Erro na conexão', error);
        _connectionStateController!.addError(error);
        _connectionStateController!.add(ConnectionState.disconnected);
      },
    );

    return _connectionStateController!.stream;
  }

  /// Mock connect for testing
  Stream<ConnectionState> _mockConnect(String deviceId) {
    final controller = StreamController<ConnectionState>.broadcast();
    _connectedDeviceId = deviceId;

    controller.add(ConnectionState.connecting);
    
    Timer(const Duration(milliseconds: 500), () {
      controller.add(ConnectionState.connected);
      AppLogger.info('Conectado (Simulado) ao dispositivo: $deviceId');
    });

    return controller.stream;
  }

  /// Map reactive BLE connection state to our enum
  ConnectionState _mapConnectionState(DeviceConnectionState state) {
    return switch (state) {
      DeviceConnectionState.connecting => ConnectionState.connecting,
      DeviceConnectionState.connected => ConnectionState.connected,
      DeviceConnectionState.disconnecting => ConnectionState.disconnecting,
      DeviceConnectionState.disconnected => ConnectionState.disconnected,
    };
  }

  /// Subscribe to notifications
  void _subscribeToNotifications(BleSettings settings) {
    if (_mockMode) {
      _startMockNotifications();
      return;
    }

    try {
      final characteristic = QualifiedCharacteristic(
        serviceId: Uuid.parse(settings.serviceUuid),
        characteristicId: Uuid.parse(settings.notifyCharacteristicUuid),
        deviceId: _connectedDeviceId!,
      );

      _notifySubscription = _ble.subscribeToCharacteristic(characteristic).listen(
        (data) {
          _notifyController?.add(data);
          AppLogger.debug('Dados recebidos: ${data.length} bytes');
        },
        onError: (error) {
          AppLogger.error('Erro ao receber notificações', error);
        },
      );
    } catch (e) {
      AppLogger.error('Erro ao assinar notificações', e);
    }
  }

  /// Start mock notifications
  void _startMockNotifications() {
    _notifyController = StreamController<List<int>>.broadcast();
    _mockTickCounter = 0;

    _mockTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      _mockTickCounter++;
      final message = 'tick: ${_mockTickCounter.toString().padLeft(2, '0')}';
      final data = message.codeUnits;
      _notifyController?.add(data);
      AppLogger.debug('Notificação simulada: $message');
    });
  }

  /// Disconnect from device
  Future<void> disconnectDevice() async {
    if (_mockMode) {
      _mockDisconnect();
      return;
    }

    await _connectionSubscription?.cancel();
    await _notifySubscription?.cancel();
    _connectionStateController?.add(ConnectionState.disconnecting);

    if (_connectedDeviceId != null) {
      try {
        // Note: flutter_reactive_ble doesn't have explicit disconnectDevice
        // Connection is managed via the connection stream
        await _connectionSubscription?.cancel();
      } catch (e) {
        AppLogger.error('Erro ao desconectar', e);
      }
    }

    _connectionStateController?.add(ConnectionState.disconnected);
    _connectedDeviceId = null;
    _connectionStateController?.close();
    _connectionStateController = null;
    _notifyController?.close();
    _notifyController = null;
    AppLogger.info('Desconectado');
  }

  /// Mock disconnect
  void _mockDisconnect() {
    _mockTimer?.cancel();
    _mockTimer = null;
    _notifyController?.close();
    _notifyController = null;
    _connectedDeviceId = null;
    AppLogger.info('Desconectado (Simulado)');
  }

  /// Write to characteristic
  Future<void> writeCharacteristic(
    String serviceUuid,
    String characteristicUuid,
    List<int> data,
  ) async {
    if (_mockMode) {
      _mockWrite(data);
      return;
    }

    if (_connectedDeviceId == null) {
      throw Exception('Nenhum dispositivo conectado');
    }

    try {
      final characteristic = QualifiedCharacteristic(
        serviceId: Uuid.parse(serviceUuid),
        characteristicId: Uuid.parse(characteristicUuid),
        deviceId: _connectedDeviceId!,
      );

      await _ble.writeCharacteristicWithResponse(
        characteristic,
        value: data,
      );
      AppLogger.debug('Dados enviados: ${data.length} bytes');
    } catch (e) {
      AppLogger.error('Erro ao enviar dados', e);
      rethrow;
    }
  }

  /// Mock write
  void _mockWrite(List<int> data) {
    final message = String.fromCharCodes(data);
    AppLogger.debug('Enviado (Simulado): $message');
    
    // Echo response after delay
    Timer(Duration(milliseconds: 300 + math.Random().nextInt(500)), () {
      final response = 'OK: $message';
      final responseData = response.codeUnits;
      _notifyController?.add(responseData);
      AppLogger.debug('Resposta simulada: $response');
    });
  }

  /// Subscribe to characteristic
  Stream<List<int>> subscribeToCharacteristic(
    String serviceUuid,
    String characteristicUuid,
  ) {
    if (_mockMode) {
      _startMockNotifications();
      return _notifyController?.stream ?? const Stream.empty();
    }

    if (_notifyController == null) {
      _notifyController = StreamController<List<int>>.broadcast();
    }

    return _notifyController!.stream;
  }

  /// Get connection state stream
  Stream<ConnectionState> getConnectionState() {
    if (_connectionStateController == null) {
      _connectionStateController = StreamController<ConnectionState>.broadcast();
      _connectionStateController!.add(ConnectionState.disconnected);
    }
    return _connectionStateController!.stream;
  }

  /// Check if Bluetooth is enabled
  Future<bool> isBluetoothEnabled() async {
    if (_mockMode) {
      return true;
    }

    try {
      if (_lastBleStatus != null && _lastBleStatus != BleStatus.unknown) {
        return _lastBleStatus == BleStatus.ready;
      }

      final status = await _ble.statusStream
          .firstWhere((status) => status != BleStatus.unknown)
          .timeout(
            const Duration(seconds: 2),
            onTimeout: () => _lastBleStatus ?? BleStatus.unknown,
          );

      if (status != BleStatus.unknown) {
        _lastBleStatus = status;
      }

      return status == BleStatus.ready;
    } catch (e) {
      AppLogger.error('Erro ao verificar status do Bluetooth', e);
      return _lastBleStatus == BleStatus.ready;
    }
  }

  /// Stream Bluetooth status changes
  Stream<bool> bluetoothEnabledStream() {
    if (_mockMode) {
      return Stream<bool>.value(true);
    }

    return _ble.statusStream
        .map((status) {
          _lastBleStatus = status;
          return status == BleStatus.ready;
        })
        .distinct();
  }

  /// Get connected device ID
  String? getConnectedDeviceId() => _connectedDeviceId;

  /// Dispose resources
  void dispose() {
    stopScan();
    disconnectDevice();
    _connectionStateController?.close();
    _notifyController?.close();
    _mockTimer?.cancel();
  }
}
