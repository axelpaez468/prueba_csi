import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_shell.dart';
import '../../core/widgets/erp_widgets.dart';
import '../../data/models/erp.dart';
import '../../data/repositories/erp_repositories.dart';
import '../shell/modulo_page.dart';
import 'tercero_form_dialog.dart';

/// Clientes de ventas (VENDEDOR y ADMIN). "CF" es del sistema y no se edita.
class ClientesScreen extends StatefulWidget {
  const ClientesScreen({super.key});

  @override
  State<ClientesScreen> createState() => _ClientesScreenState();
}

class _ClientesScreenState extends State<ClientesScreen> with CargaDatos<ClientesScreen, List<Cliente>> {
  final _buscar = TextEditingController();

  ClienteRepository get _repo => context.read<ClienteRepository>();

  @override
  Future<List<Cliente>> obtener() => _repo.listar(buscar: _buscar.text, inactivos: true);

  @override
  void dispose() {
    _buscar.dispose();
    super.dispose();
  }

  Future<void> _abrir([Cliente? cliente]) async {
    final guardado = await showDialog<Cliente>(
      context: context,
      builder: (_) => TerceroFormDialog<Cliente>.cliente(cliente: cliente, guardar: (d) => _repo.guardar(cliente?.id, d)),
    );
    if (guardado == null || !mounted) return;
    avisar(context, cliente == null ? 'Cliente ${guardado.nombre} creado.' : 'Cambios guardados.');
    await recargar();
  }

  @override
  Widget build(BuildContext context) {
    final lista = datos ?? const <Cliente>[];
    final compacto = Breakpoints.esCompacto(context);

    return ModuloPage(
      titulo: 'Clientes',
      subtitulo: '${lista.length} clientes · el NIT se valida con su dígito verificador',
      alRefrescar: recargar,
      fab: compacto
          ? FloatingActionButton(tooltip: 'Nuevo cliente', onPressed: _abrir, child: const Icon(Icons.person_add_alt_1))
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
        if (!compacto)
          FilledButton.icon(onPressed: _abrir, icon: const Icon(Icons.person_add_alt_1, size: 18), label: const Text('Nuevo cliente')),
      ],
      children: [
        TablaResponsiva(
          cargando: cargando,
          error: error,
          filas: lista.length,
          columnas: const [
            ColumnaTabla('NIT', flex: 2),
            ColumnaTabla('Nombre', flex: 4),
            ColumnaTabla('Contacto', flex: 4),
            ColumnaTabla('Estado', flex: 2),
          ],
          alTocar: (i) => lista[i].esConsumidorFinal ? null : _abrir(lista[i]),
          celdas: (i) {
            final c = lista[i];
            return [
              textoFuerte(context, c.nitFormateado, lineas: 1),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                textoFuerte(context, c.nombre),
                if (c.direccion != null) textoSecundario(context, c.direccion!, lineas: 1),
              ]),
              textoSecundario(context, contactoDe(c.telefono, c.email), lineas: 2),
              c.esConsumidorFinal
                  ? const StatusPill(texto: 'Del sistema', color: AppColors.primary, fondo: Color(0xFFE3EAFB))
                  : Pills.activo(c.activo),
            ];
          },
          ficha: (i) {
            final c = lista[i];
            return Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  textoFuerte(context, c.nombre),
                  textoSecundario(context, [c.nitFormateado, contactoDe(c.telefono, c.email)].where((t) => t.isNotEmpty).join(' · ')),
                ]),
              ),
              const SizedBox(width: 8),
              if (!c.esConsumidorFinal) Pills.activo(c.activo),
            ]);
          },
        ),
      ],
    );
  }
}

/// Selector de cliente para la venta: busca por NIT o nombre y permite crear uno nuevo sin salir del carrito.
class SeleccionarClienteDialog extends StatefulWidget {
  const SeleccionarClienteDialog({super.key});

  @override
  State<SeleccionarClienteDialog> createState() => _SeleccionarClienteDialogState();
}

class _SeleccionarClienteDialogState extends State<SeleccionarClienteDialog>
    with CargaDatos<SeleccionarClienteDialog, List<Cliente>> {
  final _buscar = TextEditingController();

  ClienteRepository get _repo => context.read<ClienteRepository>();

  @override
  Future<List<Cliente>> obtener() => _repo.listar(buscar: _buscar.text);

  @override
  void dispose() {
    _buscar.dispose();
    super.dispose();
  }

  Future<void> _nuevo() async {
    final creado = await showDialog<Cliente>(
      context: context,
      builder: (_) => TerceroFormDialog<Cliente>.cliente(guardar: (d) => _repo.guardar(null, d)),
    );
    if (creado != null && mounted) Navigator.of(context).pop(creado);
  }

  @override
  Widget build(BuildContext context) {
    final lista = datos ?? const <Cliente>[];
    return AlertDialog(
      title: const Text('Cliente de la factura'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      content: SizedBox(
        width: 460,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _buscar,
              autofocus: true,
              onSubmitted: (_) => recargar(),
              decoration: InputDecoration(
                hintText: 'NIT o nombre',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                suffixIcon: IconButton(tooltip: 'Buscar', onPressed: recargar, icon: const Icon(Icons.arrow_forward)),
              ),
            ),
            const SizedBox(height: 8),
            if (cargando) const LinearProgressIndicator(),
            if (error != null) InlineBanner.error(error!),
            Expanded(
              child: lista.isEmpty && !cargando
                  ? const EmptyState(icono: Icons.person_search_outlined, titulo: 'Sin resultados', mensaje: 'Crea el cliente con su NIT.')
                  : ListView.separated(
                      itemCount: lista.length,
                      separatorBuilder: (_, _) => const Divider(),
                      itemBuilder: (_, i) {
                        final c = lista[i];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                          leading: Icon(c.esConsumidorFinal ? Icons.person_outline : Icons.business_outlined),
                          title: Text(c.nombre, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text('NIT ${c.nitFormateado}'),
                          onTap: () => Navigator.of(context).pop(c),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(onPressed: _nuevo, icon: const Icon(Icons.person_add_alt_1, size: 18), label: const Text('Nuevo cliente')),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
      ],
    );
  }
}
