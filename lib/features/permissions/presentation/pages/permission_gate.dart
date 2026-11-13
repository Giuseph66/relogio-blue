import 'package:flutter/material.dart';

import '../../../../core/permissions/app_permissions.dart';
import '../../../../core/theme/app_palette.dart';

/// Blocks the whole app until every [AppRequirement] is satisfied.
///
/// Used in `MaterialApp.builder`, so no route (login, dashboard…) is reachable
/// while something is missing. Re-checks every time the app returns to the
/// foreground — e.g. after the user comes back from the Android settings.
class PermissionGate extends StatefulWidget {
  final Widget child;

  /// Called once per app start, as soon as everything is granted (used to
  /// start background services that need these permissions).
  final VoidCallback? onAllGranted;

  const PermissionGate({super.key, required this.child, this.onAllGranted});

  @override
  State<PermissionGate> createState() => _PermissionGateState();
}

class _PermissionGateState extends State<PermissionGate>
    with WidgetsBindingObserver {
  Map<AppRequirement, RequirementStatus>? _statuses;
  bool _requesting = false;
  bool _grantedNotified = false;

  bool get _allGranted =>
      _statuses != null &&
      _statuses!.values.every((s) => s == RequirementStatus.granted);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_requesting) _refresh();
  }

  Future<void> _refresh() async {
    final statuses = await AppPermissions.checkAll();
    if (!mounted) return;
    setState(() => _statuses = statuses);
    if (_allGranted && !_grantedNotified) {
      _grantedNotified = true;
      widget.onAllGranted?.call();
    }
  }

  Future<void> _request(AppRequirement req) async {
    if (_requesting) return;
    setState(() => _requesting = true);
    try {
      await AppPermissions.request(req);
    } finally {
      _requesting = false;
      await _refresh();
    }
  }

  AppRequirement? get _nextPending {
    final statuses = _statuses;
    if (statuses == null) return null;
    for (final req in AppRequirement.values) {
      if (statuses[req] != RequirementStatus.granted) return req;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_allGranted) return widget.child;

    return PopScope(
      canPop: false,
      child: _statuses == null
          ? const _LoadingView()
          : _PermissionView(
              statuses: _statuses!,
              next: _nextPending,
              requesting: _requesting,
              onRequest: _request,
            ),
    );
  }
}

// ─── Copy ────────────────────────────────────────────────────────────────────

class _RequirementInfo {
  final IconData icon;
  final String title;
  final String reason;
  final String action;

  const _RequirementInfo(this.icon, this.title, this.reason, this.action);
}

const Map<AppRequirement, _RequirementInfo> _info = {
  AppRequirement.location: _RequirementInfo(
    Icons.location_on_rounded,
    'Localização',
    'Detecta quando você chega a um local cadastrado.',
    'Permitir',
  ),
  AppRequirement.backgroundLocation: _RequirementInfo(
    Icons.share_location_rounded,
    'Localização o tempo todo',
    'Mantém a detecção funcionando com o app fechado. '
        'Escolha "Permitir o tempo todo".',
    'Permitir sempre',
  ),
  AppRequirement.bluetooth: _RequirementInfo(
    Icons.bluetooth_rounded,
    'Dispositivos próximos',
    'Encontra e conecta ao relógio via Bluetooth.',
    'Permitir',
  ),
  AppRequirement.notifications: _RequirementInfo(
    Icons.notifications_active_rounded,
    'Notificações',
    'Mostra as perguntas com respostas rápidas no celular.',
    'Permitir',
  ),
  AppRequirement.locationService: _RequirementInfo(
    Icons.gps_fixed_rounded,
    'GPS ligado',
    'A localização do aparelho precisa estar ativada.',
    'Ativar',
  ),
};

// ─── Views ───────────────────────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: CircularProgressIndicator(color: context.palette.accent),
      ),
    );
  }
}

class _PermissionView extends StatelessWidget {
  final Map<AppRequirement, RequirementStatus> statuses;
  final AppRequirement? next;
  final bool requesting;
  final ValueChanged<AppRequirement> onRequest;

  const _PermissionView({
    required this.statuses,
    required this.next,
    required this.requesting,
    required this.onRequest,
  });

  @override
  Widget build(BuildContext context) {
    final grantedCount =
        statuses.values.where((s) => s == RequirementStatus.granted).length;
    final total = statuses.length;
    final nextReq = next;
    final nextBlocked =
        nextReq != null && statuses[nextReq] == RequirementStatus.blocked;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: context.palette.accent.withValues(alpha: 0.08),
                      border: Border.all(
                        color: context.palette.accent.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Icon(
                      Icons.verified_user_rounded,
                      color: context.palette.accent,
                      size: 36,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Permissões necessárias',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: context.palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'O GeoNexo só funciona com todas as permissões abaixo.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      color: context.palette.textPrimary.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 20),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: grantedCount / total,
                      minHeight: 6,
                      color: context.palette.accent,
                      backgroundColor: context.palette.textPrimary.withValues(alpha: 0.1),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$grantedCount de $total concedidas',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.palette.textPrimary.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(height: 16),
                  for (final req in AppRequirement.values)
                    _RequirementTile(
                      requirement: req,
                      status: statuses[req]!,
                      isNext: req == nextReq,
                      enabled: !requesting,
                      onTap: () => onRequest(req),
                    ),
                ],
              ),
            ),
            if (nextReq != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (nextBlocked)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          'Permissão negada. Abra as configurações do app e '
                          'libere "${_info[nextReq]!.title}".',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: context.palette.warning,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    SizedBox(
                      height: 52,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: context.palette.accent,
                          foregroundColor: context.palette.onAccent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: requesting ? null : () => onRequest(nextReq),
                        child: requesting
                            ? SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: context.palette.onAccent,
                                ),
                              )
                            : Text(
                                nextBlocked
                                    ? 'Abrir configurações'
                                    : 'Continuar: ${_info[nextReq]!.title}',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RequirementTile extends StatelessWidget {
  final AppRequirement requirement;
  final RequirementStatus status;
  final bool isNext;
  final bool enabled;
  final VoidCallback onTap;

  const _RequirementTile({
    required this.requirement,
    required this.status,
    required this.isNext,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final info = _info[requirement]!;
    final granted = status == RequirementStatus.granted;
    final blocked = status == RequirementStatus.blocked;

    final accent = granted
        ? context.palette.success
        : blocked
            ? context.palette.warning
            : context.palette.accent;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: context.palette.textPrimary.withValues(alpha: isNext ? 0.07 : 0.04),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isNext
                ? context.palette.accent.withValues(alpha: 0.5)
                : context.palette.textPrimary.withValues(alpha: 0.08),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: granted || !enabled ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(info.icon, color: accent),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        info.title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: context.palette.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        info.reason,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.3,
                          color: context.palette.textPrimary.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                if (granted)
                  Icon(Icons.check_circle_rounded,
                      color: context.palette.success)
                else
                  Text(
                    blocked ? 'Configurações' : info.action,
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
