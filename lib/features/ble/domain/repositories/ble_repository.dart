import 'dart:async';
import '../../../../core/result/result.dart';
import '../../../../core/ble/ble_errors.dart';
import '../entities/ble_device.dart';
import '../entities/ble_settings.dart';

/// Connection state for BLE devices
enum ConnectionState {
  disconnected,
  connecting,
  connected,
  disconnecting,
}

/// Interface for BLE operations
abstract class BleRepository {
  /// Scan for BLE devices
  /// Returns a stream of discovered devices
  Stream<BleDevice> scanForDevices({
    String? filterByName,
    Duration? scanDuration,
  });

  /// Stop scanning
  Future<void> stopScan();

  /// Connect to a device
  /// Returns a stream of connection states
  Stream<ConnectionState> connectToDevice(
    String deviceId,
    BleSettings settings,
  );

  /// Disconnect from current device
  Future<Result<void, BleError>> disconnectDevice();

  /// Write data to a characteristic
  Future<Result<void, BleError>> writeCharacteristic(
    String serviceUuid,
    String characteristicUuid,
    List<int> data,
  );

  /// Subscribe to notifications from a characteristic
  /// Returns a stream of received data
  Stream<List<int>> subscribeToCharacteristic(
    String serviceUuid,
    String characteristicUuid,
  );

  /// Get current connection state
  Stream<ConnectionState> getConnectionState();

  /// Check if Bluetooth is enabled
  Future<bool> isBluetoothEnabled();

  /// Listen for Bluetooth status changes
  Stream<bool> getBluetoothStatusStream();

  /// Get currently connected device ID (if any)
  String? getConnectedDeviceId();
}
