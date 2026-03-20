import 'package:flutter/material.dart';
import '../../../../core/auth/auth_service.dart';

/// Um widget utilitário que só exibe o seu `child` se o usuário estiver autenticado.
/// Caso contrário, exibe o `fallback` (que por padrão é um SizedBox.shrink() vazio).
/// 
/// Como usa o ValueNotifier do AuthService, ele reage automaticamente a login/logout.
class AuthGuard extends StatelessWidget {
  final Widget child;
  final Widget fallback;

  const AuthGuard({
    super.key,
    required this.child,
    this.fallback = const SizedBox.shrink(),
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AuthService().isAuthenticatedNotifier,
      builder: (context, isAuthenticated, _) {
        if (isAuthenticated) {
          return child;
        }
        return fallback;
      },
    );
  }
}
