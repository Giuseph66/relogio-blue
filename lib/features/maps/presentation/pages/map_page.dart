import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../../core/widgets/app_drawer.dart';
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
  GoogleMapController? _googleMapController;
  MapLocation? _currentLocation;
  String? _error;
  bool _isLoading = false;
  bool _permissionGranted = false;
  bool _serviceEnabled = false;
  bool _mapCreated = false;
  bool _showLocationCard = true;
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  // Default location (São Paulo, Brasil) - usado quando não há localização
  static const LatLng _defaultLocation = LatLng(-23.5505, -46.6333);
  static const double _defaultZoom = 15.0;

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
    _googleMapController?.animateCamera(
      CameraUpdate.newLatLngZoom(
        LatLng(location.latitude, location.longitude),
        _defaultZoom,
      ),
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
    _googleMapController?.dispose();
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
          // GoogleMap widget
          SizedBox.expand(
            child: GoogleMap(
            initialCameraPosition: CameraPosition(
              target: initialLocation,
              zoom: _defaultZoom,
            ),
            onMapCreated: (controller) {
              _googleMapController = controller;
              _mapCreated = true;
              AppLogger.info('GoogleMap criado com sucesso');
              if (_currentLocation != null) {
                _moveCameraToLocation(_currentLocation!);
              }
              if (mounted) {
                setState(() {});
              }
            },
            onCameraMoveStarted: () {
              AppLogger.debug('Câmera do mapa começou a se mover');
            },
            onCameraIdle: () {
              AppLogger.debug('Câmera do mapa parou');
            },
            myLocationButtonEnabled: false,
            myLocationEnabled: _permissionGranted && _serviceEnabled,
            markers: _buildMarkers(),
            mapType: MapType.normal,
            zoomControlsEnabled: true,
            compassEnabled: true,
            ),
          ),
          if (_error != null && _currentLocation == null)
            PermissionStateView(
              errorType: _error!,
              onRequestPermission: _onRequestPermission,
              onOpenSettings: _onOpenSettings,
            ),
          if (!_mapCreated)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  const Text(
                    'Carregando mapa...',
                    style: TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange),
                    ),
                    child: const Column(
                      children: [
                        Icon(Icons.warning, color: Colors.orange, size: 32),
                        SizedBox(height: 8),
                        Text(
                          'Se o mapa não aparecer, verifique:',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          '1. API key configurada no AndroidManifest.xml\n'
                          '2. Maps SDK for Android habilitada no Google Cloud\n'
                          '3. SHA-1 fingerprint adicionado nas restrições da API key',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
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

  Set<Marker> _buildMarkers() {
    if (_currentLocation == null) {
      return {};
    }

    return {
      Marker(
        markerId: const MarkerId('current_location'),
        position: LatLng(
          _currentLocation!.latitude,
          _currentLocation!.longitude,
        ),
        infoWindow: const InfoWindow(
          title: 'Você está aqui',
          snippet: 'Sua localização atual',
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ),
    };
  }
}
