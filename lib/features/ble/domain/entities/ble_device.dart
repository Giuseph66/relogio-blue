/// BLE Device entity
class BleDevice {
  final String id;
  final String name;
  final int? rssi;
  final bool isPreferred;

  const BleDevice({
    required this.id,
    required this.name,
    this.rssi,
    this.isPreferred = false,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BleDevice &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'BleDevice(id: $id, name: $name, rssi: $rssi)';
}

