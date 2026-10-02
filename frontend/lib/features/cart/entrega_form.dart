import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_exception.dart';
import '../../core/widgets/app_shell.dart';
import '../../data/models/pipeline.dart';
import '../../data/repositories/erp_repositories.dart';
import 'cart_controller.dart';

/// Datos de entrega de la venta: dirección, departamento y municipio de Guatemala.
/// El selector de municipio solo muestra los del departamento elegido.
class EntregaForm extends StatefulWidget {
  const EntregaForm({super.key});

  @override
  State<EntregaForm> createState() => _EntregaFormState();
}

class _EntregaFormState extends State<EntregaForm> {
  late final _direccion = TextEditingController(text: context.read<CartController>().direccionEntrega);
  List<Departamento>? _departamentos;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final lista = await context.read<GeografiaRepository>().departamentos();
      if (mounted) setState(() => _departamentos = lista);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  void dispose() {
    _direccion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final carrito = context.watch<CartController>();
    final theme = Theme.of(context);
    final departamentos = _departamentos ?? const <Departamento>[];
    final elegido = departamentos.where((d) => d.nombre == carrito.departamento).firstOrNull;
    // La dirección también cambia desde fuera (al elegir un cliente o al vaciar el carrito tras facturar).
    if (_direccion.text != carrito.direccionEntrega) _direccion.text = carrito.direccionEntrega;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Entrega', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        if (_error != null) InlineBanner.error(_error!),
        TextField(
          key: const Key('campo-direccion'),
          controller: _direccion,
          enabled: !carrito.enviando,
          maxLength: 200,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Dirección',
            hintText: '6a. avenida 10-20, zona 1',
            prefixIcon: Icon(Icons.place_outlined),
            isDense: true,
            counterText: '',
          ),
          onChanged: carrito.elegirDireccion,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: const Key('campo-departamento'),
          initialValue: elegido?.nombre,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Departamento', isDense: true),
          hint: Text(_departamentos == null ? 'Cargando...' : 'Elige el departamento'),
          items: [for (final d in departamentos) DropdownMenuItem(value: d.nombre, child: Text(d.nombre))],
          // Al cambiar de departamento se borra el municipio: el anterior ya no corresponde.
          onChanged: carrito.enviando ? null : (v) => carrito.elegirDepartamento(v),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          // La clave cambia con el departamento para que el selector se reinicie con la lista nueva.
          key: ValueKey('municipio-${elegido?.nombre}'),
          initialValue: carrito.municipio,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Municipio', isDense: true),
          hint: Text(elegido == null ? 'Primero elige el departamento' : 'Elige el municipio'),
          items: [for (final m in elegido?.municipios ?? const <String>[]) DropdownMenuItem(value: m, child: Text(m))],
          onChanged: carrito.enviando || elegido == null ? null : (v) => carrito.elegirMunicipio(v),
        ),
      ],
    );
  }
}
