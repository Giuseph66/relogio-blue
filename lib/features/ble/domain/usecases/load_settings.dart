import '../../../../core/result/result.dart';
import '../../../../core/ble/ble_errors.dart';
import '../entities/ble_settings.dart';
import '../repositories/preferences_repository.dart';

/// Use case to load BLE settings
class LoadSettings {
  final PreferencesRepository repository;

  LoadSettings(this.repository);

  Future<Result<BleSettings, BleError>> call() {
    return repository.loadSettings();
  }
}

