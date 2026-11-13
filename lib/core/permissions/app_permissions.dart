import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import '../logger/app_logger.dart';

/// Everything the app needs to work. Order matters: it is the order the user
/// is asked (background location can only be requested after foreground).
enum AppRequirement {
  location,
  backgroundLocation,
  bluetooth,
  notifications,
  locationService,
}

enum RequirementStatus {
  granted,

  /// Not granted yet, the system dialog can still be shown.
  pending,

  /// Denied permanently: only the app settings screen can fix it.
  blocked,
}

/// Checks and requests the app's mandatory permissions.
class AppPermissions {
  AppPermissions._();

  static Future<Map<AppRequirement, RequirementStatus>> checkAll() async {
    final result = <AppRequirement, RequirementStatus>{};
    for (final req in AppRequirement.values) {
      result[req] = await check(req);
    }
    return result;
  }

  static Future<bool> allGranted() async {
    final all = await checkAll();
    return all.values.every((s) => s == RequirementStatus.granted);
  }

  static Future<RequirementStatus> check(AppRequirement req) async {
    try {
      switch (req) {
        case AppRequirement.location:
          return _map(await ph.Permission.locationWhenInUse.status);
        case AppRequirement.backgroundLocation:
          return _map(await ph.Permission.locationAlways.status);
        case AppRequirement.bluetooth:
          final scan = await ph.Permission.bluetoothScan.status;
          final connect = await ph.Permission.bluetoothConnect.status;
          return _combine([_map(scan), _map(connect)]);
        case AppRequirement.notifications:
          return _map(await ph.Permission.notification.status);
        case AppRequirement.locationService:
          return await Geolocator.isLocationServiceEnabled()
              ? RequirementStatus.granted
              : RequirementStatus.pending;
      }
    } catch (e) {
      AppLogger.warning('AppPermissions: check $req failed: $e');
      return RequirementStatus.pending;
    }
  }

  /// Shows the system dialog (or the right settings screen) for [req].
  static Future<RequirementStatus> request(AppRequirement req) async {
    try {
      final current = await check(req);
      if (current == RequirementStatus.granted) return current;

      if (current == RequirementStatus.blocked) {
        await ph.openAppSettings();
        return await check(req);
      }

      switch (req) {
        case AppRequirement.location:
          await ph.Permission.locationWhenInUse.request();
          break;
        case AppRequirement.backgroundLocation:
          // Android only allows asking "all the time" after "while in use".
          if (!await ph.Permission.locationWhenInUse.isGranted) {
            await ph.Permission.locationWhenInUse.request();
          }
          await ph.Permission.locationAlways.request();
          break;
        case AppRequirement.bluetooth:
          await [
            ph.Permission.bluetoothScan,
            ph.Permission.bluetoothConnect,
          ].request();
          break;
        case AppRequirement.notifications:
          await ph.Permission.notification.request();
          break;
        case AppRequirement.locationService:
          await Geolocator.openLocationSettings();
          break;
      }
      return await check(req);
    } catch (e) {
      AppLogger.warning('AppPermissions: request $req failed: $e');
      return check(req);
    }
  }

  static RequirementStatus _map(ph.PermissionStatus status) {
    if (status.isGranted || status.isLimited) return RequirementStatus.granted;
    if (status.isPermanentlyDenied || status.isRestricted) {
      return RequirementStatus.blocked;
    }
    return RequirementStatus.pending;
  }

  static RequirementStatus _combine(List<RequirementStatus> statuses) {
    if (statuses.every((s) => s == RequirementStatus.granted)) {
      return RequirementStatus.granted;
    }
    if (statuses.any((s) => s == RequirementStatus.blocked)) {
      return RequirementStatus.blocked;
    }
    return RequirementStatus.pending;
  }
}
