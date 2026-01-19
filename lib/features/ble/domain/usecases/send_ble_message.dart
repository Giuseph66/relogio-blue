import 'dart:convert';
import '../../../../core/result/result.dart';
import '../../../../core/ble/ble_errors.dart';
import '../entities/ble_settings.dart';
import '../repositories/ble_repository.dart';
import '../repositories/preferences_repository.dart';

/// Use case to send a BLE message
class SendBleMessage {
  final BleRepository bleRepository;
  final PreferencesRepository preferencesRepository;

  SendBleMessage(this.bleRepository, this.preferencesRepository);

  Future<Result<void, BleError>> call(String message) async {
    final settingsResult = await preferencesRepository.loadSettings();
    final settings = settingsResult.valueOrNull;
    
    if (settings == null || !settings.isValid) {
      return Failure(SettingsNotConfiguredError());
    }

    final data = utf8.encode(message);
    return await bleRepository.writeCharacteristic(
      settings.serviceUuid,
      settings.writeCharacteristicUuid,
      data,
    );
  }
}

