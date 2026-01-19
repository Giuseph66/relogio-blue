import 'dart:async';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import '../logger/app_logger.dart';

/// Manager for BLE Foreground Service
/// Manages the foreground service that keeps BLE connection alive in background
class BleForegroundServiceManager {
  static final BleForegroundServiceManager _instance = BleForegroundServiceManager._internal();
  factory BleForegroundServiceManager() => _instance;
  BleForegroundServiceManager._internal();

  bool _initialized = false;
  bool _isRunning = false;
  String? _currentDeviceId;
  String? _currentDeviceName;
  String? _currentNotificationTitle;
  String? _currentNotificationText;

  /// Initialize the foreground task
  Future<void> init() async {
    if (_initialized) return;

    try {
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'ble_keep_alive_channel',
          channelName: 'BLE Keep Alive',
          channelDescription: 'Mantém a conexão BLE ativa em segundo plano',
          channelImportance: NotificationChannelImportance.LOW,
          priority: NotificationPriority.LOW,
        ),
        iosNotificationOptions: const IOSNotificationOptions(
          showNotification: true,
          playSound: false,
        ),
        foregroundTaskOptions: ForegroundTaskOptions(
          eventAction: ForegroundTaskEventAction.repeat(5000),
          allowWakeLock: true,
          allowWifiLock: true,
          autoRunOnBoot: false,
        ),
      );
      _initialized = true;
      AppLogger.info('BleForegroundServiceManager inicializado');
    } catch (e) {
      AppLogger.error('Erro ao inicializar BleForegroundServiceManager', e);
    }
  }

  /// Start the BLE keep-alive foreground service
  Future<bool> startBleKeepAliveService({
    required String deviceId,
    String? deviceName,
  }) async {
    if (!_initialized) {
      await init();
    }

    if (_isRunning && _currentDeviceId == deviceId) {
      AppLogger.debug('Serviço já está rodando para este dispositivo');
      return true;
    }

    try {
      final title = deviceName ?? 'Relógio BLE';
      final text = 'Conectado e recebendo mensagens';
      _currentNotificationTitle = title;
      _currentNotificationText = text;

      await FlutterForegroundTask.startService(
        notificationTitle: title,
        notificationText: text,
        callback: _startCallback,
      );

      _isRunning = true;
      _currentDeviceId = deviceId;
      _currentDeviceName = deviceName;
      AppLogger.info('Foreground service iniciado para dispositivo: $deviceId');
      return true;
    } catch (e) {
      AppLogger.error('Erro ao iniciar foreground service', e);
      return false;
    }
  }

  /// Stop the foreground service
  Future<void> stopBleKeepAliveService() async {
    if (!_isRunning) return;

    try {
      await FlutterForegroundTask.stopService();
      _isRunning = false;
      _currentDeviceId = null;
      _currentDeviceName = null;
      _currentNotificationTitle = null;
      _currentNotificationText = null;
      AppLogger.info('Foreground service parado');
    } catch (e) {
      AppLogger.error('Erro ao parar foreground service', e);
    }
  }

  /// Update the notification text
  Future<void> updateNotification({
    String? title,
    String? text,
  }) async {
    if (!_isRunning) return;

    try {
      final updatedTitle =
          title ?? _currentNotificationTitle ?? _currentDeviceName ?? 'Relógio BLE';
      final updatedText =
          text ?? _currentNotificationText ?? 'Conectado e recebendo mensagens';
      _currentNotificationTitle = updatedTitle;
      _currentNotificationText = updatedText;
      await FlutterForegroundTask.updateService(
        notificationTitle: updatedTitle,
        notificationText: updatedText,
      );
    } catch (e) {
      AppLogger.error('Erro ao atualizar notificação', e);
    }
  }

  /// Check if the service is running
  bool isRunning() => _isRunning;

  /// Get current device ID
  String? getCurrentDeviceId() => _currentDeviceId;

  /// Get current device name
  String? getCurrentDeviceName() => _currentDeviceName;

  /// Foreground task callback (runs in isolate)
  @pragma('vm:entry-point')
  static void _startCallback() {
    FlutterForegroundTask.setTaskHandler(BleForegroundTaskHandler());
  }
}

/// Task handler for the foreground service
class BleForegroundTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // Service started
  }

  @override
  Future<void> onRepeatEvent(DateTime timestamp) async {
    // Periodic event - keep service alive
    // No need to do anything, just keep the service running
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    // Service destroyed
  }

  @override
  void onNotificationButtonPressed(String id) {
    // Handle notification button press if needed
  }

  @override
  void onNotificationPressed() {
    // Handle notification press if needed
    FlutterForegroundTask.launchApp('/');
  }
}
