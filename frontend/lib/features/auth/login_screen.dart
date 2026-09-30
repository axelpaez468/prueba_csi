import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_shell.dart';
import 'recuperar_password_screen.dart';
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
            // Mismo tono que la barra de navegación del ERP, con un toque del azul de marca.
            colors: [
              AppColors.navbar.withValues(alpha: 0.88),
              AppColors.primaryDark.withValues(alpha: 0.80),
              AppColors.primary.withValues(alpha: 0.62),
            ],
            stops: const [0, 0.6, 1],
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
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _ocultarPassword = true;
  bool _recordar = false;
  bool _mayusculas = false;

  @override
  void initState() {
    super.initState();
    final recordado = context.read<SessionController>().emailRecordado;
    if (recordado != null) {
      _email.text = recordado;
      _recordar = true;
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _enviar() {
    if (!_formKey.currentState!.validate()) return;
    context.read<SessionController>().login(_email.text, _password.text, recordar: _recordar);
  }

  /// Aviso de Bloq Mayús: se revisa en cada tecla mientras se escribe la contraseña.
  KeyEventResult _alTeclear(FocusNode _, KeyEvent _) {
    final activo = HardwareKeyboard.instance.lockModesEnabled.contains(KeyboardLockMode.capsLock);
    if (activo != _mayusculas) setState(() => _mayusculas = activo);
    return KeyEventResult.ignored;
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
            Text('Ingresa con tu correo corporativo.',
                style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 32),
            const _Etiqueta('Correo electrónico'),
            TextFormField(
              controller: _email,
              enabled: !session.procesando,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email, AutofillHints.username],
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                hintText: 'nombre@empresa.com',
                prefixIcon: Icon(Icons.mail_outline),
              ),
              validator: (v) {
                final t = v?.trim() ?? '';
                if (t.isEmpty) return 'Ingresa tu correo';
                if (!t.contains('@') || t.contains(' ')) return 'Ingresa un correo válido';
                return null;
              },
            ),
            const SizedBox(height: 18),
            const _Etiqueta('Contraseña'),
            Focus(
              onKeyEvent: _alTeclear,
              child: TextFormField(
                controller: _password,
                enabled: !session.procesando,
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
            ),
            if (_mayusculas)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  key: const Key('aviso-mayusculas'),
                  children: [
                    const Icon(Icons.keyboard_capslock, size: 16, color: AppColors.warning),
                    const SizedBox(width: 6),
                    Text('Bloq Mayús está activado',
                        style: theme.textTheme.bodySmall?.copyWith(color: AppColors.warning)),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: 4,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 260),
                  child: Casilla(
                    valor: _recordar,
                    alCambiar: session.procesando ? null : (v) => setState(() => _recordar = v),
                    texto: 'Recordar mi correo',
                  ),
                ),
                TextButton(
                  onPressed: session.procesando
                      ? null
                      : () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => RecuperarPasswordScreen(emailInicial: _email.text.trim()))),
                  child: const Text('¿Olvidaste tu contraseña?'),
                ),
              ],
            ),
            if (session.error != null) ...[
              const SizedBox(height: 12),
              InlineBanner.error(session.error!, key: const Key('login-error')),
            ],
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: session.procesando ? null : _enviar,
              child: session.procesando
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
