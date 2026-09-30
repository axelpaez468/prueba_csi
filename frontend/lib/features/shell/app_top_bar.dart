import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_shell.dart';
import '../auth/session_controller.dart';
import '../cart/cart_controller.dart';
import '../cart/cart_screen.dart';
import '../cuenta/bitacora_screen.dart';
import '../cuenta/seguridad_screen.dart';

/// Barra superior común: logo, acceso al carrito y menú del usuario.
class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  const AppTopBar({super.key, this.mostrarCarrito = true, this.leading});

  final bool mostrarCarrito;
  final Widget? leading;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.sizeOf(context).width;
    final compacto = ancho < 640;

    return AppBar(
      toolbarHeight: 64,
      automaticallyImplyLeading: false,
      titleSpacing: compacto ? 12 : 20,
      title: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 8)],
          Flexible(child: BrandLogo(soloIcono: ancho < 400)),
        ],
      ),
      actions: [
        if (mostrarCarrito) _BotonCarrito(compacto: compacto),
        const SizedBox(width: 8),
        _MenuUsuario(compacto: compacto),
        SizedBox(width: compacto ? 8 : 16),
      ],
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
      child: const Icon(Icons.shopping_cart_outlined),
    );
    void abrir() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CartScreen()));

    return compacto
        ? IconButton(tooltip: 'Carrito', onPressed: abrir, icon: icono)
        : OutlinedButton.icon(onPressed: abrir, icon: icono, label: const Text('Carrito'));
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
        final navigator = Navigator.of(context);
        switch (v) {
          case 'seguridad':
            navigator.push(MaterialPageRoute(builder: (_) => const SeguridadScreen()));
          case 'bitacora':
            navigator.push(MaterialPageRoute(builder: (_) => const BitacoraScreen()));
          case 'salir':
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
              Text(session.esVendedor ? 'Vendedor' : 'Administrador',
                  style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'seguridad',
          child: Row(children: [Icon(Icons.shield_outlined, size: 18), SizedBox(width: 10), Text('Seguridad de la cuenta')]),
        ),
        if (session.esAdmin)
          const PopupMenuItem<String>(
            value: 'bitacora',
            child: Row(children: [Icon(Icons.manage_search, size: 18), SizedBox(width: 10), Text('Bitácora de accesos')]),
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
            CircleAvatar(
              radius: 17,
              backgroundColor: AppColors.primary,
              child: Text(inicial, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            ),
            if (!compacto) ...[
              const SizedBox(width: 10),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(session.username, style: theme.textTheme.labelLarge),
                  Text(session.esVendedor ? 'Vendedor' : 'Administrador',
                      style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
                ],
              ),
              const Icon(Icons.expand_more, color: AppColors.textSecondary),
            ],
          ],
        ),
      ),
    );
  }
}
