import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/security/permisos.dart';
import '../../core/widgets/app_shell.dart';
import '../../core/widgets/erp_widgets.dart';
import '../../data/models/erp.dart';
import '../../data/repositories/erp_repositories.dart';
import '../auth/session_controller.dart';
import '../clientes/tercero_form_dialog.dart';
import '../shell/modulo_page.dart';

class ProveedoresScreen extends StatefulWidget {
  const ProveedoresScreen({super.key});

  @override
  State<ProveedoresScreen> createState() => _ProveedoresScreenState();
}

class _ProveedoresScreenState extends State<ProveedoresScreen> with CargaDatos<ProveedoresScreen, List<Proveedor>> {
  final _buscar = TextEditingController();

  CompraRepository get _repo => context.read<CompraRepository>();

  @override
  Future<List<Proveedor>> obtener() => _repo.proveedores(buscar: _buscar.text, inactivos: true);

  @override
  void dispose() {
    _buscar.dispose();
    super.dispose();
  }

  Future<void> _abrir([Proveedor? p]) async {
    final guardado = await showDialog<Proveedor>(
      context: context,
      builder: (_) => TerceroFormDialog<Proveedor>.proveedor(proveedor: p, guardar: (d) => _repo.guardarProveedor(p?.id, d)),
    );
    if (guardado == null || !mounted) return;
    avisar(context, p == null ? 'Proveedor ${guardado.nombre} creado.' : 'Cambios guardados.');
    await recargar();
  }

  @override
  Widget build(BuildContext context) {
    final lista = datos ?? const <Proveedor>[];
    final gestiona = context.watch<SessionController>().session?.gestionaCompras ?? false;
    final compacto = Breakpoints.esCompacto(context);

    return ModuloPage(
      titulo: 'Proveedores',
      subtitulo: '${lista.length} proveedores',
      alRefrescar: recargar,
      fab: gestiona && compacto
          ? FloatingActionButton(tooltip: 'Nuevo proveedor', onPressed: _abrir, child: const Icon(Icons.add_business_outlined))
          : null,
      acciones: [
        SizedBox(
          width: 280,
          child: TextField(
            controller: _buscar,
            onSubmitted: (_) => recargar(),
            decoration: const InputDecoration(hintText: 'Buscar por NIT o nombre', prefixIcon: Icon(Icons.search), isDense: true),
          ),
        ),
        if (gestiona && !compacto)
          FilledButton.icon(
              onPressed: _abrir, icon: const Icon(Icons.add_business_outlined, size: 18), label: const Text('Nuevo proveedor')),
      ],
      children: [
        TablaResponsiva(
          cargando: cargando,
          error: error,
          alReintentar: recargar,
          filas: lista.length,
          alTocar: gestiona ? (i) => _abrir(lista[i]) : null,
          columnas: const [
            ColumnaTabla('NIT', flex: 2),
            ColumnaTabla('Proveedor', flex: 4),
            ColumnaTabla('Contacto', flex: 4),
            ColumnaTabla('Estado', flex: 2),
          ],
          celdas: (i) {
            final p = lista[i];
            return [
              textoFuerte(context, p.nitFormateado, lineas: 1),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                textoFuerte(context, p.nombre),
                if (p.direccion != null) textoSecundario(context, p.direccion!, lineas: 1),
              ]),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (p.contacto != null) Text(p.contacto!),
                textoSecundario(context, contactoDe(p.telefono, p.email), lineas: 2),
              ]),
              Pills.activo(p.activo),
            ];
          },
          ficha: (i) {
            final p = lista[i];
            return Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  textoFuerte(context, p.nombre),
                  textoSecundario(
                      context, [p.nitFormateado, p.contacto ?? '', contactoDe(p.telefono, p.email)].where((t) => t.isNotEmpty).join(' · ')),
                ]),
              ),
              const SizedBox(width: 8),
              Pills.activo(p.activo),
            ]);
          },
        ),
      ],
    );
  }
}
