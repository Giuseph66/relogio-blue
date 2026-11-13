import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:latlong2/latlong.dart';
import '../../../../core/widgets/app_drawer.dart';
import '../../../../core/widgets/app_map.dart';
import '../../../../core/di/dependency_injection.dart';
import '../../../../core/logger/app_logger.dart';
import '../controllers/map_controller.dart';
import '../widgets/location_card.dart';
import '../widgets/permission_state_view.dart';
import '../../domain/entities/map_location.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  late final MapController _mapController;
  final fm.MapController _osmController = fm.MapController();
  MapLocation? _currentLocation;
  String? _error;
  bool _isLoading = false;
  bool _permissionGranted = false;
  bool _serviceEnabled = false;
  bool _mapCreated = false;
  bool _showLocationCard = true;
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  // Default location (São Paulo, Brasil) - usado quando não há localização
  static const LatLng _defaultLocation = AppMap.defaultCenter;
  static const double _defaultZoom = AppMap.defaultZoom;

  @override
  void initState() {
    super.initState();
    // Get MapController from DI
    _mapController = DependencyInjection().mapController;
    _setupListeners();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mapController.fetchMyLocation();
    });
  }

  void _setupListeners() {
    _subscriptions.add(_mapController.isLoading.listen((loading) {
      if (mounted) {
        setState(() => _isLoading = loading);
      }
    }));

    _subscriptions.add(_mapController.location.listen((location) {
      if (mounted && location != null) {
        setState(() {
          _currentLocation = location;
          _error = null;
          _showLocationCard = true;
        });
        _moveCameraToLocation(location);
      }
    }));

    _subscriptions.add(_mapController.error.listen((error) {
      if (mounted) {
        setState(() => _error = error);
      }
    }));

    _subscriptions.add(_mapController.permissionGranted.listen((granted) {
      if (mounted) {
        setState(() => _permissionGranted = granted);
      }
    }));

    _subscriptions.add(_mapController.serviceEnabled.listen((enabled) {
      if (mounted) {
        setState(() => _serviceEnabled = enabled);
      }
    }));
  }

  void _moveCameraToLocation(MapLocation location) {
    if (!_mapCreated) return; // controller only usable after onMapReady
    _osmController.move(
      LatLng(location.latitude, location.longitude),
      _defaultZoom,
    );
  }

  Future<void> _onMyLocationPressed() async {
    if (mounted) {
      setState(() => _showLocationCard = true);
    }
    await _mapController.fetchMyLocation();
  }

  Future<void> _onRequestPermission() async {
    final granted = await _mapController.requestPermission();
    if (granted) {
      await _mapController.fetchMyLocation();
    }
  }

  Future<void> _onOpenSettings() async {
    await _mapController.fetchMyLocation();
  }

  @override
  void dispose() {
    _osmController.dispose();
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final initialLocation = _currentLocation != null
        ? LatLng(_currentLocation!.latitude, _currentLocation!.longitude)
        : _defaultLocation;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mapa'),
      ),
      drawer: const AppDrawer(),
      body: Stack(
        children: [
          fm.FlutterMap(
            mapController: _osmController,
            options: fm.MapOptions(
              initialCenter: initialLocation,
              initialZoom: _defaultZoom,
              minZoom: 3,
              maxZoom: 19,
              backgroundColor: const Color(0xFF0A0A0A),
              onMapReady: () {
                _mapCreated = true;
                AppLogger.info('Mapa (OpenStreetMap) criado com sucesso');
                if (_currentLocation != null) {
                  _moveCameraToLocation(_currentLocation!);
                }
                if (mounted) setState(() {});
              },
            ),
            children: [
              AppMap.tileLayer(context),
              fm.MarkerLayer(markers: _buildMarkers()),
              AppMap.attribution(),
            ],
          ),
          if (_error != null && _currentLocation == null)
            PermissionStateView(
              errorType: _error!,
              onRequestPermission: _onRequestPermission,
              onOpenSettings: _onOpenSettings,
            ),
          if (!_mapCreated)
            const Center(
              child: CircularProgressIndicator(),
            ),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(),
            ),
          if (_currentLocation != null && _showLocationCard)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: LocationCard(
                location: _currentLocation!,
                onClose: () {
                  if (mounted) {
                    setState(() => _showLocationCard = false);
                  }
                },
              ),
            ),
          Positioned(
            bottom: _currentLocation != null ? 200 : 16,
            right: 16,
            child: FloatingActionButton(
              onPressed: _isLoading ? null : _onMyLocationPressed,
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                      ),
                    )
                  : const Icon(Icons.my_location),
            ),
          ),
        ],
      ),
    );
  }

  List<fm.Marker> _buildMarkers() {
    if (_currentLocation == null || !_permissionGranted || !_serviceEnabled) {
      return const [];
    }
    return [
      AppMap.currentLocation(
        LatLng(_currentLocation!.latitude, _currentLocation!.longitude),
      ),
    ];
  }
}
