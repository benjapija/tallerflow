import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallerflow/data/controller.dart';
import 'package:tallerflow/data/demo.dart';
import 'package:tallerflow/data/simulation.dart';
import 'package:tallerflow/data/vault.dart';
import 'package:tallerflow/domain/engine.dart';

void main() {
  test(
    'Three simulated devices exercise actual client freeze, offline blocking and immutable note',
    () async {
      final server = SimulatedWorkshop();
      final clients = <WorkshopController>[];
      for (final actor in [demoActors[0], demoActors[1], demoActors[3]]) {
        final c = WorkshopController(
          Vault(MemoryStore(), await AesGcm.with256bits().newSecretKey()),
          remote: SimulatedRemote(server, actor),
          actor: actor,
        );
        await c.load();
        clients.add(c);
      }
      final alex = clients[0], lucia = clients[1], office = clients[2];
      await office.requestClose('o-1045');
      await office.confirmClose('o-1045');
      await alex.confirmClose('o-1045');
      (lucia.remote as SimulatedRemote).disconnected = true;
      lucia.offline = true;
      await expectLater(office.issue('o-1045'), throwsA(isA<RuleException>()));
      expect(server.state.orders['o-1045']!.issued, false);
      (lucia.remote as SimulatedRemote).disconnected = false;
      lucia.offline = false;
      await lucia.synchronize();
      await lucia.confirmClose('o-1045');
      await office.synchronize();
      await office.issue('o-1045');
      final original = server.state.orders['o-1045']!.data['document'];
      expect(original['totalCents'], 4356);
      expect(office.state.orders['o-1045']!.issued, true);
      await expectLater(
        lucia.execute('o-1045', 'note', {'text': 'Forbidden edit'}),
        throwsA(isA<RuleException>()),
      );
      expect(server.state.orders['o-1045']!.data['document'], original);
      for (final c in clients) {
        c.dispose();
      }
    },
  );
}
