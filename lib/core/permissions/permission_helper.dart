import 'package:permission_handler/permission_handler.dart' as ph;
import '../logger/app_logger.dart';

class PermissionHelper {
  /// Request BLE permissions (Android 12+)
  static Future<bool> requestBlePermissions() async {
    try {
      AppLogger.debug('Solicitando permissões BLE...');
      
      // Android 12+ (API 31+)
      final bluetoothScan = await ph.Permission.bluetoothScan.request();
      final bluetoothConnect = await ph.Permission.bluetoothConnect.request();
      
      if (bluetoothScan.isGranted && bluetoothConnect.isGranted) {
        AppLogger.info('Permissões BLE concedidas');
        return true;
      }
      
      // Fallback for older Android versions
      final location = await ph.Permission.locationWhenInUse.request();
      if (location.isGranted) {
        AppLogger.info('Permissão de localização concedida (fallback)');
        return true;
      }
      
      AppLogger.warning('Permissões BLE negadas');
      return false;
    } catch (e) {
      AppLogger.error('Erro ao solicitar permissões BLE', e);
      return false;
    }
  }
  
  /// Check if BLE permissions are granted
  static Future<bool> checkBlePermissions() async {
    try {
      // Android 12+ (API 31+)
      final bluetoothScan = await ph.Permission.bluetoothScan.status;
      final bluetoothConnect = await ph.Permission.bluetoothConnect.status;
      
      if (bluetoothScan.isGranted && bluetoothConnect.isGranted) {
        return true;
      }
      
      // Fallback for older Android versions
      final location = await ph.Permission.locationWhenInUse.status;
      return location.isGranted;
    } catch (e) {
      AppLogger.error('Erro ao verificar permissões BLE', e);
      return false;
    }
  }
  
  /// Request location permission (for older Android versions)
  static Future<bool> requestLocationPermission() async {
    try {
      AppLogger.debug('Solicitando permissão de localização...');
      final status = await ph.Permission.locationWhenInUse.request();
      final granted = status.isGranted;
      AppLogger.info('Permissão de localização: ${granted ? "concedida" : "negada"}');
      return granted;
    } catch (e) {
      AppLogger.error('Erro ao solicitar permissão de localização', e);
      return false;
    }
  }
  
  /// Open app settings
  static Future<bool> openAppSettings() async {
    try {
      return await ph.openAppSettings();
    } catch (e) {
      AppLogger.error('Erro ao abrir configurações do app', e);
      return false;
    }
  }
}

