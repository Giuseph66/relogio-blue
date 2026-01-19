/// BLE Message entity
enum MessageDirection {
  tx, // Transmitted (sent)
  rx, // Received
}

class BleMessage {
  final String id;
  final String content;
  final MessageDirection direction;
  final DateTime timestamp;

  const BleMessage({
    required this.id,
    required this.content,
    required this.direction,
    required this.timestamp,
  });

  bool get isSent => direction == MessageDirection.tx;
  bool get isReceived => direction == MessageDirection.rx;

  @override
  String toString() => 
      'BleMessage(${direction.name.toUpperCase()}: $content at ${timestamp.toIso8601String()})';
}

