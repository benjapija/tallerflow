import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:uuid/uuid.dart';
import '../domain/models.dart';
import '../data/controller.dart';
import '../data/demo.dart';
import 'dialogs.dart';
import 'simulation.dart';
import 'backup_panel.dart';
import 'management_panel.dart';
import 'task_management.dart';
import 'vehicle_history.dart';
import '../domain/vehicles.dart';
import 'pricing_panel.dart';
import '../domain/order_links.dart';
import '../data/order_link_inbox.dart';
import 'qr_scanner.dart';
import 'photo_panel.dart';
import 'inspection_panel.dart';
import 'quote_panel.dart';
import 'payment_panel.dart';
import '../domain/payments.dart';
import '../domain/document_export.dart';
import 'document_export_button.dart';
import '../domain/purchases.dart';
import 'purchase_panel.dart';
import '../domain/linked_returns.dart';
import 'diagnosis_panel.dart';
import 'case_library_panel.dart';

const ink = Color(0xff192d2a),
    muted = Color(0xff72827e),
    green = Color(0xff16856b),
    paper = Color(0xfff4f6f3),
    line = Color(0xffe2e8e3);
ThemeData tallerTheme() => ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: green,
    primary: green,
    surface: Colors.white,
  ),
  scaffoldBackgroundColor: paper,
  fontFamily: 'Manrope',
  textTheme: const TextTheme(
    bodyMedium: TextStyle(color: ink, fontSize: 14),
    bodySmall: TextStyle(color: muted, fontSize: 12),
    titleLarge: TextStyle(
      color: ink,
      fontSize: 22,
      fontWeight: FontWeight.w700,
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.all(16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: line),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: line),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(48, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(48, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      side: const BorderSide(color: line),
    ),
  ),
  cardTheme: CardThemeData(
    elevation: 0,
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: const BorderSide(color: line),
    ),
  ),
);

class TallerFlowApp extends StatelessWidget {
  final WorkshopController controller;
  final Future<void> Function()? onLogout;
  const TallerFlowApp({super.key, required this.controller, this.onLogout});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'TallerFlow',
    theme: tallerTheme(),
    home: WorkshopHome(controller: controller, onLogout: onLogout),
  );
}

class WorkshopHome extends StatefulWidget {
  final WorkshopController controller;
  final Future<void> Function()? onLogout;
  const WorkshopHome({super.key, required this.controller, this.onLogout});
  @override
  State<WorkshopHome> createState() => _WorkshopHomeState();
}

class _WorkshopHomeState extends State<WorkshopHome>
    with WidgetsBindingObserver {
  int page = 0;
  String? selected;
  String search = '';
  OrderStatus? filter;
  late Timer ticker;
  WorkshopController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    c.addListener(changed);
    OrderLinkInbox.shared.addListener(openPendingLink);
    WidgetsBinding.instance.addPostFrameCallback((_) => openPendingLink());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(runAction(() => recoverInterruptedPhotoCapture(c)));
    });
    WidgetsBinding.instance.addObserver(this);
    var ticks = 0;
    ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
      if (++ticks % 30 == 0 && !c.demo && !c.offline) {
        unawaited(c.synchronize());
      }
    });
  }

  @override
  void dispose() {
    ticker.cancel();
    c.removeListener(changed);
    OrderLinkInbox.shared.removeListener(openPendingLink);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void changed() {
    if (mounted) {
      setState(() {});
      openPendingLink();
    }
  }

  void openPendingLink() {
    if (!mounted || !c.accessAllowed) return;
    final ref = OrderLinkInbox.shared.pending;
    if (ref == null) return;
    final order = ref.resolve(c.visibleOrders);
    if (order == null) {
      return; // It may arrive after login or the next snapshot.
    }
    OrderLinkInbox.shared.clear();
    setState(() {
      selected = order.id;
      page = 1;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !c.demo) {
      unawaited(c.synchronize());
    }
  }

  Future<void> runAction(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> perform(
    String id,
    String kind,
    Map<String, dynamic> payload, {
    int? expectedRevision,
  }) async {
    try {
      await c.execute(id, kind, payload, expectedRevision: expectedRevision);
      if (!c.demo && !c.offline) unawaited(c.synchronize());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$e'),
            backgroundColor: const Color(0xffa64e39),
          ),
        );
      }
    }
  }

  void go(int value) {
    setState(() {
      page = value;
      selected = null;
    });
  }

  Future<void> receive([WorkOrder? original]) async {
    final profile = original == null
        ? null
        : vehicleProfiles(
            c.state,
          ).where((v) => v['id'] == original.vehicleId).firstOrNull;
    final owner = profile?['owner'] as Map?;
    final data = await receptionDialog(
      context,
      c.state.members,
      sourceOrderId: original?.id,
      initial: profile == null
          ? const {}
          : {
              'plate': profile['plate'],
              'country': profile['country'],
              'vin': profile['vin'],
              'vehicle': profile['vehicle'],
              'engine': profile['engine'],
              'client': owner?['name'] ?? '',
              'phone': owner?['phone'] ?? '',
            },
    );
    if (data == null) return;
    final id = const Uuid().v4();
    await perform(id, 'receive', data);
    if (c.state.orders.containsKey(id)) {
      setState(() {
        selected = id;
        page = 1;
      });
    }
  }

  Future<void> openQr() async {
    final code = await readOrderCode(context);
    if (code == null) return;
    WorkOrder? found;
    try {
      found = OrderReference.parse(code).resolve(c.visibleOrders);
    } on FormatException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
      return;
    }
    if (found == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Orden no descargada o sin permiso de acceso'),
          ),
        );
      }
      return;
    }
    setState(() {
      selected = found!.id;
      page = 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!c.accessAllowed) {
      return Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, size: 42),
                  const SizedBox(height: 18),
                  const Text(
                    'Conecta para revalidar tu cuenta o revisar la retirada del dispositivo. Tus registros pendientes permanecen protegidos.',
                  ),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: () => runAction(c.synchronize),
                    child: const Text('Revalidar'),
                  ),
                  if (c.remote?.requiresLease == true)
                    TextButton(
                      onPressed: loginAgain,
                      child: const Text('Iniciar sesión de nuevo'),
                    ),
                  if (c.accessRevoked && c.outbox.isNotEmpty)
                    TextButton(
                      onPressed: () => runAction(c.recoverRetiredRecords),
                      child: const Text(
                        'Enviar registros recuperados para revisión',
                      ),
                    ),
                  if (c.accessRevoked && c.outbox.isEmpty)
                    TextButton(
                      onPressed: replaceDevice,
                      child: const Text('Registrar dispositivo sustituto'),
                    ),
                  if (c.syncError != null) Text(c.syncError!),
                ],
              ),
            ),
          ),
        ),
      );
    }
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    final order = selected == null
        ? null
        : c.visibleOrders.where((o) => o.id == selected).firstOrNull;
    return Scaffold(
      drawer: wide ? null : Drawer(child: sidebar()),
      bottomNavigationBar: wide || ![0, 1, 4].contains(page)
          ? null
          : NavigationBar(
              selectedIndex: page == 0
                  ? 0
                  : page == 1
                  ? 1
                  : 2,
              onDestinationSelected: (i) => go([0, 1, 4][i]),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.space_dashboard_outlined),
                  label: 'Panel',
                ),
                NavigationDestination(
                  icon: Icon(Icons.build_outlined),
                  label: 'Órdenes',
                ),
                NavigationDestination(
                  icon: Icon(Icons.fact_check_outlined),
                  label: 'Revisión',
                ),
              ],
            ),
      body: Row(
        children: [
          if (wide) SizedBox(width: 238, child: sidebar()),
          Expanded(
            child: Column(
              children: [
                topbar(wide),
                if (c.demo)
                  Container(
                    width: double.infinity,
                    color: const Color(0xffe9f3ed),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 9,
                    ),
                    child: Text(
                      kIsWeb
                          ? 'DEMOSTRACIÓN · Datos ficticios · Los cambios duran hasta recargar la página'
                          : 'DEMOSTRACIÓN · Datos ficticios guardados en este dispositivo',
                      style: const TextStyle(color: green, fontSize: 12),
                    ),
                  ),
                if (c.syncError != null)
                  MaterialBanner(
                    content: Text(c.syncError!),
                    actions: [
                      TextButton(
                        onPressed: c.synchronize,
                        child: const Text('Reintentar'),
                      ),
                    ],
                  ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(wide ? 32 : 18),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1440),
                        child: order != null
                            ? detail(order, wide)
                            : page == 2
                            ? VehicleHistory(
                                controller: c,
                                query: search,
                                openOrder: (id) => setState(() {
                                  selected = id;
                                  page = 1;
                                }),
                              )
                            : page == 3
                            ? catalog()
                            : page == 4
                            ? reviewList()
                            : page == 6
                            ? CaseLibraryPanel(controller: c, run: runAction)
                            : page == 5
                            ? settings()
                            : dashboard(wide),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget sidebar() => Material(
    color: ink,
    child: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 30, 24, 28),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: green,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.handyman_rounded,
                    color: Colors.white,
                    size: 23,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'TallerFlow',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 23,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 25),
            child: Text(
              c.demo ? 'TALLER DEMO' : 'MI TALLER',
              style: const TextStyle(
                color: Color(0xff96aaa2),
                fontSize: 10,
                letterSpacing: 1.8,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 20),
          for (final item in [
            (0, Icons.space_dashboard_outlined, 'Panel del taller'),
            (1, Icons.build_outlined, 'Órdenes de trabajo'),
            (2, Icons.directions_car_outlined, 'Vehículos e historial'),
            (3, Icons.inventory_2_outlined, 'Catálogo'),
            (4, Icons.fact_check_outlined, 'Revisión de oficina'),
            (5, Icons.tune_rounded, 'Configuración'),
            (6, Icons.menu_book_outlined, 'Biblioteca técnica'),
          ])
            if ((item.$1 != 4 || c.actor.isOffice) &&
                (item.$1 != 5 || c.actor.role == Role.admin || c.demo))
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 3,
                ),
                child: ListTile(
                  dense: true,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                  selected: page == item.$1,
                  selectedTileColor: const Color(0xff2b4740),
                  onTap: () {
                    go(item.$1);
                    if (MediaQuery.sizeOf(context).width < 1000) {
                      Navigator.pop(context);
                    }
                  },
                  leading: Icon(
                    item.$2,
                    color: page == item.$1
                        ? const Color(0xff8ddfc0)
                        : const Color(0xffa5b8b0),
                    size: 20,
                  ),
                  title: Text(
                    item.$3,
                    style: TextStyle(
                      color: page == item.$1
                          ? Colors.white
                          : const Color(0xffbdcdc7),
                      fontSize: 13,
                      fontWeight: page == item.$1
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                ),
              ),
          const Spacer(),
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: const Color(0xff243d36),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.verified_user_outlined,
                      color: Color(0xff85c5ac),
                      size: 18,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'El trabajo, a salvo',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 7),
                Text(
                  'Registra tu jornada aunque no tengas conexión.',
                  style: TextStyle(
                    color: Color(0xffa5b8b0),
                    height: 1.5,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 20, 24),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 17,
                  backgroundColor: const Color(0xffcfddd3),
                  child: Text(
                    c.actor.name.substring(0, 1),
                    style: const TextStyle(
                      color: ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.actor.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        roleLabels[c.actor.role.index],
                        style: const TextStyle(
                          color: Color(0xff9bb1a7),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.onLogout != null)
                  IconButton(
                    onPressed: () async {
                      try {
                        await widget.onLogout!();
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text('$e')));
                        }
                      }
                    },
                    tooltip: 'Cerrar sesión',
                    icon: const Icon(
                      Icons.logout,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  Widget topbar(bool wide) => Container(
    height: 72,
    padding: EdgeInsets.symmetric(horizontal: wide ? 32 : 12),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(bottom: BorderSide(color: line)),
    ),
    child: Row(
      children: [
        if (!wide)
          Builder(
            builder: (ctx) => IconButton(
              onPressed: () => Scaffold.of(ctx).openDrawer(),
              icon: const Icon(Icons.menu),
            ),
          ),
        if (wide)
          const Text(
            'Espacio de trabajo',
            style: TextStyle(color: muted, fontSize: 13),
          ),
        const Spacer(),
        TextButton.icon(
          onPressed: c.demo ? () => setState(c.toggleOffline) : c.synchronize,
          icon: Icon(
            c.offline
                ? Icons.cloud_off_outlined
                : c.demo
                ? Icons.devices_outlined
                : Icons.sync,
            size: 17,
          ),
          label: Text(
            c.offline
                ? 'Sin conexión'
                : c.demo
                ? 'Modo local'
                : c.outbox.isEmpty
                ? 'Actualizar'
                : '${c.outbox.length} pendientes',
            style: const TextStyle(fontSize: 12),
          ),
        ),
        const SizedBox(width: 12),
        if (c.demo)
          DropdownButton<Actor>(
            value: demoActors.firstWhere((a) => a.id == c.actor.id),
            underline: const SizedBox.shrink(),
            icon: const Icon(Icons.expand_more, size: 18),
            items: demoActors
                .map(
                  (a) => DropdownMenuItem(
                    value: a,
                    child: Text(a.name, style: const TextStyle(fontSize: 12)),
                  ),
                )
                .toList(),
            onChanged: (a) {
              if (a != null) {
                c.changeDemoActor(a);
                setState(() {
                  selected = null;
                  page = 0;
                });
              }
            },
          )
        else
          Text(c.actor.name),
      ],
    ),
  );
  Widget heading(String title, String subtitle, {Widget? action}) => Padding(
    padding: const EdgeInsets.only(bottom: 25),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 24,
      runSpacing: 16,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.7,
              ),
            ),
            const SizedBox(height: 7),
            Text(subtitle, style: const TextStyle(color: muted, fontSize: 13)),
          ],
        ),
        ?action,
      ],
    ),
  );
  Widget dashboard(bool wide) {
    final all = c.visibleOrders;
    final profiles = {for (final v in vehicleProfiles(c.state)) v['id']: v};
    final filtered = all
        .where(
          (o) =>
              (filter == null || o.status == filter) &&
                  '${o.plate} ${o.vehicle} ${o.client} ${o.data['phone']} ${o.data['vin']} ${o.number}'
                      .toLowerCase()
                      .contains(search.toLowerCase()) ||
              (filter == null || o.status == filter) &&
                  (normalizePlate(o.plate).contains(normalizePlate(search)) ||
                      (profiles[o.data['vehicleId']] != null &&
                          vehicleMatches(
                            profiles[o.data['vehicleId']]!,
                            search,
                            personal: c.actor.isOffice,
                          ))),
        )
        .toList();
    final active = all.where((o) => o.status != OrderStatus.delivered).length;
    final blocked = all
        .where(
          (o) =>
              [OrderStatus.parts, OrderStatus.authorization].contains(o.status),
        )
        .length;
    final ready = all
        .where(
          (o) =>
              [OrderStatus.finished, OrderStatus.verified].contains(o.status) &&
              !o.issued,
        )
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        heading(
          page == 1
              ? 'Órdenes de trabajo'
              : c.actor.isOffice
              ? 'Todo el taller, de un vistazo'
              : 'Tu jornada en el taller',
          'Cada reparación tiene un responsable y un siguiente paso.',
          action: c.actor.isOffice
              ? FilledButton.icon(
                  onPressed: receive,
                  icon: const Icon(Icons.add, size: 20),
                  label: const Text('Nueva recepción'),
                )
              : OutlinedButton.icon(
                  onPressed: openQr,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Abrir orden'),
                ),
        ),
        if (page == 0 && (wide || c.actor.isOffice))
          Padding(
            padding: const EdgeInsets.only(bottom: 28),
            child: LayoutBuilder(
              builder: (ctx, constraints) {
                final width =
                    (constraints.maxWidth - (wide ? 48 : 12)) / (wide ? 4 : 2);
                return Wrap(
                  spacing: wide ? 16 : 12,
                  runSpacing: 12,
                  children: [
                    stat(
                      'Vehículos en curso',
                      '$active',
                      'En el taller',
                      Icons.directions_car_outlined,
                      green,
                      width,
                    ),
                    stat(
                      'Trabajos bloqueados',
                      '$blocked',
                      'Requieren una acción',
                      Icons.pause_circle_outline,
                      const Color(0xffb28428),
                      width,
                    ),
                    stat(
                      'Pendientes de revisión',
                      '$ready',
                      'Listos para oficina',
                      Icons.fact_check_outlined,
                      const Color(0xff537da5),
                      width,
                    ),
                    stat(
                      'Registros pendientes',
                      '${c.outbox.length}',
                      c.demo ? 'Guardado local' : 'Por enviar a la nube',
                      Icons.sync_outlined,
                      muted,
                      width,
                    ),
                  ],
                );
              },
            ),
          ),
        if (page == 0 && blocked > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 25),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xfffff9eb),
                border: Border.all(color: const Color(0xffede0bc)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.notifications_none,
                    color: Color(0xffa97d2a),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '$blocked reparaciones necesitan atención. Revisa la autorización y las piezas pendientes.',
                      style: const TextStyle(
                        color: Color(0xff806322),
                        fontSize: 12,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => filter = OrderStatus.parts),
                    child: const Text('Ver bloqueos'),
                  ),
                ],
              ),
            ),
          ),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Reparaciones en curso',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            TextButton.icon(
              onPressed: openQr,
              icon: const Icon(Icons.qr_code, size: 17),
              label: const Text('Abrir por código'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: wide ? 330 : double.infinity,
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Matrícula, VIN, cliente o teléfono',
                  prefixIcon: Icon(Icons.search, size: 20),
                ),
                onChanged: (v) => setState(() => search = v),
              ),
            ),
            DropdownButton<OrderStatus?>(
              value: filter,
              hint: const Text('Todos los estados'),
              items: [
                const DropdownMenuItem<OrderStatus?>(
                  value: null,
                  child: Text('Todos los estados'),
                ),
                ...OrderStatus.values.map(
                  (s) => DropdownMenuItem<OrderStatus?>(
                    value: s,
                    child: Text(
                      statusLabels[s.index],
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
              ],
              onChanged: (v) => setState(() => filter = v),
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (filtered.isEmpty)
          const Padding(
            padding: EdgeInsets.all(35),
            child: Text('No hay órdenes que coincidan con la búsqueda.'),
          ),
        for (final o in filtered)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: orderRow(o, wide),
          ),
        const SizedBox(height: 12),
        Text(
          '${filtered.length} órdenes · El estado del cobro se gestiona por separado',
          style: const TextStyle(fontSize: 11, color: muted),
        ),
      ],
    );
  }

  Widget stat(
    String title,
    String value,
    String detail,
    IconData icon,
    Color color,
    double width,
  ) => SizedBox(
    width: width,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontSize: 12, color: muted),
                  ),
                ),
                Icon(icon, size: 20, color: color),
              ],
            ),
            const SizedBox(height: 17),
            Text(
              value,
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 7),
            Text(detail, style: TextStyle(fontSize: 11, color: color)),
          ],
        ),
      ),
    ),
  );
  Widget plate(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: const Color(0xfff6f8f5),
      border: Border.all(color: line),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 1,
      ),
    ),
  );
  Widget status(WorkOrder o) {
    final color =
        [OrderStatus.parts, OrderStatus.authorization].contains(o.status)
        ? const Color(0xffae8123)
        : o.status == OrderStatus.verified
        ? const Color(0xff527da1)
        : green;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 6, color: color),
          const SizedBox(width: 6),
          Text(
            statusLabels[o.status.index],
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget orderRow(WorkOrder o, bool wide) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => setState(() {
        selected = o.id;
        page = 1;
      }),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: wide
            ? Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: paper,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.directions_car_outlined,
                      color: muted,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              o.vehicle,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            plate(o.plate),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${o.number} · ${o.client}',
                          style: const TextStyle(fontSize: 11, color: muted),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        status(o),
                        const SizedBox(height: 7),
                        Text(
                          o.data['block'] ?? o.tasks.first['title'],
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: muted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          o.data['due'],
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          o.data['location'],
                          style: const TextStyle(fontSize: 11, color: muted),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: muted, size: 20),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          o.vehicle,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      plate(o.plate),
                    ],
                  ),
                  const SizedBox(height: 12),
                  status(o),
                  const SizedBox(height: 12),
                  Text(
                    '${o.number} · ${o.client}',
                    style: const TextStyle(fontSize: 12, color: muted),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    '${o.data['due']} · ${o.data['location']}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  if (o.data['block'] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        o.data['block'],
                        style: const TextStyle(
                          color: Color(0xffae8123),
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
      ),
    ),
  );
  Widget section(String title, List<Widget> children, {Widget? trailing}) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  ?trailing,
                ],
              ),
              const SizedBox(height: 18),
              ...children,
            ],
          ),
        ),
      );
  Widget detail(WorkOrder o, bool wide) {
    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TaskManagement(controller: c, order: o, perform: perform),
        const SizedBox(height: 18),
        DiagnosisPanel(
          order: o,
          actor: c.actor,
          onSave: (kind, p, revision) =>
              perform(o.id, kind, p, expectedRevision: revision),
        ),
        TextButton.icon(
          onPressed: () => draftCase(context, c, o, runAction),
          icon: const Icon(Icons.menu_book_outlined),
          label: const Text('Preparar caso para la biblioteca'),
        ),
        if (c.actor.isOffice &&
            (o.issued ||
                [
                  OrderStatus.finished,
                  OrderStatus.verified,
                  OrderStatus.delivered,
                ].contains(o.status)))
          TextButton.icon(
            onPressed: () => receive(o),
            icon: const Icon(Icons.assignment_return_outlined),
            label: const Text('Abrir regreso vinculado'),
          ),
        if (o.data['returnHistory'] is List &&
            (o.data['returnHistory'] as List).isNotEmpty)
          section('Regreso vinculado', [
            for (final link in (o.data['returnHistory'] as List).reversed)
              Text(
                '${returnClassifications[link['classification']]} · ${link['reason']} · ${link['at']}',
              ),
            if (c.actor.isOffice && !o.issued)
              TextButton(
                onPressed: () async {
                  final first = o.data['returnHistory'].first;
                  final p = await formDialog(
                    context,
                    'Revisar clasificación del regreso',
                    [
                      FieldSpec(
                        'classification',
                        'Clasificación',
                        initial: o.data['returnHistory'].last['classification'],
                        choices: returnClassifications,
                      ),
                      const FieldSpec(
                        'reason',
                        'Motivo de la revisión',
                        multiline: true,
                      ),
                    ],
                    (v) => {...v, 'sourceOrderId': first['sourceOrderId']},
                  );
                  if (p != null) {
                    await perform(
                      o.id,
                      'return_classify',
                      p,
                      expectedRevision: o.revision,
                    );
                  }
                },
                child: const Text('Revisar clasificación'),
              ),
          ]),
        const SizedBox(height: 18),
        section('Descripción del cliente', [
          Text(
            '“${o.symptom}”',
            style: const TextStyle(fontSize: 16, height: 1.6),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 24,
            runSpacing: 12,
            children: [
              info('Kilometraje', '${o.data['km']} km'),
              info('Vehículo', o.data['engine']),
              info('Ubicación', o.data['location']),
              info('Llaves', o.data['keys']),
            ],
          ),
          if (o.data['block'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 18),
              child: Text(
                '${o.data['block']}\n${o.data['nextAction'] ?? ''}',
                style: const TextStyle(color: Color(0xffad7f24), height: 1.5),
              ),
            ),
        ]),
        const SizedBox(height: 18),
        section(
          'Tareas y tiempos',
          [for (final t in o.tasks) taskCard(o, t)],
          trailing: Text(
            '${o.tasks.where((t) => t['done'] == true).length}/${o.tasks.length}',
            style: const TextStyle(color: muted),
          ),
        ),
        const SizedBox(height: 18),
        section(
          'Piezas y consumibles',
          [
            if (o.parts.isEmpty)
              const Text(
                'Sin consumos registrados.',
                style: TextStyle(color: muted),
              ),
            for (final p in o.parts)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    const Icon(
                      Icons.inventory_2_outlined,
                      size: 20,
                      color: muted,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p['description'],
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            '${p['reference']} · ${p['kind'] == 'reserve'
                                ? 'Reservada'
                                : p['kind'] == 'return'
                                ? 'Devuelta'
                                : p['kind'] == 'customer'
                                ? 'Aportada por el cliente'
                                : 'Consumida'}',
                            style: const TextStyle(color: muted, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${quantity(p['quantityMilli'])} ${p['unit']}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    if (!o.issued && p['kind'] == 'consume')
                      IconButton(
                        tooltip: 'Devolver al almacén',
                        onPressed: () async {
                          final value = await textDialog(
                            context,
                            'Devolución al almacén',
                            'Cantidad devuelta',
                            initial: quantity(p['quantityMilli']),
                          );
                          if (value != null) {
                            try {
                              await perform(o.id, 'return', {
                                'sourceId': p['id'],
                                'quantityMilli': parseQuantity(value),
                              });
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(
                                  context,
                                ).showSnackBar(SnackBar(content: Text('$e')));
                              }
                            }
                          }
                        },
                        icon: const Icon(Icons.undo, size: 18),
                      ),
                  ],
                ),
              ),
          ],
          trailing: o.issued
              ? null
              : TextButton.icon(
                  onPressed: () async {
                    final p = await partDialog(
                      context,
                      c.state.catalog,
                      o.tasks
                          .where(
                            (t) =>
                                t['authorized'] == true &&
                                (c.actor.isOffice ||
                                    (t['assignees'] as List).contains(
                                      c.actor.id,
                                    )),
                          )
                          .toList(),
                    );
                    if (p != null) await perform(o.id, 'part', p);
                  },
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Añadir'),
                ),
        ),
        const SizedBox(height: 18),
        section(
          'Observaciones y traspaso',
          [
            for (final n in o.notes)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(n['text'], style: const TextStyle(height: 1.5)),
                    const SizedBox(height: 5),
                    Text(
                      '${n['author']} · ${n['at'].toString().substring(0, 16)}',
                      style: const TextStyle(color: muted, fontSize: 11),
                    ),
                  ],
                ),
              ),
            if (o.notes.isEmpty)
              const Text(
                'Deja lo que hiciste, qué falta y las mediciones relevantes.',
                style: TextStyle(color: muted, height: 1.5),
              ),
          ],
          trailing: o.issued
              ? null
              : TextButton(
                  onPressed: () async {
                    final text = await textDialog(
                      context,
                      'Observación o traspaso de turno',
                      'Qué se hizo, qué falta y ubicación de piezas',
                      multiline: true,
                    );
                    if (text != null) {
                      await perform(o.id, 'note', {'text': text});
                    }
                  },
                  child: const Text('Añadir'),
                ),
        ),
        const SizedBox(height: 18),
        section('Comprobación final', [
          Text(
            o.verified
                ? o.data['quality']['result']
                : 'Comprueba el trabajo realizado y registra el resultado y los síntomas pendientes.',
            style: const TextStyle(height: 1.5, color: muted),
          ),
          if (!o.issued)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: OutlinedButton.icon(
                onPressed: () async {
                  final data = await qualityDialog(context);
                  if (data != null) await perform(o.id, 'quality', data);
                },
                icon: const Icon(Icons.verified_outlined),
                label: const Text('Registrar comprobación'),
              ),
            ),
        ]),
      ],
    );
    final right = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        section('Resumen de la reparación', [
          Row(
            children: [
              Expanded(child: info('Estimado', '${o.estimatedMinutes} min')),
              Expanded(
                child: info(
                  'Trabajado',
                  hours(o.workedSeconds(DateTime.now())),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          info('Facturable revisado', '${o.billableMinutes} min'),
          const SizedBox(height: 16),
          const Text(
            'Las esperas y el tiempo trabajado no se convierten automáticamente en cargos.',
            style: TextStyle(fontSize: 11, color: muted, height: 1.5),
          ),
          const Divider(height: 30),
          info(
            'Responsables',
            o.tasks
                .expand((t) => (t['assignees'] as List).cast<String>())
                .toSet()
                .map(
                  (id) =>
                      c.state.members
                          .where((a) => a.id == id)
                          .firstOrNull
                          ?.name ??
                      id,
                )
                .join('\n'),
          ),
          const SizedBox(height: 16),
          info('Fecha prevista', o.data['due']),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () => showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(o.number),
                content: SizedBox(
                  width: 240,
                  height: 280,
                  child: Column(
                    children: [
                      QrImageView(
                        data: c.demo && o.id.startsWith('o-')
                            ? o.number
                            : orderLink(o.id),
                        size: 220,
                      ),
                      const Text(
                        'El acceso requiere una cuenta con permisos.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(
                          text: c.demo && o.id.startsWith('o-')
                              ? o.number
                              : orderLink(o.id),
                        ),
                      );
                      Navigator.pop(ctx);
                    },
                    child: const Text('Copiar código'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cerrar'),
                  ),
                ],
              ),
            ),
            icon: const Icon(Icons.qr_code, size: 20),
            label: const Text('QR de la orden'),
          ),
        ]),
        const SizedBox(height: 18),
        PhotoPanel(controller: c, order: o),
        const SizedBox(height: 18),
        InspectionPanel(
          order: o,
          canEdit: !c.frozen(o.id),
          onSave: (p) => perform(o.id, 'inspection_save', p),
        ),
        const SizedBox(height: 18),
        if (c.prices || c.costs) ...[
          if (c.actor.isOffice) ...[
            QuotePanel(
              order: o,
              actor: c.actor,
              catalog: c.state.catalog,
              defaultTaxBps: c.state.settings['taxBps'] as int,
              canEdit: !c.frozen(o.id),
              onSave: (kind, p) =>
                  perform(o.id, kind, p, expectedRevision: o.revision),
            ),
            const SizedBox(height: 18),
          ],
          PricingPanel(
            order: o,
            canEdit: c.actor.isOffice,
            showPrices: c.prices,
            showCosts: c.costs,
            settings: c.state.settings,
            members: c.state.members,
            onReview: (p) => perform(o.id, 'pricing_review', p),
          ),
          const SizedBox(height: 18),
        ],
        if (c.actor.isOffice && o.issued) ...[
          PaymentPanel(
            order: o,
            canEdit: !c.frozen(o.id),
            onSave: (kind, p) =>
                perform(o.id, kind, p, expectedRevision: o.revision),
          ),
          const SizedBox(height: 18),
        ],
        if (!c.demo && !o.issued)
          section('Confirmación de este dispositivo', [
            Text(
              c.frozen(o.id)
                  ? 'Orden bloqueada localmente. Se conserva el bloqueo al reiniciar.'
                  : 'Antes de confirmar, pausa tus cronómetros y sincroniza los registros.',
            ),
            if (c.closure(o.id) != null) ...[
              Text(
                'Revisión ${c.closure(o.id)!['revision']} · ${(c.closure(o.id)!['confirmedDevices'] as List).length}/${(c.closure(o.id)!['requiredDevices'] as List).length} dispositivos confirmados',
              ),
              if (c.closure(o.id)!['exceptionReason'] != null)
                Text(
                  'Excepción administrativa: ${c.closure(o.id)!['exceptionReason']}',
                ),
              TextButton(
                onPressed: () => runAction(() => c.confirmClose(o.id)),
                child: const Text('Sincronizado: bloquear y confirmar'),
              ),
            ],
          ]),
        if (c.actor.isOffice) reviewCard(o),
        if (c.prices)
          Padding(padding: const EdgeInsets.only(top: 18), child: noteCard(o)),
        const SizedBox(height: 18),
        section('Trazabilidad', [
          for (final a
              in c.state.audit
                  .where((a) => a['orderId'] == o.id)
                  .toList()
                  .reversed
                  .take(5))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                '${auditLabel(a['kind'])}\n${a['actor']} · ${a['at'].toString().substring(11, 16)}',
                style: const TextStyle(color: muted, fontSize: 11, height: 1.5),
              ),
            ),
          if (!c.state.audit.any((a) => a['orderId'] == o.id))
            const Text(
              'Sin modificaciones en esta demostración.',
              style: TextStyle(color: muted, fontSize: 12),
            ),
        ]),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          onPressed: () => setState(() => selected = null),
          icon: const Icon(Icons.arrow_back, size: 17),
          label: const Text('Volver a órdenes'),
        ),
        const SizedBox(height: 10),
        heading(
          '${o.vehicle} · ${o.number}',
          '${o.plate} · ${o.client}',
          action: status(o),
        ),
        wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 7, child: left),
                  const SizedBox(width: 22),
                  Expanded(flex: 3, child: right),
                ],
              )
            : Column(children: [left, const SizedBox(height: 18), right]),
      ],
    );
  }

  Widget taskCard(WorkOrder o, Map<String, dynamic> t) {
    final active = o.times
        .where(
          (e) =>
              e['taskId'] == t['id'] &&
              e['actorId'] == c.actor.id &&
              e['end'] == null,
        )
        .firstOrNull;
    final allowed =
        c.actor.isOffice || (t['assignees'] as List).contains(c.actor.id);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: paper,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                t['done'] == true
                    ? Icons.check_circle_outline
                    : t['authorized'] == true
                    ? Icons.radio_button_unchecked
                    : Icons.lock_outline,
                color: t['authorized'] == true
                    ? green
                    : const Color(0xffae8123),
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  t['title'],
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${t['estimateMinutes']} min estimados · ${t['billableMinutes']} min facturables',
            style: const TextStyle(color: muted, fontSize: 11),
          ),
          if (t['authorized'] != true)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                'Ampliación pendiente · no se incluye en la nota',
                style: TextStyle(color: Color(0xffae8123), fontSize: 11),
              ),
            ),
          if (active != null)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(
                duration(
                  DateTime.now()
                      .difference(DateTime.parse(active['start']))
                      .inSeconds,
                ),
                style: const TextStyle(
                  fontSize: 27,
                  color: green,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          if (!o.issued)
            Padding(
              padding: const EdgeInsets.only(top: 13),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (allowed &&
                      t['authorized'] == true &&
                      t['done'] != true &&
                      t['cancelled'] != true)
                    FilledButton.tonalIcon(
                      onPressed: () => perform(
                        o.id,
                        active == null ? 'start' : 'stop',
                        active == null
                            ? {'taskId': t['id']}
                            : {'sessionId': active['id']},
                      ),
                      icon: Icon(
                        active == null ? Icons.play_arrow : Icons.pause,
                        size: 19,
                      ),
                      label: Text(active == null ? 'Iniciar' : 'Pausar'),
                    ),
                  if (allowed &&
                      t['authorized'] == true &&
                      t['done'] != true &&
                      t['cancelled'] != true)
                    OutlinedButton(
                      onPressed: () =>
                          perform(o.id, 'finish_task', {'taskId': t['id']}),
                      child: const Text('Terminar'),
                    ),
                  if (allowed && t['authorized'] == true)
                    TextButton(
                      onPressed: () async {
                        final p = await manualTimeDialog(context);
                        if (p != null) {
                          await perform(o.id, 'manual_time', {
                            ...p,
                            'taskId': t['id'],
                          });
                        }
                      },
                      child: const Text('Tiempo manual'),
                    ),
                  if (c.actor.isOffice)
                    TextButton(
                      onPressed: () async {
                        final p = await authorizationDialog(context, o.client);
                        if (p != null) {
                          await perform(o.id, 'authorize', {
                            ...p,
                            'taskId': t['id'],
                          });
                        }
                      },
                      child: Text(
                        t['authorized'] == true ? 'Autorización' : 'Autorizar',
                      ),
                    ),
                  if (c.actor.isOffice && t['authorized'] == true)
                    TextButton(
                      onPressed: () async {
                        final p = await billableDialog(
                          context,
                          t['billableMinutes'],
                        );
                        if (p != null) {
                          await perform(o.id, 'billable', {
                            ...p,
                            'taskId': t['id'],
                          });
                        }
                      },
                      child: const Text('Revisar minutos'),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget info(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontSize: 11, color: muted)),
      const SizedBox(height: 5),
      Text(
        value,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          height: 1.4,
        ),
      ),
    ],
  );
  Widget reviewCard(WorkOrder o) {
    final issues = c.issues(o);
    return section('Revisión de cierre', [
      if (o.issued)
        const Text(
          'Nota emitida y conservada. Los nuevos datos se gestionan como incidencias.',
          style: TextStyle(color: green, height: 1.5),
        )
      else ...[
        if (!c.demo) ...[
          Text(
            c.frozen(o.id)
                ? 'Este dispositivo ha bloqueado la orden para confirmar el cierre.'
                : 'El cierre requiere confirmar todos los dispositivos de esta orden.',
          ),
          TextButton(
            onPressed: () => runAction(() => c.requestClose(o.id)),
            child: const Text('Solicitar o renovar cierre'),
          ),
          if (c.actor.role == Role.admin)
            TextButton(
              onPressed: () async {
                final reason = await textDialog(
                  context,
                  'Excepción por dispositivos retirados',
                  'Motivo y seguimiento de registros no recuperados',
                  help:
                      'La retirada no demuestra sincronización. La excepción quedará indicada en la nota.',
                );
                if (reason != null) {
                  await runAction(
                    () => c.requestClose(o.id, exceptionReason: reason),
                  );
                }
              },
              child: const Text(
                'Solicitar cierre con excepción administrativa',
              ),
            ),
        ],
        for (final issue in issues)
          Padding(
            padding: const EdgeInsets.only(bottom: 11),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline,
                  color: Color(0xffae8123),
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    issue,
                    style: const TextStyle(
                      color: muted,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (issues.isEmpty)
          const Text(
            'Comprobaciones completas.',
            style: TextStyle(color: green),
          ),
        if (o.parts.any((p) => p['reviewed'] != true))
          TextButton(
            onPressed: () => perform(o.id, 'review_parts', {}),
            child: const Text('Confirmar consumos'),
          ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: issues.isEmpty
                ? () => perform(o.id, 'issue', {
                    'pending': 0,
                    'connected': !c.offline,
                    'conflict': false,
                  })
                : null,
            child: Text(c.demo ? 'Emitir nota de demostración' : 'Emitir nota'),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Nota de trabajo. No es una factura fiscal.',
          style: TextStyle(fontSize: 10, color: muted),
        ),
      ],
      if (o.issued && o.status != OrderStatus.delivered)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: OutlinedButton(
            onPressed: () async {
              final reason = await textDialog(
                context,
                PaymentBalance.forOrder(o).outstandingCents > 0
                    ? 'Entregar con saldo pendiente: ${money(PaymentBalance.forOrder(o).outstandingCents)}'
                    : 'Registrar entrega con saldo pagado',
                'Motivo y persona que autoriza la entrega',
              );
              if (reason != null) {
                await perform(o.id, 'deliver', {
                  'reason': reason,
                }, expectedRevision: o.revision);
              }
            },
            child: const Text('Registrar entrega'),
          ),
        ),
    ]);
  }

  Widget noteCard(WorkOrder o) {
    final note = o.issued
        ? o.data['document'] as Map<String, dynamic>
        : calculateNote(o).toJson();
    return section(o.issued ? 'Nota emitida' : 'Borrador de nota', [
      if (o.issued && c.actor.isOffice)
        DocumentExportButton(
          source: () => DocumentExport.note(o, c.actor),
          filename: 'TallerFlow-nota-${o.number}.pdf',
        ),
      for (final l in note['lines'])
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  '${l['description']}\n${l['quantity']}${(l['discountCents'] ?? 0) > 0 ? '\nDescuento: ${money(l['discountCents'])}' : ''}${l['charge'] == false ? '\nSin cobro: ${l['noChargeReason'] ?? ''}' : ''}',
                  style: const TextStyle(fontSize: 11, height: 1.5),
                ),
              ),
              const SizedBox(width: 8),
              Text(money(l['netCents']), style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      if ((note['lines'] as List).isEmpty)
        const Text(
          'Sin importes confirmados.',
          style: TextStyle(color: muted, fontSize: 12),
        ),
      const Divider(height: 28),
      Row(
        children: [
          const Expanded(
            child: Text('Base', style: TextStyle(color: muted, fontSize: 12)),
          ),
          Text(money(note['netCents']), style: const TextStyle(fontSize: 12)),
        ],
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          const Expanded(
            child: Text(
              'Impuestos',
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ),
          Text(money(note['taxCents']), style: const TextStyle(fontSize: 12)),
        ],
      ),
      const Divider(height: 28),
      Row(
        children: [
          const Expanded(
            child: Text('Total', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          Text(
            money(note['totalCents']),
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 23,
              color: green,
            ),
          ),
        ],
      ),
    ]);
  }

  Widget catalog() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      heading(
        'Catálogo del taller',
        'La reserva y el consumo se muestran por separado.',
      ),
      if (c.actor.role == Role.admin ||
          (c.actor.isOffice && c.actor.seeCosts)) ...[
        PurchasePanel(
          ledger: PurchaseLedger(c.state.configuration['purchaseLedger']),
          catalog: c.state.catalog,
          repairOrders: c.visibleOrders.toList(),
          canEdit: c.accessAllowed,
          pending: c.outbox.isNotEmpty || c.pendingCommands.isNotEmpty,
          onSave: (action, payload) =>
              runAction(() => c.inventory(action, payload)),
        ),
        const SizedBox(height: 24),
      ],
      for (final item in c.state.catalog)
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: section(item.description, [
            Wrap(
              spacing: 24,
              runSpacing: 16,
              children: [
                info('Referencia', item.reference),
                info(
                  'Existencias',
                  '${quantity(c.state.stock(item.id))} ${item.unit}',
                ),
                info(
                  'Reservadas',
                  '${quantity(c.state.reserved(item.id))} ${item.unit}',
                ),
                info('Mínimo', '${quantity(item.minMilli)} ${item.unit}'),
                if (c.prices) info('Precio unitario', money(item.priceCents)),
                if (c.actor.role == Role.admin)
                  info('Coste unitario', money(item.costCents)),
              ],
            ),
            if (c.state.stock(item.id) < item.minMilli)
              const Padding(
                padding: EdgeInsets.only(top: 15),
                child: Text(
                  'Por debajo del stock mínimo',
                  style: TextStyle(color: Color(0xffae8123)),
                ),
              ),
          ]),
        ),
    ],
  );
  Widget reviewList() {
    if (!c.actor.isOffice) {
      return const Text('Esta vista requiere permisos de oficina.');
    }
    final orders = c.visibleOrders.where(
      (o) =>
          [OrderStatus.finished, OrderStatus.verified].contains(o.status) ||
          o.issued,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        heading(
          'Revisión de oficina',
          'Comprueba el trabajo antes de emitir la nota y entregar.',
        ),
        for (final o in orders)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: section('${o.number} · ${o.vehicle}', [
              status(o),
              const SizedBox(height: 14),
              Text(
                o.issued
                    ? 'Nota emitida · Pendiente: ${money(PaymentBalance.forOrder(o).outstandingCents)}'
                    : '${c.issues(o).length} comprobaciones pendientes',
                style: const TextStyle(color: muted),
              ),
              TextButton(
                onPressed: () => setState(() {
                  selected = o.id;
                  page = 1;
                }),
                child: const Text('Revisar reparación'),
              ),
            ]),
          ),
        if (orders.isEmpty)
          const Text('No hay órdenes pendientes de revisión.'),
        if (c.failures.isNotEmpty)
          section(
            'Registros en conflicto',
            c.failures.values
                .map(
                  (r) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(r),
                  ),
                )
                .toList(),
          ),
        section('Conflictos e incidencias conservados', [
          if (c.state.incidents.isEmpty)
            const Text('No hay incidencias descargadas.'),
          for (final i in c.state.incidents)
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${auditLabel(i['operation']?['kind'] ?? 'Registro')} · ${i['reason'] ?? 'Pendiente de revisión'}',
                  ),
                  Text(
                    incidentSummary(i),
                    style: const TextStyle(fontSize: 13),
                  ),
                  ExpansionTile(
                    title: const Text('Ver registro original'),
                    children: [
                      SelectableText(
                        '${i['operation'] ?? {}}',
                        style: const TextStyle(fontSize: 12, color: muted),
                      ),
                    ],
                  ),
                  if (i['resolution'] != null)
                    Text(
                      'Resultado: ${i['resolution']['outcome'] == 'retry' ? 'Corrección aplicada' : 'Conservado sin aplicar'} · ${i['resolution']['reason']} · Responsable: ${actorName(i['resolution']['responsibleId'])}',
                    )
                  else if (!c.demo)
                    Wrap(
                      spacing: 12,
                      children: [
                        TextButton(
                          onPressed: () => resolveIncident(i, 'retry'),
                          child: const Text('Revisar y aplicar registro'),
                        ),
                        TextButton(
                          onPressed: () => resolveIncident(i, 'archive'),
                          child: const Text(
                            'Conservar sin aplicar, con motivo',
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
        ]),
        if (!c.demo)
          section('Dispositivos del taller', [
            for (final d in c.devices)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '${actorName(d['userId'])} · equipo ${d['id'].toString().substring(0, 8)}${d['id'] == c.deviceId ? ' (este dispositivo)' : ''}',
                ),
                subtitle: Text(
                  d['retiredAt'] == null
                      ? 'Activo · Última conexión: ${d['lastSeen']}'
                      : 'Retirado · ${d['reason']}',
                ),
                trailing: d['id'] != c.deviceId && d['retiredAt'] == null
                    ? TextButton(
                        onPressed: () async {
                          final reason = await textDialog(
                            context,
                            'Retirar equipo de ${actorName(d['userId'])}',
                            'Motivo de pérdida o sustitución',
                            help:
                                'Se revoca su capacidad de editar y se invalidan los cierres afectados. Sus registros podrán recuperarse como incidencias.',
                          );
                          if (reason != null) {
                            await runAction(
                              () => c.retireDevice(d['id'], reason),
                            );
                          }
                        },
                        child: const Text('Retirar'),
                      )
                    : null,
              ),
          ]),
        if (!c.demo && c.retiredTimers.isNotEmpty)
          section('Cronómetros de dispositivos retirados', [
            const Text(
              'La retirada no inventa una hora de fin. Oficina debe registrar la hora real y el motivo para conservar la trazabilidad.',
            ),
            for (final t in c.retiredTimers)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${t['orderId']} · ${t['actorId']}'),
                subtitle: Text('Inicio: ${t['start']}'),
                trailing: TextButton(
                  onPressed: () => stopRetiredTimer(t),
                  child: const Text('Registrar fin real'),
                ),
              ),
          ]),
      ],
    );
  }

  String actorName(dynamic id) =>
      c.state.members.where((a) => a.id == id).firstOrNull?.name ?? 'Usuario';
  String incidentSummary(Map<String, dynamic> incident) {
    final op = incident['operation'] as Map? ?? {};
    final p = op['payload'] as Map? ?? {};
    final order = c.state.orders[op['orderId']];
    final prefix =
        '${order?.number ?? 'Recepción pendiente'} · ${actorName(op['actorId'])}';
    if (op['kind'] == 'note') return '$prefix · ${p['text']}';
    if (op['kind'] == 'part') {
      final item = c.state.catalog
          .where((i) => i.id == p['itemId'])
          .firstOrNull;
      final movement =
          {
            'consume': 'Consumo',
            'reserve': 'Reserva',
            'customer': 'Aportado por el cliente',
          }[p['kind']] ??
          'Movimiento';
      return '$prefix · $movement: ${quantity((p['quantityMilli'] as int?) ?? 0)} ${item?.unit ?? ''} de ${item?.description ?? 'pieza'}';
    }
    if (op['kind'] == 'manual_time') {
      return '$prefix · ${p['start']} → ${p['end']} · Motivo: ${p['reason']}';
    }
    if (op['kind'] == 'billable') {
      return '$prefix · ${p['minutes']} minutos facturables · ${p['reason']}';
    }
    if (op['kind'] == 'receive') {
      return '$prefix · ${p['plate']} · ${p['symptom']}';
    }
    return '$prefix · ${auditLabel(op['kind'] ?? 'Registro')}';
  }

  Future<void> resolveIncident(Map<String, dynamic> i, String outcome) async {
    final reason = await textDialog(
      context,
      'Resolver registro conservado',
      'Motivo y resultado de la revisión',
      help: outcome == 'retry'
          ? 'Se conserva el original y se crea una corrección vinculada. El servidor vuelve a validar autorización, tiempos, stock y revisión. No modifica notas emitidas.'
          : 'El registro original se conserva. Indica por qué no se aplica y el seguimiento necesario.',
    );
    if (reason != null) await runAction(() => c.resolve(i, outcome, reason));
  }

  Future<void> loginAgain() async {
    final credentials = await replacementCredentials(context, replacing: false);
    if (credentials != null) {
      await runAction(
        () => c.reauthenticate(credentials['email']!, credentials['password']!),
      );
    }
  }

  Future<void> replaceDevice() async {
    if (c.remote?.requiresLease == true && c.replacement == null) {
      final credentials = await replacementCredentials(context);
      if (credentials != null) {
        await runAction(
          () => c.replaceRetiredDevice(
            email: credentials['email'],
            password: credentials['password'],
          ),
        );
      }
    } else {
      await runAction(c.replaceRetiredDevice);
    }
  }

  Future<void> stopRetiredTimer(Map<String, dynamic> timer) async {
    final reason = await textDialog(
      context,
      'Finalizar cronómetro recuperado',
      'Motivo y soporte de la hora real de fin',
    );
    if (reason == null || !mounted) return;
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.parse(timer['start']).toLocal(),
      lastDate: DateTime.now(),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (time == null) return;
    final end = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    await runAction(() => c.endRetiredTimer(timer['id'], end, reason));
  }

  Widget settings() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      heading(
        'Configuración y puesta en marcha',
        'España · Usuarios, catálogo, tarifas y copias de seguridad',
      ),
      ManagementPanel(controller: c),
      const SizedBox(height: 18),
      BackupPanel(controller: c),
      const SizedBox(height: 18),
      section('Perfiles y permisos', [
        const Text(
          'Operario: órdenes y tareas asignadas, tiempos, consumos y observaciones.\nOficina: recepción, autorizaciones, revisión de importes y cierre.\nAdministrador: acceso de oficina y preparación de configuración.',
          style: TextStyle(height: 1.8),
        ),
        const SizedBox(height: 16),
        const Text(
          'En la demostración puedes cambiar de cuenta desde la barra superior.',
          style: TextStyle(color: muted, fontSize: 12),
        ),
      ]),
      const SizedBox(height: 18),
      section('Prueba de desconexión', [
        if (c.demo)
          FilledButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ReliabilitySimulation()),
            ),
            icon: const Icon(Icons.devices),
            label: const Text('Probar dos móviles y oficina'),
          ),
        const SizedBox(height: 16),
        Text(
          c.demo
              ? 'En modo local, todos los cambios se conservan en este dispositivo. La vista de navegador es temporal.'
              : 'Los registros pendientes permanecen cifrados en este dispositivo hasta que se envían.',
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: c.toggleOffline,
          icon: Icon(
            c.offline ? Icons.cloud_outlined : Icons.cloud_off_outlined,
          ),
          label: Text(
            c.offline ? 'Restablecer conexión' : 'Simular falta de conexión',
          ),
        ),
      ]),
      const SizedBox(height: 18),
      section('Próximas fases', [
        const Text(
          'Portal del cliente con verificación y autorización por versión.\nCompras, almacén y garantías.\nAsistente técnico con fuentes y revisión humana.\nFacturación fiscal española e integraciones.',
          style: TextStyle(height: 1.8, color: muted),
        ),
      ]),
    ],
  );
}

String duration(int seconds) {
  final s = seconds < 0 ? 0 : seconds;
  return '${(s ~/ 3600).toString().padLeft(2, '0')}:${((s % 3600) ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
}

String auditLabel(String kind) =>
    {
      'start': 'Cronómetro iniciado',
      'stop': 'Cronómetro pausado',
      'manual_time': 'Tiempo manual registrado',
      'part': 'Pieza registrada',
      'return': 'Devolución registrada',
      'note': 'Observación añadida',
      'finish_task': 'Tarea terminada',
      'authorize': 'Autorización registrada',
      'billable': 'Minutos facturables revisados',
      'pricing_review': 'Precio, descuento o cobro revisado',
      'quality': 'Comprobación final',
      'issue': 'Nota emitida',
      'receive': 'Recepción creada',
      'review_parts': 'Consumos revisados',
      'deliver': 'Entrega registrada',
      'payment_record': 'Cobro recibido registrado',
      'payment_reverse': 'Devolución o corrección de cobro',
      'request_close': 'Cierre solicitado',
      'ack_close': 'Dispositivo reconciliado',
      'resolve': 'Incidencia revisada',
      'retire_device': 'Dispositivo retirado',
      'replace_device': 'Dispositivo sustituido',
      'end_retired_timer': 'Fin de cronómetro recuperado',
      'session_rebound': 'Acceso revalidado',
      'csv_row_imported': 'Fila CSV importada',
      'csv_import': 'Importación CSV registrada',
      'photo_prepare': 'Carga de fotografía preparada',
      'photo_verified': 'Fotografía verificada',
      'photo_approve': 'Fotografía recuperada incorporada',
      'photo_archive': 'Fotografía archivada con motivo',
      'photo_file_restored': 'Archivo de fotografía recuperado',
    }[kind] ??
    kind;
