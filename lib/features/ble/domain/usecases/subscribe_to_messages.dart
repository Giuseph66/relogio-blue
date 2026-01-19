import 'dart:async';
import '../entities/ble_settings.dart';
import '../repositories/ble_repository.dart';
import '../repositories/preferences_repository.dart';

/// Use case to subscribe to BLE messages
class SubscribeToMessages {
  final BleRepository bleRepository;
  final PreferencesRepository preferencesRepository;

  SubscribeToMessages(this.bleRepository, this.preferencesRepository);

  Future<Stream<List<int>>> call() async {
    final settingsResult = await preferencesRepository.loadSettings();
    final settings = settingsResult.valueOrNull;
    
    if (settings == null || !settings.isValid) {
      return Stream.empty();
    }

    return bleRepository.subscribeToCharacteristic(
      settings.serviceUuid,
      settings.notifyCharacteristicUuid,
    );
  }
}

