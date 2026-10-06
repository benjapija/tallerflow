import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'data/cloud.dart';
import 'data/controller.dart';
import 'data/local.dart';
import 'domain/models.dart';
import 'ui/app.dart';
import 'data/order_link_inbox.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  OrderLinkInbox.shared.startNative();
  const url = String.fromEnvironment('SUPABASE_URL');
  const key = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  const workshop = String.fromEnvironment('WORKSHOP_ID');
  try {
    if (url.isEmpty && key.isEmpty && workshop.isEmpty) {
      final controller = WorkshopController(await openVault('demo'));
      await controller.load();
      runApp(TallerFlowApp(controller: controller));
    } else {
      if (kIsWeb) {
        throw StateError(
          'La vista web es solo una demostración. Usa la aplicación nativa para acceder al taller.',
        );
      }
      if (url.isEmpty || key.isEmpty || workshop.isEmpty) {
        throw StateError('Faltan parámetros de configuración del taller.');
      }
      await Supabase.initialize(
        url: url,
        publishableKey: key,
        authOptions: const FlutterAuthClientOptions(
          localStorage: SecureSessionStorage(),
        ),
      );
      runApp(LoginApp(workshopId: workshop));
    }
  } catch (e) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'No se puede abrir TallerFlow. Tus registros se conservan.\n\n$e',
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class LoginApp extends StatefulWidget {
  final String workshopId;
  const LoginApp({super.key, required this.workshopId});
  @override
  State<LoginApp> createState() => _LoginAppState();
}

class _LoginAppState extends State<LoginApp> {
  final email = TextEditingController(), password = TextEditingController();
  WorkshopController? controller;
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    if (Supabase.instance.client.auth.currentSession != null) unawaited(open());
  }

  Future<void> open({bool login = false}) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final client = Supabase.instance.client;
      if (login) {
        await client.auth.signInWithPassword(
          email: email.text.trim(),
          password: password.text,
        );
        password.clear();
      }
      final remote = SupabaseRemote(client, widget.workshopId);
      final userId = client.auth.currentUser?.id;
      if (userId == null) throw StateError('Cuenta individual requerida');
      final vault = await openVault('${widget.workshopId}-$userId');
      final saved = await vault.read();
      final actor = saved != null && saved['actor']['id'] == userId
          ? Actor.fromJson(Map<String, dynamic>.from(saved['actor']))
          : await remote.actor();
      final c = WorkshopController(vault, remote: remote, actor: actor);
      await c.load();
      if (mounted) {
        setState(() => controller = c);
        unawaited(c.synchronize());
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'No se pudo acceder. Comprueba la conexión, tu cuenta y la configuración del taller.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (controller != null) {
      return TallerFlowApp(
        controller: controller!,
        onLogout: () async {
          if (controller!.outbox.isNotEmpty ||
              controller!.pendingCommands.isNotEmpty ||
              controller!.hasPendingPhotos) {
            throw StateError(
              'Sincroniza los registros antes de cerrar sesión.',
            );
          }
          await Supabase.instance.client.auth.signOut(
            scope: SignOutScope.local,
          );
          controller!.dispose();
          OrderLinkInbox.shared.clear();
          setState(() => controller = null);
        },
      );
    }
    return MaterialApp(
      theme: tallerTheme(),
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.handyman_rounded,
                    color: Color(0xff16856b),
                    size: 48,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'TallerFlow',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Tu taller, conectado.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: email,
                    decoration: const InputDecoration(
                      labelText: 'Correo electrónico',
                    ),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: password,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Contraseña'),
                    onSubmitted: (_) => open(login: true),
                  ),
                  const SizedBox(height: 24),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  FilledButton(
                    onPressed: busy ? null : () => open(login: true),
                    child: Text(busy ? 'Accediendo…' : 'Entrar al taller'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
