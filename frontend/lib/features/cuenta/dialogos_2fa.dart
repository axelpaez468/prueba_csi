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
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(child: contenido),
        ),
        actions: acciones,
      );
}

/// Campo para el código de 6 dígitos de Google Authenticator.
class CampoCodigoApp extends StatelessWidget {
  const CampoCodigoApp({super.key, required this.controlador, required this.habilitado, this.alCompletar, this.alCambiar});

  final TextEditingController controlador;
  final bool habilitado;
  final VoidCallback? alCompletar;
  final ValueChanged<String>? alCambiar;

  @override
  Widget build(BuildContext context) => TextField(
        key: const Key('campo-codigo'),
        controller: controlador,
        enabled: habilitado,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(letterSpacing: 10),
        keyboardType: TextInputType.number,
        autofillHints: const [AutofillHints.oneTimeCode],
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
        decoration: const InputDecoration(hintText: '000000'),
        onChanged: alCambiar,
        onSubmitted: (_) => alCompletar?.call(),
      );
}

/// Instrucciones, código QR y clave manual para agregar la cuenta a Google Authenticator.
/// El QR se genera en el navegador: el secreto no se envía a ningún servicio externo.
class QrGoogleAuthenticator extends StatelessWidget {
  const QrGoogleAuthenticator({super.key, required this.uri, required this.secreto});

  final String? uri;
  final String? secreto;

  /// "JBSW Y3DP EHPK 3PXP": más fácil de copiar a mano si la cámara no está disponible.
  static String agrupar(String s) =>
      [for (var i = 0; i < s.length; i += 4) s.substring(i, (i + 4).clamp(0, s.length))].join(' ');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secundario = theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('1. Instala Google Authenticator (gratis en Play Store o App Store) y toca "+" → "Escanear un código QR".',
            style: theme.textTheme.bodyMedium),
        const SizedBox(height: 16),
        Center(
          child: uri == null
              ? const SizedBox.square(dimension: 180, child: Center(child: CircularProgressIndicator()))
              : Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: QrImageView(key: const Key('qr-totp'), data: uri!, size: 180),
                ),
        ),
        if (secreto != null) ...[
          const SizedBox(height: 12),
          Text('¿No puedes escanearlo? Elige "Ingresar una clave de configuración" y escribe:', style: secundario),
          const SizedBox(height: 4),
          SelectableText(agrupar(secreto!),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(fontFamily: 'monospace', letterSpacing: 1)),
        ],
        const SizedBox(height: 20),
        Text('2. Escribe el código de 6 dígitos que muestra la app para "Sistema de Pedidos".',
            style: theme.textTheme.bodyMedium),
      ],
    );
  }
}

/// Lista de códigos de respaldo con botón para copiarlos.
class ListaCodigosRespaldo extends StatefulWidget {
  const ListaCodigosRespaldo({super.key, required this.codigos});

  final List<String> codigos;

  @override
  State<ListaCodigosRespaldo> createState() => _ListaCodigosRespaldoState();
}

class _ListaCodigosRespaldoState extends State<ListaCodigosRespaldo> {
  bool _copiados = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
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
      ],
    );
  }
}

// ---------- Configurar desde "Seguridad de la cuenta" ----------

/// Muestra el QR para escanear con Google Authenticator y confirma con el primer código.
/// Devuelve los códigos de respaldo.
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

  @override
  Widget build(BuildContext context) {
    final config = _config;
    return _Dialogo(
      titulo: 'Configurar Google Authenticator',
      contenido: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          QrGoogleAuthenticator(uri: config?.uri, secreto: config?.secreto),
          const SizedBox(height: 8),
          CampoCodigoApp(controlador: _codigo, habilitado: config != null && !_trabajando, alCompletar: _confirmar),
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

  @override
  Widget build(BuildContext context) => _Dialogo(
        titulo: 'Guarda tus códigos de respaldo',
        contenido: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListaCodigosRespaldo(codigos: widget.codigos),
            Casilla(
              valor: _guardados,
              alCambiar: (v) => setState(() => _guardados = v),
              texto: 'Los guardé en un lugar seguro',
            ),
          ],
        ),
        acciones: [
          FilledButton(onPressed: _guardados ? () => Navigator.of(context).pop() : null, child: const Text('Listo')),
        ],
      );
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
