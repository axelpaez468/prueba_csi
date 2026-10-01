import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pedidos_app/core/network/api_exception.dart';
import 'package:pedidos_app/core/theme/app_theme.dart';
import 'package:pedidos_app/features/clientes/tercero_form_dialog.dart';

/// Formularios ante datos inválidos y rechazos del servidor: el usuario ve qué corregir y no pierde lo escrito.
void main() {
  late List<Map<String, dynamic>> enviados;

  Future<void> abrir(WidgetTester tester, Future<Object?> Function(Map<String, dynamic>) guardar) async {
    enviados = [];
    tester.view
      ..physicalSize = const Size(1200, 1000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: TerceroFormDialog<Object?>.cliente(
            guardar: (d) {
              enviados.add(d);
              return guardar(d);
            },
          ),
        ),
      ),
    );
  }

  Finder campo(String etiqueta) => find.widgetWithText(TextFormField, etiqueta);

  testWidgets('sin NIT ni nombre no envía nada y dice qué falta', (tester) async {
    await abrir(tester, (_) async => null);
    await tester.tap(find.text('Guardar'));
    await tester.pump();

    expect(enviados, isEmpty);
    expect(find.text('Campo obligatorio'), findsWidgets);
  });

  testWidgets('correo con formato inválido no se envía', (tester) async {
    await abrir(tester, (_) async => null);
    await tester.enterText(campo('NIT'), '1234567-9');
    await tester.enterText(campo('Nombre o razón social'), 'Comercial Prueba');
    await tester.enterText(campo('Correo (opcional)'), 'no-es-un-correo');
    await tester.tap(find.text('Guardar'));
    await tester.pump();

    expect(enviados, isEmpty);
  });

  testWidgets('si el servidor lo rechaza, muestra el motivo y conserva lo escrito', (tester) async {
    await abrir(tester, (_) async => throw const ApiException('Ya existe un cliente con el NIT 1234567-9.', statusCode: 400));
    await tester.enterText(campo('NIT'), '1234567-9');
    await tester.enterText(campo('Nombre o razón social'), 'Comercial Prueba');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Ya existe un cliente'), findsOneWidget);
    expect(find.text('Comercial Prueba'), findsOneWidget); // lo escrito sigue ahí
    expect(find.byType(TerceroFormDialog<Object?>), findsOneWidget); // el diálogo no se cerró
    final boton = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Guardar'));
    expect(boton.onPressed, isNotNull); // se puede corregir y reintentar
  });

  testWidgets('sin conexión al guardar: mensaje claro y se puede reintentar', (tester) async {
    var intentos = 0;
    await abrir(tester, (_) async {
      intentos++;
      if (intentos == 1) throw const ApiException('No se pudo conectar con el servidor. Verifique su conexión.');
      return 'ok';
    });
    await tester.enterText(campo('NIT'), '1234567-9');
    await tester.enterText(campo('Nombre o razón social'), 'Cliente de mostrador');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No se pudo conectar'), findsOneWidget);

    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(intentos, 2);
    expect(find.byType(TerceroFormDialog<Object?>), findsNothing); // al segundo intento se guardó y cerró
  });

  testWidgets('doble clic en Guardar envía una sola vez', (tester) async {
    final respuesta = Completer<Object?>();
    await abrir(tester, (_) => respuesta.future);
    await tester.enterText(campo('NIT'), '1234567-9');
    await tester.enterText(campo('Nombre o razón social'), 'Comercial Prueba');

    await tester.tap(find.text('Guardar'));
    await tester.pump();
    await tester.tap(find.byType(FilledButton), warnIfMissed: false);
    await tester.pump();
    respuesta.complete('ok');
    await tester.pumpAndSettle();

    expect(enviados, hasLength(1));
  });

  testWidgets('los espacios alrededor se quitan antes de enviar', (tester) async {
    await abrir(tester, (_) async => 'ok');
    await tester.enterText(campo('NIT'), '  1234567-9  ');
    await tester.enterText(campo('Nombre o razón social'), '  Comercial Prueba  ');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(enviados.single['nit'], '1234567-9');
    expect(enviados.single['nombre'], 'Comercial Prueba');
  });
}
