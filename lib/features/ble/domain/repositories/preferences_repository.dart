import '../../../../core/result/result.dart';
import '../../../../core/ble/ble_errors.dart';
import '../entities/ble_settings.dart';
import '../entities/ble_device.dart';

/// Interface for preferences storage
abstract class PreferencesRepository {
  /// Load BLE settings
  Future<Result<BleSettings, BleError>> loadSettings();

  /// Save BLE settings
  Future<Result<void, BleError>> saveSettings(BleSettings settings);

  /// Get last connected device
  Future<BleDevice?> getLastDevice();

  /// Save last connected device
  Future<void> saveLastDevice(BleDevice device);

  /// Clear last device
  Future<void> clearLastDevice();
}

