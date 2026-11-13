import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import '../../../../core/theme/app_palette.dart';

class AddLocationDialog extends StatefulWidget {
  final double? currentLat;
  final double? currentLng;
  // If calledFrom map tap, these will have the tapped coordinates
  final double? selectedLat;
  final double? selectedLng;
  final String? resolvedAddress;

  const AddLocationDialog({
    super.key,
    this.currentLat,
    this.currentLng,
    this.selectedLat,
    this.selectedLng,
    this.resolvedAddress,
  });

  @override
  State<AddLocationDialog> createState() => _AddLocationDialogState();
}

class _AddLocationDialogState extends State<AddLocationDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _nameController = TextEditingController();
  final _searchController = TextEditingController();
  final _radiusController = TextEditingController(text: '50');
  final _formKey = GlobalKey<FormState>();

  bool _isSearching = false;
  String? _searchError;
  _LocationResult? _searchResult;

  // Which tab source is "active" for final submit
  _LocationResult? _activeSource;

  @override
  void initState() {
    super.initState();
    final hasGps = widget.currentLat != null && widget.currentLng != null;
    final hasSelected = widget.selectedLat != null && widget.selectedLng != null;

    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: hasSelected ? 1 : 0,
    );
    _tabController.addListener(_onTabChanged);

    if (hasSelected) {
      _searchResult = _LocationResult(
        lat: widget.selectedLat!,
        lng: widget.selectedLng!,
        displayAddr: widget.resolvedAddress ?? 'Local selecionado no mapa',
      );
      _activeSource = _searchResult;
    } else if (hasGps) {
      _activeSource = _LocationResult(
        lat: widget.currentLat!,
        lng: widget.currentLng!,
        displayAddr: 'Posição atual do GPS',
      );
    }
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) {
      setState(() {
        if (_tabController.index == 0 && widget.currentLat != null) {
          _activeSource = _LocationResult(
            lat: widget.currentLat!,
            lng: widget.currentLng!,
            displayAddr: 'Posição atual do GPS',
          );
        } else if (_tabController.index == 1) {
          // Prefer explicit search result, then fall back to map pin
          _activeSource = _searchResult ?? (widget.selectedLat != null
            ? _LocationResult(
                lat: widget.selectedLat!,
                lng: widget.selectedLng!,
                displayAddr: widget.resolvedAddress ?? 'Local selecionado no mapa',
              )
            : null);
        }
      });
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _nameController.dispose();
    _searchController.dispose();
    _radiusController.dispose();
    super.dispose();
  }

  Future<void> _searchAddress() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isSearching = true;
      _searchError = null;
      _searchResult = null;
      _activeSource = null;
    });

    try {
      final locations = await geocoding.locationFromAddress(query);
      if (locations.isNotEmpty) {
        final loc = locations.first;
        // Reverse geocode to get formatted address
        final placemarks = await geocoding.placemarkFromCoordinates(loc.latitude, loc.longitude);
        String addr = query; // fallback
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          final parts = <String>[];
          if (p.thoroughfare != null && p.thoroughfare!.isNotEmpty) parts.add(p.thoroughfare!);
          if (p.subLocality != null && p.subLocality!.isNotEmpty) parts.add(p.subLocality!);
          if (p.locality != null && p.locality!.isNotEmpty) parts.add(p.locality!);
          if (p.administrativeArea != null && p.administrativeArea!.isNotEmpty) parts.add(p.administrativeArea!);
          if (parts.isNotEmpty) addr = parts.join(', ');
        }
        setState(() {
          _searchResult = _LocationResult(lat: loc.latitude, lng: loc.longitude, displayAddr: addr);
          _activeSource = _searchResult;
          _isSearching = false;
        });
      } else {
        setState(() {
          _searchError = 'Nenhum local encontrado para "$query"';
          _isSearching = false;
        });
      }
    } catch (e) {
      setState(() {
        _searchError = 'Erro ao buscar: verifique a conexão de internet';
        _isSearching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxHeight: 560),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: context.palette.cardElevated,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: context.palette.textPrimary.withValues(alpha: 0.1)),
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: context.palette.accent.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.add_location_alt, color: context.palette.accent, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Text('Catalogar Local', style: TextStyle(color: context.palette.textPrimary, fontSize: 17, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 16),
              // Name field
              TextFormField(
                controller: _nameController,
                style: TextStyle(color: context.palette.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Nome do Local',
                  labelStyle: TextStyle(color: context.palette.textPrimary.withValues(alpha: 0.54)),
                  filled: true,
                  fillColor: context.palette.textPrimary.withValues(alpha: 0.05),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  prefixIcon: Icon(Icons.label_outline, color: context.palette.textPrimary.withValues(alpha: 0.38)),
                ),
                validator: (val) => val == null || val.trim().isEmpty ? 'Insira um nome' : null,
              ),
              const SizedBox(height: 12),
              // Radius field
              TextFormField(
                controller: _radiusController,
                keyboardType: TextInputType.number,
                style: TextStyle(color: context.palette.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Raio (metros)',
                  labelStyle: TextStyle(color: context.palette.textPrimary.withValues(alpha: 0.54)),
                  filled: true,
                  fillColor: context.palette.textPrimary.withValues(alpha: 0.05),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  prefixIcon: Icon(Icons.radar, color: context.palette.textPrimary.withValues(alpha: 0.38)),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) return 'Insira o raio';
                  if (double.tryParse(val) == null) return 'Somente números';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              // Source tabs
              Container(
                decoration: BoxDecoration(
                  color: context.palette.textPrimary.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicator: BoxDecoration(color: context.palette.accent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                  labelColor: context.palette.accent,
                  unselectedLabelColor: context.palette.textPrimary.withValues(alpha: 0.38),
                  dividerColor: Colors.transparent,
                  labelStyle: const TextStyle(fontSize: 12),
                  tabs: const [
                    Tab(icon: Icon(Icons.my_location, size: 16), text: 'GPS Atual'),
                    Tab(icon: Icon(Icons.search, size: 16), text: 'Pesquisar'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Tab content
              SizedBox(
                height: 100,
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // Tab 0 — GPS
                    _buildGpsTab(),
                    // Tab 1 — Pesquisar
                    _buildSearchTab(),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('Cancelar', style: TextStyle(color: context.palette.textPrimary.withValues(alpha: 0.38))),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _activeSource == null ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.palette.accent,
                      foregroundColor: context.palette.onAccent,
                      disabledBackgroundColor: context.palette.textPrimary.withValues(alpha: 0.1),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Salvar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGpsTab() {
    if (widget.currentLat == null) {
      return Center(child: Text('GPS indisponível', style: TextStyle(color: context.palette.textPrimary.withValues(alpha: 0.38))));
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: context.palette.textPrimary.withValues(alpha: 0.03), borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(children: [
            Icon(Icons.gps_fixed, color: context.palette.accent, size: 14),
            const SizedBox(width: 8),
            Text('Posição atual do GPS', style: TextStyle(color: context.palette.textPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 4),
          Text(
            'Lat: ${widget.currentLat!.toStringAsFixed(5)}, Lon: ${widget.currentLng!.toStringAsFixed(5)}',
            style: TextStyle(color: context.palette.textPrimary.withValues(alpha: 0.38), fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchTab() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 42,
                child: TextField(
                  controller: _searchController,
                  style: TextStyle(color: context.palette.textPrimary, fontSize: 13),
                  onSubmitted: (_) => _searchAddress(),
                  decoration: InputDecoration(
                    hintText: 'Ex: Av. Paulista, São Paulo',
                    hintStyle: TextStyle(color: context.palette.textPrimary.withValues(alpha: 0.24), fontSize: 12),
                    filled: true,
                    fillColor: context.palette.textPrimary.withValues(alpha: 0.05),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 42,
              child: ElevatedButton(
                onPressed: _isSearching ? null : _searchAddress,
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.palette.accent.withValues(alpha: 0.15),
                  foregroundColor: context.palette.accent,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: _isSearching
                  ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: context.palette.accent))
                  : const Icon(Icons.search, size: 18),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_searchError != null)
          Text(_searchError!, style: TextStyle(color: context.palette.danger, fontSize: 11))
        else if (_searchResult != null)
          Row(
            children: [
              Icon(Icons.check_circle, color: context.palette.accent, size: 14),
              const SizedBox(width: 6),
              Expanded(child: Text(_searchResult!.displayAddr, style: TextStyle(color: context.palette.textPrimary.withValues(alpha: 0.7), fontSize: 11), overflow: TextOverflow.ellipsis)),
            ],
          )
        else
          Text('Digite um endereço e pressione buscar', style: TextStyle(color: context.palette.textPrimary.withValues(alpha: 0.24), fontSize: 11)),
      ],
    );
  }

  void _submit() {
    if (_formKey.currentState!.validate() && _activeSource != null) {
      Navigator.of(context).pop({
        'name': _nameController.text.trim(),
        'radius': double.parse(_radiusController.text.trim()),
        'lat': _activeSource!.lat,
        'lng': _activeSource!.lng,
      });
    }
  }
}

class _LocationResult {
  final double lat;
  final double lng;
  final String displayAddr;
  _LocationResult({required this.lat, required this.lng, required this.displayAddr});
}
