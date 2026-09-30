import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/network/api_exception.dart';
import '../../core/widgets/app_shell.dart';
import '../../core/widgets/erp_widgets.dart';
import '../../data/models/erp.dart';

/// Valida el NIT de Guatemala en el navegador (módulo 11; el verificador 10 es "K"). El servidor vuelve a validar.
bool nitValido(String valor) {
  final nit = valor.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
  if (!RegExp(r'^\d{1,12}[0-9K]$').hasMatch(nit)) return false;
  final cuerpo = nit.substring(0, nit.length - 1);
  var suma = 0;
  for (var i = 0; i < cuerpo.length; i++) {
    suma += int.parse(cuerpo[i]) * (cuerpo.length + 1 - i);
  }
  final digito = (11 - suma % 11) % 11;
  return nit[nit.length - 1] == (digito == 10 ? 'K' : '$digito');
}

/// Formulario de cliente o proveedor (comparten NIT, nombre y contacto). Devuelve lo que guardó la API.
class TerceroFormDialog<T> extends StatefulWidget {
  const TerceroFormDialog({
    super.key,
    required this.titulo,
    required this.guardar,
    this.esProveedor = false,
    this.nit,
    this.nombre,
    this.contacto,
    this.direccion,
    this.telefono,
    this.email,
    this.activo = true,
    this.esNuevo = true,
  });

  final String titulo;
  final Future<T> Function(Map<String, dynamic> datos) guardar;
  final bool esProveedor;
  final String? nit;
  final String? nombre;
  final String? contacto;
  final String? direccion;
  final String? telefono;
  final String? email;
  final bool activo;
  final bool esNuevo;

  factory TerceroFormDialog.cliente({required Future<T> Function(Map<String, dynamic>) guardar, Cliente? cliente}) =>
      TerceroFormDialog(
        titulo: cliente == null ? 'Nuevo cliente' : 'Editar cliente',
        guardar: guardar,
        nit: cliente?.nitFormateado,
        nombre: cliente?.nombre,
        direccion: cliente?.direccion,
        telefono: telefonoLocal(cliente?.telefono),
        email: cliente?.email,
        activo: cliente?.activo ?? true,
        esNuevo: cliente == null,
      );

  factory TerceroFormDialog.proveedor({required Future<T> Function(Map<String, dynamic>) guardar, Proveedor? proveedor}) =>
      TerceroFormDialog(
        titulo: proveedor == null ? 'Nuevo proveedor' : 'Editar proveedor',
        guardar: guardar,
        esProveedor: true,
        nit: proveedor?.nitFormateado,
        nombre: proveedor?.nombre,
        contacto: proveedor?.contacto,
        direccion: proveedor?.direccion,
        telefono: telefonoLocal(proveedor?.telefono),
        email: proveedor?.email,
        activo: proveedor?.activo ?? true,
        esNuevo: proveedor == null,
      );

  @override
  State<TerceroFormDialog<T>> createState() => _TerceroFormDialogState<T>();
}

class _TerceroFormDialogState<T> extends State<TerceroFormDialog<T>> {
  final _form = GlobalKey<FormState>();
  late final _nit = TextEditingController(text: widget.nit);
  late final _nombre = TextEditingController(text: widget.nombre);
  late final _contacto = TextEditingController(text: widget.contacto);
  late final _direccion = TextEditingController(text: widget.direccion);
  late final _telefono = TextEditingController(text: widget.telefono);
  late final _email = TextEditingController(text: widget.email);
  late bool _activo = widget.activo;
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_nit, _nombre, _contacto, _direccion, _telefono, _email]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_guardando || !_form.currentState!.validate()) return;
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      final guardado = await widget.guardar({
        'nit': _nit.text.trim(),
        'nombre': _nombre.text.trim(),
        if (widget.esProveedor) 'contacto': _contacto.text.trim(),
        'direccion': _direccion.text.trim(),
        'telefono': _telefono.text.trim(),
        'email': _email.text.trim(),
        'activo': _activo,
      });
      if (mounted) Navigator.of(context).pop(guardado);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titulo),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: const Key('campo-nit'),
                  controller: _nit,
                  enabled: !_guardando,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9kK\- ]')), LengthLimitingTextInputFormatter(15)],
                  decoration: const InputDecoration(labelText: 'NIT', hintText: '1234567-9', prefixIcon: Icon(Icons.badge_outlined)),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Campo obligatorio'
                      : nitValido(v)
                          ? null
                          : 'NIT no válido (revisa el dígito verificador)',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _nombre,
                  enabled: !_guardando,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(labelText: widget.esProveedor ? 'Razón social' : 'Nombre o razón social'),
                  validator: (v) => (v == null || v.trim().length < 2) ? 'Campo obligatorio' : null,
                ),
                if (widget.esProveedor) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _contacto,
                    enabled: !_guardando,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Persona de contacto (opcional)'),
                  ),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  controller: _direccion,
                  enabled: !_guardando,
                  decoration: const InputDecoration(labelText: 'Dirección (opcional)', prefixIcon: Icon(Icons.place_outlined)),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _telefono,
                  enabled: !_guardando,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
                  decoration: const InputDecoration(
                      labelText: 'Teléfono (opcional)', prefixText: '+502 ', prefixIcon: Icon(Icons.phone_outlined)),
                  validator: (v) =>
                      (v == null || v.isEmpty || RegExp(r'^[2-7]\d{7}$').hasMatch(v)) ? null : '8 dígitos de Guatemala',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _email,
                  enabled: !_guardando,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Correo (opcional)', prefixIcon: Icon(Icons.mail_outline)),
                  validator: (v) => (v == null || v.trim().isEmpty || RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$').hasMatch(v.trim()))
                      ? null
                      : 'Correo no válido',
                ),
                if (!widget.esNuevo) ...[
                  const SizedBox(height: 8),
                  Casilla(
                    valor: _activo,
                    alCambiar: _guardando ? null : (v) => setState(() => _activo = v),
                    texto: 'Activo',
                    detalle: widget.esProveedor ? 'Un proveedor inactivo no recibe órdenes.' : 'A un cliente inactivo no se le factura.',
                  ),
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
              : const Text('Guardar'),
        ),
      ],
    );
  }
}

/// Texto de contacto para listas: teléfono y correo, si los hay.
String contactoDe(String? telefono, String? email) =>
    [if (telefono != null) telefonoLegible(telefono), ?email].join(' · ');

Widget pillActivo(bool activo) => Pills.activo(activo);
