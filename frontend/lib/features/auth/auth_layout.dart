import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_shell.dart';

/// Tarjeta centrada (mismo estilo que el login) para las pantallas de verificación y recuperación.
class AuthTarjeta extends StatelessWidget {
  const AuthTarjeta({
    super.key,
    required this.icono,
    required this.titulo,
    required this.subtitulo,
    required this.child,
    this.alVolver,
  });

  final IconData icono;
  final String titulo;
  final String subtitulo;
  final Widget child;
  final VoidCallback? alVolver;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compacto = Breakpoints.esCompacto(context);

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(compacto ? 16 : 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: BrandLogo()),
                const SizedBox(height: 24),
                Container(
                  padding: EdgeInsets.all(compacto ? 24 : 36),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.border),
                    boxShadow: [
                      BoxShadow(color: AppColors.primary.withValues(alpha: 0.10), blurRadius: 40, offset: const Offset(0, 16)),
                      BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2)),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(icono, color: AppColors.primary),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(titulo, style: theme.textTheme.headlineSmall),
                      const SizedBox(height: 6),
                      Text(subtitulo, style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary)),
                      const SizedBox(height: 28),
                      child,
                    ],
                  ),
                ),
                if (alVolver != null) ...[
                  const SizedBox(height: 16),
                  Center(
                    child: TextButton.icon(
                      onPressed: alVolver,
                      icon: const Icon(Icons.arrow_back, size: 18),
                      label: const Text('Volver al inicio de sesión'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
