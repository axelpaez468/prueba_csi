import 'package:intl/intl.dart';

final _moneda = NumberFormat.currency(locale: 'en_US', symbol: 'Q ', decimalDigits: 2);
final _numero = NumberFormat.decimalPattern('en_US');
final _fecha = DateFormat('dd/MM/yyyy HH:mm');
final _dia = DateFormat('dd/MM/yyyy');
final _iso = DateFormat('yyyy-MM-dd');

String formatearMoneda(num valor) => _moneda.format(valor);

String formatearNumero(num valor) => _numero.format(valor);

String formatearFecha(DateTime fecha) => _fecha.format(fecha.toLocal());

/// Fecha sin hora (p. ej. una fecha contable).
String formatearDia(DateTime dia) => _dia.format(dia);

/// "2026-09-30" para la API (fechas contables y filtros desde/hasta).
String fechaIso(DateTime dia) => _iso.format(dia);

/// Lee "2026-09-30" como un día local (sin conversión de zona horaria).
DateTime leerDia(String iso) {
  final p = iso.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

DateTime hoy() {
  final ahora = DateTime.now();
  return DateTime(ahora.year, ahora.month, ahora.day);
}

DateTime inicioDeMes([DateTime? dia]) {
  final d = dia ?? DateTime.now();
  return DateTime(d.year, d.month, 1);
}

const _dias = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
const _meses = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre',
  'noviembre', 'diciembre'];

/// "mar 30".
String diaCorto(DateTime d) => '${_dias[d.weekday - 1].substring(0, 3)} ${d.day}';

/// "martes 30 de septiembre de 2026".
String fechaLarga(DateTime d) => '${_dias[d.weekday - 1]} ${d.day} de ${_meses[d.month - 1]} de ${d.year}';
