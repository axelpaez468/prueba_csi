import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pedidos_app/core/theme/app_theme.dart';
import 'package:pedidos_app/core/widgets/erp_widgets.dart';

Widget _tabla(int filas) => MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: TablaResponsiva(
            filas: filas,
            columnas: const [ColumnaTabla('Nombre'), ColumnaTabla('Monto', derecha: true)],
            celdas: (i) => [Text('Fila $i'), Text('${i * 10}')],
            ficha: (i) => Text('Fila $i'),
          ),
        ),
      ),
    );

String _rango(WidgetTester t) => t.widget<Text>(find.byKey(const Key('paginador-rango'))).data!;

void main() {
  testWidgets('pagina de 25 en 25 y navega entre páginas', (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_tabla(60));

    expect(_rango(tester), 'Mostrando 1–25 de 60');
    expect(find.text('Fila 0'), findsOneWidget);
    expect(find.text('Fila 25'), findsNothing);

    await tester.tap(find.byTooltip('Página siguiente'));
    await tester.pump();
    expect(_rango(tester), 'Mostrando 26–50 de 60');
    expect(find.text('Fila 25'), findsOneWidget);
    expect(find.text('Fila 0'), findsNothing);

    await tester.tap(find.byTooltip('Última página'));
    await tester.pump();
    expect(_rango(tester), 'Mostrando 51–60 de 60');
    expect(find.text('3 / 3'), findsOneWidget);

    // Cambiar las filas por página vuelve a la primera página.
    await tester.tap(find.text('25'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('50').last);
    await tester.pumpAndSettle();
    expect(_rango(tester), 'Mostrando 1–50 de 60');
  });

  testWidgets('si la lista se achica, se ajusta la página', (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_tabla(60));
    await tester.tap(find.byTooltip('Última página'));
    await tester.pump();

    await tester.pumpWidget(_tabla(30)); // p. ej. después de filtrar
    expect(_rango(tester), 'Mostrando 26–30 de 30');
  });

  testWidgets('con pocas filas no muestra el paginador', (tester) async {
    await tester.pumpWidget(_tabla(8));
    expect(find.byType(Paginador), findsNothing);
  });

  testWidgets('el paginador cabe en un celular chico', (tester) async {
    tester.view.physicalSize = const Size(320, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_tabla(200));
    expect(_rango(tester), 'Mostrando 1–25 de 200');
  });
}
