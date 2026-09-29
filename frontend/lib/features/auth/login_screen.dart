import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'session_controller.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
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

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Icon(Icons.storefront, size: 48, color: theme.colorScheme.primary),
                        const SizedBox(height: 8),
                        Text('Sistema de Pedidos',
                            textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
                        const SizedBox(height: 24),
                        TextFormField(
                          controller: _usuario,
                          enabled: !session.loggingIn,
                          autofillHints: const [AutofillHints.username],
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Usuario',
                            prefixIcon: Icon(Icons.person_outline),
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Ingrese su usuario' : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _password,
                          enabled: !session.loggingIn,
                          obscureText: _ocultarPassword,
                          autofillHints: const [AutofillHints.password],
                          onFieldSubmitted: (_) => _enviar(),
                          decoration: InputDecoration(
                            labelText: 'Contraseña',
                            prefixIcon: const Icon(Icons.lock_outline),
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              tooltip: _ocultarPassword ? 'Mostrar' : 'Ocultar',
                              icon: Icon(_ocultarPassword ? Icons.visibility : Icons.visibility_off),
                              onPressed: () => setState(() => _ocultarPassword = !_ocultarPassword),
                            ),
                          ),
                          validator: (v) => (v == null || v.isEmpty) ? 'Ingrese su contraseña' : null,
                        ),
                        if (session.error != null) ...[
                          const SizedBox(height: 16),
                          Text(
                            session.error!,
                            key: const Key('login-error'),
                            style: TextStyle(color: theme.colorScheme.error),
                            textAlign: TextAlign.center,
                          ),
                        ],
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: session.loggingIn ? null : _enviar,
                          child: session.loggingIn
                              ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Text('Ingresar'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
