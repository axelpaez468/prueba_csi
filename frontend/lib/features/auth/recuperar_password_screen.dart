import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_shell.dart';
import '../../data/repositories/auth_repository.dart';
import 'auth_layout.dart';

/// "¿Olvidaste tu contraseña?": envía un enlace de un solo uso al correo.
class RecuperarPasswordScreen extends StatefulWidget {
  const RecuperarPasswordScreen({super.key, this.emailInicial = ''});

  final String emailInicial;

  @override
  State<RecuperarPasswordScreen> createState() => _RecuperarPasswordScreenState();
}

class _RecuperarPasswordScreenState extends State<RecuperarPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.emailInicial);
  bool _enviando = false;
  String? _error;
  String? _confirmacion;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (_enviando || !_formKey.currentState!.validate()) return;
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      final mensaje = await context.read<AuthRepository>().solicitarRecuperacion(_email.text.trim());
      setState(() => _confirmacion = mensaje);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AuthTarjeta(
      icono: Icons.lock_reset,
      titulo: 'Recuperar contraseña',
      subtitulo: _confirmacion == null
          ? 'Escribe tu correo y te enviaremos un enlace para crear una nueva contraseña.'
          : 'Revisa tu bandeja de entrada.',
      alVolver: () => Navigator.of(context).maybePop(),
      child: _confirmacion != null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  key: const Key('recuperacion-enviada'),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: AppColors.successBg, borderRadius: BorderRadius.circular(12)),
                  child: Text(_confirmacion!, style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w500)),
                ),
                const SizedBox(height: 12),
                Text('El enlace vence en 30 minutos y funciona una sola vez. Si no llega, revisa la carpeta de spam.',
                    style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
              ],
            )
          : Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _email,
                    enabled: !_enviando,
                    autofocus: widget.emailInicial.isEmpty,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(hintText: 'nombre@empresa.com', prefixIcon: Icon(Icons.mail_outline)),
                    validator: (v) => (v == null || !v.contains('@')) ? 'Ingresa un correo válido' : null,
                    onFieldSubmitted: (_) => _enviar(),
                  ),
                  if (_error != null) ...[const SizedBox(height: 12), InlineBanner.error(_error!)],
                  const SizedBox(height: 20),
                  FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: _enviando ? null : _enviar,
                    child: _enviando
                        ? const SizedBox.square(
                            dimension: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Enviar enlace'),
                  ),
                ],
              ),
            ),
    );
  }
}
