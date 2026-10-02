import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/widgets/app_shell.dart';
import '../cuenta/dialogos_2fa.dart';
import 'auth_layout.dart';
import 'session_controller.dart';

/// Paso 2 del login con Google Authenticator.
/// - Verificar: código de la app o un código de respaldo.
/// - Configurar (primer ingreso, sin la app): escanear el QR y confirmar el primer código para poder entrar.
class SegundoFactorScreen extends StatefulWidget {
  const SegundoFactorScreen({super.key});

  @override
  State<SegundoFactorScreen> createState() => _SegundoFactorScreenState();
}

class _SegundoFactorScreenState extends State<SegundoFactorScreen> {
  final _codigo = TextEditingController();
  bool _usarRespaldo = false;
  bool _confiar = false;

  @override
  void dispose() {
    _codigo.dispose();
    super.dispose();
  }

  bool get _codigoCompleto {
    final t = _codigo.text.trim();
    return _usarRespaldo ? t.length == 11 : t.length == 6;
  }

  void _verificar() {
    if (!_codigoCompleto) return;
    context.read<SessionController>().verificarCodigo(_codigo.text, confiarDispositivo: _confiar);
  }

  void _alCambiar(String _) {
    setState(() {});
    if (!_usarRespaldo && _codigoCompleto) _verificar(); // se envía solo al completar los 6 dígitos
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final desafio = session.desafio;
    final theme = Theme.of(context);
    if (desafio == null) return const SizedBox.shrink();
    final configurando = desafio.esConfiguracion;

    final campo = _usarRespaldo
        ? TextField(
            key: const Key('campo-respaldo'),
            controller: _codigo,
            autofocus: true,
            enabled: !session.procesando,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(letterSpacing: 2),
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [LengthLimitingTextInputFormatter(11)],
            decoration: const InputDecoration(hintText: 'XXXXX-XXXXX'),
            onChanged: _alCambiar,
            onSubmitted: (_) => _verificar(),
          )
        : CampoCodigoApp(
            controlador: _codigo,
            habilitado: !session.procesando,
            alCambiar: _alCambiar,
            alCompletar: _verificar,
          );

    return AuthTarjeta(
      icono: configurando ? Icons.qr_code_2 : Icons.phonelink_lock_outlined,
      titulo: configurando ? 'Configura la verificación en dos pasos' : 'Verificación en dos pasos',
      subtitulo: configurando
          ? 'Para entrar necesitas Google Authenticator (es obligatorio para todos los usuarios). Solo lo configurarás esta vez.'
          : _usarRespaldo
              ? 'Escribe uno de tus códigos de respaldo (formato XXXXX-XXXXX). Cada código funciona una sola vez.'
              : 'Abre Google Authenticator en tu teléfono y escribe el código de 6 dígitos de "Sistema de Pedidos".',
      alVolver: session.procesando ? null : session.cancelarSegundoFactor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (configurando) ...[
            QrGoogleAuthenticator(uri: desafio.uri, secreto: desafio.secreto),
            const SizedBox(height: 8),
          ],
          campo,
          const SizedBox(height: 12),
          Casilla(
            valor: _confiar,
            alCambiar: session.procesando ? null : (v) => setState(() => _confiar = v),
            texto: 'Confiar en este dispositivo por 30 días',
            detalle: 'No te pediremos el código en este navegador.',
          ),
          if (session.error != null) ...[
            const SizedBox(height: 8),
            InlineBanner.error(session.error!, key: const Key('error-2fa')),
          ],
          const SizedBox(height: 20),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: session.procesando || !_codigoCompleto ? null : _verificar,
            child: session.procesando
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(configurando ? 'Activar y entrar' : 'Verificar'),
          ),
          if (!configurando) ...[
            const SizedBox(height: 12),
            Center(
              child: TextButton(
                onPressed: session.procesando
                    ? null
                    : () => setState(() {
                          _usarRespaldo = !_usarRespaldo;
                          _codigo.clear();
                          session.limpiarMensajes();
                        }),
                child: Text(_usarRespaldo ? 'Usar el código de Google Authenticator' : '¿Perdiste tu teléfono? Usa un código de respaldo'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Tras configurar Google Authenticator en el login: muestra los códigos de respaldo una sola vez antes de entrar.
class CodigosRespaldoNuevosScreen extends StatefulWidget {
  const CodigosRespaldoNuevosScreen({super.key, required this.codigos});

  final List<String> codigos;

  @override
  State<CodigosRespaldoNuevosScreen> createState() => _CodigosRespaldoNuevosScreenState();
}

class _CodigosRespaldoNuevosScreenState extends State<CodigosRespaldoNuevosScreen> {
  bool _guardados = false;

  @override
  Widget build(BuildContext context) => AuthTarjeta(
        icono: Icons.verified_user_outlined,
        titulo: 'Verificación en dos pasos activada',
        subtitulo: 'Guarda estos códigos de respaldo antes de continuar.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListaCodigosRespaldo(codigos: widget.codigos),
            Casilla(
              valor: _guardados,
              alCambiar: (v) => setState(() => _guardados = v),
              texto: 'Los guardé en un lugar seguro',
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('continuar-codigos'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: _guardados ? context.read<SessionController>().codigosRespaldoGuardados : null,
              child: const Text('Continuar'),
            ),
          ],
        ),
      );
}
