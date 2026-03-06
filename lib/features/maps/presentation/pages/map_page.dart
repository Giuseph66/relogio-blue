import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import '../../../../core/di/dependency_injection.dart';
import '../../../maps_old/presentation/controllers/map_controller.dart';
import '../../../maps_old/presentation/widgets/permission_state_view.dart';
import '../../../maps_old/domain/entities/map_location.dart';
import '../../../location_tracker/presentation/controllers/location_tracker_controller.dart';
import '../../../location_tracker/presentation/widgets/add_location_dialog.dart';

class ModernMapPage extends StatefulWidget {
  const ModernMapPage({super.key});

  @override
  State<ModernMapPage> createState() => _ModernMapPageState();
}

class _ModernMapPageState extends State<ModernMapPage> {
  late final MapController _mapController;
  late final LocationTrackerController _trackerController;
  GoogleMapController? _googleMapController;
  MapLocation? _currentLocation;
  String? _error;
  bool _isLoading = false;
  bool _permissionGranted = false;
  bool _serviceEnabled = false;
  bool _mapCreated = false;
  bool _showLocationCard = true;
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  static const LatLng _defaultLocation = LatLng(-23.5505, -46.6333);
  static const double _defaultZoom = 15.0;

  // Map selection mode state
  bool _isSelectionMode = false;
  LatLng? _selectedPin;
  String? _selectedPinAddress;
  bool _isResolving = false;

  @override
  void initState() {
    super.initState();
    _mapController = DependencyInjection().mapController;
    _trackerController = DependencyInjection().locationTrackerController;
    _trackerController.addListener(_onTrackerUpdated);
    _setupListeners();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mapController.fetchMyLocation();
    });
  }

  void _onTrackerUpdated() {
    if (mounted) setState(() {});
  }

  void _setupListeners() {
    _subscriptions.add(_mapController.isLoading.listen((loading) {
      if (mounted) setState(() => _isLoading = loading);
    }));

    _subscriptions.add(_mapController.location.listen((location) async {
      if (mounted && location != null) {
        setState(() {
          _currentLocation = location;
          _error = null;
          _showLocationCard = true;
        });
        _moveCameraToLocation(location);

        // Check proximity with tracked locations silently
        final visited = await _trackerController.checkProximityAndRegisterVisit(location);
        if (visited != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Visita detectada: ${visited.name}! Registrada no histórico.'),
              backgroundColor: Colors.cyan[700],
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    }));

    _subscriptions.add(_mapController.error.listen((error) {
      if (mounted) setState(() => _error = error);
    }));

    _subscriptions.add(_mapController.permissionGranted.listen((granted) {
      if (mounted) setState(() => _permissionGranted = granted);
    }));

    _subscriptions.add(_mapController.serviceEnabled.listen((enabled) {
      if (mounted) setState(() => _serviceEnabled = enabled);
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

  /// Called when user taps on the map (only active in selection mode)
  void _onMapTap(LatLng latLng) async {
    if (!_isSelectionMode) return;
    setState(() {
      _selectedPin = latLng;
      _selectedPinAddress = null;
      _isResolving = true;
    });
    try {
      final placemarks = await geocoding.placemarkFromCoordinates(latLng.latitude, latLng.longitude);
      if (mounted && placemarks.isNotEmpty) {
        final p = placemarks.first;
        final parts = <String>[];
        if (p.thoroughfare?.isNotEmpty == true) parts.add(p.thoroughfare!);
        if (p.subLocality?.isNotEmpty == true) parts.add(p.subLocality!);
        if (p.locality?.isNotEmpty == true) parts.add(p.locality!);
        if (p.administrativeArea?.isNotEmpty == true) parts.add(p.administrativeArea!);
        setState(() {
          _selectedPinAddress = parts.isNotEmpty ? parts.join(', ') : '${latLng.latitude.toStringAsFixed(4)}, ${latLng.longitude.toStringAsFixed(4)}';
          _isResolving = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() {
        _selectedPinAddress = '${latLng.latitude.toStringAsFixed(4)}, ${latLng.longitude.toStringAsFixed(4)}';
        _isResolving = false;
      });
    }
  }

  void _clearSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedPin = null;
      _selectedPinAddress = null;
      _isResolving = false;
    });
  }

  @override
  void dispose() {
    _trackerController.removeListener(_onTrackerUpdated);
    _googleMapController?.dispose();
    for (final s in _subscriptions) {
      s.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final initialLoc = _currentLocation != null
        ? LatLng(_currentLocation!.latitude, _currentLocation!.longitude)
        : _defaultLocation;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Localização'),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: initialLoc, zoom: _defaultZoom),
            style: _mapStyle,
            onMapCreated: (c) {
              _googleMapController = c;
              setState(() => _mapCreated = true);
              if (_currentLocation != null) _moveCameraToLocation(_currentLocation!);
            },
            onTap: _isSelectionMode ? _onMapTap : null,
            myLocationButtonEnabled: false,
            myLocationEnabled: _permissionGranted && _serviceEnabled,
            markers: _buildMarkers(),
            mapType: MapType.normal,
            zoomControlsEnabled: false,
          ),
          if (!_mapCreated || _isLoading)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: const Center(child: CircularProgressIndicator(color: Colors.cyanAccent)),
            ),
          if (_error != null && _currentLocation == null)
            PermissionStateView(
              errorType: _error!,
              onRequestPermission: _mapController.requestPermission,
              onOpenSettings: _mapController.fetchMyLocation,
            ),
          // Selection mode banner
          if (_isSelectionMode)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(12, 64, 12, 0),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.cyanAccent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.cyanAccent.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.touch_app, color: Colors.cyanAccent, size: 18),
                      const SizedBox(width: 10),
                      const Expanded(child: Text('Toque no mapa para escolher um ponto', style: TextStyle(color: Colors.cyanAccent, fontSize: 13))),
                      GestureDetector(
                        onTap: _clearSelectionMode,
                        child: const Icon(Icons.close, color: Colors.white38, size: 20),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // Selected pin confirm card
          if (_selectedPin != null)
            Positioned(
              bottom: 24,
              left: 24,
              right: 24,
              child: _buildSelectedPinCard(),
            )
          else if (_currentLocation != null && _showLocationCard && !_isSelectionMode)
            Positioned(
              bottom: 24,
              left: 24,
              right: 24,
              child: _buildLocationCard(_currentLocation!),
            ),
          Positioned(
            right: 24,
            bottom: (_selectedPin != null || (_currentLocation != null && _showLocationCard && !_isSelectionMode)) ? 200 : 40,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!_isSelectionMode) ...[
                  // Pin-on-map button
                  FloatingActionButton(
                    heroTag: 'select_on_map',
                    onPressed: () => setState(() { _isSelectionMode = true; _showLocationCard = false; }),
                    backgroundColor: const Color(0xFF1E1E1E),
                    foregroundColor: Colors.white70,
                    mini: true,
                    tooltip: 'Selecionar ponto no mapa',
                    child: const Icon(Icons.pin_drop_outlined),
                  ),
                  const SizedBox(height: 10),
                  // Add dialog (address search) button
                  if (_currentLocation != null) ...[
                    FloatingActionButton(
                      heroTag: 'add_location',
                      onPressed: _showAddLocationDialog,
                      backgroundColor: const Color(0xFF1E1E1E),
                      foregroundColor: Colors.cyanAccent,
                      mini: true,
                      tooltip: 'Catalogar local atual ou pesquisar',
                      child: const Icon(Icons.bookmark_add_outlined),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
                FloatingActionButton(
                  heroTag: 'my_location',
                  onPressed: _isLoading ? null : () => _mapController.fetchMyLocation(),
                  backgroundColor: Colors.cyanAccent,
                  foregroundColor: Colors.black,
                  child: _isLoading
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                    : const Icon(Icons.my_location),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedPinCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A).withOpacity(0.95),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.cyanAccent.withOpacity(0.3)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 20)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.pin_drop, color: Colors.cyanAccent, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: _isResolving
                  ? const Text('Identificando endereço...', style: TextStyle(color: Colors.white54, fontSize: 13))
                  : Text(_selectedPinAddress ?? 'Local selecionado', style: const TextStyle(color: Colors.white, fontSize: 13), overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => setState(() { _selectedPin = null; _selectedPinAddress = null; }),
                child: const Text('Limpar pin', style: TextStyle(color: Colors.white38, fontSize: 12)),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                onPressed: _isResolving ? null : () => _showAddLocationDialog(pin: _selectedPin, pinAddr: _selectedPinAddress),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.cyanAccent,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
                icon: const Icon(Icons.bookmark_add, size: 16),
                label: const Text('Catalogar', style: TextStyle(fontSize: 13)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLocationCard(MapLocation location) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A).withOpacity(0.9),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white10),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 5)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.cyanAccent.withOpacity(0.1), shape: BoxShape.circle),
                child: const Icon(Icons.location_on, color: Colors.cyanAccent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Sua Posição', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    Text(
                      'Lat: ${location.latitude.toStringAsFixed(4)}, Lon: ${location.longitude.toStringAsFixed(4)}',
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white38, size: 18),
                onPressed: () => setState(() => _showLocationCard = false),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildInfoRow(Icons.access_time, 'Atualizado em', _formatTime(location.timestamp)),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.white38),
        const SizedBox(width: 8),
        Text('$label: ', style: const TextStyle(color: Colors.white38, fontSize: 11)),
        Text(value, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Set<Marker> _buildMarkers() {
    final markers = <Marker>{};

    // Selection pin (green)
    if (_selectedPin != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('_selection_pin'),
          position: _selectedPin!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          zIndex: 10,
        ),
      );
    }

    // Saved catalog locations (orange)
    for (final loc in _trackerController.locations) {
      markers.add(
        Marker(
          markerId: MarkerId(loc.id),
          position: LatLng(loc.latitude, loc.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
          infoWindow: InfoWindow(title: loc.name, snippet: 'Raio: ${loc.radiusMeters.toInt()}m'),
        ),
      );
    }

    // Current Location (cyan)
    if (_currentLocation != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('me'),
          position: LatLng(_currentLocation!.latitude, _currentLocation!.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan),
        ),
      );
    }

    return markers;
  }

  void _showAddLocationDialog({LatLng? pin, String? pinAddr}) async {
    final srcLat = pin?.latitude ?? _currentLocation?.latitude;
    final srcLng = pin?.longitude ?? _currentLocation?.longitude;
    if (srcLat == null) return;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => AddLocationDialog(
        currentLat: _currentLocation?.latitude,
        currentLng: _currentLocation?.longitude,
        selectedLat: pin?.latitude,
        selectedLng: pin?.longitude,
        resolvedAddress: pinAddr,
      ),
    );

    if (result != null && mounted) {
      final lat = (result['lat'] as double?) ?? srcLat;
      final lng = (result['lng'] as double?) ?? srcLng;
      await _trackerController.addLocation(
        result['name'],
        lat,
        lng!,
        radiusMeters: result['radius'],
      );
      if (pin != null) _clearSelectionMode();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${result['name']} salvo!'), backgroundColor: Colors.cyan),
      );
    }
  }

  String _formatTime(DateTime t) {
    return '${t.hour.toString().padLeft(2,'0')}:${t.minute.toString().padLeft(2,'0')}';
  }

  // Estilo Dark opcional para o mapa (Simplificado para o exemplo)
  static const String _mapStyle = ''; 
}
