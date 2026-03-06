import 'package:flutter/material.dart';
import '../../../../core/di/dependency_injection.dart';
import '../controllers/location_tracker_controller.dart';
import '../../domain/entities/tracked_location.dart';

class LocationCatalogPage extends StatefulWidget {
  const LocationCatalogPage({super.key});

  @override
  State<LocationCatalogPage> createState() => _LocationCatalogPageState();
}

class _LocationCatalogPageState extends State<LocationCatalogPage> with SingleTickerProviderStateMixin {
  late final LocationTrackerController _controller;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _controller = DependencyInjection().locationTrackerController;
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Catálogo de Locais'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.cyanAccent,
          labelColor: Colors.cyanAccent,
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(icon: Icon(Icons.bookmark_added), text: 'Catalogados'),
            Tab(icon: Icon(Icons.history), text: 'Histórico de Visitas'),
          ],
        ),
      ),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          return TabBarView(
            controller: _tabController,
            children: [
              _buildCatalogList(),
              _buildHistoryList(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCatalogList() {
    if (_controller.locations.isEmpty) {
      return _buildEmptyState(
        Icons.map_outlined,
        'Nenhum local salvo',
        'Adicione locais pelo mapa para catalogá-los.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _controller.locations.length,
      itemBuilder: (context, index) {
        final loc = _controller.locations[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: Color(0x1A00E5FF),
              child: Icon(Icons.location_on, color: Colors.cyanAccent),
            ),
            title: Text(loc.name, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
            subtitle: Text('Raio: ${loc.radiusMeters.toInt()}m\nCriado em: ${_formatDate(loc.createdAt)}', style: const TextStyle(color: Colors.white54)),
            isThreeLine: true,
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              onPressed: () => _confirmDeleteLocation(loc),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHistoryList() {
    if (_controller.visits.isEmpty) {
      return _buildEmptyState(
        Icons.history,
        'Nenhuma visita registrada',
        'As visitas são registradas automaticamente quando você se aproxima de um local catalogado.',
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${_controller.visits.length} registros', style: const TextStyle(color: Colors.white54)),
              TextButton.icon(
                onPressed: _confirmClearHistory,
                icon: const Icon(Icons.clear_all, color: Colors.white54, size: 18),
                label: const Text('Limpar Histórico', style: TextStyle(color: Colors.white54)),
              )
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _controller.visits.length,
            separatorBuilder: (_, __) => const Divider(color: Colors.white10),
            itemBuilder: (context, index) {
              final visit = _controller.visits[index];
              final loc = _controller.locations.firstWhere(
                (l) => l.id == visit.locationId,
                orElse: () => TrackedLocation(id: '', name: 'Local Removido', latitude: 0, longitude: 0, radiusMeters: 0, createdAt: DateTime.now()),
              );

              return ListTile(
                leading: const Icon(Icons.tour, color: Colors.white38),
                title: Text(loc.name, style: const TextStyle(color: Colors.white)),
                subtitle: Text(_formatDateVerbose(visit.timestamp), style: const TextStyle(color: Colors.cyanAccent, fontSize: 12)),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(IconData icon, String title, String subtitle) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: Colors.white10),
            const SizedBox(height: 24),
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white54)),
            const SizedBox(height: 8),
            Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white38)),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteLocation(TrackedLocation loc) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Excluir local?'),
        content: Text('Tem certeza que deseja excluir "${loc.name}"? As visitas associadas também serão apagadas.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _controller.removeLocation(loc.id);
            },
            child: const Text('Excluir', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  void _confirmClearHistory() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Limpar histórico?'),
        content: const Text('Esta ação apagará remotará todo o registro de visitas.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _controller.clearVisits();
            },
            child: const Text('Limpar', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  String _formatDateVerbose(DateTime d) => '${_formatDate(d)} às ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
