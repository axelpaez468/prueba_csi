import 'package:flutter/material.dart';

import '../../core/widgets/app_shell.dart';
import 'app_top_bar.dart';
import 'modulos.dart';

/// Estructura común de las pantallas de los módulos: barra superior con "volver", encabezado con acciones
/// y contenido desplazable con pull-to-refresh.
class ModuloPage extends StatelessWidget {
  const ModuloPage({
    super.key,
    required this.titulo,
    this.subtitulo,
    this.acciones = const [],
    required this.children,
    this.alRefrescar,
    this.fab,
    this.maxWidth = 1180,
    this.esInicio = false,
    this.encabezado,
  });

  final String titulo;
  final String? subtitulo;
  final List<Widget> acciones;
  final List<Widget> children;
  final Future<void> Function()? alRefrescar;
  final Widget? fab;
  final double maxWidth;

  /// Pantalla de inicio del rol: sin botón "volver".
  final bool esInicio;

  /// Reemplaza el encabezado estándar (p. ej. la bienvenida del panel).
  final Widget? encabezado;

  @override
  Widget build(BuildContext context) {
    final margen = Breakpoints.esCompacto(context) ? 16.0 : 24.0;
    final modulo = moduloActual(context);
    final area = modulo == null ? null : grupos.where((g) => g.nombre == modulo.grupo).firstOrNull;
    final lista = ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        PageBody(
          maxWidth: maxWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              encabezado ??
                  PageHeader(
                    titulo: titulo,
                    subtitulo: subtitulo,
                    acciones: acciones,
                    area: area?.nombre,
                    iconoArea: area?.icono,
                  ),
              for (final c in children) Padding(padding: EdgeInsets.fromLTRB(margen, 0, margen, 16), child: c),
            ],
          ),
        ),
      ],
    );

    return Scaffold(
      appBar: AppTopBar(
        mostrarCarrito: false,
        leading: esInicio
            ? null
            : IconButton(
                tooltip: 'Volver',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back),
              ),
      ),
      floatingActionButton: fab,
      body: alRefrescar == null ? lista : RefreshIndicator(onRefresh: alRefrescar!, child: lista),
    );
  }
}
