import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import '../../../../core/di/dependency_injection.dart';
import '../../../../core/background/ble_foreground_service.dart';
import '../../../../core/notifications/notification_service.dart';
import '../../../../core/network/ble_message_relay.dart';
import '../../domain/entities/ble_message.dart';
import '../../domain/usecases/load_settings.dart';
import '../../data/models/ble_message_model.dart' as model;

/// Controller for BLE messages
class MessagesController {
  static final MessagesController _instance = MessagesController._internal();
  factory MessagesController() => _instance;
  MessagesController._internal() {
    _loadSettings = LoadSettings(_di.preferencesRepository);
    _startListening();
    _startTickMonitor();
  }

  final DependencyInjection _di = DependencyInjection();
  final BleForegroundServiceManager _foregroundService = BleForegroundServiceManager();
  final NotificationService _notificationService = NotificationService();
  final BleMessageRelayService _messageRelay = BleMessageRelayService();
  late final LoadSettings _loadSettings;

  final _messagesController = StreamController<List<BleMessage>>.broadcast();
  final _tickStatusController = StreamController<TickStatus>.broadcast();
  Stream<List<BleMessage>> get messages => _messagesController.stream;
  Stream<TickStatus> get tickStatus => _tickStatusController.stream;

  List<BleMessage> _messages = [];
  StreamSubscription<List<int>>? _subscribeSubscription;
  int _messageIdCounter = 0;
  Timer? _tickTimer;
  TickStatus _lastTickStatus = const TickStatus();
  AppLifecycleState? _appLifecycleState;

  /// Start listening to messages
  void _startListening() {
    _di.subscribeToMessages().then((stream) {
      _subscribeSubscription = stream.listen(
      (data) {
        try {
          // First, try to decode as UTF-8
          final content = utf8.decode(data);
          
          // Check if it's a tick message - if so, update status and don't add to messages
          if (_tryUpdateTickFromText(content)) {
            return; // Tick message processed, don't add to message list
          }
          
          // Not a tick message, add it to the message list
          final message = model.BleMessageModel(
            id: 'msg_${_messageIdCounter++}',
            content: content,
            direction: MessageDirection.rx,
            timestamp: DateTime.now(),
          );
          _addMessage(message);
          // Handle background notifications
          _handleRxMessage(content);
        } catch (e) {
          // If not UTF-8, try to extract tick from raw data
          if (_tryUpdateTickFromData(data)) {
            return; // Tick message processed, don't add to message list
          }
          
          // Not a tick message, show as hex
          final hex = data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
          final message = model.BleMessageModel(
            id: 'msg_${_messageIdCounter++}',
            content: 'HEX: $hex',
            direction: MessageDirection.rx,
            timestamp: DateTime.now(),
          );
          _addMessage(message);
          // Handle background notifications
          _handleRxMessage('HEX: $hex');
        }
      },
      onError: (error) {
        // Handle error
      },
    );
    });
  }

  /// Add message to list
  void _addMessage(BleMessage message) {
    _messages.add(message);
    _messagesController.add(List.unmodifiable(_messages));
  }

  /// Send message
  Future<bool> sendMessage(String content) async {
    if (content.trim().isEmpty) return false;

    final message = model.BleMessageModel(
      id: 'msg_${_messageIdCounter++}',
      content: content,
      direction: MessageDirection.tx,
      timestamp: DateTime.now(),
    );
    _addMessage(message);

    final result = await _di.sendBleMessage(content);
    return result.isSuccess;
  }

  /// Simulate an RX message (used in mock mode)
  Future<void> simulateRxMessage({String? content}) async {
    final trimmed = content?.trim();
    final messageText = (trimmed == null || trimmed.isEmpty)
        ? 'Mock RX em ${DateTime.now().toIso8601String()}'
        : trimmed;

    final message = model.BleMessageModel(
      id: 'msg_${_messageIdCounter++}',
      content: messageText,
      direction: MessageDirection.rx,
      timestamp: DateTime.now(),
    );
    _addMessage(message);
    await _handleRxMessage(messageText);
  }

  /// Clear messages
  void clearMessages() {
    _messages.clear();
    _messagesController.add([]);
  }

  /// Get last message
  BleMessage? getLastMessage() {
    if (_messages.isEmpty) return null;
    return _messages.last;
  }

  /// Dispose
  void dispose() {
    // Singleton: keep streams alive for the app lifetime.
  }

  bool _tryUpdateTickFromData(List<int> data) {
    if (data.isEmpty) {
      return false;
    }

    final buffer = StringBuffer();
    for (final byte in data) {
      if (byte >= 32 && byte <= 126) {
        buffer.writeCharCode(byte);
      }
    }

    if (buffer.isEmpty) {
      return false;
    }

    return _tryUpdateTickFromText(buffer.toString());
  }

  bool _tryUpdateTickFromText(String content) {
    final normalized = _normalizeText(content);
    final match = RegExp(r'\btick\s*:\s*(\d+)\b', caseSensitive: false)
        .firstMatch(normalized);
    if (match == null) {
      return false;
    }

    final tickNumber = int.tryParse(match.group(1) ?? '');
    _updateTickStatus(tickNumber);
    return true;
  }

  void _updateTickStatus(int? tickNumber) {
    _lastTickStatus = _lastTickStatus.copyWith(
      tickNumber: tickNumber,
      lastSeen: DateTime.now(),
      online: true,
    );
    _tickStatusController.add(_lastTickStatus);
  }

  String _normalizeText(String content) {
    return content.replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), ' ').trim();
  }

  void _startTickMonitor() {
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final lastSeen = _lastTickStatus.lastSeen;
      if (lastSeen == null) {
        if (_lastTickStatus.online) {
          _lastTickStatus = _lastTickStatus.copyWith(online: false);
          _tickStatusController.add(_lastTickStatus);
        }
        return;
      }

      final isOnline = DateTime.now().difference(lastSeen) <= const Duration(seconds: 8);
      if (isOnline != _lastTickStatus.online) {
        _lastTickStatus = _lastTickStatus.copyWith(online: isOnline);
        _tickStatusController.add(_lastTickStatus);
      }
    });
  }

  /// Handle RX message - update foreground service notification and show local notification if needed
  Future<void> _handleRxMessage(String content) async {
    try {
      // Load settings to check if notifications are enabled
      final settingsResult = await _loadSettings();
      final settings = settingsResult.valueOrNull;
      
      if (settings == null) return;

      final lifecycleState =
          _appLifecycleState ?? WidgetsBinding.instance.lifecycleState;
      final isInBackground = lifecycleState == AppLifecycleState.paused ||
          lifecycleState == AppLifecycleState.inactive ||
          lifecycleState == AppLifecycleState.hidden;
      final shouldNotify = isInBackground || settings.backgroundNotifyOnRx;

      final serverUrl = settings.serverApiUrl.trim();
      if (serverUrl.isNotEmpty) {
        await _messageRelay.sendRxMessage(
          baseUrl: serverUrl,
          content: content,
          deviceId: _di.bleRepository.getConnectedDeviceId(),
        );
      }

      if (!shouldNotify) return;

      // Update foreground service notification
      if (_foregroundService.isRunning()) {
        final preview = content.length > 50 ? '${content.substring(0, 47)}...' : content;
        await _foregroundService.updateNotification(
          text: 'Última mensagem: $preview',
        );
      }

      // Show local notification when in background or explicitly enabled
      await _notificationService.showRxNotification(content);
    } catch (e) {
      // Silently fail - notifications are optional
    }
  }

  /// Update app lifecycle state (called from DashboardPage)
  void updateAppLifecycleState(AppLifecycleState state) {
    _appLifecycleState = state;
  }
}

class TickStatus {
  final int? tickNumber;
  final DateTime? lastSeen;
  final bool online;

  const TickStatus({
    this.tickNumber,
    this.lastSeen,
    this.online = false,
  });

  TickStatus copyWith({
    int? tickNumber,
    DateTime? lastSeen,
    bool? online,
  }) {
    return TickStatus(
      tickNumber: tickNumber ?? this.tickNumber,
      lastSeen: lastSeen ?? this.lastSeen,
      online: online ?? this.online,
    );
  }
}
