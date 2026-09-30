import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_shell.dart';
import 'auth_layout.dart';
import 'session_controller.dart';

/// Paso 2 del login: código de la app autenticadora, del SMS o un código de respaldo.
class SegundoFactorScreen extends StatefulWidget {
  const SegundoFactorScreen({super.key});

  @override
  State<SegundoFactorScreen> createState() => _SegundoFactorScreenState();
}

class _SegundoFactorScreenState extends State<SegundoFactorScreen> {
  static const _esperaReenvio = 30;

  final _codigo = TextEditingController();
  bool _usarRespaldo = false;
  bool _confiar = false;
  int _segundosParaReenviar = _esperaReenvio;
  Timer? _temporizador;

  @override
  void initState() {
    super.initState();
    if (context.read<SessionController>().desafio?.esSms ?? false) _iniciarCuentaRegresiva();
  }

  @override
  void dispose() {
    _temporizador?.cancel();
    _codigo.dispose();
    super.dispose();
  }

  void _iniciarCuentaRegresiva() {
    _temporizador?.cancel();
    setState(() => _segundosParaReenviar = _esperaReenvio);
    _temporizador = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _segundosParaReenviar--);
      if (_segundosParaReenviar <= 0) t.cancel();
    });
  }

  bool get _codigoCompleto {
    final t = _codigo.text.trim();
    return _usarRespaldo ? t.length == 11 : t.length == 6;
  }

  void _verificar() {
    if (!_codigoCompleto) return;
    context.read<SessionController>().verificarCodigo(_codigo.text, confiarDispositivo: _confiar);
  }

  Future<void> _reenviar() async {
    await context.read<SessionController>().reenviarCodigo();
    if (mounted && context.read<SessionController>().error == null) _iniciarCuentaRegresiva();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final desafio = session.desafio;
    final theme = Theme.of(context);
    if (desafio == null) return const SizedBox.shrink();

    final instruccion = _usarRespaldo
        ? 'Escribe uno de tus códigos de respaldo (formato XXXXX-XXXXX). Cada código funciona una sola vez.'
        : desafio.esSms
            ? 'Enviamos un código de 6 dígitos por SMS al ${desafio.destino ?? 'teléfono registrado'}.'
            : 'Abre tu app autenticadora (Google o Microsoft Authenticator) y escribe el código de 6 dígitos.';

    return AuthTarjeta(
      icono: desafio.esSms ? Icons.sms_outlined : Icons.phonelink_lock_outlined,
      titulo: 'Verificación en dos pasos',
      subtitulo: instruccion,
      alVolver: session.procesando ? null : session.cancelarSegundoFactor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('campo-codigo'),
            controller: _codigo,
            autofocus: true,
            enabled: !session.procesando,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(letterSpacing: _usarRespaldo ? 2 : 10),
            keyboardType: _usarRespaldo ? TextInputType.text : TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            textCapitalization: TextCapitalization.characters,
            inputFormatters: _usarRespaldo
                ? [LengthLimitingTextInputFormatter(11)]
                : [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
            decoration: InputDecoration(hintText: _usarRespaldo ? 'XXXXX-XXXXX' : '000000'),
            onChanged: (_) {
              setState(() {});
              if (!_usarRespaldo && _codigoCompleto) _verificar(); // se envía solo al completar los 6 dígitos
            },
            onSubmitted: (_) => _verificar(),
          ),
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
          if (session.aviso != null) ...[
            const SizedBox(height: 8),
            _AvisoExito(session.aviso!),
          ],
          const SizedBox(height: 20),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: session.procesando || !_codigoCompleto ? null : _verificar,
            child: session.procesando
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Verificar'),
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              TextButton(
                onPressed: session.procesando
                    ? null
                    : () => setState(() {
                          _usarRespaldo = !_usarRespaldo;
                          _codigo.clear();
                          session.limpiarMensajes();
                        }),
                child: Text(_usarRespaldo ? 'Usar el código de verificación' : 'Usar un código de respaldo'),
              ),
              if (desafio.esSms && !_usarRespaldo)
                TextButton(
                  onPressed: session.procesando || _segundosParaReenviar > 0 ? null : _reenviar,
                  child: Text(_segundosParaReenviar > 0 ? 'Reenviar en $_segundosParaReenviar s' : 'Reenviar código'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AvisoExito extends StatelessWidget {
  const _AvisoExito(this.mensaje);

  final String mensaje;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppColors.successBg, borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          const Icon(Icons.check_circle_outline, color: AppColors.success, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(mensaje, style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w500))),
        ]),
      );
}
