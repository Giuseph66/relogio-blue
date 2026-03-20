import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/logger/app_logger.dart';
import '../../../../core/config/app_config.dart';
import '../models/ble_device_model.dart';
import '../models/ble_settings_model.dart';

/// Data source for preferences storage
class PreferencesDataSource {
  static const String _keySettings = 'ble_settings';
  static const String _keyLastDeviceId = 'last_device_id';
  static const String _keyLastDeviceName = 'last_device_name';
  /// Tracks which AppConfig.serverApiUrl was active when settings were last saved.
  /// Used to detect when the config file changed so we can reset the stored URL.
  static const String _keyLastConfigServerUrl = 'last_config_server_url';

  Future<SharedPreferences> get _prefs async => SharedPreferences.getInstance();

  /// Load BLE settings
  Future<BleSettingsModel?> loadSettings() async {
    try {
      final prefs = await _prefs;
      final settingsJson = prefs.getString(_keySettings);

      if (settingsJson == null) {
        AppLogger.debug('Nenhuma configuração salva, retornando padrões');
        await prefs.setString(_keyLastConfigServerUrl, AppConfig.serverApiUrl);
        return BleSettingsModel.defaults();
      }

      final json = jsonDecode(settingsJson) as Map<String, dynamic>;
      var model = BleSettingsModel.fromJson(json);

      // If AppConfig.serverApiUrl changed since last save, reset the stored URL.
      final lastConfigUrl = prefs.getString(_keyLastConfigServerUrl) ?? '';
      if (lastConfigUrl != AppConfig.serverApiUrl) {
        AppLogger.debug('AppConfig.serverApiUrl mudou — resetando URL armazenada');
        model = model.copyWith(serverApiUrl: AppConfig.serverApiUrl);
        await prefs.setString(_keyLastConfigServerUrl, AppConfig.serverApiUrl);
        // Persist the corrected value immediately.
        await prefs.setString(_keySettings, jsonEncode(model.toJson()));
      }

      return model;
    } catch (e) {
      AppLogger.error('Erro ao carregar configurações', e);
      return BleSettingsModel.defaults();
    }
  }

  /// Save BLE settings
  Future<bool> saveSettings(BleSettingsModel settings) async {
    try {
      final prefs = await _prefs;
      final json = jsonEncode(settings.toJson());
      final success = await prefs.setString(_keySettings, json);
      // Mark the saved URL as the new "user-chosen" baseline so it won't be
      // overridden on next load unless AppConfig changes again.
      await prefs.setString(_keyLastConfigServerUrl, AppConfig.serverApiUrl);
      AppLogger.debug('Configurações salvas: $success');
      return success;
    } catch (e) {
      AppLogger.error('Erro ao salvar configurações', e);
      return false;
    }
  }

  /// Get last connected device
  Future<BleDeviceModel?> getLastDevice() async {
    try {
      final prefs = await _prefs;
      final deviceId = prefs.getString(_keyLastDeviceId);
      final deviceName = prefs.getString(_keyLastDeviceName);
      
      if (deviceId == null) {
        return null;
      }

      return BleDeviceModel(
        id: deviceId,
        name: deviceName ?? 'Unknown',
      );
    } catch (e) {
      AppLogger.error('Erro ao carregar último dispositivo', e);
      return null;
    }
  }

  /// Save last connected device
  Future<bool> saveLastDevice(BleDeviceModel device) async {
    try {
      final prefs = await _prefs;
      final idSuccess = await prefs.setString(_keyLastDeviceId, device.id);
      final nameSuccess = await prefs.setString(_keyLastDeviceName, device.name);
      AppLogger.debug('Último dispositivo salvo: ${device.name}');
      return idSuccess && nameSuccess;
    } catch (e) {
      AppLogger.error('Erro ao salvar último dispositivo', e);
      return false;
    }
  }

  /// Clear last device
  Future<bool> clearLastDevice() async {
    try {
      final prefs = await _prefs;
      final idSuccess = await prefs.remove(_keyLastDeviceId);
      final nameSuccess = await prefs.remove(_keyLastDeviceName);
      AppLogger.debug('Último dispositivo removido');
      return idSuccess && nameSuccess;
    } catch (e) {
      AppLogger.error('Erro ao remover último dispositivo', e);
      return false;
    }
  }
}

