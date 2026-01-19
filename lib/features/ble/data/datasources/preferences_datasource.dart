import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/logger/app_logger.dart';
import '../models/ble_device_model.dart';
import '../models/ble_settings_model.dart';

/// Data source for preferences storage
class PreferencesDataSource {
  static const String _keySettings = 'ble_settings';
  static const String _keyLastDeviceId = 'last_device_id';
  static const String _keyLastDeviceName = 'last_device_name';

  Future<SharedPreferences> get _prefs async => SharedPreferences.getInstance();

  /// Load BLE settings
  Future<BleSettingsModel?> loadSettings() async {
    try {
      final prefs = await _prefs;
      final settingsJson = prefs.getString(_keySettings);
      
      if (settingsJson == null) {
        AppLogger.debug('Nenhuma configuração salva, retornando padrões');
        return BleSettingsModel.defaults();
      }

      final json = jsonDecode(settingsJson) as Map<String, dynamic>;
      return BleSettingsModel.fromJson(json);
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

