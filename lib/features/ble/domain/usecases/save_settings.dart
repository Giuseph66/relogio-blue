import '../../../../core/result/result.dart';
import '../../../../core/ble/ble_errors.dart';
import '../entities/ble_settings.dart';
import '../repositories/preferences_repository.dart';

/// Use case to save BLE settings
class SaveSettings {
  final PreferencesRepository repository;

  SaveSettings(this.repository);

  Future<Result<void, BleError>> call(BleSettings settings) async {
    if (!settings.isValid) {
      return Failure(SettingsNotConfiguredError());
    }
    return await repository.saveSettings(settings);
  }
}

