import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/security/session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/formatters.dart';
import '../../core/widgets/app_shell.dart';
import '../../data/models/seguridad.dart';
import '../../data/repositories/cuenta_repository.dart';
import '../auth/restablecer_password_screen.dart';
import '../auth/session_controller.dart';
import '../shell/app_top_bar.dart';
import 'dialogos_2fa.dart';

/// "Seguridad de la cuenta": verificación en dos pasos, contraseña y accesos recientes.
class SeguridadScreen extends StatefulWidget {
  const SeguridadScreen({super.key});

  @override
  State<SeguridadScreen> createState() => _SeguridadScreenState();
}

class _SeguridadScreenState extends State<SeguridadScreen> {
  EstadoSeguridad? _estado;
  List<RegistroAcceso> _accesos = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  CuentaRepository get _repo => context.read<CuentaRepository>();

  Future<void> _cargar() async {
    try {
      final estado = await _repo.estado();
      final accesos = await _repo.misAccesos();
      if (mounted) {
        setState(() {
          _estado = estado;
          _accesos = accesos;
          _error = null;
        });
      }
    } on UnauthorizedException {
      // La app vuelve al login.
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on TypeError {
      if (mounted) setState(() => _error = ApiClient.respuestaInesperada);
    }
  }

  void _avisar(String mensaje) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(mensaje)));

  Future<void> _mostrarCodigos(List<String>? codigos) async {
    if (codigos == null || !mounted) return;
    await showDialog<void>(
        context: context, barrierDismissible: false, builder: (_) => CodigosRespaldoDialog(codigos: codigos));
    await _cargar();
  }

  Future<void> _configurarTotp() async =>
      _mostrarCodigos(await showDialog<List<String>>(context: context, builder: (_) => const ConfigurarTotpDialog()));


  Future<void> _regenerar() async {
    final password = await pedirPassword(context, titulo: 'Regenerar códigos de respaldo', accion: 'Regenerar');
    if (password == null || password.isEmpty) return;
    try {
      await _mostrarCodigos(await _repo.regenerarCodigos(password));
    } on ApiException catch (e) {
      _avisar(e.message);
    }
  }

  Future<void> _desactivar() async {
    final session = context.read<SessionController>();
    final password = await pedirPassword(context, titulo: 'Desactivar verificación en dos pasos', accion: 'Desactivar');
    if (password == null || password.isEmpty) return;
    try {
      await session.actualizarSesion(await _repo.desactivar(password)); // token nuevo: el anterior quedó invalidado
      _avisar('Se desactivó la verificación en dos pasos.');
      await _cargar();
    } on ApiException catch (e) {
      _avisar(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.sizeOf(context).width;
    final margen = Breakpoints.esCompacto(context) ? 16.0 : 24.0;
    final estado = _estado;

    final izquierda = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TarjetaDosFactor(
          estado: estado,
          alConfigurarTotp: _configurarTotp,
          alRegenerar: _regenerar,
          alDesactivar: _desactivar,
        ),
        const SizedBox(height: 20),
        _TarjetaPassword(alCambiar: (s) async {
          await context.read<SessionController>().actualizarSesion(s);
          _avisar('Contraseña actualizada. Se cerraron las sesiones en otros dispositivos.');
          await _cargar();
        }),
      ],
    );
    final derecha = _TarjetaAccesos(accesos: _accesos);

    return Scaffold(
      appBar: AppTopBar(
        leading: IconButton(
          tooltip: 'Volver',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: SingleChildScrollView(
        child: PageBody(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                titulo: 'Seguridad de la cuenta',
                subtitulo: estado?.email ?? 'Verificación en dos pasos, contraseña y accesos recientes',
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(margen, 0, margen, 32),
                child: _error != null
                    ? InlineBanner.error(_error!, alReintentar: _cargar)
                    : ancho >= Breakpoints.amplio
                        ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Expanded(child: izquierda),
                            const SizedBox(width: 24),
                            Expanded(child: derecha),
                          ])
                        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            izquierda,
                            const SizedBox(height: 20),
                            derecha,
                          ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Seccion extends StatelessWidget {
  const _Seccion({required this.icono, required this.titulo, required this.child, this.accion});

  final IconData icono;
  final String titulo;
  final Widget child;
  final Widget? accion;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Icon(icono, color: AppColors.primary),
                const SizedBox(width: 10),
                Expanded(child: Text(titulo, style: Theme.of(context).textTheme.titleMedium)),
                ?accion,
              ]),
              const SizedBox(height: 16),
              child,
            ],
          ),
        ),
      );
}

class _TarjetaDosFactor extends StatelessWidget {
  const _TarjetaDosFactor({
    required this.estado,
    required this.alConfigurarTotp,
    required this.alRegenerar,
    required this.alDesactivar,
  });

  final EstadoSeguridad? estado;
  final VoidCallback alConfigurarTotp;
  final VoidCallback alRegenerar;
  final VoidCallback alDesactivar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final e = estado;
    final secundario = theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary);

    return _Seccion(
      icono: Icons.verified_user_outlined,
      titulo: 'Verificación en dos pasos',
      accion: e == null
          ? null
          : e.activo
              ? const StatusPill(texto: 'Activada', color: AppColors.success, fondo: AppColors.successBg, icono: Icons.check)
              : const StatusPill(texto: 'Desactivada', color: AppColors.warning, fondo: AppColors.warningBg),
      child: e == null
          ? const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (e.activo) ...[
                  Text('Método: Google Authenticator.', style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 4),
                  Text('Códigos de respaldo disponibles: ${e.codigosRespaldoRestantes} de 10.', style: secundario),
                  if (e.codigosRespaldoRestantes <= 3) ...[
                    const SizedBox(height: 8),
                    const InlineBanner.info('Te quedan pocos códigos de respaldo. Genera nuevos.'),
                  ],
                ] else
                  Text(
                    'Protege tu cuenta con un código adicional al iniciar sesión, aunque alguien conozca tu contraseña.',
                    style: theme.textTheme.bodyMedium,
                  ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: alConfigurarTotp,
                      icon: const Icon(Icons.qr_code_2, size: 18),
                      label: Text(e.activo ? 'Configurar en otro teléfono' : 'Activar Google Authenticator'),
                    ),
                    if (e.activo)
                      OutlinedButton.icon(
                        onPressed: alRegenerar,
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Nuevos códigos de respaldo'),
                      ),
                    if (e.activo && !e.dosFactorObligatorio)
                      TextButton(
                        onPressed: alDesactivar,
                        style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                        child: const Text('Desactivar'),
                      ),
                  ],
                ),
                if (e.dosFactorObligatorio) ...[
                  const SizedBox(height: 12),
                  Text('La verificación en dos pasos es obligatoria para todos los usuarios.', style: secundario),
                ] else if (!e.activo) ...[
                  const SizedBox(height: 12),
                  Text('Google Authenticator es gratuita (Android y iPhone) y funciona sin conexión.', style: secundario),
                ],
              ],
            ),
    );
  }
}

class _TarjetaPassword extends StatefulWidget {
  const _TarjetaPassword({required this.alCambiar});

  final Future<void> Function(Session sesion) alCambiar;

  @override
  State<_TarjetaPassword> createState() => _TarjetaPasswordState();
}

class _TarjetaPasswordState extends State<_TarjetaPassword> {
  final _formKey = GlobalKey<FormState>();
  final _actual = TextEditingController();
  final _nueva = TextEditingController();
  final _repetir = TextEditingController();
  bool _enviando = false;
  String? _error;

  @override
  void dispose() {
    _actual.dispose();
    _nueva.dispose();
    _repetir.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_enviando || !_formKey.currentState!.validate()) return;
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      final sesion = await context.read<CuentaRepository>().cambiarPassword(_actual.text, _nueva.text);
      _formKey.currentState!.reset();
      for (final c in [_actual, _nueva, _repetir]) {
        c.clear();
      }
      await widget.alCambiar(sesion);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Seccion(
      icono: Icons.password,
      titulo: 'Cambiar contraseña',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _actual,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              decoration: const InputDecoration(labelText: 'Contraseña actual'),
              validator: (v) => (v == null || v.isEmpty) ? 'Requerida' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nueva,
              obscureText: true,
              autofillHints: const [AutofillHints.newPassword],
              decoration: const InputDecoration(labelText: 'Nueva contraseña'),
              validator: (v) => (v == null || v.length < 12) ? 'Usa al menos 12 caracteres' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _repetir,
              obscureText: true,
              autofillHints: const [AutofillHints.newPassword],
              decoration: const InputDecoration(labelText: 'Repite la nueva contraseña'),
              validator: (v) => v != _nueva.text ? 'Las contraseñas no coinciden' : null,
            ),
            const SizedBox(height: 12),
            const RequisitosPassword(),
            if (_error != null) ...[const SizedBox(height: 12), InlineBanner.error(_error!)],
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _enviando ? null : _guardar,
                child: _enviando
                    ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Guardar contraseña'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TarjetaAccesos extends StatelessWidget {
  const _TarjetaAccesos({required this.accesos});

  final List<RegistroAcceso> accesos;

  @override
  Widget build(BuildContext context) => _Seccion(
        icono: Icons.history,
        titulo: 'Actividad reciente',
        child: accesos.isEmpty
            ? const Text('Sin actividad registrada.')
            : Column(children: [for (final a in accesos) FilaAcceso(acceso: a)]),
      );
}

/// Fila de la bitácora (se reutiliza en la pantalla de administración).
class FilaAcceso extends StatelessWidget {
  const FilaAcceso({super.key, required this.acceso, this.mostrarEmail = false});

  final RegistroAcceso acceso;
  final bool mostrarEmail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = acceso;
    final secundario = theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(a.exito ? Icons.check_circle_outline : Icons.error_outline,
              size: 20, color: a.exito ? AppColors.success : AppColors.danger),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a.descripcion, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                if (mostrarEmail) Text(a.email, style: theme.textTheme.bodySmall),
                Text(
                  [formatearFecha(a.fecha), a.dispositivo, a.ip].whereType<String>().join(' · '),
                  style: secundario,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
