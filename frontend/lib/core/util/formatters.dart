import 'package:intl/intl.dart';

final _moneda = NumberFormat.currency(locale: 'en_US', symbol: 'Q ', decimalDigits: 2);
final _fecha = DateFormat('dd/MM/yyyy HH:mm');

String formatearMoneda(num valor) => _moneda.format(valor);

String formatearFecha(DateTime fecha) => _fecha.format(fecha.toLocal());
