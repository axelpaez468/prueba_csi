import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_shell.dart';
import '../../data/models/seguridad.dart';
import '../../data/repositories/cuenta_repository.dart';

/// Estructura común de los diálogos: título, contenido desplazable y acciones; ancho acotado.
class _Dialogo extends StatelessWidget {
  const _Dialogo({required this.titulo, required this.contenido, required this.acciones});

  final String titulo;
  final Widget contenido;
  final List<Widget> acciones;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(titulo),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(child: contenido),
        ),
        actions: acciones,
      );
}

Widget _campoCodigo(TextEditingController c, {required bool enabled, VoidCallback? alCompletar}) => TextField(
      controller: c,
      enabled: enabled,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 22, letterSpacing: 8, fontWeight: FontWeight.w600),
      keyboardType: TextInputType.number,
      autofillHints: const [AutofillHints.oneTimeCode],
      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
      decoration: const InputDecoration(hintText: '000000'),
      onSubmitted: (_) => alCompletar?.call(),
    );

// ---------- App autenticadora (TOTP) ----------

/// Muestra el QR para escanear con la app y confirma con el primer código. Devuelve los códigos de respaldo.
class ConfigurarTotpDialog extends StatefulWidget {
  const ConfigurarTotpDialog({super.key});

  @override
  State<ConfigurarTotpDialog> createState() => _ConfigurarTotpDialogState();
}

class _ConfigurarTotpDialogState extends State<ConfigurarTotpDialog> {
  final _codigo = TextEditingController();
  ConfiguracionTotp? _config;
  bool _trabajando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  @override
  void dispose() {
    _codigo.dispose();
    super.dispose();
  }

  Future<void> _iniciar() async {
    try {
      final c = await context.read<CuentaRepository>().iniciarTotp();
      setState(() => _config = c);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  Future<void> _confirmar() async {
    if (_trabajando || _codigo.text.length != 6) return;
    setState(() {
      _trabajando = true;
      _error = null;
    });
    try {
      final codigos = await context.read<CuentaRepository>().confirmarTotp(_codigo.text);
      if (mounted) Navigator.of(context).pop(codigos);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  /// "JBSW Y3DP EHPK 3PXP": más fácil de copiar a mano si la cámara no está disponible.
  String _agrupar(String s) => [for (var i = 0; i < s.length; i += 4) s.substring(i, (i + 4).clamp(0, s.length))].join(' ');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final config = _config;

    return _Dialogo(
      titulo: 'Configurar app autenticadora',
      contenido: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('1. Escanea este código con Google Authenticator, Microsoft Authenticator u otra app compatible.',
              style: theme.textTheme.bodyMedium),
          const SizedBox(height: 16),
          Center(
            child: config == null
                ? const SizedBox.square(dimension: 180, child: Center(child: CircularProgressIndicator()))
                : Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    // El QR se genera en el navegador: el secreto no se envía a ningún servicio externo.
                    child: QrImageView(key: const Key('qr-totp'), data: config.uri, size: 180),
                  ),
          ),
          if (config != null) ...[
            const SizedBox(height: 12),
            Text('¿No puedes escanearlo? Escribe esta clave en la app:',
                style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            SelectableText(_agrupar(config.secreto),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall?.copyWith(fontFamily: 'monospace', letterSpacing: 1)),
          ],
          const SizedBox(height: 20),
          Text('2. Escribe el código de 6 dígitos que muestra la app.', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 8),
          _campoCodigo(_codigo, enabled: config != null && !_trabajando, alCompletar: _confirmar),
          if (_error != null) ...[const SizedBox(height: 12), InlineBanner.error(_error!)],
        ],
      ),
      acciones: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(onPressed: config == null || _trabajando ? null : _confirmar, child: const Text('Activar')),
      ],
    );
  }
}

// ---------- SMS ----------

class ConfigurarSmsDialog extends StatefulWidget {
  const ConfigurarSmsDialog({super.key});

  @override
  State<ConfigurarSmsDialog> createState() => _ConfigurarSmsDialogState();
}

class _ConfigurarSmsDialogState extends State<ConfigurarSmsDialog> {
  final _telefono = TextEditingController(text: '+502');
  final _codigo = TextEditingController();
  bool _codigoEnviado = false;
  bool _trabajando = false;
  String? _error;

  @override
  void dispose() {
    _telefono.dispose();
    _codigo.dispose();
    super.dispose();
  }

  Future<void> _ejecutar(Future<void> Function() accion) async {
    if (_trabajando) return;
    setState(() {
      _trabajando = true;
      _error = null;
    });
    try {
      await accion();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  void _enviar() => _ejecutar(() async {
        await context.read<CuentaRepository>().iniciarSms(_telefono.text.trim());
        setState(() => _codigoEnviado = true);
      });

  void _confirmar() => _ejecutar(() async {
        final codigos = await context.read<CuentaRepository>().confirmarSms(_codigo.text);
        if (mounted) Navigator.of(context).pop(codigos);
      });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Dialogo(
      titulo: 'Verificación por SMS',
      contenido: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Te enviaremos un código cada vez que inicies sesión.', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 16),
          TextField(
            controller: _telefono,
            enabled: !_codigoEnviado && !_trabajando,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
            decoration: const InputDecoration(
              labelText: 'Teléfono con código de país',
              hintText: '+50255550101',
              prefixIcon: Icon(Icons.phone_iphone),
            ),
          ),
          if (_codigoEnviado) ...[
            const SizedBox(height: 16),
            Text('Escribe el código que recibiste por SMS.', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            _campoCodigo(_codigo, enabled: !_trabajando, alCompletar: _confirmar),
          ],
          if (_error != null) ...[const SizedBox(height: 12), InlineBanner.error(_error!)],
        ],
      ),
      acciones: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        if (_codigoEnviado)
          FilledButton(onPressed: _trabajando ? null : _confirmar, child: const Text('Activar'))
        else
          FilledButton(onPressed: _trabajando ? null : _enviar, child: const Text('Enviar código')),
      ],
    );
  }
}

// ---------- Códigos de respaldo ----------

/// Se muestran una sola vez: el servidor solo guarda su huella. Obliga a confirmar que se guardaron.
class CodigosRespaldoDialog extends StatefulWidget {
  const CodigosRespaldoDialog({super.key, required this.codigos});

  final List<String> codigos;

  @override
  State<CodigosRespaldoDialog> createState() => _CodigosRespaldoDialogState();
}

class _CodigosRespaldoDialogState extends State<CodigosRespaldoDialog> {
  bool _guardados = false;
  bool _copiados = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Dialogo(
      titulo: 'Guarda tus códigos de respaldo',
      contenido: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const InlineBanner.info(
              'Úsalos si pierdes tu teléfono. Cada código funciona una sola vez y no volverán a mostrarse.'),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(10)),
            child: Wrap(
              spacing: 16,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final c in widget.codigos)
                  SelectableText(c, style: theme.textTheme.titleSmall?.copyWith(fontFamily: 'monospace', letterSpacing: 1)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: widget.codigos.join('\n')));
                setState(() => _copiados = true);
              },
              icon: Icon(_copiados ? Icons.check : Icons.copy, size: 18),
              label: Text(_copiados ? 'Copiados' : 'Copiar todos'),
            ),
          ),
          CheckboxListTile(
            value: _guardados,
            onChanged: (v) => setState(() => _guardados = v ?? false),
            title: const Text('Los guardé en un lugar seguro'),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
      acciones: [
        FilledButton(onPressed: _guardados ? () => Navigator.of(context).pop() : null, child: const Text('Listo')),
      ],
    );
  }
}

// ---------- Confirmación con contraseña ----------

/// Acciones sensibles (desactivar el 2FA, regenerar códigos) piden la contraseña actual.
Future<String?> pedirPassword(BuildContext context, {required String titulo, required String accion}) {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => _Dialogo(
      titulo: titulo,
      contenido: TextField(
        controller: c,
        autofocus: true,
        obscureText: true,
        autofillHints: const [AutofillHints.password],
        decoration: const InputDecoration(labelText: 'Contraseña actual', prefixIcon: Icon(Icons.lock_outline)),
        onSubmitted: (_) => Navigator.of(ctx).pop(c.text),
      ),
      acciones: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.of(ctx).pop(c.text), child: Text(accion)),
      ],
    ),
  ).whenComplete(c.dispose);
}
