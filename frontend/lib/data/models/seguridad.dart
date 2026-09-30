import '../../core/security/session.dart';

/// Resultado del primer paso del login: sesión iniciada o segundo factor pendiente.
sealed class ResultadoLogin {
  const ResultadoLogin();
}

class SesionIniciada extends ResultadoLogin {
  const SesionIniciada(this.session, {this.tokenDispositivo});

  final Session session;

  /// Presente si el usuario marcó "confiar en este dispositivo".
  final String? tokenDispositivo;
}

class SegundoFactorRequerido extends ResultadoLogin {
  const SegundoFactorRequerido({required this.desafio, required this.metodo, this.destino});

  /// Token de corta duración que solo sirve para completar este login.
  final String desafio;

  /// "TOTP" (app autenticadora) o "SMS".
  final String metodo;

  /// Teléfono enmascarado, si el método es SMS.
  final String? destino;

  bool get esSms => metodo == 'SMS';
}

class EstadoSeguridad {
  const EstadoSeguridad({
    required this.email,
    required this.metodo,
    required this.telefonoEnmascarado,
    required this.codigosRespaldoRestantes,
    required this.dosFactorObligatorio,
  });

  final String email;
  final String metodo;
  final String? telefonoEnmascarado;
  final int codigosRespaldoRestantes;
  final bool dosFactorObligatorio;

  bool get activo => metodo != 'NINGUNO';

  factory EstadoSeguridad.fromJson(Map<String, dynamic> j) => EstadoSeguridad(
        email: j['email'] as String,
        metodo: j['metodo'] as String,
        telefonoEnmascarado: j['telefonoEnmascarado'] as String?,
        codigosRespaldoRestantes: j['codigosRespaldoRestantes'] as int,
        dosFactorObligatorio: j['dosFactorObligatorio'] as bool,
      );
}

class ConfiguracionTotp {
  const ConfiguracionTotp({required this.secreto, required this.uri});

  final String secreto;

  /// URI otpauth:// que se muestra como código QR.
  final String uri;
}

class RegistroAcceso {
  const RegistroAcceso({
    required this.fecha,
    required this.email,
    required this.evento,
    required this.exito,
    this.ip,
    this.dispositivo,
    this.detalle,
  });

  final DateTime fecha;
  final String email;
  final String evento;
  final bool exito;
  final String? ip;
  final String? dispositivo;
  final String? detalle;

  factory RegistroAcceso.fromJson(Map<String, dynamic> j) => RegistroAcceso(
        fecha: DateTime.parse(j['fecha'] as String),
        email: j['email'] as String,
        evento: j['evento'] as String,
        exito: j['exito'] as bool,
        ip: j['ip'] as String?,
        dispositivo: j['dispositivo'] as String?,
        detalle: j['detalle'] as String?,
      );

  /// Texto legible del evento para la interfaz.
  String get descripcion => switch (evento) {
        'LOGIN_EXITOSO' => 'Inicio de sesión',
        'LOGIN_FALLIDO' => 'Intento fallido de inicio de sesión',
        'CUENTA_BLOQUEADA' => 'Cuenta bloqueada temporalmente',
        '2FA_REQUERIDO' => 'Se solicitó el segundo factor',
        '2FA_FALLIDO' => 'Código de verificación incorrecto',
        'CODIGO_RESPALDO_USADO' => 'Se usó un código de respaldo',
        'RECUPERACION_SOLICITADA' => 'Solicitud de recuperación de contraseña',
        'PASSWORD_RESTABLECIDA' => 'Contraseña restablecida',
        'PASSWORD_CAMBIADA' => 'Contraseña cambiada',
        '2FA_ACTIVADO' => 'Verificación en dos pasos activada',
        '2FA_DESACTIVADO' => 'Verificación en dos pasos desactivada',
        'CODIGOS_RESPALDO_REGENERADOS' => 'Códigos de respaldo regenerados',
        'DISPOSITIVO_NUEVO' => 'Acceso desde un dispositivo nuevo',
        _ => evento,
      };
}
