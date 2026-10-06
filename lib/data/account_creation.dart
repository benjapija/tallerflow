import '../domain/engine.dart';

/// The only account fields allowed in durable storage; credentials stay in RAM.
Map<String, dynamic> accountPreferences(Map<String, dynamic> input) {
  String text(String key, int max) {
    final value = input[key];
    if (value is! String || value.trim().isEmpty || value.trim().length > max) {
      throw const RuleException('Completa los datos de la cuenta y su motivo');
    }
    return value.trim();
  }

  final email = text('email', 254).toLowerCase();
  if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email) ||
      !['technician', 'office', 'admin'].contains(input['role']) ||
      input['seePrices'] is! bool ||
      input['seeCosts'] is! bool) {
    throw const RuleException('Revisa el correo y los permisos');
  }
  if (input['role'] == 'technician' &&
      input['seeCosts'] == true &&
      input['seePrices'] != true) {
    throw const RuleException('Consultar costes requiere acceso a precios');
  }
  return {
    'email': email,
    'name': text('name', 120),
    'role': input['role'],
    'seePrices': input['seePrices'],
    'seeCosts': input['seeCosts'],
    'reason': text('reason', 2000),
  };
}
