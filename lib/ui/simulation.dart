import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import '../data/controller.dart';
import '../data/demo.dart';
import '../data/simulation.dart';
import '../data/vault.dart';
import 'app.dart';

class ReliabilitySimulation extends StatefulWidget {
  const ReliabilitySimulation({super.key});
  @override
  State<ReliabilitySimulation> createState() => _ReliabilitySimulationState();
}

class _ReliabilitySimulationState extends State<ReliabilitySimulation> {
  final server = SimulatedWorkshop();
  final List<WorkshopController> controllers = [];
  int selected = 2;
  String? error;
  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      for (final actor in [demoActors[0], demoActors[1], demoActors[3]]) {
        final c = WorkshopController(
          Vault(MemoryStore(), await AesGcm.with256bits().newSecretKey()),
          remote: SimulatedRemote(server, actor),
          actor: actor,
        );
        await c.load();
        controllers.add(c);
      }
      for (final c in controllers) {
        await c.synchronize();
      }
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  @override
  void dispose() {
    for (final c in controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (controllers.length != 3) {
      return Scaffold(
        appBar: AppBar(title: const Text('Simulación de fiabilidad')),
        body: Center(
          child: error == null
              ? const CircularProgressIndicator()
              : Text(error!),
        ),
      );
    }
    final c = controllers[selected];
    final remote = c.remote as SimulatedRemote;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Container(
              color: const Color(0xfffff2d2),
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      TextButton.icon(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Volver'),
                      ),
                      const Text(
                        'SIMULACIÓN · Dos móviles y oficina · Sin conexión a Supabase',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const Text(
                    'Datos ficticios y servidor en memoria. Al salir se reinicia la simulación. No acredita funcionamiento nativo ni sincronización alojada.',
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (var i = 0; i < controllers.length; i++)
                        ChoiceChip(
                          label: Text(
                            [
                              'Móvil Álex',
                              'Móvil Lucía',
                              'Oficina / administrador',
                            ][i],
                          ),
                          selected: selected == i,
                          onSelected: (_) => setState(() => selected = i),
                        ),
                      OutlinedButton(
                        onPressed: () {
                          setState(() {
                            remote.disconnected = !remote.disconnected;
                            c.offline = remote.disconnected;
                          });
                          if (!remote.disconnected) c.synchronize();
                        },
                        child: Text(
                          remote.disconnected
                              ? 'Reconectar este dispositivo'
                              : 'Desconectar este dispositivo',
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          await c.synchronize();
                          if (mounted) setState(() {});
                        },
                        child: const Text('Actualizar dispositivo'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: Theme(
                data: tallerTheme(),
                child: WorkshopHome(key: ValueKey(c.deviceId), controller: c),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
