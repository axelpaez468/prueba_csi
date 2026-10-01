import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/security/permisos.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_shell.dart';
import '../auth/session_controller.dart';
import '../cart/cart_controller.dart';
import '../cart/cart_screen.dart';
import '../cuenta/seguridad_screen.dart';
import 'modulos.dart';

/// Header del ERP: barra de navegación oscura con las áreas del sistema (según el rol), carrito y cuenta.
/// En pantallas anchas las áreas van en la barra, cada una con su submenú; en tablet y celular se abren
/// desde el botón de menú como un panel lateral.
class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  const AppTopBar({super.key, this.mostrarCarrito = true, this.leading});

  final bool mostrarCarrito;
  final Widget? leading;

  static const alto = 64.0;

  /// Desde este ancho las áreas caben en la barra.
  static const anchoNavegacion = 1240.0;

  /// Con hasta esta cantidad de módulos (vendedor, bodega, compras) cada módulo va directo en la barra,
  /// uno al lado del otro; con más (contador, administrador) se agrupan por área con submenú.
  static const modulosEnBarraMax = 6;

  /// Ancho desde el que caben los módulos directos (son pocos).
  static const anchoNavegacionPlana = 1000.0;

  @override
  Size get preferredSize => const Size.fromHeight(alto);

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.sizeOf(context).width;
    final compacto = ancho < 640;
    final session = context.watch<SessionController>().session;
    final areas = session == null ? const <(Grupo, List<Modulo>)>[] : gruposDe(session);
    final todos = session == null ? const <Modulo>[] : modulosDe(session);
    final plana = todos.length <= modulosEnBarraMax;
    final enBarra = ancho >= (plana ? anchoNavegacionPlana : anchoNavegacion);
    final vende = session?.puedeVender ?? false;

    return Material(
      color: AppColors.navbar,
      elevation: 3,
      shadowColor: const Color(0x400B1426),
      child: Container(
        height: alto,
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [AppColors.navbar, AppColors.navbarClaro]),
        ),
        child: SafeArea(
          bottom: false,
          child: IconTheme(
            data: const IconThemeData(color: Colors.white),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: compacto ? 8 : 16),
              child: Row(
                children: [
                  ?leading,
                  if (!enBarra && areas.isNotEmpty)
                    IconButton(
                      tooltip: 'Menú',
                      onPressed: () => _abrirPanel(context, areas),
                      icon: const Icon(Icons.menu),
                    ),
                  const SizedBox(width: 4),
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: session == null ? null : () => abrirModulo(context, inicioModuloDe(session)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                      child: BrandLogo(claro: true, soloIcono: ancho < 400),
                    ),
                  ),
                  const SizedBox(width: 20),
                  if (enBarra)
                    // Si no caben todas las áreas (textos largos, zoom del navegador), la barra se desplaza.
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(children: [
                          if (plana)
                            for (final m in todos) _ItemModulo(modulo: m)
                          else
                            for (final (grupo, lista) in areas) _ItemArea(grupo: grupo, modulos: lista),
                        ]),
                      ),
                    )
                  else
                    const Spacer(),
                  if (mostrarCarrito && vende) _BotonCarrito(compacto: compacto),
                  const SizedBox(width: 8),
                  _MenuUsuario(compacto: compacto),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _abrirPanel(BuildContext context, List<(Grupo, List<Modulo>)> areas) {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cerrar menú',
      barrierColor: Colors.black45,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (ctx, _, _) => _PanelNavegacion(areas: areas, alElegir: (m) {
        Navigator.of(ctx).pop();
        abrirModulo(context, m);
      }),
      transitionBuilder: (_, animacion, _, hijo) => SlideTransition(
        position: Tween(begin: const Offset(-1, 0), end: Offset.zero)
            .animate(CurvedAnimation(parent: animacion, curve: Curves.easeOutCubic)),
        child: hijo,
      ),
    );
  }
}

/// Opción de la barra: ícono y texto, resaltada cuando es la pantalla abierta.
class _BotonBarra extends StatelessWidget {
  const _BotonBarra({required this.icono, required this.texto, required this.activo, this.conFlecha = false});

  final IconData icono;
  final String texto;
  final bool activo;
  final bool conFlecha;

  @override
  Widget build(BuildContext context) {
    final color = activo ? Colors.white : AppColors.navbarTexto;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      height: AppTopBar.alto,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: activo ? Colors.white.withValues(alpha: 0.08) : null,
        border: Border(bottom: BorderSide(color: activo ? const Color(0xFF7FA2FF) : Colors.transparent, width: 3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icono, size: 18, color: color),
        const SizedBox(width: 8),
        Text(texto, style: TextStyle(color: color, fontWeight: activo ? FontWeight.w700 : FontWeight.w500, fontSize: 14)),
        if (conFlecha) ...[
          const SizedBox(width: 2),
          Icon(Icons.expand_more, size: 16, color: color),
        ],
      ]),
    );
  }
}

/// Módulo directo en la barra (roles con pocos módulos).
class _ItemModulo extends StatelessWidget {
  const _ItemModulo({required this.modulo});

  final Modulo modulo;

  @override
  Widget build(BuildContext context) {
    final activo = moduloActual(context) == modulo;
    return Tooltip(
      message: modulo.descripcion,
      child: InkWell(
        onTap: () => abrirModulo(context, modulo),
        // El panel de indicadores se muestra como "Inicio".
        child: _BotonBarra(icono: modulo.icono, texto: modulo.grupo == 'Inicio' ? 'Inicio' : modulo.titulo, activo: activo),
      ),
    );
  }
}

/// Área en la barra (Ventas, Inventario...). Con un solo módulo abre directo; si no, despliega su submenú.
class _ItemArea extends StatelessWidget {
  const _ItemArea({required this.grupo, required this.modulos});

  final Grupo grupo;
  final List<Modulo> modulos;

  @override
  Widget build(BuildContext context) {
    final activo = moduloActual(context)?.grupo == grupo.nombre;
    final contenido = _BotonBarra(icono: grupo.icono, texto: grupo.nombre, activo: activo, conFlecha: modulos.length > 1);

    if (modulos.length == 1) {
      return InkWell(onTap: () => abrirModulo(context, modulos.first), child: contenido);
    }
    final actual = moduloActual(context);
    return PopupMenuButton<Modulo>(
      tooltip: grupo.nombre,
      position: PopupMenuPosition.under,
      offset: const Offset(0, 2),
      onSelected: (m) => abrirModulo(context, m),
      itemBuilder: (_) => [
        for (final m in modulos)
          PopupMenuItem<Modulo>(
            value: m,
            height: 56,
            child: _FilaModulo(modulo: m, activo: actual == m),
          ),
      ],
      child: contenido,
    );
  }
}

class _FilaModulo extends StatelessWidget {
  const _FilaModulo({required this.modulo, required this.activo, this.oscuro = false});

  final Modulo modulo;
  final bool activo;
  final bool oscuro;

  @override
  Widget build(BuildContext context) {
    final titulo = oscuro ? Colors.white : AppColors.textPrimary;
    final detalle = oscuro ? AppColors.navbarTexto : AppColors.textSecondary;
    // En el submenú de la barra, ancho fijo; en el panel lateral, el que haya.
    return SizedBox(
      width: oscuro ? null : 260,
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: activo
                ? AppColors.primary
                : oscuro
                    ? Colors.white.withValues(alpha: 0.08)
                    : const Color(0xFFE3EAFB),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(modulo.icono, size: 18, color: activo || oscuro ? Colors.white : AppColors.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(modulo.titulo, style: TextStyle(fontWeight: FontWeight.w600, color: titulo)),
            Text(modulo.descripcion,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: detalle)),
          ]),
        ),
      ]),
    );
  }
}

/// Menú lateral (tablet y celular): todas las áreas y módulos del rol.
class _PanelNavegacion extends StatelessWidget {
  const _PanelNavegacion({required this.areas, required this.alElegir});

  final List<(Grupo, List<Modulo>)> areas;
  final ValueChanged<Modulo> alElegir;

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.sizeOf(context).width;
    final actual = moduloActual(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: AppColors.navbar,
        child: SizedBox(
          width: ancho < 400 ? ancho * 0.86 : 320,
          height: double.infinity,
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Row(children: [
                  const Expanded(child: Align(alignment: Alignment.centerLeft, child: BrandLogo(claro: true))),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ]),
                const SizedBox(height: 12),
                for (final (grupo, lista) in areas) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                    child: Row(children: [
                      Icon(grupo.icono, size: 16, color: AppColors.navbarTexto),
                      const SizedBox(width: 8),
                      Text(grupo.nombre.toUpperCase(),
                          style: const TextStyle(
                              color: AppColors.navbarTexto, fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                  for (final m in lista)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Material(
                        color: actual == m ? Colors.white.withValues(alpha: 0.1) : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => alElegir(m),
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: _FilaModulo(modulo: m, activo: actual == m, oscuro: true),
                          ),
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BotonCarrito extends StatelessWidget {
  const _BotonCarrito({required this.compacto});

  final bool compacto;

  @override
  Widget build(BuildContext context) {
    final unidades = context.watch<CartController>().totalUnidades;
    final icono = Badge(
      isLabelVisible: unidades > 0,
      label: Text('$unidades'),
      child: const Icon(Icons.shopping_cart_outlined, color: Colors.white),
    );
    void abrir() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CartScreen()));

    return compacto
        ? IconButton(tooltip: 'Carrito', onPressed: abrir, icon: icono)
        : OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
            ),
            onPressed: abrir,
            icon: icono,
            label: const Text('Carrito'),
          );
  }
}

class _MenuUsuario extends StatelessWidget {
  const _MenuUsuario({required this.compacto});

  final bool compacto;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>().session;
    if (session == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final inicial = session.username.isEmpty ? '?' : session.username[0].toUpperCase();

    return PopupMenuButton<String>(
      tooltip: 'Cuenta',
      position: PopupMenuPosition.under,
      onSelected: (v) {
        switch (v) {
          case 'seguridad':
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SeguridadScreen()));
          case 'salir':
            context.read<NavegacionController?>()?.reiniciar();
            context.read<SessionController>().logout();
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(session.username, style: theme.textTheme.titleSmall?.copyWith(color: AppColors.textPrimary)),
              Text(session.email, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
              const SizedBox(height: 6),
              StatusPill(texto: session.nombreRol, color: AppColors.primary, fondo: const Color(0xFFE3EAFB)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'seguridad',
          child: Row(children: [Icon(Icons.shield_outlined, size: 18), SizedBox(width: 10), Text('Seguridad de la cuenta')]),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'salir',
          child: Row(children: [Icon(Icons.logout, size: 18), SizedBox(width: 10), Text('Cerrar sesión')]),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFF7FA2FF), width: 2)),
              child: CircleAvatar(
                radius: 15,
                backgroundColor: AppColors.primary,
                child: Text(inicial, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ),
            if (!compacto) ...[
              const SizedBox(width: 10),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(session.username,
                      style: theme.textTheme.labelLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w600)),
                  Text(session.nombreRol, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.navbarTexto)),
                ],
              ),
              const Icon(Icons.expand_more, color: AppColors.navbarTexto),
            ],
          ],
        ),
      ),
    );
  }
}
