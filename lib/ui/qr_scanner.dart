import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../domain/order_links.dart';
import 'dialogs.dart';

bool get hasMobileCamera =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android);

Future<String?> readOrderCode(BuildContext context) async {
  if (!hasMobileCamera) {
    return textDialog(
      context,
      'Abrir orden por QR o código',
      'Código de la orden',
      initial: '',
      help:
          'Pega el enlace de TallerFlow o introduce OT-1048. También puedes usar un lector conectado al teclado. El código no concede permisos.',
    );
  }
  return Navigator.of(
    context,
  ).push<String>(MaterialPageRoute(builder: (_) => const OrderQrScanner()));
}

class OrderQrScanner extends StatefulWidget {
  const OrderQrScanner({super.key});
  @override
  State<OrderQrScanner> createState() => _OrderQrScannerState();
}

class _OrderQrScannerState extends State<OrderQrScanner>
    with WidgetsBindingObserver {
  final scanner = MobileScannerController(
    autoStart: false,
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  StreamSubscription<BarcodeCapture>? subscription;
  bool returned = false;
  String? message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    subscription = scanner.barcodes.listen(detected);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(start());
    });
  }

  Future<void> start() async {
    try {
      await scanner.start();
    } catch (_) {
      if (mounted) {
        setState(
          () => message =
              'No se puede usar la cámara. Puedes introducir el código.',
        );
      }
    }
  }

  void detected(BarcodeCapture capture) {
    if (returned || !mounted) return;
    for (final b in capture.barcodes) {
      if (b.rawValue == null) continue;
      try {
        OrderReference.parse(b.rawValue!);
        returned = true;
        Navigator.of(context).pop(b.rawValue);
        return;
      } on FormatException {
        setState(
          () => message = 'Ese QR no corresponde a una orden de TallerFlow.',
        );
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!scanner.value.hasCameraPermission || returned) return;
    if (state == AppLifecycleState.resumed) {
      unawaited(start());
    } else {
      unawaited(scanner.stop());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(subscription?.cancel());
    unawaited(scanner.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Escanear QR de la orden')),
    body: Column(
      children: [
        Expanded(
          child: MobileScanner(
            controller: scanner,
            errorBuilder: (_, _) =>
                const Center(child: Text('Cámara no disponible')),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(
                message ??
                    'Apunta al QR de TallerFlow. El acceso depende de tu cuenta.',
              ),
              TextButton(
                onPressed: () async {
                  await scanner.stop();
                  if (!context.mounted) return;
                  final code = await textDialog(
                    context,
                    'Código de la orden',
                    'Código o enlace',
                    initial: '',
                  );
                  if (code != null && context.mounted) {
                    try {
                      OrderReference.parse(code);
                      returned = true;
                      Navigator.of(context).pop(code);
                    } on FormatException catch (e) {
                      setState(() => message = e.message);
                      unawaited(start());
                    }
                  } else if (mounted) {
                    unawaited(start());
                  }
                },
                child: const Text('Introducir código'),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
