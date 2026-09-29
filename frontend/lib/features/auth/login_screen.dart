import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_shell.dart';
import 'session_controller.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.sizeOf(context).width;

    return Scaffold(
      body: Row(
        children: [
          if (ancho >= 900) const Expanded(flex: 5, child: _PanelMarca()),
          Expanded(
            flex: 4,
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(ancho < Breakpoints.compacto ? 16 : 32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  // Tarjeta del formulario: esquinas redondeadas y sombra suave en dos capas
                  // (una amplia y difusa para la elevación, otra corta para definir el borde).
                  child: Container(
                    padding: EdgeInsets.all(ancho < Breakpoints.compacto ? 24 : 36),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.border),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.10),
                          blurRadius: 40,
                          offset: const Offset(0, 16),
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const _FormularioLogin(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelMarca extends StatelessWidget {
  const _PanelMarca();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const blanco70 = Color(0xB3FFFFFF);

    // Foto de un almacén de fondo, con un velo azul degradado encima: aporta contexto (inventario, pedidos)
    // sin competir con el texto, que necesita contraste suficiente para leerse en blanco.
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.primaryDark,
        image: DecorationImage(
          image: AssetImage('assets/fondos/login-almacen.jpg'),
          fit: BoxFit.cover,
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.primary.withValues(alpha: 0.74),
              AppColors.primaryDark.withValues(alpha: 0.90),
            ],
          ),
        ),
        child: _cuerpo(theme, blanco70),
      ),
    );
  }

  // Desplazable y con altura mínima = pantalla: en ventanas bajas no se desborda.
  Widget _cuerpo(ThemeData theme, Color blanco70) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.all(48),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight - 96),
          child: IntrinsicHeight(child: _contenido(theme, blanco70)),
        ),
      ),
    );
  }

  Widget _contenido(ThemeData theme, Color blanco70) {
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BrandLogo(claro: true),
          const Spacer(),
          Text(
            'Gestión de pedidos\npara tu equipo de ventas',
            style: theme.textTheme.headlineMedium?.copyWith(color: Colors.white, height: 1.25),
          ),
          const SizedBox(height: 16),
          Text(
            'Consulta el catálogo en tiempo real, arma pedidos en segundos y '
            'confirma con precios y existencias siempre actualizados.',
            style: theme.textTheme.bodyLarge?.copyWith(color: blanco70, height: 1.5),
          ),
          const SizedBox(height: 32),
          for (final (icono, texto) in const [
            (Icons.inventory_outlined, 'Existencias actualizadas al instante'),
            (Icons.verified_user_outlined, 'Precios oficiales calculados por el sistema'),
            (Icons.bolt_outlined, 'Confirmación inmediata del pedido'),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                children: [
                  Icon(icono, color: Colors.white, size: 20),
                  const SizedBox(width: 12),
                  Flexible(child: Text(texto, style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white))),
                ],
              ),
            ),
          const Spacer(),
          Text('© ${DateTime.now().year} Sistema de Pedidos',
              style: theme.textTheme.bodySmall?.copyWith(color: blanco70)),        ],
    );
  }
}

class _FormularioLogin extends StatefulWidget {
  const _FormularioLogin();

  @override
  State<_FormularioLogin> createState() => _FormularioLoginState();
}

class _FormularioLoginState extends State<_FormularioLogin> {
  final _formKey = GlobalKey<FormState>();
  final _usuario = TextEditingController();
  final _password = TextEditingController();
  bool _ocultarPassword = true;

  @override
  void dispose() {
    _usuario.dispose();
    _password.dispose();
    super.dispose();
  }

  void _enviar() {
    if (!_formKey.currentState!.validate()) return;
    context.read<SessionController>().login(_usuario.text, _password.text);
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final theme = Theme.of(context);
    final estrecho = MediaQuery.sizeOf(context).width < 900;

    return Form(
      key: _formKey,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (estrecho) ...[const Align(alignment: Alignment.centerLeft, child: BrandLogo()), const SizedBox(height: 40)],
            Text('Iniciar sesión', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 6),
            Text('Ingresa tus credenciales para continuar.',
                style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 32),
            const _Etiqueta('Usuario'),
            TextFormField(
              controller: _usuario,
              enabled: !session.loggingIn,
              autofillHints: const [AutofillHints.username],
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                hintText: 'Tu nombre de usuario',
                prefixIcon: Icon(Icons.person_outline),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Ingresa tu usuario' : null,
            ),
            const SizedBox(height: 18),
            const _Etiqueta('Contraseña'),
            TextFormField(
              controller: _password,
              enabled: !session.loggingIn,
              obscureText: _ocultarPassword,
              autofillHints: const [AutofillHints.password],
              onFieldSubmitted: (_) => _enviar(),
              decoration: InputDecoration(
                hintText: 'Tu contraseña',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  tooltip: _ocultarPassword ? 'Mostrar' : 'Ocultar',
                  icon: Icon(_ocultarPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _ocultarPassword = !_ocultarPassword),
                ),
              ),
              validator: (v) => (v == null || v.isEmpty) ? 'Ingresa tu contraseña' : null,
            ),
            if (session.error != null) ...[
              const SizedBox(height: 20),
              InlineBanner.error(session.error!, key: const Key('login-error')),
            ],
            const SizedBox(height: 28),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: session.loggingIn ? null : _enviar,
              child: session.loggingIn
                  ? const SizedBox.square(
                      dimension: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Ingresar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Etiqueta extends StatelessWidget {
  const _Etiqueta(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(texto, style: Theme.of(context).textTheme.labelLarge),
      );
}
