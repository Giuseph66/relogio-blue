/// Base class for BLE errors
abstract class BleError {
  final String message;
  BleError(this.message);
  
  @override
  String toString() => message;
}

/// Bluetooth is not enabled
class BluetoothDisabledError extends BleError {
  BluetoothDisabledError() : super('Bluetooth está desligado');
}

/// Permissions not granted
class PermissionsNotGrantedError extends BleError {
  PermissionsNotGrantedError() : super('Permissões não concedidas');
}

/// Device not found
class DeviceNotFoundError extends BleError {
  DeviceNotFoundError() : super('Dispositivo não encontrado');
}

/// Connection failed
class ConnectionFailedError extends BleError {
  ConnectionFailedError([String? details]) 
      : super('Falha na conexão${details != null ? ': $details' : ''}');
}

/// Disconnection failed
class DisconnectionFailedError extends BleError {
  DisconnectionFailedError() : super('Falha ao desconectar');
}

/// Write failed
class WriteFailedError extends BleError {
  WriteFailedError([String? details]) 
      : super('Falha ao enviar mensagem${details != null ? ': $details' : ''}');
}

/// Subscribe failed
class SubscribeFailedError extends BleError {
  SubscribeFailedError([String? details]) 
      : super('Falha ao assinar notificações${details != null ? ': $details' : ''}');
}

/// Invalid UUID
class InvalidUuidError extends BleError {
  InvalidUuidError(String uuid) : super('UUID inválido: $uuid');
}

/// Settings not configured
class SettingsNotConfiguredError extends BleError {
  SettingsNotConfiguredError() : super('Configurações não definidas');
}

