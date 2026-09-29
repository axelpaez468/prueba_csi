import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pedidos_app/data/models/producto.dart';
import 'package:pedidos_app/features/catalog/producto_tile.dart';

Widget _envolver(Widget child) => MaterialApp(home: Scaffold(body: child));

FilledButton _botonAgregar(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byWidgetPredicate((w) => w is FilledButton));

void main() {
  testWidgets('un producto sin stock se muestra deshabilitado', (tester) async {
    await tester.pumpWidget(_envolver(ProductoTile(
      producto: const Producto(id: 5, codigo: 'P-005', nombre: 'Webcam', precio: 310, stock: 0),
      enCarrito: 0,
      onAgregar: (_) => fail('no debería poder agregarse'),
    )));

    expect(find.text('Sin stock'), findsWidgets);
    expect(_botonAgregar(tester).onPressed, isNull);
  });

  testWidgets('agrega la cantidad elegida', (tester) async {
    int? agregado;
    await tester.pumpWidget(_envolver(ProductoTile(
      producto: const Producto(id: 1, codigo: 'P-001', nombre: 'Teclado', precio: 450, stock: 5),
      enCarrito: 0,
      onAgregar: (c) => agregado = c,
    )));

    await tester.tap(find.byTooltip('Más'));
    await tester.pump();
    await tester.tap(find.byTooltip('Más'));
    await tester.pump();
    await tester.tap(find.text('Agregar'));

    expect(agregado, 3);
  });
}
