import '../../domain/entities/ble_settings.dart';
import '../../../../core/ble/ble_constants.dart';
import '../../../../core/config/app_config.dart';

/// Model for BLE Settings (extends entity)
class BleSettingsModel extends BleSettings {
  const BleSettingsModel({
    super.connectionMode,
    required super.serviceUuid,
    required super.writeCharacteristicUuid,
    required super.notifyCharacteristicUuid,
    super.preferredDeviceName,
    super.preferredDeviceId,
    super.autoReconnect,
    super.enableMockMode,
    super.keepServiceWhenAppClosed,
    super.keepBleAliveInBackground,
    super.backgroundNotifyOnRx,
    super.backgroundNotifyFilterEnabled,
    super.backgroundNotifyAllowedPatterns,
    super.backgroundServiceTitle,
    super.backgroundServiceText,
    super.serverApiUrl,
  });

  factory BleSettingsModel.defaults() {
    return BleSettingsModel(
      serviceUuid: BleConstants.defaultServiceUuid,
      writeCharacteristicUuid: BleConstants.defaultWriteCharacteristicUuid,
      notifyCharacteristicUuid: BleConstants.defaultNotifyCharacteristicUuid,
      preferredDeviceName: BleConstants.defaultPreferredDeviceName,
      autoReconnect: false,
      enableMockMode: false,
      keepServiceWhenAppClosed: true,
      keepBleAliveInBackground: true,
      backgroundNotifyOnRx: true,
      backgroundNotifyFilterEnabled: false,
      backgroundNotifyAllowedPatterns: const [],
      serverApiUrl: AppConfig.serverApiUrl,
    );
  }

  factory BleSettingsModel.fromJson(Map<String, dynamic> json) {
    return BleSettingsModel(
      connectionMode: ConnectionMode.values.firstWhere(
        (e) => e.name == json['connectionMode'],
        orElse: () => ConnectionMode.ble,
      ),
      serviceUuid: json['serviceUuid'] as String? ?? BleConstants.defaultServiceUuid,
      writeCharacteristicUuid: json['writeCharacteristicUuid'] as String? ?? BleConstants.defaultWriteCharacteristicUuid,
      notifyCharacteristicUuid: json['notifyCharacteristicUuid'] as String? ?? BleConstants.defaultNotifyCharacteristicUuid,
      // 'ESP32' was the old hard-coded default — treat it as "not set".
      preferredDeviceName: (() {
        final name = json['preferredDeviceName'] as String? ?? '';
        return name == 'ESP32' ? '' : name;
      })(),
      preferredDeviceId: json['preferredDeviceId'] as String?,
      autoReconnect: json['autoReconnect'] as bool? ?? false,
      enableMockMode: json['enableMockMode'] as bool? ?? false,
      keepServiceWhenAppClosed: json['keepServiceWhenAppClosed'] as bool? ?? true,
      keepBleAliveInBackground: json['keepBleAliveInBackground'] as bool? ?? true,
      backgroundNotifyOnRx: json['backgroundNotifyOnRx'] as bool? ?? true,
      backgroundNotifyFilterEnabled:
          json['backgroundNotifyFilterEnabled'] as bool? ?? false,
      backgroundNotifyAllowedPatterns:
          (json['backgroundNotifyAllowedPatterns'] as List<dynamic>?)
                  ?.map((e) => e.toString())
                  .toList() ??
              const [],
      backgroundServiceTitle: json['backgroundServiceTitle'] as String?,
      backgroundServiceText: json['backgroundServiceText'] as String?,
      // Always follow AppConfig: the settings page already saves it on every
      // save, and a stale stored URL would keep the background service
      // pointing at the old server.
      serverApiUrl: AppConfig.serverApiUrl,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'connectionMode': connectionMode.name,
      'serviceUuid': serviceUuid,
      'writeCharacteristicUuid': writeCharacteristicUuid,
      'notifyCharacteristicUuid': notifyCharacteristicUuid,
      'preferredDeviceName': preferredDeviceName,
      'preferredDeviceId': preferredDeviceId,
      'autoReconnect': autoReconnect,
      'enableMockMode': enableMockMode,
      'keepServiceWhenAppClosed': keepServiceWhenAppClosed,
      'keepBleAliveInBackground': keepBleAliveInBackground,
      'backgroundNotifyOnRx': backgroundNotifyOnRx,
      'backgroundNotifyFilterEnabled': backgroundNotifyFilterEnabled,
      'backgroundNotifyAllowedPatterns': backgroundNotifyAllowedPatterns,
      'backgroundServiceTitle': backgroundServiceTitle,
      'backgroundServiceText': backgroundServiceText,
      'serverApiUrl': serverApiUrl,
    };
  }

  @override
  BleSettingsModel copyWith({
    ConnectionMode? connectionMode,
    String? serviceUuid,
    String? writeCharacteristicUuid,
    String? notifyCharacteristicUuid,
    String? preferredDeviceName,
    String? preferredDeviceId,
    bool? autoReconnect,
    bool? enableMockMode,
    bool? keepServiceWhenAppClosed,
    bool? keepBleAliveInBackground,
    bool? backgroundNotifyOnRx,
    bool? backgroundNotifyFilterEnabled,
    List<String>? backgroundNotifyAllowedPatterns,
    String? backgroundServiceTitle,
    String? backgroundServiceText,
    String? serverApiUrl,
  }) {
    return BleSettingsModel(
      connectionMode: connectionMode ?? this.connectionMode,
      serviceUuid: serviceUuid ?? this.serviceUuid,
      writeCharacteristicUuid: writeCharacteristicUuid ?? this.writeCharacteristicUuid,
      notifyCharacteristicUuid: notifyCharacteristicUuid ?? this.notifyCharacteristicUuid,
      preferredDeviceName: preferredDeviceName ?? this.preferredDeviceName,
      preferredDeviceId: preferredDeviceId ?? this.preferredDeviceId,
      autoReconnect: autoReconnect ?? this.autoReconnect,
      enableMockMode: enableMockMode ?? this.enableMockMode,
      keepServiceWhenAppClosed:
          keepServiceWhenAppClosed ?? this.keepServiceWhenAppClosed,
      keepBleAliveInBackground: keepBleAliveInBackground ?? this.keepBleAliveInBackground,
      backgroundNotifyOnRx: backgroundNotifyOnRx ?? this.backgroundNotifyOnRx,
      backgroundNotifyFilterEnabled:
          backgroundNotifyFilterEnabled ?? this.backgroundNotifyFilterEnabled,
      backgroundNotifyAllowedPatterns:
          backgroundNotifyAllowedPatterns ?? this.backgroundNotifyAllowedPatterns,
      backgroundServiceTitle: backgroundServiceTitle ?? this.backgroundServiceTitle,
      backgroundServiceText: backgroundServiceText ?? this.backgroundServiceText,
      serverApiUrl: serverApiUrl ?? this.serverApiUrl,
    );
  }
}
