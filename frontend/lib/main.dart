import 'package:flutter/material.dart';

import 'app.dart';
import 'core/config/app_config.dart';

void main() {
  if (!AppConfig.isValid) {
    runApp(const _ConfiguracionFaltante());
    return;
  }
  runApp(const PedidosApp());
}

class _ConfiguracionFaltante extends StatelessWidget {
  const _ConfiguracionFaltante();

  @override
  Widget build(BuildContext context) => const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Falta configurar la URL de la API.\n'
                'Compile con --dart-define=API_URL=http://servidor:puerto',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
}
