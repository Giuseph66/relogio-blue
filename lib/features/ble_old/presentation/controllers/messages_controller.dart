import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import '../../../../core/di/dependency_injection.dart';
import '../../../../core/background/ble_foreground_service.dart';
import '../../../../core/notifications/notification_service.dart';
import '../../../../core/notifications/message_notification_filter.dart';
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
  final BleForegroundServiceManager _foregroundService =
      BleForegroundServiceManager();
  final NotificationService _notificationService = NotificationService();
  final BleMessageRelayService _messageRelay = BleMessageRelayService();
  late final LoadSettings _loadSettings;

  final _messagesController = StreamController<List<BleMessage>>.broadcast();
  final _tickStatusController = StreamController<TickStatus>.broadcast();
  Stream<List<BleMessage>> get messages => _messagesController.stream;
  Stream<TickStatus> get tickStatus => _tickStatusController.stream;

  /// Whether the watch is currently considered online (sent a tick in the last 8s).
  bool get isWatchOnline => _lastTickStatus.online;

  /// Whether a BLE device is currently connected (lower-level check, no tick required).
  bool get isWatchConnected => _di.bleRepository.getConnectedDeviceId() != null;

  List<BleMessage> _messages = [];
  StreamSubscription<List<int>>? _subscribeSubscription;
  int _messageIdCounter = 0;
  Timer? _tickTimer;
  TickStatus _lastTickStatus = const TickStatus();
  AppLifecycleState? _appLifecycleState;

  // ── BLE fragment reassembly ──────────────────────────────────────────────
  // BLE notifications are limited to ATT_MTU-3 bytes per packet (often 20 bytes).
  // Protocol messages like QANS can exceed this limit and arrive fragmented.
  // We buffer incoming data and flush it after a short idle gap.
  String _rxBuffer = '';
  Timer? _rxFlushTimer;
  // Short idle gap for generic messages; longer for incomplete protocol frames.
  static const Duration _rxBufferTimeout = Duration(milliseconds: 300);
  static const Duration _rxProtocolTimeout = Duration(milliseconds: 1500);

  /// Start listening to messages
  void _startListening() {
    _di.subscribeToMessages().then((stream) {
      _subscribeSubscription = stream.listen(_onRawBleData, onError: (_) {});
    });
  }

  /// Handles a single BLE notification packet.
  ///
  /// Tick messages are processed immediately (they are always short).
  /// All other data is accumulated in [_rxBuffer] and processed once
  /// [_rxBufferTimeout] elapses without new data — this reassembles
  /// QANS/QERR protocol messages that span multiple 20-byte BLE packets.
  void _onRawBleData(List<int> data) {
    String content;
    try {
      content = utf8.decode(data);
    } catch (_) {
      // Non-UTF8: keep printable ASCII chars only
      if (_tryUpdateTickFromData(data)) return;
      content = data
          .where((b) => b >= 32 && b <= 126)
          .map((b) => String.fromCharCode(b))
          .join();
    }

    // Tick messages are short (≤8 bytes) and always arrive in a single packet.
    // Process them immediately so the online/offline state stays accurate.
    if (_tryUpdateTickFromText(content)) return;

    // Accumulate content.
    _rxBuffer += content;
    _rxFlushTimer?.cancel();

    // If the buffer now forms a complete protocol message (e.g. QANS with all 3
    // pipe-separated parts), flush immediately — no need to wait.
    if (_isCompleteProtocolMessage(_rxBuffer)) {
      _flushRxBuffer();
      return;
    }

    // If we have the start of a protocol message but it's still incomplete,
    // use a longer timeout to give the remaining fragment time to arrive.
    final timeout =
        _rxBuffer.startsWith('QANS|') || _rxBuffer.startsWith('QERR|')
        ? _rxProtocolTimeout
        : _rxBufferTimeout;
    _rxFlushTimer = Timer(timeout, _flushRxBuffer);
  }

  /// Flushes the reassembly buffer as a single complete message.
  void _flushRxBuffer() {
    // Remove null bytes and other control chars that ESP32 uses to pad
    // BLE notifications to the full 20-byte ATT payload.
    final assembled = _rxBuffer
        .replaceAll('\x00', '')
        .replaceAll(RegExp(r'[\x01-\x08\x0B\x0C\x0E-\x1F\x7F]'), '')
        .trim();
    _rxBuffer = '';
    if (assembled.isEmpty) return;

    final message = model.BleMessageModel(
      id: 'msg_${_messageIdCounter++}',
      content: assembled,
      direction: MessageDirection.rx,
      timestamp: DateTime.now(),
    );
    _addMessage(message);
    _handleRxMessage(assembled);
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

    final mainBleConnected = _di.bleRepository.getConnectedDeviceId() != null;
    if (!mainBleConnected && _foregroundService.isRunning()) {
      final forwarded = await _foregroundService.sendCommand(content);
      if (forwarded) {
        return true;
      }
    }

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
    _rxFlushTimer?.cancel();
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
    final match = RegExp(
      r'\btick\s*:\s*(\d+)\b',
      caseSensitive: false,
    ).firstMatch(normalized);
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

  /// Returns true if the buffer already contains a complete QANS/QERR message
  /// (exactly 3 pipe-separated, non-empty parts).
  bool _isCompleteProtocolMessage(String buffer) {
    if (!buffer.startsWith('QANS|') && !buffer.startsWith('QERR|'))
      return false;
    final parts = buffer.split('|');
    return parts.length >= 3 && parts[1].isNotEmpty && parts[2].isNotEmpty;
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

      final isOnline =
          DateTime.now().difference(lastSeen) <= const Duration(seconds: 8);
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
      final isInBackground =
          lifecycleState == AppLifecycleState.paused ||
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

      final shouldShowRxNotification = MessageNotificationFilter.shouldNotify(
        content: content,
        notificationsEnabled: settings.backgroundNotifyOnRx,
        filterEnabled: settings.backgroundNotifyFilterEnabled,
        allowedPatterns: settings.backgroundNotifyAllowedPatterns,
      );

      // Update foreground service notification
      if (_foregroundService.isRunning()) {
        final preview = content.length > 50
            ? '${content.substring(0, 47)}...'
            : content;
        await _foregroundService.updateNotification(
          text: 'Última mensagem: $preview',
        );
      }

      // Show local notification when in background or explicitly enabled
      if (shouldShowRxNotification) {
        await _notificationService.showRxNotification(content);
      }
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

  const TickStatus({this.tickNumber, this.lastSeen, this.online = false});

  TickStatus copyWith({int? tickNumber, DateTime? lastSeen, bool? online}) {
    return TickStatus(
      tickNumber: tickNumber ?? this.tickNumber,
      lastSeen: lastSeen ?? this.lastSeen,
      online: online ?? this.online,
    );
  }
}
