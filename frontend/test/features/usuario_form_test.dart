import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pedidos_app/core/network/api_client.dart';
import 'package:pedidos_app/core/theme/app_theme.dart';
import 'package:pedidos_app/data/repositories/usuario_repository.dart';
import 'package:pedidos_app/features/usuarios/usuario_form_dialog.dart';
import 'package:provider/provider.dart';

void main() {
  late List<http.Request> enviados;

  Future<void> montar(WidgetTester tester) async {
    enviados = [];
    final api = ApiClient(
      baseUrl: 'http://api.test',
      tokenProvider: () async => 't',
      httpClient: MockClient((req) async {
        enviados.add(req);
        final b = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'id': 9, 'nombre': b['nombre'], 'apellido': b['apellido'], 'nombreCompleto': '${b['nombre']} ${b['apellido']}',
            'email': b['email'], 'telefono': '+502${b['telefono']}', 'codigoCorporativo': b['codigoCorporativo'],
            'rol': b['rol'], 'activo': true, 'dosFactor': 'NINGUNO', 'tieneContrasena': false, 'creadoEn': '2026-09-30T00:00:00Z',
          }),
          201,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    tester.view
      ..physicalSize = const Size(1200, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(Provider.value(
      value: UsuarioRepository(api),
      child: MaterialApp(theme: AppTheme.light(), home: const Scaffold(body: UsuarioFormDialog())),
    ));
  }

  Future<void> llenar(WidgetTester tester, {required String telefono, String codigo = 'ven-0100'}) async {
    await tester.enterText(find.widgetWithText(TextFormField, 'Nombre'), 'Ana');
    await tester.enterText(find.widgetWithText(TextFormField, 'Apellido'), 'López');
    await tester.enterText(find.widgetWithText(TextFormField, 'Correo electrónico'), 'ana@empresa.gt');
    await tester.enterText(find.widgetWithText(TextFormField, 'Número de teléfono'), telefono);
    await tester.enterText(find.widgetWithText(TextFormField, 'Código corporativo'), codigo);
    await tester.tap(find.text('Crear y enviar invitación'));
    await tester.pumpAndSettle();
  }

  testWidgets('un teléfono que no es de Guatemala no se envía al servidor', (tester) async {
    await montar(tester);
    await llenar(tester, telefono: '91234567');

    expect(find.textContaining('8 dígitos de Guatemala'), findsOneWidget);
    expect(enviados, isEmpty);
  });

  testWidgets('el teléfono se limita a 8 dígitos y el código se convierte a mayúsculas', (tester) async {
    await montar(tester);
    await llenar(tester, telefono: '5555-0101-99');

    expect(enviados, hasLength(1));
    final cuerpo = jsonDecode(enviados.single.body) as Map<String, dynamic>;
    expect(cuerpo['telefono'], '55550101'); // el servidor antepone +502
    expect(cuerpo['codigoCorporativo'], 'VEN-0100');
    expect(cuerpo['rol'], 'VENDEDOR');
    expect(cuerpo.containsKey('password'), isFalse); // el admin nunca define la contraseña
  });
}
