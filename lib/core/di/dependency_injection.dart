import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import '../../../features/ble/data/datasources/reactive_ble_datasource.dart';
import '../../../features/ble/data/datasources/preferences_datasource.dart';
import '../../../features/ble/data/repositories/ble_repository_impl.dart';
import '../../../features/ble/data/repositories/preferences_repository_impl.dart';
import '../../../features/ble/domain/repositories/ble_repository.dart';
import '../../../features/ble/domain/repositories/preferences_repository.dart';
import '../../../features/ble/domain/usecases/start_ble_scan.dart';
import '../../../features/ble/domain/usecases/stop_ble_scan.dart';
import '../../../features/ble/domain/usecases/connect_to_device.dart';
import '../../../features/ble/domain/usecases/disconnect_device.dart';
import '../../../features/ble/domain/usecases/send_ble_message.dart';
import '../../../features/ble/domain/usecases/subscribe_to_messages.dart';
import '../../../features/ble/domain/usecases/load_settings.dart';
import '../../../features/ble/domain/usecases/save_settings.dart';
import '../../../features/ble/domain/usecases/auto_reconnect_if_enabled.dart';
import '../../../features/ble/data/models/ble_settings_model.dart';
import '../background/ble_foreground_service.dart';
import '../notifications/notification_service.dart';

/// Simple dependency injection container
class DependencyInjection {
  static final DependencyInjection _instance = DependencyInjection._internal();
  factory DependencyInjection() => _instance;
  DependencyInjection._internal();

  // Core
  late final FlutterReactiveBle _ble;
  late final ReactiveBleDataSource _bleDataSource;
  late final PreferencesDataSource _preferencesDataSource;

  // Repositories
  late final BleRepository _bleRepository;
  late final PreferencesRepository _preferencesRepository;

  // Use cases
  late final StartBleScan _startBleScan;
  late final StopBleScan _stopBleScan;
  late final ConnectToDevice _connectToDevice;
  late final DisconnectDevice _disconnectDevice;
  late final SendBleMessage _sendBleMessage;
  late final SubscribeToMessages _subscribeToMessages;
  late final LoadSettings _loadSettings;
  late final SaveSettings _saveSettings;
  late final AutoReconnectIfEnabled _autoReconnectIfEnabled;

  bool _initialized = false;

  /// Initialize dependencies
  Future<void> initialize({bool mockMode = false}) async {
    if (_initialized) return;

    // Preferences
    _preferencesDataSource = PreferencesDataSource();
    _preferencesRepository = PreferencesRepositoryImpl(_preferencesDataSource);
    _loadSettings = LoadSettings(_preferencesRepository);
    _saveSettings = SaveSettings(_preferencesRepository);

    // Load settings before wiring BLE to respect stored mock mode
    final settingsResult = await _loadSettings();
    final settings = settingsResult.valueOrNull ?? BleSettingsModel.defaults();
    final effectiveMockMode = settings.enableMockMode || mockMode;

    // Core
    _ble = FlutterReactiveBle();
    _bleDataSource = ReactiveBleDataSource(
      ble: _ble,
      mockMode: effectiveMockMode,
    );

    // Repositories
    _bleRepository = BleRepositoryImpl(_bleDataSource);

    // Use cases
    _startBleScan = StartBleScan(_bleRepository);
    _stopBleScan = StopBleScan(_bleRepository);
    _connectToDevice = ConnectToDevice(_bleRepository, _preferencesRepository);
    _disconnectDevice = DisconnectDevice(_bleRepository);
    _sendBleMessage = SendBleMessage(_bleRepository, _preferencesRepository);
    _subscribeToMessages = SubscribeToMessages(_bleRepository, _preferencesRepository);
    _autoReconnectIfEnabled = AutoReconnectIfEnabled(
      _bleRepository,
      _preferencesRepository,
      _connectToDevice,
    );

    _initialized = true;
  }

  // Getters
  StartBleScan get startBleScan => _startBleScan;
  StopBleScan get stopBleScan => _stopBleScan;
  ConnectToDevice get connectToDevice => _connectToDevice;
  DisconnectDevice get disconnectDevice => _disconnectDevice;
  SendBleMessage get sendBleMessage => _sendBleMessage;
  SubscribeToMessages get subscribeToMessages => _subscribeToMessages;
  LoadSettings get loadSettings => _loadSettings;
  SaveSettings get saveSettings => _saveSettings;
  AutoReconnectIfEnabled get autoReconnectIfEnabled => _autoReconnectIfEnabled;
  BleRepository get bleRepository => _bleRepository;
  PreferencesRepository get preferencesRepository => _preferencesRepository;
  
  // Background services (singletons, can be accessed directly or via DI)
  BleForegroundServiceManager get foregroundService => BleForegroundServiceManager();
  NotificationService get notificationService => NotificationService();
}
