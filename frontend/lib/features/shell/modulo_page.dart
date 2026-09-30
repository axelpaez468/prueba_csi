import 'package:flutter/material.dart';

import '../../core/widgets/app_shell.dart';
import 'app_top_bar.dart';

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

  @override
  Widget build(BuildContext context) {
    final margen = Breakpoints.esCompacto(context) ? 16.0 : 24.0;
    final lista = ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        PageBody(
          maxWidth: maxWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(titulo: titulo, subtitulo: subtitulo, acciones: acciones),
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
