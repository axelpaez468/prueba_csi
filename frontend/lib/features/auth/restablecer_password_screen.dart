import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_shell.dart';
import '../../data/repositories/auth_repository.dart';
import 'auth_layout.dart';

/// Se abre desde el enlace del correo (?restablecer=TOKEN) para definir una nueva contraseña.
/// Con la invitación de un usuario nuevo (&invitacion=1) es la bienvenida: crea su primera contraseña.
class RestablecerPasswordScreen extends StatefulWidget {
  const RestablecerPasswordScreen({super.key, required this.token, required this.alTerminar, this.esInvitacion = false});

  final String token;

  /// Usuario invitado por el administrador que aún no tiene contraseña.
  final bool esInvitacion;

  /// Vuelve al inicio de sesión (tras restablecer o si el enlace no sirve).
  final VoidCallback alTerminar;

  @override
  State<RestablecerPasswordScreen> createState() => _RestablecerPasswordScreenState();
}

class _RestablecerPasswordScreenState extends State<RestablecerPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nueva = TextEditingController();
  final _confirmacion = TextEditingController();
  bool _ocultar = true;
  bool _enviando = false;
  String? _error;
  String? _exito;

  @override
  void dispose() {
    _nueva.dispose();
    _confirmacion.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (_enviando || !_formKey.currentState!.validate()) return;
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      final mensaje = await context.read<AuthRepository>().restablecerPassword(widget.token, _nueva.text);
      setState(() => _exito = mensaje);
    } on ApiException catch (e) {
      setState(() => _error = e.message); // la política (largo, filtradas...) la valida el servidor
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_exito != null) {
      return AuthTarjeta(
        icono: Icons.check_circle_outline,
        titulo: widget.esInvitacion ? 'Cuenta activada' : 'Contraseña actualizada',
        subtitulo: widget.esInvitacion
            ? 'Ya puedes iniciar sesión con tu correo y tu contraseña. Ten a mano Google Authenticator para configurarlo.'
            : _exito!,
        child: FilledButton(
          key: const Key('ir-a-login'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: widget.alTerminar,
          child: const Text('Ir a iniciar sesión'),
        ),
      );
    }

    return AuthTarjeta(
      icono: Icons.password,
      titulo: widget.esInvitacion ? 'Bienvenido: crea tu contraseña' : 'Crea una nueva contraseña',
      subtitulo: widget.esInvitacion
          ? 'Con tu correo y esta contraseña iniciarás sesión en el Sistema de Pedidos.'
          : 'Al guardarla se cerrarán las sesiones abiertas en otros dispositivos.',
      alVolver: widget.alTerminar,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _nueva,
              obscureText: _ocultar,
              enabled: !_enviando,
              autofillHints: const [AutofillHints.newPassword],
              decoration: InputDecoration(
                hintText: widget.esInvitacion ? 'Contraseña' : 'Nueva contraseña',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  tooltip: _ocultar ? 'Mostrar' : 'Ocultar',
                  icon: Icon(_ocultar ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _ocultar = !_ocultar),
                ),
              ),
              validator: (v) => (v == null || v.length < 12) ? 'Usa al menos 12 caracteres' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _confirmacion,
              obscureText: _ocultar,
              enabled: !_enviando,
              autofillHints: const [AutofillHints.newPassword],
              decoration: const InputDecoration(hintText: 'Repite la contraseña', prefixIcon: Icon(Icons.lock_outline)),
              validator: (v) => v != _nueva.text ? 'Las contraseñas no coinciden' : null,
              onFieldSubmitted: (_) => _enviar(),
            ),
            const SizedBox(height: 12),
            const RequisitosPassword(),
            if (_error != null) ...[const SizedBox(height: 12), InlineBanner.error(_error!)],
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: _enviando ? null : _enviar,
              child: _enviando
                  ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Guardar contraseña'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Recordatorio de la política de contraseñas (la valida el servidor).
class RequisitosPassword extends StatelessWidget {
  const RequisitosPassword({super.key});

  @override
  Widget build(BuildContext context) {
    final estilo = Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final r in const [
          'Al menos 12 caracteres (una frase es más fácil de recordar).',
          'Que no contenga tu correo.',
          'Que no aparezca en filtraciones públicas (se verifica automáticamente).',
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('•  ', style: estilo),
              Expanded(child: Text(r, style: estilo)),
            ]),
          ),
      ],
    );
  }
}
