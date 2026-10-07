import 'package:timezone/data/latest.dart' as data;
import 'package:timezone/timezone.dart' as tz;
import 'engine.dart';

class PlanningTime {
  static bool _ready = false;
  static tz.Location location(String zone) {
    if (!['Europe/Madrid', 'Atlantic/Canary'].contains(zone)) {
      throw const RuleException('Selecciona la zona horaria española');
    }
    if (!_ready) {
      data.initializeTimeZones();
      _ready = true;
    }
    return tz.getLocation(zone);
  }

  static DateTime parse(String input, String zone, {String fold = ''}) {
    final match = RegExp(
      r'^(\d{2})/(\d{2})/(\d{4}) (\d{2}):(\d{2})$',
    ).firstMatch(input.trim());
    if (match == null) {
      throw const RuleException('Indica fecha y hora: 08/10/2026 09:00');
    }
    final values = [for (var i = 1; i <= 5; i++) int.parse(match.group(i)!)];
    final day = values[0],
        month = values[1],
        year = values[2],
        hour = values[3],
        minute = values[4];
    final wall = DateTime.utc(year, month, day, hour, minute);
    if (year < 2000 ||
        year > 2100 ||
        wall.year != year ||
        wall.month != month ||
        wall.day != day ||
        wall.hour != hour ||
        wall.minute != minute) {
      throw const RuleException('Fecha u hora inválidas');
    }
    final loc = location(zone), candidates = <DateTime>[];
    for (final offset in loc.zones.map((z) => z.offset).toSet()) {
      final utc = wall.subtract(offset), local = tz.TZDateTime.from(utc, loc);
      if (local.year == year &&
          local.month == month &&
          local.day == day &&
          local.hour == hour &&
          local.minute == minute) {
        candidates.add(utc);
      }
    }
    candidates.sort();
    if (candidates.isEmpty) {
      throw const RuleException(
        'Esta hora no existe por el cambio de horario. Elige otra',
      );
    }
    if (candidates.length > 1 && !['first', 'second'].contains(fold)) {
      throw const RuleException(
        'Esta hora se repite por el cambio de horario. Elige la primera o segunda',
      );
    }
    return candidates[candidates.length > 1 && fold == 'second'
        ? candidates.length - 1
        : 0];
  }

  static String format(DateTime utc, String zone) {
    final d = tz.TZDateTime.from(utc, location(zone));
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${pad(d.day)}/${pad(d.month)}/${d.year} ${pad(d.hour)}:${pad(d.minute)}';
  }
}
