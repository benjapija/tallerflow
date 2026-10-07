import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/controller.dart';
import '../domain/models.dart';
import '../domain/portal.dart';
import 'dialogs.dart';

class PortalPanel extends StatelessWidget {
  final WorkshopController controller;
  final WorkOrder order;
  final Future<void> Function(Future<void> Function()) run;
  const PortalPanel({
    super.key,
    required this.controller,
    required this.order,
    required this.run,
  });
  Future<void> configure(BuildContext context) async {
    final p = await formDialog(
      context,
      'Dirección del portal del cliente',
      [
        FieldSpec(
          'url',
          'Dirección HTTPS',
          initial: controller.state.settings['portalBaseUrl'] ?? '',
          required: false,
        ),
        const FieldSpec('reason', 'Motivo'),
      ],
      (v) => {'url': validatePortalUrl(v['url']), 'reason': v['reason']},
      help:
          'Introduce la dirección del portal publicado. Una dirección vacía desactiva la creación de enlaces nuevos; retira también los accesos existentes si procede.',
    );
    if (p != null) await run(() => controller.portal('portal_configure', p));
  }

  Future<void> create(BuildContext context) async {
    final versions = (order.data['quoteLedger']?['versions'] as List? ?? []);
    final choices = {
      for (final q in versions)
        '${q['id']}|${q['version']}': '${q['title']} · versión ${q['version']}',
    };
    if (choices.isEmpty) return;
    final p = await formDialog(
      context,
      'Crear acceso temporal para el destinatario',
      [
        FieldSpec(
          'quote',
          'Presupuesto exacto que se compartirá',
          initial: choices.keys.last,
          choices: choices,
        ),
        const FieldSpec(
          'hours',
          'Duración en horas · máximo 168',
          initial: '24',
          numeric: true,
        ),
        const FieldSpec(
          'photos',
          'Fotografías de esta orden',
          initial: 'none',
          choices: {
            'none': 'No compartir fotografías',
            'reviewed': 'He revisado las fotografías y autorizo compartirlas',
          },
        ),
        const FieldSpec(
          'documents',
          'Documentos del destinatario original',
          initial: 'none',
          choices: {
            'none': 'No compartir documentos',
            'reviewed': 'Compartir los documentos autorizados de esta orden',
          },
        ),
        const FieldSpec(
          'confirmed',
          'Verificación del destinatario',
          initial: 'no',
          choices: {
            'no': 'Todavía no comprobado',
            'yes': 'He comprobado la identidad y las evidencias compartidas',
          },
        ),
        const FieldSpec(
          'verificationEvidence',
          'Cómo comprobaste el destinatario y cómo entregarás el código separado',
          multiline: true,
        ),
        const FieldSpec('reason', 'Motivo'),
      ],
      (v) {
        final hours = int.tryParse(v['hours'] ?? '');
        if (hours == null || hours < 1 || hours > 168) {
          throw const FormatException('Usa entre 1 y 168 horas');
        }
        if (v['confirmed'] != 'yes') {
          throw const FormatException(
            'Comprueba personalmente el destinatario',
          );
        }
        final q = v['quote']!.split('|');
        final photos =
            (controller.state.configuration['photoManifest'] as List? ?? [])
                .where(
                  (x) => x['orderId'] == order.id && x['status'] == 'attached',
                );
        final docs =
            (controller.state.configuration['portalDocuments'] as List? ?? [])
                .where((x) => x['orderId'] == order.id);
        return {
          'orderId': order.id,
          'revision': order.revision,
          'quoteId': q[0],
          'quoteVersion': int.parse(q[1]),
          'expiresAt': DateTime.now()
              .toUtc()
              .add(Duration(hours: hours))
              .toIso8601String(),
          'recipientConfirmed': true,
          'verificationEvidence': v['verificationEvidence'],
          'reason': v['reason'],
          'photoIds': v['photos'] == 'reviewed'
              ? photos.map((x) => x['id']).toList()
              : [],
          'documentIds': v['documents'] == 'reviewed'
              ? docs.map((x) => x['id']).toList()
              : [],
        };
      },
      help:
          'Comprueba el destinatario personalmente. Entrega el enlace y el código por canales separados. El enlace no autoriza versiones nuevas.',
    );
    if (p == null) return;
    await run(() async {
      final access = await controller.createPortal(p);
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Acceso creado'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Entrega el enlace y el código por canales separados, tras verificar al destinatario. Se muestran una sola vez; no se envían mensajes automáticamente.',
                  ),
                  const SizedBox(height: 12),
                  const Text('Enlace'),
                  SelectableText(
                    access.link(controller.state.settings['portalBaseUrl']),
                  ),
                  TextButton(
                    onPressed: () => Clipboard.setData(
                      ClipboardData(
                        text: access.link(
                          controller.state.settings['portalBaseUrl'],
                        ),
                      ),
                    ),
                    child: const Text('Copiar enlace'),
                  ),
                  const Text('Código independiente'),
                  SelectableText(access.code),
                  TextButton(
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: access.code)),
                    child: const Text('Copiar código'),
                  ),
                  const Text(
                    'Si pierdes estos datos, retira el acceso y crea otro. No pueden recuperarse desde su huella guardada.',
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('He guardado los datos de entrega'),
            ),
          ],
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!controller.actor.isOffice) return const SizedBox.shrink();
    final grants =
        (controller.state.configuration['portalGrants'] as List? ?? []).where(
          (g) => g['orderId'] == order.id,
        );
    final enabled = (controller.state.settings['portalBaseUrl'] ?? '')
        .toString()
        .isNotEmpty;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Portal del cliente',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (!enabled)
              const Text(
                'Falta configurar la dirección HTTPS del portal en administración.',
              ),
            if (controller.demo)
              const Text(
                'La demo muestra el flujo; crear accesos requiere un taller conectado.',
              ),
            if (controller.actor.role == Role.admin)
              TextButton(
                onPressed: () => configure(context),
                child: const Text('Configurar dirección del portal'),
              ),
            FilledButton.tonal(
              onPressed:
                  enabled &&
                      !controller.demo &&
                      (order.data['quoteLedger']?['versions'] as List? ?? [])
                          .isNotEmpty
                  ? () => create(context)
                  : null,
              child: const Text('Crear acceso temporal'),
            ),
            for (final g in grants)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Presupuesto versión ${g['quoteVersion']}'),
                subtitle: Text(
                  'Caduca: ${g['expiresAt']} · ${g['revokedAt'] != null
                      ? 'Retirado'
                      : g['restored'] == true
                      ? 'Restaurado sin acceso'
                      : g['locked'] == true
                      ? 'Bloqueado por intentos'
                      : 'Vigente hasta caducidad'}',
                ),
                trailing: g['revokedAt'] == null
                    ? TextButton(
                        onPressed: () async {
                          final p = await formDialog(
                            context,
                            'Retirar acceso',
                            [const FieldSpec('reason', 'Motivo')],
                            (v) => {'id': g['id'], 'reason': v['reason']},
                          );
                          if (p != null) {
                            await run(
                              () => controller.portal('portal_revoke', p),
                            );
                          }
                        },
                        child: const Text('Retirar'),
                      )
                    : null,
              ),
          ],
        ),
      ),
    );
  }
}
