// VM-only reproducible integration probe. Fictional local data; no UI/network.
import 'dart:convert';
import 'dart:io';
import 'package:tallerflow/domain/fiscal_draft_integrity.dart';
import 'package:tallerflow/domain/fiscal_draft_xml.dart';
import 'package:tallerflow/domain/fiscal_profile.dart';
import 'package:tallerflow/domain/verifactu_draft.dart';

Future<void> main() async {
  final fixtures =
      jsonDecode(
            File(
              'tool/fixtures/fiscal-draft-integrity.json',
            ).readAsStringSync(),
          )
          as Map;
  var checks = 0;
  void check(bool valid, String description) {
    if (!valid) throw StateError(description);
    checks++;
  }

  for (final item in fixtures['cases'] as List) {
    final body = Map<String, dynamic>.from(item['body'] as Map);
    check(
      fiscalDraftJsonbText(body) == item['canonical'],
      'PostgreSQL canonical text',
    );
    check(
      await fiscalDraftLedgerHash(body, item['previousHash'] as String) ==
          item['ledgerHash'],
      'PostgreSQL fingerprint',
    );
  }
  final body = Map<String, dynamic>.from(fixtures['cases'][2]['body'] as Map);
  Map<String, dynamic> row(
    Map<String, dynamic> body,
    String previous,
    String hash,
  ) => {
    'workshop_id': '00000000-0000-4000-8000-000000000010',
    'id': body['id'],
    'issuer_nif': body['issuerNif'],
    'installation': body['installation'],
    'sequence': body['sequence'],
    'kind': body['kind'],
    'prefix': body['prefix'],
    'number': body['number'],
    'target_id': body['targetId'],
    'actor_id': body['actorId'],
    'device_id': body['deviceId'],
    'body': body,
    'previous_hash': previous,
    'ledger_hash': hash,
  };
  final first = row(body, '', fixtures['cases'][2]['ledgerHash'] as String);
  final before = jsonEncode(first);
  final nextBody =
      Map<String, dynamic>.from(jsonDecode(jsonEncode(body)) as Map)
        ..['id'] = '00000000-0000-4000-8000-000000000005'
        ..['sequence'] = 2
        ..['number'] = 2
        ..['createdAt'] = '2026-10-07T12:00:00.223456+00:00';
  final next = row(
    nextBody,
    first['ledger_hash'] as String,
    await fiscalDraftLedgerHash(nextBody, first['ledger_hash'] as String),
  );
  final manufacturer = VerifactuParty(
    name: 'Fabricante ficticio',
    nif: '12345678Z',
  );
  final chain = await FiscalDraftXmlChain.generateGeneralRegime(
    confirmedRecords: [first, next],
    preparation: {
      ...initialFiscalProfile(),
      'territory': 'common',
      'sii': 'no',
    },
    issuer: VerifactuParty(name: 'Emisor ficticio', nif: 'B12345678'),
    system: VerifactuSystem(
      manufacturer: manufacturer,
      name: 'TallerFlow ensayo',
      id: 'TF',
      version: 'ensayo-v1',
      installation: 'sandbox-a',
      onlyVerifactu: true,
      canHaveMultipleTaxpayers: true,
      hasMultipleTaxpayers: false,
    ),
  );
  check(
    chain.artifacts.length == 2,
    'Two confirmed source records generate two artifacts',
  );
  check(
    chain.artifacts[1].previousXmlRecordId == first['id'],
    'Second projection preserves chain identity',
  );
  check(
    chain.artifacts[0].xml.contains('<sf:ImporteTotal>52.94</sf:ImporteTotal>'),
    'Saved totals',
  );
  check(
    chain.artifacts[0].ledgerHash != chain.artifacts[0].aeatHash,
    'Independent fingerprints',
  );
  check(jsonEncode(first) == before, 'Original stays immutable');
  await validateFiscalDraftXmlStoredArtifact(
    chain.artifacts[0].toJson(),
    confirmedRecord: first,
  );
  checks++;
  final changed = chain.artifacts[0].toJson()
    ..['xml'] = '${chain.artifacts[0].xml} ';
  var denied = false;
  try {
    await validateFiscalDraftXmlStoredArtifact(changed, confirmedRecord: first);
  } catch (_) {
    denied = true;
  }
  check(denied, 'Modified bytes fail conserved correspondence');
  final directory = Directory('build/fiscal-fixtures')
    ..createSync(recursive: true);
  final manifest = <Map<String, dynamic>>[];
  for (var index = 0; index < chain.artifacts.length; index++) {
    final name = 'ledger-${index + 1}.xml';
    File(
      '${directory.path}/$name',
    ).writeAsStringSync(chain.artifacts[index].xml);
    manifest.add({'file': name, ...chain.artifacts[index].toJson()});
  }
  File(
    '${directory.path}/ledger-manifest.json',
  ).writeAsStringSync(jsonEncode(manifest));
  print(
    '$checks local VM projection checks passed. No AEAT service, physical device or fiscal emission.',
  );
}
