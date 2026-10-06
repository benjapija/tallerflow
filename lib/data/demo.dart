import '../domain/engine.dart';
import '../domain/models.dart';

const demoActors = [
  Actor('tech-alex', 'Álex Martín', Role.technician),
  Actor('tech-lucia', 'Lucía Pérez', Role.technician),
  Actor('office', 'Marta Ruiz', Role.office, seePrices: true),
  Actor('admin', 'Administrador', Role.admin, seePrices: true),
];
Map<String, dynamic> demoTask(
  String id,
  String title, {
  bool authorized = true,
  bool done = false,
  int estimate = 60,
  int billed = 0,
  List<String> assignees = const ['tech-alex'],
  int approval = 40000,
}) => {
  'id': id,
  'title': title,
  'authorized': authorized,
  'done': done,
  'assignees': assignees,
  'estimateMinutes': estimate,
  'billableMinutes': billed,
  'rateCents': 4800,
  'taxBps': 2100,
  'approvedCents': authorized ? approval : 0,
  'authorization': authorized
      ? {
          'version': 1,
          'customer': 'Cliente demo',
          'evidence': 'Autorización telefónica · ejemplo',
          'at': '2026-10-06T07:00:00Z',
        }
      : null,
};
WorkshopState demoState() {
  final specs = [
    [
      'o-1048',
      'OT-1048',
      '4821 LKR',
      'Volkswagen Golf',
      '2.0 TDI · 2020',
      'Elena García',
      'repair',
      'Al frenar noto una vibración en el volante.',
      'Elevador 2',
      'Panel B · 12',
      'Alta',
      'Hoy · 17:00',
      128450,
    ],
    [
      'o-1047',
      'OT-1047',
      '7392 JDS',
      'Seat León',
      '1.6 TDI · 2018',
      'Javier Moreno',
      'authorization',
      'Se enciende el testigo del motor de forma intermitente.',
      'Zona de diagnóstico',
      'Panel A · 08',
      'Normal',
      'Mañana · 12:00',
      164220,
    ],
    [
      'o-1046',
      'OT-1046',
      '2056 MBC',
      'Toyota Yaris',
      '1.5 Hybrid · 2022',
      'Laura Sánchez',
      'parts',
      'Revisión de mantenimiento y ruido al girar.',
      'Plaza 4',
      'Panel B · 04',
      'Normal',
      'Mañana · 16:00',
      48200,
    ],
    [
      'o-1045',
      'OT-1045',
      '6184 KPN',
      'Renault Kangoo',
      '1.5 dCi · 2019',
      'Floristería Azahar',
      'verified',
      'Cambio de aceite y filtro. Revisar niveles.',
      'Salida · plaza 1',
      'Recepción',
      'Normal',
      'Hoy · 15:30',
      98200,
    ],
    [
      'o-1044',
      'OT-1044',
      '9031 LTX',
      'Peugeot 3008',
      '1.2 PureTech · 2021',
      'Carlos Romero',
      'diagnosis',
      'Ruido en la parte delantera al pasar por baches.',
      'Elevador 1',
      'Panel A · 03',
      'Normal',
      'Hoy · 18:00',
      73400,
    ],
  ];
  final orders = <String, WorkOrder>{};
  for (var i = 0; i < specs.length; i++) {
    final s = specs[i];
    final tasks = i == 0
        ? [
            demoTask(
              't-1',
              'Sustituir discos y pastillas delanteras',
              estimate: 90,
            ),
            demoTask(
              't-2',
              'Comprobar vibración y prueba de frenado',
              estimate: 30,
            ),
          ]
        : i == 1
        ? [
            demoTask('t-3', 'Diagnóstico inicial', done: true, billed: 30),
            demoTask(
              't-4',
              'Ampliación: comprobación del sistema de admisión',
              authorized: false,
            ),
          ]
        : i == 3
        ? [
            demoTask(
              't-6',
              'Servicio de aceite y filtro',
              done: true,
              estimate: 45,
              billed: 45,
            ),
          ]
        : [
            demoTask(
              't-$i-main',
              i == 2 ? 'Mantenimiento periódico' : 'Diagnóstico de ruido',
              assignees: ['tech-lucia'],
            ),
          ];
    orders[s[0] as String] = WorkOrder({
      'id': s[0],
      'number': s[1],
      'vehicleId': 'vehicle-$i',
      'plate': normalizePlate(s[2] as String),
      'country': 'ES',
      'vin': 'VIN-DEMO-$i-NO-VALIDO',
      'vehicle': s[3],
      'engine': s[4],
      'client': s[5],
      'phone': '600 000 10$i',
      'status': s[6],
      'symptom': s[7],
      'location': s[8],
      'keys': s[9],
      'priority': s[10],
      'due': s[11],
      'km': s[12],
      'revision': 0,
      'tasks': tasks,
      'times': <Map<String, dynamic>>[],
      'parts': <Map<String, dynamic>>[],
      'notes': <Map<String, dynamic>>[],
      'quality': i == 3
          ? {
              'result': 'Niveles y fugas comprobados. Sin síntomas pendientes.',
              'actorId': 'tech-alex',
              'at': '2026-10-06T11:00:00Z',
            }
          : null,
      'block': i == 2
          ? 'Filtro pendiente de recepción'
          : i == 1
          ? 'Ampliación pendiente del cliente'
          : null,
      'nextAction': i == 2
          ? 'Oficina · confirmar entrega del proveedor'
          : i == 1
          ? 'Marta · contactar con el cliente'
          : null,
    });
  }
  return WorkshopState(
    workshopId: 'demo-workshop',
    orders: orders,
    members: demoActors,
    catalog: const [
      CatalogItem(
        id: 'p-1',
        reference: 'BRK-DF-01',
        description: 'Disco de freno delantero',
        unit: 'ud',
        priceCents: 6800,
        costCents: 3900,
        stockMilli: 8000,
      ),
      CatalogItem(
        id: 'p-2',
        reference: 'BRK-PD-01',
        description: 'Juego de pastillas delanteras',
        unit: 'juego',
        priceCents: 5400,
        costCents: 2850,
        stockMilli: 4000,
      ),
      CatalogItem(
        id: 'p-3',
        reference: 'OIL-5W30',
        description: 'Aceite 5W-30',
        unit: 'L',
        priceCents: 1450,
        costCents: 650,
        stockMilli: 48000,
        minMilli: 15000,
      ),
      CatalogItem(
        id: 'p-4',
        reference: 'FLT-OL-01',
        description: 'Filtro de aceite',
        unit: 'ud',
        priceCents: 1800,
        costCents: 900,
        stockMilli: 6000,
      ),
    ],
  );
}
