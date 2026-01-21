import '../../../../core/result/result.dart';
import '../../../../core/ble/ble_errors.dart';
import '../../domain/entities/ble_device.dart';
import '../../domain/entities/ble_settings.dart';
import '../../domain/repositories/preferences_repository.dart';
import '../datasources/preferences_datasource.dart';
import '../models/ble_device_model.dart';
import '../models/ble_settings_model.dart';

/// Implementation of PreferencesRepository
class PreferencesRepositoryImpl implements PreferencesRepository {
  final PreferencesDataSource _dataSource;

  PreferencesRepositoryImpl(this._dataSource);

  @override
  Future<Result<BleSettings, BleError>> loadSettings() async {
    try {
      final settings = await _dataSource.loadSettings();
      if (settings == null) {
        return Failure(SettingsNotConfiguredError());
      }
      return Success(settings);
    } catch (e) {
      return Failure(SettingsNotConfiguredError());
    }
  }

  @override
  Future<Result<void, BleError>> saveSettings(BleSettings settings) async {
    try {
      final model = settings is BleSettingsModel
          ? settings
          : BleSettingsModel(
              connectionMode: settings.connectionMode,
              serviceUuid: settings.serviceUuid,
              writeCharacteristicUuid: settings.writeCharacteristicUuid,
              notifyCharacteristicUuid: settings.notifyCharacteristicUuid,
              preferredDeviceName: settings.preferredDeviceName,
              preferredDeviceId: settings.preferredDeviceId,
              autoReconnect: settings.autoReconnect,
              enableMockMode: settings.enableMockMode,
              keepServiceWhenAppClosed: settings.keepServiceWhenAppClosed,
              keepBleAliveInBackground: settings.keepBleAliveInBackground,
              backgroundNotifyOnRx: settings.backgroundNotifyOnRx,
              backgroundServiceTitle: settings.backgroundServiceTitle,
              backgroundServiceText: settings.backgroundServiceText,
              serverApiUrl: settings.serverApiUrl,
            );

      final success = await _dataSource.saveSettings(model);
      if (success) {
        return const Success(null);
      } else {
        return Failure(SettingsNotConfiguredError());
      }
    } catch (e) {
      return Failure(SettingsNotConfiguredError());
    }
  }

  @override
  Future<BleDevice?> getLastDevice() async {
    try {
      return await _dataSource.getLastDevice();
    } catch (e) {
      return null;
    }
  }

  @override
  Future<void> saveLastDevice(BleDevice device) async {
    try {
      final model = device is BleDeviceModel
          ? device
          : BleDeviceModel(
              id: device.id,
              name: device.name,
              rssi: device.rssi,
              isPreferred: device.isPreferred,
            );
      await _dataSource.saveLastDevice(model);
    } catch (e) {
      // Silently fail
    }
  }

  @override
  Future<void> clearLastDevice() async {
    try {
      await _dataSource.clearLastDevice();
    } catch (e) {
      // Silently fail
    }
  }
}
