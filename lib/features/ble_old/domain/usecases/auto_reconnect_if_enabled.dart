import 'dart:async';
import '../../../../core/logger/app_logger.dart';
import '../entities/ble_settings.dart';
import '../repositories/ble_repository.dart';
import '../repositories/preferences_repository.dart';
import 'connect_to_device.dart';
import '../repositories/ble_repository.dart' show ConnectionState;

/// Use case to auto-reconnect if enabled
class AutoReconnectIfEnabled {
  final BleRepository bleRepository;
  final PreferencesRepository preferencesRepository;
  final ConnectToDevice connectToDevice;

  AutoReconnectIfEnabled(
    this.bleRepository,
    this.preferencesRepository,
    this.connectToDevice,
  );

  Future<void> call() async {
    final settingsResult = await preferencesRepository.loadSettings();
    final settings = settingsResult.valueOrNull;
    
    if (settings == null || !settings.autoReconnect) {
      return;
    }

    final lastDevice = await preferencesRepository.getLastDevice();
    if (lastDevice == null) {
      AppLogger.debug('Nenhum dispositivo salvo para reconexão automática');
      return;
    }

    final connectionState = bleRepository.getConnectionState();
    StreamSubscription<ConnectionState>? subscription;
    StreamSubscription<ConnectionState>? reconnectSubscription;
    
    subscription = connectionState.listen((state) async {
      if (state == ConnectionState.disconnected) {
        AppLogger.info('Tentando reconectar automaticamente ao dispositivo: ${lastDevice.name}');
        final stream = await connectToDevice(lastDevice.id, settings);
        reconnectSubscription = stream.listen(
          (newState) {
            if (newState == ConnectionState.connected) {
              AppLogger.info('Reconexão automática bem-sucedida');
              subscription?.cancel();
              reconnectSubscription?.cancel();
            }
          },
          onError: (error) {
            AppLogger.error('Erro na reconexão automática', error);
            subscription?.cancel();
            reconnectSubscription?.cancel();
          },
        );
      }
    });
  }
}

