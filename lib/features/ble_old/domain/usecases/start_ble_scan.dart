import 'dart:async';
import '../../../../core/ble/ble_constants.dart';
import '../entities/ble_device.dart';
import '../repositories/ble_repository.dart';

/// Use case to start BLE scan
class StartBleScan {
  final BleRepository repository;

  StartBleScan(this.repository);

  Stream<BleDevice> call({
    String? filterByName,
    Duration? scanDuration,
  }) {
    return repository.scanForDevices(
      filterByName: filterByName,
      scanDuration: scanDuration ?? BleConstants.scanDuration,
    );
  }
}

