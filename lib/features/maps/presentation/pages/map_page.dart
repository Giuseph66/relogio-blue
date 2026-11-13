import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:latlong2/latlong.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import '../../../../core/config/app_config.dart';
import '../../../../core/di/dependency_injection.dart';
import '../../../maps_old/presentation/controllers/map_controller.dart';
import '../../../maps_old/presentation/widgets/permission_state_view.dart';
import '../../../maps_old/domain/entities/map_location.dart';
import '../../../../core/geofence/geofence_service.dart';
import '../../../../core/permissions/permission_helper.dart';
import '../../../../core/widgets/app_map.dart';
import '../../../location_tracker/presentation/controllers/location_tracker_controller.dart';
import '../../../location_tracker/presentation/widgets/add_location_dialog.dart';
import '../../../../core/theme/app_palette.dart';

class ModernMapPage extends StatefulWidget {
  /// False when embedded in MainScreen, which already provides the header.
  final bool showAppBar;

  const ModernMapPage({super.key, this.showAppBar = true});

  @override
  State<ModernMapPage> createState() => _ModernMapPageState();
}

class _ModernMapPageState extends State<ModernMapPage> {
  late final MapController _mapController;
  late final LocationTrackerController _trackerController;
  final fm.MapController _osmController = fm.MapController();
  MapLocation? _currentLocation;
  String? _error;
  bool _isLoading = false;
  bool _permissionGranted = false;
  bool _serviceEnabled = false;
  bool _mapCreated = false;
  bool _showLocationCard = true;
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  static const LatLng _defaultLocation = AppMap.defaultCenter;
  static const double _defaultZoom = AppMap.defaultZoom;

  // Map selection mode state
  bool _isSelectionMode = false;
  LatLng? _selectedPin;
  String? _selectedPinAddress;
  bool _isResolving = false;
  bool _isSyncingLocations = false;
  bool _autoSyncDone = false;
  String? _lastCity;

  @override
  void initState() {
    super.initState();
    _mapController = DependencyInjection().mapController;
    _trackerController = DependencyInjection().locationTrackerController;
    _trackerController.addListener(_onTrackerUpdated);
    _setupListeners();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initWithPermissionCheck();
    });
  }

  void _onTrackerUpdated() {
    if (mounted) setState(() {});
  }

  Future<void> _initWithPermissionCheck() async {
    await PermissionHelper.requestAllPermissions();
    final granted = await _mapController.requestPermission();
    if (granted) {
      _mapController.fetchMyLocation();
    }
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

        // Auto-sync locations from server on first GPS fix (silent)
        if (!_autoSyncDone) {
          _autoSyncDone = true;
          _syncLocationsFromServer(silent: true);
        }

        // Delegate geofence check + question flow to the GeofenceService.
        // It deduplicates with its own timer, so calling updateLocation on every
        // UI GPS event just keeps the shared position fresh.
        GeofenceService().updateLocation(location, city: _lastCity);
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
    if (!_mapCreated) return; // controller only usable after onMapReady
    _osmController.move(
      LatLng(location.latitude, location.longitude),
      _defaultZoom,
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
    _osmController.dispose();
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

    // Height of the floating nav bar when embedded (Scaffold.extendBody).
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      extendBodyBehindAppBar: widget.showAppBar,
      appBar: widget.showAppBar
          ? AppBar(
              title: const Text('Localização'),
              elevation: 0,
              backgroundColor: Colors.transparent,
            )
          : null,
      body: Stack(
        children: [
          fm.FlutterMap(
            mapController: _osmController,
            options: fm.MapOptions(
              initialCenter: initialLoc,
              initialZoom: _defaultZoom,
              minZoom: 3,
              maxZoom: 19,
              backgroundColor: context.palette.scaffold,
              interactionOptions: const fm.InteractionOptions(
                flags: fm.InteractiveFlag.all & ~fm.InteractiveFlag.rotate,
              ),
              onMapReady: () {
                setState(() => _mapCreated = true);
                if (_currentLocation != null) _moveCameraToLocation(_currentLocation!);
              },
              onTap: (_, point) {
                if (_isSelectionMode) _onMapTap(point);
              },
            ),
            children: [
              AppMap.tileLayer(context),
              fm.CircleLayer(circles: _buildRadiusCircles()),
              fm.MarkerLayer(markers: _buildMarkers()),
              AppMap.attribution(),
            ],
          ),
          if (!_mapCreated || _isLoading)
            Container(
              color: Colors.black.withValues(alpha: 0.5),
              child: Center(child: CircularProgressIndicator(color: context.palette.accent)),
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
                  margin: EdgeInsets.fromLTRB(12, widget.showAppBar ? 64 : 12, 12, 0),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: context.palette.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: context.palette.accent.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.touch_app, color: context.palette.accent, size: 18),
                      const SizedBox(width: 10),
                      Expanded(child: Text('Toque no mapa para escolher um ponto', style: TextStyle(color: context.palette.accent, fontSize: 13))),
                      GestureDetector(
                        onTap: _clearSelectionMode,
                        child: Icon(Icons.close, color: context.palette.textPrimary.withValues(alpha: 0.38), size: 20),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // Selected pin confirm card
          if (_selectedPin != null)
            Positioned(
              bottom: 24 + bottomInset,
              left: 24,
              right: 24,
              child: _buildSelectedPinCard(),
            )
          else if (_currentLocation != null && _showLocationCard && !_isSelectionMode)
            Positioned(
              bottom: 24 + bottomInset,
              left: 24,
              right: 24,
              child: _buildLocationCard(_currentLocation!),
            ),
          Positioned(
            right: 24,
            bottom: bottomInset + ((_selectedPin != null || (_currentLocation != null && _showLocationCard && !_isSelectionMode)) ? 200 : 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!_isSelectionMode) ...[
                  // Sync locations from server button
                  FloatingActionButton(
                    heroTag: 'sync_locations',
                    onPressed: _isSyncingLocations ? null : _syncLocationsFromServer,
                    backgroundColor: context.palette.cardElevated,
                    foregroundColor: context.palette.success,
                    mini: true,
                    tooltip: 'Atualizar locais do servidor',
                    child: _isSyncingLocations
                        ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: context.palette.success))
                        : const Icon(Icons.cloud_download_outlined),
                  ),
                  const SizedBox(height: 10),
                  // Pin-on-map button
                  FloatingActionButton(
                    heroTag: 'select_on_map',
                    onPressed: () => setState(() { _isSelectionMode = true; _showLocationCard = false; }),
                    backgroundColor: context.palette.cardElevated,
                    foregroundColor: context.palette.textPrimary.withValues(alpha: 0.7),
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
                      backgroundColor: context.palette.cardElevated,
                      foregroundColor: context.palette.accent,
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
                  backgroundColor: context.palette.accent,
                  foregroundColor: context.palette.onAccent,
                  child: _isLoading
                    ? SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: context.palette.onAccent))
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
        color: context.palette.card.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.palette.accent.withValues(alpha: 0.3)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: context.isDarkTheme ? 0.4 : 0.08), blurRadius: 20)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.pin_drop, color: context.palette.accent, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: _isResolving
                  ? Text('Identificando endereço...', style: TextStyle(color: context.palette.textPrimary.withValues(alpha: 0.54), fontSize: 13))
                  : Text(_selectedPinAddress ?? 'Local selecionado', style: TextStyle(color: context.palette.textPrimary, fontSize: 13), overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => setState(() { _selectedPin = null; _selectedPinAddress = null; }),
                child: Text('Limpar pin', style: TextStyle(color: context.palette.textPrimary.withValues(alpha: 0.38), fontSize: 12)),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                onPressed: _isResolving ? null : () => _showAddLocationDialog(pin: _selectedPin, pinAddr: _selectedPinAddress),
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.palette.accent,
                  foregroundColor: context.palette.onAccent,
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
        color: context.palette.card.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: context.palette.textPrimary.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: context.isDarkTheme ? 0.3 : 0.08), blurRadius: 20, offset: const Offset(0, 5)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: context.palette.accent.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: Icon(Icons.location_on, color: context.palette.accent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Sua Posição', style: TextStyle(color: context.palette.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
                    Text(
                      'Lat: ${location.latitude.toStringAsFixed(4)}, Lon: ${location.longitude.toStringAsFixed(4)}',
                      style: TextStyle(color: context.palette.textPrimary.withValues(alpha: 0.54), fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, color: context.palette.textPrimary.withValues(alpha: 0.38), size: 18),
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
        Icon(icon, size: 14, color: context.palette.textPrimary.withValues(alpha: 0.38)),
        const SizedBox(width: 8),
        Text('$label: ', style: TextStyle(color: context.palette.textPrimary.withValues(alpha: 0.38), fontSize: 11)),
        Text(value, style: TextStyle(color: context.palette.textPrimary.withValues(alpha: 0.7), fontSize: 11, fontWeight: FontWeight.bold)),
      ],
    );
  }

  /// Geofence radius around each saved location.
  List<fm.CircleMarker> _buildRadiusCircles() {
    return [
      for (final loc in _trackerController.locations)
        AppMap.radius(
          LatLng(loc.latitude, loc.longitude),
          loc.radiusMeters,
          context.palette.warning,
        ),
    ];
  }

  List<fm.Marker> _buildMarkers() {
    return [
      // Saved catalog locations (orange) — tap shows name + radius.
      for (final loc in _trackerController.locations)
        AppMap.pin(
          LatLng(loc.latitude, loc.longitude),
          color: context.palette.warning,
          onTap: () => _showMarkerInfo(loc.name, 'Raio: ${loc.radiusMeters.toInt()}m'),
        ),

      // Current location (cyan dot)
      if (_currentLocation != null && _permissionGranted && _serviceEnabled)
        AppMap.currentLocation(
          LatLng(_currentLocation!.latitude, _currentLocation!.longitude),
          color: context.palette.accent,
        ),

      // Selection pin (green) — last so it renders on top.
      if (_selectedPin != null)
        AppMap.pin(_selectedPin!, color: context.palette.success, size: 48),
    ];
  }

  void _showMarkerInfo(String title, String subtitle) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('$title · $subtitle'),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  Future<void> _syncLocationsFromServer({bool silent = false}) async {
    if (_isSyncingLocations) return;

    if (_currentLocation == null) {
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Aguarde a localização GPS ser obtida.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    setState(() => _isSyncingLocations = true);

    try {
      final settingsResult = await DependencyInjection().loadSettings();
      final configuredUrl = settingsResult.valueOrNull?.serverApiUrl.trim() ?? '';
      // Fall back to the app-wide server (same one used for questions/answers).
      final serverUrl =
          configuredUrl.isNotEmpty ? configuredUrl : AppConfig.serverApiUrl;

      if (serverUrl.isEmpty) {
        if (!silent && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Configure a URL do servidor em Ajustes.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Reverse geocode to get city name
      String? city;
      try {
        final placemarks = await geocoding.placemarkFromCoordinates(
          _currentLocation!.latitude,
          _currentLocation!.longitude,
        );
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          city = (p.locality?.isNotEmpty == true)
              ? p.locality
              : (p.subAdministrativeArea?.isNotEmpty == true)
                  ? p.subAdministrativeArea
                  : p.administrativeArea;
          if (city != null) _lastCity = city;
        }
      } catch (_) {}

      final result = await _trackerController.syncFromServer(
        serverUrl,
        latitude: _currentLocation!.latitude,
        longitude: _currentLocation!.longitude,
        city: city,
      );
      if (!silent && mounted) {
        final parts = <String>[
          if (result.added > 0) '${result.added} novo(s)',
          if (result.updated > 0) '${result.updated} atualizado(s)',
        ];
        final where = city != null ? ' em $city' : '';
        final message = parts.isEmpty
            ? 'Nenhuma alteração$where (${result.total} local(is) verificado(s)).'
            : '${parts.join(', ')}$where — serão perguntados novamente ao entrar no raio.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.cyan[700],
          ),
        );
      }
    } catch (e) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao buscar locais: $e'),
            backgroundColor: Colors.red[700],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncingLocations = false);
    }
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
}
