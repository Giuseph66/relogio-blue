import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import '../../../features/ble_old/data/datasources/reactive_ble_datasource.dart';
import '../../../features/ble_old/data/datasources/preferences_datasource.dart';
import '../../../features/ble_old/data/repositories/ble_repository_impl.dart';
import '../../../features/ble_old/data/repositories/preferences_repository_impl.dart';
import '../../../features/ble_old/domain/repositories/ble_repository.dart';
import '../../../features/ble_old/domain/repositories/preferences_repository.dart';
import '../../../features/ble_old/domain/usecases/start_ble_scan.dart';
import '../../../features/ble_old/domain/usecases/stop_ble_scan.dart';
import '../../../features/ble_old/domain/usecases/connect_to_device.dart';
import '../../../features/ble_old/domain/usecases/disconnect_device.dart';
import '../../../features/ble_old/domain/usecases/send_ble_message.dart';
import '../../../features/ble_old/domain/usecases/subscribe_to_messages.dart';
import '../../../features/ble_old/domain/usecases/load_settings.dart';
import '../../../features/ble_old/domain/usecases/save_settings.dart';
import '../../../features/ble_old/domain/usecases/auto_reconnect_if_enabled.dart';
import '../../../features/ble_old/data/models/ble_settings_model.dart';
import '../background/ble_foreground_service.dart';
import '../notifications/notification_service.dart';
import '../../../features/maps_old/data/datasources/geolocator_datasource.dart';
import '../../../features/maps_old/data/datasources/geocoding_datasource.dart';
import '../../../features/maps_old/data/repositories/location_repository_impl.dart';
import '../../../features/maps_old/domain/repositories/location_repository.dart';
import '../../../features/maps_old/domain/usecases/get_current_location.dart';
import '../../../features/maps_old/domain/usecases/reverse_geocode.dart';
import '../../../features/maps_old/presentation/controllers/map_controller.dart';
import '../../../features/location_tracker/data/repositories/location_tracker_repository.dart';
import '../../../features/location_tracker/presentation/controllers/location_tracker_controller.dart';
import '../network/connectivity_service.dart';
import '../sync/sync_service.dart';
import '../../../features/history/data/datasources/watch_response_dao.dart';
import '../../../features/history/data/repositories/watch_response_repository.dart';
import '../../../features/location_tracker/presentation/controllers/visit_question_orchestrator.dart';
import '../../../features/ble_old/presentation/controllers/messages_controller.dart';
import '../geofence/geofence_service.dart';

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
  late final LocationRepository _locationRepository;

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
  
  // Maps use cases
  late final GetCurrentLocation _getCurrentLocation;
  late final ReverseGeocode _reverseGeocode;
  
  // Maps controller
  late final MapController _mapController;

  bool _initialized = false;

  late final LocationTrackerRepository _locationTrackerRepository;
  late final LocationTrackerController _locationTrackerController;

  // History / sync
  late final WatchResponseDao _watchResponseDao;
  late final WatchResponseRepository _watchResponseRepository;
  late final ConnectivityService _connectivityService;
  late final SyncService _syncService;
  late final VisitQuestionOrchestrator _visitQuestionOrchestrator;

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

    // Maps dependencies
    final geolocatorDataSource = GeolocatorDataSource();
    final geocodingDataSource = GeocodingDataSource();
    _locationRepository = LocationRepositoryImpl(
      geolocatorDataSource,
      geocodingDataSource,
    );
    _getCurrentLocation = GetCurrentLocation(_locationRepository);
    _reverseGeocode = ReverseGeocode(_locationRepository);
    _mapController = MapController(
      _getCurrentLocation,
      _reverseGeocode,
      _locationRepository,
    );

    _locationTrackerRepository = LocationTrackerRepository();
    _locationTrackerController = LocationTrackerController(
      repository: _locationTrackerRepository,
    );
    await _locationTrackerController.loadData();

    // History / sync
    _watchResponseDao = WatchResponseDao();
    _watchResponseRepository = WatchResponseRepository(dao: _watchResponseDao);
    _connectivityService = ConnectivityService();
    _syncService = SyncService(
      repository: _watchResponseRepository,
      connectivity: _connectivityService,
      serverUrlProvider: () => settings.serverApiUrl,
    );

    _visitQuestionOrchestrator = VisitQuestionOrchestrator(
      responseRepository: _watchResponseRepository,
      messagesController: MessagesController(),
    );

    // Start geofence background service
    GeofenceService().init(
      getLocation: _getCurrentLocation,
      tracker: _locationTrackerController,
      orchestrator: _visitQuestionOrchestrator,
    );
    GeofenceService().start();

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
  
  LocationRepository get locationRepository => _locationRepository;
  GetCurrentLocation get getCurrentLocation => _getCurrentLocation;
  ReverseGeocode get reverseGeocode => _reverseGeocode;
  MapController get mapController => _mapController;
  LocationTrackerRepository get locationTrackerRepository => _locationTrackerRepository;
  LocationTrackerController get locationTrackerController => _locationTrackerController;
  
  // Background services (singletons, can be accessed directly or via DI)
  BleForegroundServiceManager get foregroundService => BleForegroundServiceManager();
  NotificationService get notificationService => NotificationService();

  // History / sync
  WatchResponseDao get watchResponseDao => _watchResponseDao;
  WatchResponseRepository get watchResponseRepository => _watchResponseRepository;
  ConnectivityService get connectivityService => _connectivityService;
  SyncService get syncService => _syncService;
  VisitQuestionOrchestrator get visitQuestionOrchestrator => _visitQuestionOrchestrator;
  GeofenceService get geofenceService => GeofenceService();
}
