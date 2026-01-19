import 'dart:async';
import 'dart:convert';
import '../../../../core/di/dependency_injection.dart';
import '../../domain/entities/ble_message.dart';
import '../../domain/usecases/send_ble_message.dart';
import '../../domain/usecases/subscribe_to_messages.dart';
import '../../data/models/ble_message_model.dart' as model;

/// Controller for BLE messages
class MessagesController {
  final DependencyInjection _di = DependencyInjection();

  final _messagesController = StreamController<List<BleMessage>>.broadcast();
  final _tickStatusController = StreamController<TickStatus>.broadcast();
  Stream<List<BleMessage>> get messages => _messagesController.stream;
  Stream<TickStatus> get tickStatus => _tickStatusController.stream;

  List<BleMessage> _messages = [];
  StreamSubscription<List<int>>? _subscribeSubscription;
  int _messageIdCounter = 0;
  Timer? _tickTimer;
  TickStatus _lastTickStatus = const TickStatus();

  MessagesController() {
    _startListening();
    _startTickMonitor();
  }

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
    _subscribeSubscription?.cancel();
    _tickTimer?.cancel();
    _messagesController.close();
    _tickStatusController.close();
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
