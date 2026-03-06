import '../repositories/ble_repository.dart';

/// Use case to stop BLE scan
class StopBleScan {
  final BleRepository repository;

  StopBleScan(this.repository);

  Future<void> call() {
    return repository.stopScan();
  }
}

