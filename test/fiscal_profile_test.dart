import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallerflow/data/controller.dart';
import 'package:tallerflow/data/demo.dart';
import 'package:tallerflow/data/simulation.dart';
import 'package:tallerflow/data/vault.dart';
import 'package:tallerflow/domain/engine.dart';
import 'package:tallerflow/domain/fiscal_profile.dart';

class LostFiscalReply extends SimulatedRemote {
  bool lose = true;
  LostFiscalReply(super.workshop, super.actor);
  @override
  Future<Map<String, dynamic>> command(
    String id,
    String action,
    Map<String, dynamic> payload,
  ) async {
    final result = await super.command(id, action, payload);
    if (lose) {
      lose = false;
      throw StateError('Fictional lost preparation response');
    }
    return result;
  }
}

void main() {
  test(
    'Lost fiscal reply survives restart and has one audited effect',
    () async {
      final remote = LostFiscalReply(SimulatedWorkshop(), demoActors[3]);
      final store = MemoryStore(),
          key = await AesGcm.with256bits().newSecretKey();
      final first = WorkshopController(
        Vault(store, key),
        remote: remote,
        actor: demoActors[3],
      );
      await first.load();
      await expectLater(
        first.manage('fiscal_profile_save', {
          'reason': 'Fictional preparation',
          'profile': initialFiscalProfile(),
        }),
        throwsStateError,
      );
      final commandId = first.pendingCommands.single['id'];
      first.dispose();
      final second = WorkshopController(
        Vault(store, key),
        remote: remote,
        actor: demoActors[3],
      );
      await second.load();
      expect(second.pendingCommands.single['id'], commandId);
      await second.synchronize();
      expect(second.pendingCommands, isEmpty);
      expect(remote.workshop.state.managementRevision, 1);
      expect(second.state.settings['fiscalProfile']['emissionEnabled'], false);
      expect(
        remote.workshop.state.audit.where(
          (x) => x['kind'] == 'fiscal_profile_save',
        ),
        hasLength(1),
      );
      second.dispose();
    },
  );
  test(
    'Every workshop can prepare each supported Spanish option without emission',
    () {
      for (final field in fiscalChoices.keys) {
        for (final option in fiscalChoices[field]!.keys) {
          final normalized = validateFiscalProfile({
            ...initialFiscalProfile(),
            field: option,
          });
          expect(normalized[field], option);
          expect(normalized['emissionEnabled'], false);
        }
      }
    },
  );
  test(
    'Preparation refuses fabricated activation, private keys and unknown fields',
    () {
      for (final change in [
        {'emissionEnabled': true},
        {'profileVersion': 2},
        {'country': 'FR'},
        {'legalForm': 'invented'},
        {'taxSystem': null},
        {'apiKey': 'fictional-secret'},
      ]) {
        expect(
          () => validateFiscalProfile({...initialFiscalProfile(), ...change}),
          throwsA(isA<RuleException>()),
        );
      }
    },
  );
  test(
    'Fiscal preparation retains tariffs, prior orders, documents and other workshops',
    () {
      final state = demoState(), other = demoState();
      final originalOrders = jsonEncode(state.toJson()['orders']);
      final rate = state.settings['hourlyRateCents'];
      state.manage(
        'fiscal-1',
        'fiscal_profile_save',
        {
          'revision': 0,
          'reason': 'Preparación ficticia por taller',
          'profile': {
            ...initialFiscalProfile(),
            'legalForm': 'company',
            'territory': 'canary',
            'taxSystem': 'igic',
          },
        },
        demoActors[3],
        DateTime.utc(2026, 10, 7),
      );
      expect(state.settings['fiscalProfile']['taxSystem'], 'igic');
      expect(state.settings['hourlyRateCents'], rate);
      expect(jsonEncode(state.toJson()['orders']), originalOrders);
      expect(other.settings['fiscalProfile'], isNull);
      expect(state.audit.last['kind'], 'fiscal_profile_save');
      final restored = WorkshopState.fromJson(state.toJson());
      expect(
        restored.settings['fiscalProfile'],
        state.settings['fiscalProfile'],
      );
    },
  );
  test(
    'Office, technician and stale administration cannot change preparation',
    () {
      final state = demoState();
      final p = {
        'revision': 0,
        'reason': 'Preparación ficticia',
        'profile': initialFiscalProfile(),
      };
      for (final actor in [demoActors[0], demoActors[2]]) {
        expect(
          () => state.manage(
            'unauthorized',
            'fiscal_profile_save',
            p,
            actor,
            DateTime.utc(2026),
          ),
          throwsA(isA<RuleException>()),
        );
      }
      state.manage(
        'first',
        'fiscal_profile_save',
        p,
        demoActors[3],
        DateTime.utc(2026),
      );
      expect(
        () => state.manage(
          'stale',
          'fiscal_profile_save',
          p,
          demoActors[3],
          DateTime.utc(2026),
        ),
        throwsA(isA<RuleException>()),
      );
      expect(state.managementRevision, 1);
    },
  );
}
