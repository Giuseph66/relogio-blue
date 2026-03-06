import '../../domain/entities/ble_message.dart';

/// Model for BLE Message (extends entity)
class BleMessageModel extends BleMessage {
  const BleMessageModel({
    required super.id,
    required super.content,
    required super.direction,
    required super.timestamp,
  });

  factory BleMessageModel.fromJson(Map<String, dynamic> json) {
    return BleMessageModel(
      id: json['id'] as String,
      content: json['content'] as String,
      direction: MessageDirection.values.firstWhere(
        (e) => e.name == json['direction'],
        orElse: () => MessageDirection.rx,
      ),
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'content': content,
      'direction': direction.name,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}

