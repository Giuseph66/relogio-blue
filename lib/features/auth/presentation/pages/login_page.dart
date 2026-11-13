import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../../core/auth/auth_service.dart';
import '../../../../core/theme/app_palette.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _errorMsg;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _loading = true;
      _errorMsg = null;
    });

    await Future.delayed(const Duration(milliseconds: 600));
    final ok = await AuthService().login(_emailCtrl.text, _passwordCtrl.text);

    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pushReplacementNamed('/dashboard');
    } else {
      setState(() {
        _loading = false;
        _errorMsg = 'Credenciais inválidas. Verifique os dados.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: context.palette.scaffold,
      body: Stack(
        children: [
          // ─── Decorative background elements ─────────────────────────────
          Positioned(
            top: -100,
            left: -100,
            child: _BlurredSphere(
              color: context.palette.accent.withValues(alpha: 0.18),
              size: 320,
            ),
          ),
          Positioned(
            bottom: -50,
            right: -80,
            child: _BlurredSphere(
              color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.14),
              size: 280,
            ),
          ),
          Positioned(
            top: size.height * 0.4,
            right: -120,
            child: _BlurredSphere(
              color: context.palette.accent.withValues(alpha: 0.08),
              size: 200,
            ),
          ),

          // ─── Main Content ───────────────────────────────────────────────
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(32),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 1000),
                  curve: Curves.easeOutBack,
                  builder: (context, value, child) {
                    return Opacity(
                      opacity: value.clamp(0.0, 1.0),
                      child: Transform.translate(
                        offset: Offset(0, 30 * (1 - value)),
                        child: child,
                      ),
                    );
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ─── Logo ─────────────────────────────────────────────
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: context.palette.textPrimary.withValues(alpha: 0.03),
                          border: Border.all(
                            color: context.palette.accent.withValues(alpha: 0.2),
                            width: 1.5,
                          ),
                        ),
                        child: Icon(
                          Icons.watch_rounded,
                          size: 64,
                          color: context.palette.accent,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'GeoNexo',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          color: context.palette.textPrimary,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'GeoNexo Admin',
                        style: TextStyle(
                          color: context.palette.textPrimary.withValues(alpha: 0.5),
                          fontSize: 15,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 48),

                      // ─── Glass Login Container ────────────────────────────
                      ClipRRect(
                        borderRadius: BorderRadius.circular(32),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                          child: Container(
                            padding: const EdgeInsets.all(32),
                            decoration: BoxDecoration(
                              color: context.palette.textPrimary.withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(32),
                              border: Border.all(
                                color: context.palette.textPrimary.withValues(alpha: 0.08),
                                width: 1.2,
                              ),
                            ),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _buildField(
                                    controller: _emailCtrl,
                                    label: 'E-mail',
                                    icon: Icons.alternate_email_rounded,
                                    type: TextInputType.emailAddress,
                                  ),
                                  const SizedBox(height: 20),
                                  _buildField(
                                    controller: _passwordCtrl,
                                    label: 'Senha',
                                    icon: Icons.lock_person_outlined,
                                    obscure: _obscure,
                                    suffix: IconButton(
                                      icon: Icon(
                                        _obscure 
                                            ? Icons.visibility_off_outlined
                                            : Icons.visibility_outlined,
                                        color: context.palette.textPrimary.withValues(alpha: 0.38),
                                        size: 20,
                                      ),
                                      onPressed: () => setState(() => _obscure = !_obscure),
                                    ),
                                  ),

                                  if (_errorMsg != null)
                                    _ErrorBanner(message: _errorMsg!),

                                  const SizedBox(height: 32),

                                  _LoginButton(
                                    loading: _loading,
                                    onPressed: _submit,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 32),

                      // ─── Guest Access ─────────────────────────────────────
                      TextButton(
                        onPressed: () async {
                          await AuthService().logout();
                          if (context.mounted) {
                            Navigator.of(context).pushReplacementNamed('/dashboard');
                          }
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: context.palette.textPrimary.withValues(alpha: 0.38),
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Entrar como Visitante',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                            ),
                            SizedBox(width: 6),
                            Icon(Icons.arrow_forward_rounded, size: 14),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? type,
    bool obscure = false,
    Widget? suffix,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            label,
            style: TextStyle(
              color: context.palette.textPrimary.withValues(alpha: 0.38),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        TextFormField(
          controller: controller,
          obscureText: obscure,
          keyboardType: type,
          style: TextStyle(color: context.palette.textPrimary, fontSize: 15),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: context.palette.accent.withValues(alpha: 0.5), size: 20),
            suffixIcon: suffix,
            filled: true,
            fillColor: Colors.black.withValues(alpha: 0.2),
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: context.palette.textPrimary.withValues(alpha: 0.1)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: context.palette.textPrimary.withValues(alpha: 0.1)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: context.palette.accent, width: 1.5),
            ),
            errorStyle: const TextStyle(height: 0),
          ),
          validator: (v) => (v == null || v.isEmpty) ? '' : null,
        ),
      ],
    );
  }
}

class _BlurredSphere extends StatelessWidget {
  final Color color;
  final double size;

  const _BlurredSphere({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, color.withValues(alpha: 0)],
        ),
      ),
    );
  }
}

class _LoginButton extends StatelessWidget {
  final bool loading;
  final VoidCallback onPressed;

  const _LoginButton({required this.loading, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: [context.palette.accent, Theme.of(context).colorScheme.secondary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: context.palette.accent.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: loading ? null : onPressed,
          borderRadius: BorderRadius.circular(18),
          child: Center(
            child: loading
                ? SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: context.palette.onAccent,
                    ),
                  )
                : Text(
                    'ACESSAR PAINEL',
                    style: TextStyle(
                      color: context.palette.onAccent,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: context.palette.danger.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.palette.danger.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded, color: context.palette.danger, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: context.palette.danger, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
