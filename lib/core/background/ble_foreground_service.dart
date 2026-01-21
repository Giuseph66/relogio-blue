import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import '../ble/ble_constants.dart';
import '../logger/app_logger.dart';
import '../network/ble_message_relay.dart';

const String _kDeviceIdKey = 'ble_device_id';
const String _kDeviceNameKey = 'ble_device_name';
const String _kServiceUuidKey = 'ble_service_uuid';
const String _kNotifyUuidKey = 'ble_notify_uuid';
const String _kServerApiUrlKey = 'ble_server_api_url';
const String _kKeepServiceWhenClosedKey = 'ble_keep_when_closed';

const Duration _kHeartbeatTimeout = Duration(seconds: 3);

/// Manager for BLE Foreground Service
/// Manages the foreground service that keeps BLE connection alive in background
class BleForegroundServiceManager {
  static final BleForegroundServiceManager _instance =
      BleForegroundServiceManager._internal();
  factory BleForegroundServiceManager() => _instance;
  BleForegroundServiceManager._internal();

  bool _initialized = false;
  bool _isRunning = false;
  String? _currentDeviceId;
  String? _currentDeviceName;
  String? _currentNotificationTitle;
  String? _currentNotificationText;
  Timer? _heartbeatTimer;

  /// Initialize the foreground task
  Future<void> init() async {
    if (_initialized) return;

    try {
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'ble_keep_alive_channel',
          channelName: 'BLE Keep Alive',
          channelDescription: 'Mantem a conexao BLE ativa em segundo plano',
          channelImportance: NotificationChannelImportance.LOW,
          priority: NotificationPriority.LOW,
        ),
        iosNotificationOptions: const IOSNotificationOptions(
          showNotification: true,
          playSound: false,
        ),
        foregroundTaskOptions: ForegroundTaskOptions(
          eventAction: ForegroundTaskEventAction.repeat(1000),
          allowWakeLock: true,
          allowWifiLock: true,
          autoRunOnBoot: false,
        ),
      );
      FlutterForegroundTask.initCommunicationPort();
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
    required String serviceUuid,
    required String notifyCharacteristicUuid,
    String? serverApiUrl,
    bool keepServiceWhenAppClosed = true,
  }) async {
    if (!_initialized) {
      await init();
    }

    await _persistConfig(
      deviceId: deviceId,
      deviceName: deviceName,
      serviceUuid: serviceUuid,
      notifyCharacteristicUuid: notifyCharacteristicUuid,
      serverApiUrl: serverApiUrl,
      keepServiceWhenAppClosed: keepServiceWhenAppClosed,
    );

    if (await FlutterForegroundTask.isRunningService) {
      _isRunning = true;
      _currentDeviceId = deviceId;
      _currentDeviceName = deviceName;
      _sendConfigToTask(
        deviceId: deviceId,
        deviceName: deviceName,
        serviceUuid: serviceUuid,
        notifyCharacteristicUuid: notifyCharacteristicUuid,
        serverApiUrl: serverApiUrl,
        keepServiceWhenAppClosed: keepServiceWhenAppClosed,
      );
      _startHeartbeat();
      return true;
    }

    if (_isRunning && _currentDeviceId == deviceId) {
      _sendConfigToTask(
        deviceId: deviceId,
        deviceName: deviceName,
        serviceUuid: serviceUuid,
        notifyCharacteristicUuid: notifyCharacteristicUuid,
        serverApiUrl: serverApiUrl,
        keepServiceWhenAppClosed: keepServiceWhenAppClosed,
      );
      _startHeartbeat();
      AppLogger.debug('Servico ja esta rodando para este dispositivo');
      return true;
    }

    try {
      final title = deviceName ?? 'Relogio BLE';
      final text = 'Conectado e recebendo mensagens';
      _currentNotificationTitle = title;
      _currentNotificationText = text;

      await FlutterForegroundTask.startService(
        notificationTitle: title,
        notificationText: text,
        callback: bleForegroundTaskStartCallback,
      );

      _isRunning = true;
      _currentDeviceId = deviceId;
      _currentDeviceName = deviceName;
      _sendConfigToTask(
        deviceId: deviceId,
        deviceName: deviceName,
        serviceUuid: serviceUuid,
        notifyCharacteristicUuid: notifyCharacteristicUuid,
        serverApiUrl: serverApiUrl,
        keepServiceWhenAppClosed: keepServiceWhenAppClosed,
      );
      _startHeartbeat();
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
      _stopHeartbeat();
      await _clearConfig();
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
          title ?? _currentNotificationTitle ?? _currentDeviceName ?? 'Relogio BLE';
      final updatedText =
          text ?? _currentNotificationText ?? 'Conectado e recebendo mensagens';
      _currentNotificationTitle = updatedTitle;
      _currentNotificationText = updatedText;
      await FlutterForegroundTask.updateService(
        notificationTitle: updatedTitle,
        notificationText: updatedText,
      );
    } catch (e) {
      AppLogger.error('Erro ao atualizar notificacao', e);
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
    bleForegroundTaskStartCallback();
  }

  Future<void> _persistConfig({
    required String deviceId,
    required String serviceUuid,
    required String notifyCharacteristicUuid,
    String? deviceName,
    String? serverApiUrl,
    bool keepServiceWhenAppClosed = true,
  }) async {
    await FlutterForegroundTask.saveData(key: _kDeviceIdKey, value: deviceId);
    await FlutterForegroundTask.saveData(key: _kServiceUuidKey, value: serviceUuid);
    await FlutterForegroundTask.saveData(
      key: _kNotifyUuidKey,
      value: notifyCharacteristicUuid,
    );
    await FlutterForegroundTask.saveData(
      key: _kDeviceNameKey,
      value: deviceName ?? '',
    );
    await FlutterForegroundTask.saveData(
      key: _kServerApiUrlKey,
      value: serverApiUrl ?? '',
    );
    await FlutterForegroundTask.saveData(
      key: _kKeepServiceWhenClosedKey,
      value: keepServiceWhenAppClosed,
    );
  }

  Future<void> _clearConfig() async {
    await FlutterForegroundTask.removeData(key: _kDeviceIdKey);
    await FlutterForegroundTask.removeData(key: _kServiceUuidKey);
    await FlutterForegroundTask.removeData(key: _kNotifyUuidKey);
    await FlutterForegroundTask.removeData(key: _kDeviceNameKey);
    await FlutterForegroundTask.removeData(key: _kServerApiUrlKey);
    await FlutterForegroundTask.removeData(key: _kKeepServiceWhenClosedKey);
  }

  void _sendConfigToTask({
    required String deviceId,
    required String serviceUuid,
    required String notifyCharacteristicUuid,
    String? deviceName,
    String? serverApiUrl,
    bool keepServiceWhenAppClosed = true,
  }) {
    FlutterForegroundTask.sendDataToTask({
      'type': 'config',
      'deviceId': deviceId,
      'deviceName': deviceName,
      'serviceUuid': serviceUuid,
      'notifyUuid': notifyCharacteristicUuid,
      'serverApiUrl': serverApiUrl,
      'keepWhenClosed': keepServiceWhenAppClosed,
    });
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    FlutterForegroundTask.sendDataToTask({'type': 'heartbeat'});
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      FlutterForegroundTask.sendDataToTask({'type': 'heartbeat'});
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }
}

/// Task handler for the foreground service
class BleForegroundTaskHandler extends TaskHandler {
  final FlutterReactiveBle _ble = FlutterReactiveBle();
  final BleMessageRelayService _relay = BleMessageRelayService();

  StreamSubscription<ConnectionStateUpdate>? _connectionSubscription;
  StreamSubscription<List<int>>? _notifySubscription;

  String? _deviceId;
  String? _deviceName;
  String? _serviceUuid;
  String? _notifyUuid;
  String? _serverApiUrl;
  bool _keepServiceWhenClosed = true;

  bool _isConnected = false;
  bool _isConnecting = false;
  int _reconnectAttempt = 0;
  DateTime? _nextConnectAt;
  DateTime? _lastHeartbeatAt;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await _loadConfigFromStorage();
    _lastHeartbeatAt = DateTime.now();
    AppLogger.info(
      'FG task start | device=$_deviceId keepClosed=$_keepServiceWhenClosed',
    );
    await _maybeMaintainConnection();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    AppLogger.debug('FG tick | appAlive=${_isAppAlive()} connected=$_isConnected');
    _maybeMaintainConnection();
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    AppLogger.info('FG task destroy');
    await _disconnect();
  }

  @override
  void onReceiveData(Object data) {
    if (data is Map) {
      final type = data['type'];
      if (type == 'heartbeat') {
        _lastHeartbeatAt = DateTime.now();
        AppLogger.debug('FG heartbeat');
        return;
      }
      if (type == 'config') {
        final deviceId = data['deviceId'] as String?;
        final serviceUuid = data['serviceUuid'] as String?;
        final notifyUuid = data['notifyUuid'] as String?;
        final deviceName = data['deviceName'] as String?;
        final serverApiUrl = data['serverApiUrl'] as String?;
        final keepWhenClosed = data['keepWhenClosed'] as bool? ?? true;
        final shouldReconnect = _deviceId != deviceId ||
            _serviceUuid != serviceUuid ||
            _notifyUuid != notifyUuid;

        _deviceId = deviceId;
        _serviceUuid = serviceUuid;
        _notifyUuid = notifyUuid;
        _deviceName = deviceName;
        _serverApiUrl = serverApiUrl;
        _keepServiceWhenClosed = keepWhenClosed;
        AppLogger.info(
          'FG config | device=$_deviceId service=$_serviceUuid notify=$_notifyUuid keepClosed=$_keepServiceWhenClosed',
        );

        if (shouldReconnect) {
          _scheduleReconnect(reset: true);
        }
        _maybeMaintainConnection();
      }
    }
  }

  @override
  void onNotificationButtonPressed(String id) {
    // Handle notification button press if needed
  }

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp('/');
  }

  Future<void> _loadConfigFromStorage() async {
    _deviceId = await FlutterForegroundTask.getData<String>(key: _kDeviceIdKey);
    _deviceName =
        await FlutterForegroundTask.getData<String>(key: _kDeviceNameKey);
    _serviceUuid =
        await FlutterForegroundTask.getData<String>(key: _kServiceUuidKey);
    _notifyUuid =
        await FlutterForegroundTask.getData<String>(key: _kNotifyUuidKey);
    _serverApiUrl =
        await FlutterForegroundTask.getData<String>(key: _kServerApiUrlKey);
    _keepServiceWhenClosed =
        await FlutterForegroundTask.getData<bool>(key: _kKeepServiceWhenClosedKey) ??
            true;
  }

  bool _isAppAlive() {
    final lastHeartbeat = _lastHeartbeatAt;
    if (lastHeartbeat == null) return false;
    return DateTime.now().difference(lastHeartbeat) <= _kHeartbeatTimeout;
  }

  Future<void> _maybeMaintainConnection() async {
    if (_deviceId == null || _deviceId!.isEmpty) return;
    if (_serviceUuid == null || _serviceUuid!.isEmpty) return;
    if (_notifyUuid == null || _notifyUuid!.isEmpty) return;

    if (!_keepServiceWhenClosed && !_isAppAlive()) {
      AppLogger.info('FG stop | keepClosed disabled and app not alive');
      await _disconnect();
      await FlutterForegroundTask.stopService();
      return;
    }

    if (_isAppAlive()) {
      if (_isConnected || _isConnecting) {
        AppLogger.info('FG release BLE | app alive');
        await _disconnect();
      }
      return;
    }

    if (_isConnected || _isConnecting) return;
    final nextConnectAt = _nextConnectAt;
    if (nextConnectAt != null && DateTime.now().isBefore(nextConnectAt)) return;

    AppLogger.info('FG connect attempt');
    _connect();
  }

  void _connect() {
    final deviceId = _deviceId;
    if (deviceId == null || deviceId.isEmpty) return;

    _updateStatusNotification('Reconectando...');
    _isConnecting = true;
    _connectionSubscription?.cancel();
    _connectionSubscription = _ble
        .connectToDevice(
          id: deviceId,
          connectionTimeout: BleConstants.connectionTimeout,
        )
        .listen(
      (update) {
        if (update.connectionState == DeviceConnectionState.connected) {
          _isConnected = true;
          _isConnecting = false;
          _reconnectAttempt = 0;
          _nextConnectAt = null;
          _subscribeToNotifications();
          _updateStatusNotification('Conectado em segundo plano');
          AppLogger.info('FG connected');
        } else if (update.connectionState == DeviceConnectionState.disconnected) {
          _isConnected = false;
          _isConnecting = false;
          _scheduleReconnect();
          AppLogger.info('FG disconnected');
        }
      },
      onError: (error) {
        _isConnected = false;
        _isConnecting = false;
        _scheduleReconnect();
        AppLogger.warning('FG connect error: $error');
      },
    );
  }

  void _subscribeToNotifications() {
    final deviceId = _deviceId;
    final serviceUuid = _serviceUuid;
    final notifyUuid = _notifyUuid;
    if (deviceId == null || serviceUuid == null || notifyUuid == null) return;

    _notifySubscription?.cancel();
    final characteristic = QualifiedCharacteristic(
      serviceId: Uuid.parse(serviceUuid),
      characteristicId: Uuid.parse(notifyUuid),
      deviceId: deviceId,
    );

    _notifySubscription = _ble.subscribeToCharacteristic(characteristic).listen(
      (data) {
        if (data.isEmpty) return;
        final content = _decodeMessage(data);
        _handleIncomingMessage(content);
      },
      onError: (error) {
        AppLogger.warning('Erro ao receber notificacao BLE: $error');
      },
    );
    AppLogger.info('FG subscribed to notify');
  }

  void _handleIncomingMessage(String content) {
    AppLogger.debug('FG RX: $content');
    final preview = content.length > 50 ? '${content.substring(0, 47)}...' : content;
    FlutterForegroundTask.updateService(
      notificationTitle: _deviceName ?? 'Relogio BLE',
      notificationText: 'Ultima mensagem: $preview',
    );

    final serverUrl = _serverApiUrl?.trim() ?? '';
    if (serverUrl.isNotEmpty) {
      _relay.sendRxMessage(
        baseUrl: serverUrl,
        content: content,
        deviceId: _deviceId,
        deviceName: _deviceName,
      );
    }
  }

  String _decodeMessage(List<int> data) {
    try {
      return utf8.decode(data);
    } catch (_) {
      final hex = data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
      return 'HEX: $hex';
    }
  }

  Future<void> _disconnect() async {
    _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _notifySubscription?.cancel();
    _notifySubscription = null;
    _isConnected = false;
    _isConnecting = false;
    AppLogger.info('FG disconnect cleanup');
  }

  void _scheduleReconnect({bool reset = false}) {
    _notifySubscription?.cancel();
    _notifySubscription = null;

    if (reset) {
      _reconnectAttempt = 0;
    } else if (_reconnectAttempt < 5) {
      _reconnectAttempt += 1;
    }

    final delaySeconds = _reconnectAttempt <= 1
        ? 2
        : _reconnectAttempt == 2
            ? 4
            : _reconnectAttempt == 3
                ? 6
                : 8;

    _nextConnectAt = DateTime.now().add(Duration(seconds: delaySeconds));
    _isConnected = false;
    _isConnecting = false;
    AppLogger.info('FG reconnect scheduled in ${delaySeconds}s');
  }

  void _updateStatusNotification(String text) {
    FlutterForegroundTask.updateService(
      notificationTitle: _deviceName ?? 'Relogio BLE',
      notificationText: text,
    );
  }

}

/// Foreground task entrypoint (top-level).
@pragma('vm:entry-point')
void bleForegroundTaskStartCallback() {
  FlutterForegroundTask.setTaskHandler(BleForegroundTaskHandler());
}
