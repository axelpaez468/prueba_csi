import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_shell.dart';
import '../../data/models/usuario.dart';
import '../../data/repositories/usuario_repository.dart';

/// Alta o edición de un usuario. Devuelve el usuario guardado (o null si se canceló).
/// Las validaciones aquí son para guiar al usuario; las definitivas las hace el servidor.
class UsuarioFormDialog extends StatefulWidget {
  const UsuarioFormDialog({super.key, this.usuario});

  /// null: alta de un usuario nuevo.
  final Usuario? usuario;

  @override
  State<UsuarioFormDialog> createState() => _UsuarioFormDialogState();
}

class _UsuarioFormDialogState extends State<UsuarioFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _nombre = TextEditingController(text: widget.usuario?.nombre);
  late final _apellido = TextEditingController(text: widget.usuario?.apellido);
  late final _email = TextEditingController(text: widget.usuario?.email);
  late final _telefono = TextEditingController(text: widget.usuario?.telefonoLocal);
  late final _codigo = TextEditingController(text: widget.usuario?.codigoCorporativo);
  late String _rol = widget.usuario?.rol ?? 'VENDEDOR';
  bool _guardando = false;
  String? _error;

  bool get _esAlta => widget.usuario == null;

  static final _nombreValido = RegExp(r"^\p{L}[\p{L}' .\-]{1,59}$", unicode: true);
  static final _emailValido = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$');
  static final _telefonoValido = RegExp(r'^[2-7]\d{7}$');
  static final _codigoValido = RegExp(r'^[A-Z0-9][A-Z0-9\-]{2,19}$');

  @override
  void dispose() {
    for (final c in [_nombre, _apellido, _email, _telefono, _codigo]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_guardando || !_formKey.currentState!.validate()) return;
    setState(() {
      _guardando = true;
      _error = null;
    });
    final datos = DatosUsuario(
      nombre: _nombre.text.trim(),
      apellido: _apellido.text.trim(),
      telefono: _telefono.text,
      email: _email.text.trim(),
      codigoCorporativo: _codigo.text.trim(),
      rol: _rol,
    );
    try {
      final repo = context.read<UsuarioRepository>();
      final guardado = _esAlta ? await repo.crear(datos) : await repo.editar(widget.usuario!.id, datos);
      if (mounted) Navigator.of(context).pop(guardado);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  String? _requerido(String? v, RegExp formato, String mensaje) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return 'Campo obligatorio';
    return formato.hasMatch(t) ? null : mensaje;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final angosto = MediaQuery.sizeOf(context).width < 520;

    final nombre = TextFormField(
      controller: _nombre,
      enabled: !_guardando,
      textCapitalization: TextCapitalization.words,
      decoration: const InputDecoration(labelText: 'Nombre'),
      validator: (v) => _requerido(v, _nombreValido, 'Solo letras (2 a 60)'),
    );
    final apellido = TextFormField(
      controller: _apellido,
      enabled: !_guardando,
      textCapitalization: TextCapitalization.words,
      decoration: const InputDecoration(labelText: 'Apellido'),
      validator: (v) => _requerido(v, _nombreValido, 'Solo letras (2 a 60)'),
    );

    return AlertDialog(
      title: Text(_esAlta ? 'Nuevo usuario' : 'Editar usuario'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (angosto) ...[nombre, const SizedBox(height: 12), apellido]
                else
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: nombre),
                    const SizedBox(width: 12),
                    Expanded(child: apellido),
                  ]),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _email,
                  enabled: !_guardando,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Correo electrónico', prefixIcon: Icon(Icons.mail_outline)),
                  validator: (v) => _requerido(v, _emailValido, 'Correo no válido'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _telefono,
                  enabled: !_guardando,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
                  decoration: const InputDecoration(
                    labelText: 'Número de teléfono',
                    prefixIcon: Icon(Icons.phone_outlined),
                    prefixText: '+502 ',
                    hintText: '55550101',
                  ),
                  validator: (v) => _requerido(v, _telefonoValido, '8 dígitos de Guatemala (empieza con 2 a 7)'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _codigo,
                  enabled: !_guardando,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\-]')),
                    LengthLimitingTextInputFormatter(20),
                    TextInputFormatter.withFunction((_, n) => n.copyWith(text: n.text.toUpperCase())),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Código corporativo',
                    prefixIcon: Icon(Icons.badge_outlined),
                    hintText: 'VEN-0002',
                  ),
                  validator: (v) => _requerido(v?.toUpperCase(), _codigoValido, '3 a 20 letras, números o guiones'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _rol,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Rol', prefixIcon: Icon(Icons.admin_panel_settings_outlined)),
                  items: const [
                    DropdownMenuItem(value: 'VENDEDOR', child: Text('Vendedor')),
                    DropdownMenuItem(value: 'ADMIN', child: Text('Administrador')),
                  ],
                  onChanged: _guardando ? null : (v) => setState(() => _rol = v ?? 'VENDEDOR'),
                ),
                if (_rol == 'ADMIN') ...[
                  const SizedBox(height: 8),
                  Text('Los administradores inician sesión con un código por SMS a este teléfono.',
                      style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
                ],
                if (_esAlta) ...[
                  const SizedBox(height: 16),
                  const InlineBanner.info(
                      'Le enviaremos un correo de invitación para que cree su propia contraseña (el enlace vence en 48 horas).'),
                ],
                if (_error != null) ...[const SizedBox(height: 12), InlineBanner.error(_error!)],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _guardando ? null : () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(
          onPressed: _guardando ? null : _guardar,
          child: _guardando
              ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(_esAlta ? 'Crear y enviar invitación' : 'Guardar cambios'),
        ),
      ],
    );
  }
}
