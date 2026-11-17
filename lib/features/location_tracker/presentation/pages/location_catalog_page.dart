import 'package:flutter/material.dart';
import '../../../../core/di/dependency_injection.dart';
import '../controllers/location_tracker_controller.dart';
import '../../domain/entities/location_question.dart';
import '../../domain/entities/tracked_location.dart';
import '../../../../core/theme/app_palette.dart';

class LocationCatalogPage extends StatefulWidget {
  const LocationCatalogPage({super.key});

  @override
  State<LocationCatalogPage> createState() => _LocationCatalogPageState();
}

class _LocationCatalogPageState extends State<LocationCatalogPage>
    with SingleTickerProviderStateMixin {
  late final LocationTrackerController _controller;
  late final TabController _tabController;
  String? _sendingId;

  /// Question each location would trigger, cached per id.
  final Map<String, Future<LocationQuestion?>> _questionPreviews = {};

  Future<LocationQuestion?> _questionFor(TrackedLocation loc) {
    return _questionPreviews.putIfAbsent(
      loc.id,
      () => DependencyInjection().visitQuestionOrchestrator.resolveQuestionFor(
        loc,
      ),
    );
  }

  Future<void> _reloadPreviews() async {
    setState(_questionPreviews.clear);
    await Future.wait(_controller.locations.map(_questionFor));
  }

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
          indicatorColor: context.palette.accent,
          labelColor: context.palette.accent,
          unselectedLabelColor: context.palette.textPrimary.withValues(alpha: 0.54),
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
            children: [_buildCatalogList(), _buildHistoryList()],
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

    final list = ListView.builder(
      padding: const EdgeInsets.all(16),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _controller.locations.length,
      itemBuilder: (context, index) {
        final loc = _controller.locations[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: Color(0x1A00E5FF),
                  child: Icon(Icons.location_on, color: context.palette.accent),
                ),
                title: Text(
                  loc.name,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: context.palette.textPrimary,
                  ),
                ),
                subtitle: Text(
                  'Raio: ${loc.radiusMeters.toInt()}m\nCriado em: ${_formatDate(loc.createdAt)}',
                  style: TextStyle(color: context.palette.textPrimary.withValues(alpha: 0.54)),
                ),
                isThreeLine: true,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.delete_outline,
                        color: context.palette.danger,
                      ),
                      onPressed: () => _confirmDeleteLocation(loc),
                    ),
                  ],
                ),
              ),
              _QuestionPreview(future: _questionFor(loc)),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: Wrap(
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: () =>
                          setState(() => _questionPreviews.remove(loc.id)),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Buscar perguntas'),
                    ),
                    TextButton.icon(
                      onPressed: _sendingId == null
                          ? () => _sendNotification(loc)
                          : null,
                      icon: _sendingId == loc.id
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.notifications_active_outlined),
                      label: const Text('Enviar / reenviar notificação'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );

    return RefreshIndicator(
      color: context.palette.accent,
      onRefresh: _reloadPreviews,
      child: list,
    );
  }

  /// Opens the location question on this device without recording a GPS visit.
  Future<void> _sendNotification(TrackedLocation loc) async {
    setState(() => _sendingId = loc.id);
    final triggered = await DependencyInjection().visitQuestionOrchestrator
        .handleVisit(loc, resendToPhone: true);
    if (!mounted) return;
    setState(() => _sendingId = null);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          triggered
              ? 'Pergunta de ${loc.name} aberta neste dispositivo. '
                    'O aviso do celular depende da permissão em Ajustes.'
              : 'Não foi possível enviar. Verifique se ${loc.name} tem uma '
                    'pergunta ativa com pelo menos duas opções e tente novamente.',
        ),
      ),
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
              Text(
                '${_controller.visits.length} registros',
                style: TextStyle(color: context.palette.textPrimary.withValues(alpha: 0.54)),
              ),
              TextButton.icon(
                onPressed: _confirmClearHistory,
                icon: Icon(
                  Icons.clear_all,
                  color: context.palette.textPrimary.withValues(alpha: 0.54),
                  size: 18,
                ),
                label: Text(
                  'Limpar Histórico',
                  style: TextStyle(color: context.palette.textPrimary.withValues(alpha: 0.54)),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _controller.visits.length,
            separatorBuilder: (_, __) => Divider(color: context.palette.textPrimary.withValues(alpha: 0.1)),
            itemBuilder: (context, index) {
              final visit = _controller.visits[index];
              final loc = _controller.locations.firstWhere(
                (l) => l.id == visit.locationId,
                orElse: () => TrackedLocation(
                  id: '',
                  name: 'Local Removido',
                  latitude: 0,
                  longitude: 0,
                  radiusMeters: 0,
                  createdAt: DateTime.now(),
                ),
              );

              return ListTile(
                leading: Icon(Icons.tour, color: context.palette.textPrimary.withValues(alpha: 0.38)),
                title: Text(
                  loc.name,
                  style: TextStyle(color: context.palette.textPrimary),
                ),
                subtitle: Text(
                  _formatDateVerbose(visit.timestamp),
                  style: TextStyle(
                    color: context.palette.accent,
                    fontSize: 12,
                  ),
                ),
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
            Icon(icon, size: 64, color: context.palette.textPrimary.withValues(alpha: 0.1)),
            const SizedBox(height: 24),
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: context.palette.textPrimary.withValues(alpha: 0.54),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.palette.textPrimary.withValues(alpha: 0.38)),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteLocation(TrackedLocation loc) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.palette.cardElevated,
        title: const Text('Excluir local?'),
        content: Text(
          'Tem certeza que deseja excluir "${loc.name}"? As visitas associadas também serão apagadas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _controller.removeLocation(loc.id);
            },
            child: Text(
              'Excluir',
              style: TextStyle(color: context.palette.danger),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmClearHistory() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.palette.cardElevated,
        title: const Text('Limpar histórico?'),
        content: const Text(
          'Esta ação apagará remotará todo o registro de visitas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _controller.clearVisits();
            },
            child: Text(
              'Limpar',
              style: TextStyle(color: context.palette.danger),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  String _formatDateVerbose(DateTime d) =>
      '${_formatDate(d)} às ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// Shows the question (and options) a visit to the location would trigger.
class _QuestionPreview extends StatelessWidget {
  final Future<LocationQuestion?> future;

  const _QuestionPreview({required this.future});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.palette.textPrimary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.palette.textPrimary.withValues(alpha: 0.08)),
      ),
      child: FutureBuilder<LocationQuestion?>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 10),
                Text(
                  'Buscando pergunta…',
                  style: TextStyle(color: context.palette.textPrimary.withValues(alpha: 0.54)),
                ),
              ],
            );
          }

          if (snapshot.hasError) {
            return _PreviewMessage(
              icon: Icons.cloud_off,
              color: context.palette.warning,
              text:
                  'Servidor indisponível. Puxe para baixo para tentar de novo.',
            );
          }

          final question = snapshot.data;
          if (question == null) {
            return _PreviewMessage(
              icon: Icons.help_outline,
              color: context.palette.textPrimary.withValues(alpha: 0.38),
              text: 'Nenhuma pergunta cadastrada — nada será disparado.',
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'PERGUNTA',
                style: TextStyle(
                  color: context.palette.accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                question.prompt,
                style: TextStyle(color: context.palette.textPrimary, fontSize: 14),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in question.options)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: context.palette.accent.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Text(
                        option.label,
                        style: TextStyle(
                          color: context.palette.textPrimary.withValues(alpha: 0.7),
                          fontSize: 13,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PreviewMessage extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _PreviewMessage({
    required this.icon,
    required this.color,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: TextStyle(color: color, fontSize: 13)),
        ),
      ],
    );
  }
}
