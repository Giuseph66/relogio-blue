import 'dart:async';
import '../../../../core/result/result.dart';
import '../../../../core/ble/ble_errors.dart';
import '../../domain/entities/ble_device.dart';
import '../../domain/entities/ble_settings.dart';
import '../../domain/repositories/ble_repository.dart';
import '../datasources/reactive_ble_datasource.dart';

/// Implementation of BleRepository
class BleRepositoryImpl implements BleRepository {
  final ReactiveBleDataSource _dataSource;

  BleRepositoryImpl(this._dataSource);

  @override
  Stream<BleDevice> scanForDevices({
    String? filterByName,
    Duration? scanDuration,
  }) {
    return _dataSource.scanForDevices(
      filterByName: filterByName,
      scanDuration: scanDuration,
    );
  }

  @override
  Future<void> stopScan() {
    return _dataSource.stopScan();
  }

  @override
  Stream<ConnectionState> connectToDevice(
    String deviceId,
    BleSettings settings,
  ) {
    return _dataSource.connectToDevice(deviceId, settings);
  }

  @override
  Future<Result<void, BleError>> disconnectDevice() async {
    try {
      await _dataSource.disconnectDevice();
      return const Success(null);
    } catch (e) {
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
      await _dataSource.writeCharacteristic(
        serviceUuid,
        characteristicUuid,
        data,
      );
      return const Success(null);
    } catch (e) {
      return Failure(WriteFailedError(e.toString()));
    }
  }

  @override
  Stream<List<int>> subscribeToCharacteristic(
    String serviceUuid,
    String characteristicUuid,
  ) {
    return _dataSource.subscribeToCharacteristic(
      serviceUuid,
      characteristicUuid,
    );
  }

  @override
  Stream<ConnectionState> getConnectionState() {
    return _dataSource.getConnectionState();
  }

  @override
  Future<bool> isBluetoothEnabled() {
    return _dataSource.isBluetoothEnabled();
  }

  @override
  Stream<bool> getBluetoothStatusStream() {
    return _dataSource.bluetoothEnabledStream();
  }

  @override
  String? getConnectedDeviceId() {
    return _dataSource.getConnectedDeviceId();
  }
}
