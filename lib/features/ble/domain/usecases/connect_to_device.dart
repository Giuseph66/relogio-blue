import '../entities/ble_settings.dart';
import '../repositories/ble_repository.dart';
import '../repositories/preferences_repository.dart';
import '../../../../core/ble/ble_constants.dart';
import '../../../../core/result/result.dart';

/// Use case to connect to a BLE device
class ConnectToDevice {
  final BleRepository bleRepository;
  final PreferencesRepository preferencesRepository;

  ConnectToDevice(this.bleRepository, this.preferencesRepository);

  Future<Stream<ConnectionState>> call(
    String deviceId,
    BleSettings settings,
  ) async {
    // Load settings if not provided
    final effectiveSettings = settings.isValid
        ? settings
        : (await preferencesRepository.loadSettings()).valueOrNull ??
            BleSettings(
              serviceUuid: BleConstants.defaultServiceUuid,
              writeCharacteristicUuid: BleConstants.defaultWriteCharacteristicUuid,
              notifyCharacteristicUuid: BleConstants.defaultNotifyCharacteristicUuid,
            );

    return bleRepository.connectToDevice(deviceId, effectiveSettings);
  }
}

