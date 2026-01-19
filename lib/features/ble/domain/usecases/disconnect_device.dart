import '../../../../core/result/result.dart';
import '../../../../core/ble/ble_errors.dart';
import '../repositories/ble_repository.dart';

/// Use case to disconnect from BLE device
class DisconnectDevice {
  final BleRepository repository;

  DisconnectDevice(this.repository);

  Future<Result<void, BleError>> call() {
    return repository.disconnectDevice();
  }
}

