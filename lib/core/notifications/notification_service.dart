import 'dart:io' show Platform;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../logger/app_logger.dart';

/// Service for managing local notifications
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// Initialize the notification service
  Future<void> init() async {
    if (_initialized) return;

    try {
      // Android initialization settings
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      
      // iOS initialization settings
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: false,
      );

      // Initialization settings
      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      // Initialize plugin
      final initialized = await _notifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      if (initialized == true) {
        // Create notification channel for Android
        if (Platform.isAndroid) {
          await _createNotificationChannel();
        }
        _initialized = true;
        AppLogger.info('NotificationService inicializado');
      } else {
        AppLogger.warning('NotificationService não foi inicializado');
      }
    } catch (e) {
      AppLogger.error('Erro ao inicializar NotificationService', e);
    }
  }

  /// Create Android notification channel
  Future<void> _createNotificationChannel() async {
    const channel = AndroidNotificationChannel(
      'ble_messages_channel',
      'Mensagens BLE',
      description: 'Notificações de mensagens recebidas do relógio',
      importance: Importance.defaultImportance,
      playSound: false,
      enableVibration: false,
    );

    await _notifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  /// Show notification when a message is received
  Future<void> showRxNotification(String preview) async {
    if (!_initialized) {
      await init();
    }

    try {
      // Truncate preview if too long
      final displayText = preview.length > 100 
          ? '${preview.substring(0, 97)}...' 
          : preview;

      const androidDetails = AndroidNotificationDetails(
        'ble_messages_channel',
        'Mensagens BLE',
        channelDescription: 'Notificações de mensagens recebidas do relógio',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        showWhen: true,
        playSound: false,
        enableVibration: false,
        icon: '@mipmap/ic_launcher',
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: false,
      );

      const details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _notifications.show(
        DateTime.now().millisecondsSinceEpoch % 100000,
        'Mensagem recebida do relógio',
        displayText,
        details,
      );

      AppLogger.debug('Notificação local exibida: $displayText');
    } catch (e) {
      AppLogger.error('Erro ao exibir notificação local', e);
    }
  }

  /// Handle notification tap
  void _onNotificationTapped(NotificationResponse response) {
    AppLogger.debug('Notificação tocada: ${response.id}');
    // Could navigate to messages page here if needed
  }

  /// Cancel all notifications
  Future<void> cancelAll() async {
    if (!_initialized) return;
    await _notifications.cancelAll();
  }

  /// Check if service is initialized
  bool get isInitialized => _initialized;
}

