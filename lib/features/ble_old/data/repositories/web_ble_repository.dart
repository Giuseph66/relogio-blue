import 'dart:async';
import '../../../../core/ble/ble_errors.dart';
import '../../../../core/platform/browser_bridge.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/ble_device.dart';
import '../../domain/entities/ble_settings.dart';
import '../../domain/repositories/ble_repository.dart';

class WebBleRepository implements BleRepository {
  final BleSettings settings;
  final _states = StreamController<ConnectionState>.broadcast();
  final _data = StreamController<List<int>>.broadcast();
  ConnectionState _state = ConnectionState.disconnected;
  String? _deviceId;
  String? _notifyService;
  String? _notifyCharacteristic;
  int _scanGeneration = 0;
  Future<void> _writes = Future.value();

  WebBleRepository(this.settings) {
    BrowserBridge.events.listen((event) {
      if (event['id'] != _deviceId) return;
      if (event['type'] == 'ble.disconnected') {
        _deviceId = null;
        _setState(ConnectionState.disconnected);
      } else if (event['type'] == 'ble.data') {
        _data.add((event['bytes'] as List).cast<int>());
      }
    });
  }

  void _setState(ConnectionState value) {
    _state = value;
    _states.add(value);
  }

  @override
  Stream<BleDevice> scanForDevices({
    String? filterByName,
    Duration? scanDuration,
  }) {
    final controller = StreamController<BleDevice>();
    final generation = ++_scanGeneration;
    // Start immediately, before any await can consume user activation.
    final selection = BrowserBridge.call('ble.select', {
      'name': filterByName,
      'services': [settings.serviceUuid],
    });
    selection
        .then(
          (value) {
            if (generation == _scanGeneration && value != null) {
              controller.add(
                BleDevice(
                  id: value['id'] as String,
                  name: value['name'] as String,
                ),
              );
            }
          },
          onError: (Object error) {
            if (generation == _scanGeneration &&
                !error.toString().contains('User cancelled')) {
              controller.addError(ConnectionFailedError(error.toString()));
            }
          },
        )
        .whenComplete(controller.close);
    controller.onCancel = () {
      if (generation == _scanGeneration) _scanGeneration++;
    };
    return controller.stream;
  }

  @override
  Future<void> stopScan() async {
    _scanGeneration++;
    await BrowserBridge.call('ble.stop');
  }

  @override
  Stream<ConnectionState> connectToDevice(
    String deviceId,
    BleSettings settings,
  ) async* {
    _setState(ConnectionState.connecting);
    yield ConnectionState.connecting;
    try {
      await BrowserBridge.call('ble.connect', {'id': deviceId});
      _deviceId = deviceId;
      await BrowserBridge.call('ble.subscribe', {
        'id': deviceId,
        'service': _notifyService ?? settings.serviceUuid,
        'characteristic':
            _notifyCharacteristic ?? settings.notifyCharacteristicUuid,
      });
      _setState(ConnectionState.connected);
      yield ConnectionState.connected;
    } catch (error) {
      await BrowserBridge.call('ble.disconnect', {'id': deviceId});
      _deviceId = null;
      _setState(ConnectionState.disconnected);
      throw ConnectionFailedError(error.toString());
    }
    yield* _states.stream;
  }

  @override
  Future<Result<void, BleError>> disconnectDevice() async {
    try {
      if (_deviceId != null) {
        await BrowserBridge.call('ble.disconnect', {'id': _deviceId});
      }
      _deviceId = null;
      _setState(ConnectionState.disconnected);
      return const Success(null);
    } catch (_) {
      return Failure(DisconnectionFailedError());
    }
  }

  @override
  Future<Result<void, BleError>> writeCharacteristic(
    String serviceUuid,
    String characteristicUuid,
    List<int> data,
  ) async {
    try {
      final id = _deviceId;
      if (id == null) return Failure(WriteFailedError('Relógio desconectado'));
      final write = _writes.then(
        (_) => BrowserBridge.call('ble.write', {
          'id': id,
          'service': serviceUuid,
          'characteristic': characteristicUuid,
          'bytes': data,
        }),
      );
      _writes = write.then<void>((_) {}, onError: (Object _) {});
      await write;
      return const Success(null);
    } catch (error) {
      return Failure(WriteFailedError(error.toString()));
    }
  }

  @override
  Stream<List<int>> subscribeToCharacteristic(
    String serviceUuid,
    String characteristicUuid,
  ) {
    _notifyService = serviceUuid;
    _notifyCharacteristic = characteristicUuid;
    return _data.stream;
  }

  @override
  Stream<ConnectionState> getConnectionState() async* {
    yield _state;
    yield* _states.stream;
  }

  @override
  Future<bool> isBluetoothEnabled() async => BrowserBridge.bluetoothSupported;
  @override
  Stream<bool> getBluetoothStatusStream() async* {
    yield BrowserBridge.bluetoothSupported;
  }

  @override
  String? getConnectedDeviceId() => _deviceId;
}
