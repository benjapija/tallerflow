import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallerflow/domain/engine.dart';
import 'package:tallerflow/domain/fiscal_calculation.dart';
import 'package:tallerflow/domain/fiscal_draft_integrity.dart';
import 'package:tallerflow/domain/fiscal_draft_xml.dart';
import 'package:tallerflow/domain/fiscal_profile.dart';
import 'package:tallerflow/domain/verifactu_draft.dart';

const workshop = '00000000-0000-4000-8000-000000000010';
const actor = '00000000-0000-4000-8000-000000000002';
const device = '00000000-0000-4000-8000-000000000003';
String id(int n) => '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';
Map<String, dynamic> copy(Map<String, dynamic> value) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);
final issuer = VerifactuParty(
  name: 'Emisor ficticio & Hijos',
  nif: 'B12345678',
);
final preparation = {
  ...initialFiscalProfile(),
  'territory': 'common',
  'sii': 'no',
};
VerifactuSystem system({
  String installation = 'sandbox-a',
  String version = 'ensayo-v1',
}) => VerifactuSystem(
  manufacturer: VerifactuParty(name: 'Fabricante ficticio', nif: '12345678Z'),
  name: 'TallerFlow ensayo',
  id: 'TF',
  version: version,
  installation: installation,
  onlyVerifactu: true,
  canHaveMultipleTaxpayers: true,
  hasMultipleTaxpayers: false,
);

Map<String, dynamic> savedCalculation({
  int rate = 2100,
  String tax = 'iva',
  String treatment = 'taxable',
  String reason = '',
}) {
  final quota = treatment == 'taxable' ? (4375 * rate + 5000) ~/ 10000 : 0;
  return {
    'lines': [
      {
        'id': id(4),
        'description': 'Revisión ficticia <guardada>',
        'unitCents': 3333,
        'quantityMilli': 1500,
        'discountBps': 1250,
        'taxBps': rate,
        'tax': tax,
        'treatment': treatment,
        if (reason.isNotEmpty) 'reason': reason,
        'baseCents': 4375,
        'taxCents': quota,
        'totalCents': 4375 + quota,
      },
    ],
    'baseCents': 4375,
    'taxCents': quota,
    'totalCents': 4375 + quota,
  };
}

Future<Map<String, dynamic>> record({
  int sequence = 1,
  String previous = '',
  String prefix = 'ENSAYO-A',
  int number = 1,
  String kind = 'draft',
  Map<String, dynamic>? original,
  String date = '2026-10-07',
  String at = '2026-10-07T12:00:00.123456+00:00',
  Map<String, dynamic>? calculation,
}) async {
  final body = <String, dynamic>{
    'draftFormat': 1,
    'scope': 'sandbox',
    'emissionEnabled': false,
    'transmissionEnabled': false,
    'id': id(100 + sequence),
    'issuerNif': issuer.nif,
    'installation': 'sandbox-a',
    'sequence': sequence,
    'kind': kind,
    'prefix': prefix,
    'number': number,
    'reason': 'Ensayo técnico ficticio',
    'actorId': actor,
    'deviceId': device,
    'createdAt': at,
    if (kind == 'draft') ...{
      'issueDate': date,
      'recipient': {'name': 'Cliente ficticio', 'nif': '12345678Z'},
      'calculation': calculation ?? savedCalculation(),
    } else ...{
      'targetId': original!['id'],
      'originalLedgerHash': original['ledger_hash'],
    },
  };
  return {
    'workshop_id': workshop,
    'id': body['id'],
    'issuer_nif': issuer.nif,
    'installation': 'sandbox-a',
    'sequence': sequence,
    'kind': kind,
    'prefix': prefix,
    'number': number,
    'target_id': original?['id'],
    'actor_id': actor,
    'device_id': device,
    'body': body,
    'previous_hash': previous,
    'ledger_hash': await fiscalDraftLedgerHash(body, previous),
  };
}

Future<void> rehash(Map<String, dynamic> row) async {
  row['ledger_hash'] = await fiscalDraftLedgerHash(
    Map<String, dynamic>.from(row['body'] as Map),
    row['previous_hash'] as String,
  );
}

Future<FiscalDraftXmlChain> generate(
  List<Map<String, dynamic>> records, {
  VerifactuSystem? technical,
  Map<String, dynamic>? profile,
}) => FiscalDraftXmlChain.generateGeneralRegime(
  confirmedRecords: records,
  preparation: profile ?? preparation,
  issuer: issuer,
  system: technical ?? system(),
);

void main() {
  test(
    'Dart canonical sandbox digests match three independent PostgreSQL vectors',
    () async {
      final fixture =
          jsonDecode(
                File(
                  'tool/fixtures/fiscal-draft-integrity.json',
                ).readAsStringSync(),
              )
              as Map;
      for (final raw in fixture['cases'] as List) {
        final value = Map<String, dynamic>.from(raw['body'] as Map);
        expect(fiscalDraftJsonbText(value), raw['canonical']);
        expect(
          await fiscalDraftLedgerHash(value, raw['previousHash'] as String),
          raw['ledgerHash'],
        );
      }
    },
  );
  test(
    'Canonical sandbox format rejects floating point, invalid Unicode, nontext keys and unsafe integers',
    () async {
      for (final value in [
        1.0,
        double.nan,
        {2: 'x'},
        '\u0000',
        '\ud800',
        '\udc00',
        9007199254740992,
      ]) {
        expect(
          () => fiscalDraftJsonbText(value),
          throwsA(isA<RuleException>()),
        );
      }
      expect(
        () => fiscalDraftLedgerHash({'ok': true}, 'lowercase'),
        throwsA(isA<RuleException>()),
      );
    },
  );
  test(
    'Confirmed calculation uses saved one-round server arithmetic, never the generic two-round policy',
    () {
      final saved = {
        'lines': [
          {
            'id': id(4),
            'description': 'Fracción ficticia',
            'unitCents': 1,
            'quantityMilli': 600,
            'discountBps': 2500,
            'taxBps': 2100,
            'tax': 'iva',
            'treatment': 'taxable',
            'baseCents': 0,
            'taxCents': 0,
            'totalCents': 0,
          },
        ],
        'baseCents': 0,
        'taxCents': 0,
        'totalCents': 0,
      };
      final before = jsonEncode(saved);
      final confirmed = FiscalCalculation.fromConfirmedSandbox(saved);
      final generic = FiscalCalculation.calculate([
        FiscalLine(
          id: id(4),
          description: 'Fracción ficticia',
          quantityMilli: 600,
          unitPriceCents: 1,
          discountBps: 2500,
          rateBps: 2100,
          tax: FiscalTax.iva,
        ),
      ]);
      expect(confirmed.baseCents, 0);
      expect(generic.baseCents, 1);
      expect(jsonEncode(saved), before);
      expect(
        () => confirmed.lines.add(confirmed.lines.single),
        throwsUnsupportedError,
      );
    },
  );
  test(
    'Altered saved totals, duplicates, fractions, tax and extra fields cannot become XML',
    () {
      final valid = savedCalculation();
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (c) => c['baseCents']++,
        (c) => c['lines'][0]['totalCents']++,
        (c) => c['lines'].add(copy(c['lines'][0])),
        (c) => c['lines'][0]['unitCents'] = 3333.0,
        (c) => c['lines'][0]['tax'] = 'invented',
        (c) => c['lines'][0]['regime'] = '17',
        (c) => c['lines'][0]['unitCents'] = -1,
        (c) => c['lines'][0]['quantityMilli'] = 0,
      ]) {
        final modified = copy(valid);
        mutate(modified);
        expect(
          () => FiscalCalculation.fromConfirmedSandbox(modified),
          throwsA(isA<RuleException>()),
        );
      }
    },
  );
  test(
    'Confirmed F1 XML is deterministic, preserves source amounts and separates both hashes',
    () async {
      final source = await record();
      final original = jsonEncode(source);
      final first = (await generate([source])).artifacts.single;
      final second = (await generate([source])).artifacts.single;
      expect(first.toJson(), second.toJson());
      expect(
        first.xml,
        contains('<sf:NumSerieFactura>ENSAYO-A/1</sf:NumSerieFactura>'),
      );
      expect(first.xml, contains('<sf:ImporteTotal>52.94</sf:ImporteTotal>'));
      expect(first.xml, contains('<sf:CuotaTotal>9.19</sf:CuotaTotal>'));
      expect(first.xml, contains('&lt;guardada&gt;'));
      expect(first.aeatHash, isNot(first.ledgerHash));
      expect(first.ledgerHash, source['ledger_hash']);
      expect(
        first.snapshot['sourceTimestamp'],
        '2026-10-07T12:00:00.123456+00:00',
      );
      expect(first.generatedAt, '2026-10-07T12:00:00+00:00');
      expect(first.generatorVersion, fiscalDraftXmlGeneratorVersion);
      expect(first.emissionEnabled, false);
      expect(first.transmissionEnabled, false);
      expect(jsonEncode(source), original);
      expect(
        () => first.snapshot['system']['version'] = 'Changed',
        throwsUnsupportedError,
      );
      final serialized = first.toJson();
      serialized['snapshot']['system']['version'] = 'Changed';
      expect(first.snapshot['system']['version'], 'ensayo-v1');
    },
  );
  test(
    'A withdrawal stays separate; adjacent highs chain across series in the same second',
    () async {
      final first = await record();
      final withdrawal = await record(
        sequence: 2,
        previous: first['ledger_hash'],
        kind: 'withdrawal',
        original: first,
        at: '2026-10-07T12:00:00.223456+00:00',
      );
      final next = await record(
        sequence: 3,
        previous: withdrawal['ledger_hash'],
        prefix: 'ENSAYO-B',
        at: '2026-10-07T12:00:00.323456+00:00',
      );
      final chain = await generate([first, withdrawal, next]);
      expect(chain.artifacts.length, 2);
      expect(chain.withdrawals.length, 1);
      expect(chain.withdrawnRecordIds, {first['id']});
      final artifact = chain.artifacts.last;
      expect(artifact.sequence, 3);
      expect(artifact.previousXmlRecordId, first['id']);
      expect(artifact.previousLedgerHash, withdrawal['ledger_hash']);
      expect(
        artifact.xml,
        contains('<sf:Huella>${chain.artifacts.first.aeatHash}</sf:Huella>'),
      );
      expect(artifact.xml, isNot(contains('<sf:RegistroAnulacion>')));
      expect(chain.emissionEnabled, false);
      expect(chain.transmissionEnabled, false);
      if (const bool.fromEnvironment('WRITE_FISCAL_EVIDENCE')) {
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
      }
    },
  );
  test(
    'Saved XML bytes survive restart and workshop rebinding without regeneration',
    () async {
      final source = await record();
      final stored = (await generate([source])).artifacts.single.toJson();
      await validateFiscalDraftXmlStoredArtifact(
        copy(stored),
        confirmedRecord: source,
      );
      final rebound = copy(source)..['workshop_id'] = id(20);
      await validateFiscalDraftXmlStoredArtifact(
        copy(stored),
        confirmedRecord: rebound,
      );
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (v) => v['xml'] += ' ',
        (v) => v['snapshot']['system']['version'] = 'Changed',
        (v) => v['generatorVersion'] = 'unknown',
        (v) => v['ledgerHash'] = 'A' * 64,
        (v) => v['emissionEnabled'] = true,
        (v) => v['recordId'] = id(999),
      ]) {
        final modified = copy(stored);
        mutate(modified);
        await expectLater(
          validateFiscalDraftXmlStoredArtifact(
            modified,
            confirmedRecord: source,
          ),
          throwsA(isA<RuleException>()),
        );
      }
      final forgedBytes = copy(stored);
      forgedBytes['xml'] = (forgedBytes['xml'] as String).replaceFirst(
        '<sf:ImporteTotal>52.94</sf:ImporteTotal>',
        '<sf:ImporteTotal>52.95</sf:ImporteTotal>',
      );
      forgedBytes['xmlSha256'] = await fiscalDraftSha256(
        forgedBytes['xml'] as String,
      );
      await expectLater(
        validateFiscalDraftXmlStoredArtifact(
          forgedBytes,
          confirmedRecord: source,
        ),
        throwsA(isA<RuleException>()),
      );
    },
  );
  test(
    'Explicit system versions change projection identity without modifying ledger identity',
    () async {
      final source = await record();
      final a = (await generate([source])).artifacts.single;
      final b = (await generate([
        source,
      ], technical: system(version: 'ensayo-v2'))).artifacts.single;
      expect(a.ledgerHash, b.ledgerHash);
      expect(a.inputHash, isNot(b.inputHash));
      expect(a.xmlSha256, isNot(b.xmlSha256));
      // System data is not an input to the AEAT fingerprint, unlike XML snapshot identity.
      expect(a.aeatHash, b.aeatHash);
    },
  );
  test(
    'Missing, reordered or duplicated source records and mixed boundaries are rejected',
    () async {
      final first = await record();
      final second = await record(
        sequence: 2,
        number: 2,
        previous: first['ledger_hash'],
        at: '2026-10-07T12:00:01+00:00',
      );
      for (final input in [
        [second],
        [second, first],
        [first, first],
        [
          first,
          {...second, 'workshop_id': id(30)},
        ],
        [
          first,
          {...second, 'installation': 'another'},
        ],
        [
          first,
          {...second, 'issuer_nif': 'A87654321'},
        ],
        [
          first,
          {...second, 'previous_hash': 'A' * 64},
        ],
      ]) {
        await expectLater(generate(input), throwsA(isA<RuleException>()));
      }
      await expectLater(
        generate([first], technical: system(installation: 'another')),
        throwsA(isA<RuleException>()),
      );
    },
  );
  test(
    'Body modifications fail even when totals still appear plausible',
    () async {
      final source = await record();
      final modified = copy(source);
      modified['body']['reason'] = 'Changed';
      await expectLater(generate([modified]), throwsA(isA<RuleException>()));
      final changedColumn = copy(source)..['actor_id'] = id(999);
      await expectLater(
        generate([changedColumn]),
        throwsA(isA<RuleException>()),
      );
    },
  );
  test(
    'Unsupported format, activation and numbering never generate a partial chain',
    () async {
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (v) => v['body']['draftFormat'] = 2,
        (v) => v['body']['transmissionEnabled'] = true,
        (v) => v['body']['invoiceType'] = 'R1',
        (v) {
          v['number'] = 2;
          v['body']['number'] = 2;
        },
        (v) {
          v['prefix'] = 'REAL-2026';
          v['body']['prefix'] = 'REAL-2026';
        },
      ]) {
        final source = await record();
        mutate(source);
        await rehash(source);
        await expectLater(generate([source]), throwsA(isA<RuleException>()));
      }
    },
  );
  test(
    'Withdrawals must reference a preceding original once and cannot replace its data',
    () async {
      final first = await record();
      final withdrawal = await record(
        sequence: 2,
        previous: first['ledger_hash'],
        kind: 'withdrawal',
        original: first,
      );
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (v) => v['body']['originalLedgerHash'] = 'A' * 64,
        (v) => v['body']['calculation'] = savedCalculation(),
        (v) {
          v['target_id'] = id(999);
          v['body']['targetId'] = id(999);
        },
      ]) {
        final modified = copy(withdrawal);
        mutate(modified);
        await rehash(modified);
        await expectLater(
          generate([first, modified]),
          throwsA(isA<RuleException>()),
        );
      }
      final again = await record(
        sequence: 3,
        previous: withdrawal['ledger_hash'],
        kind: 'withdrawal',
        original: first,
      );
      await expectLater(
        generate([first, withdrawal, again]),
        throwsA(isA<RuleException>()),
      );
    },
  );
  test(
    'Special treatments and Other tax cannot silently invent absent classifications or regimes',
    () async {
      for (final calculation in [
        savedCalculation(tax: 'other'),
        savedCalculation(
          treatment: 'exempt',
          rate: 0,
          reason: 'Ensayo ficticio',
        ),
      ]) {
        await expectLater(
          generate([await record(calculation: calculation)]),
          throwsA(isA<RuleException>()),
        );
      }
      for (final profile in [
        {...preparation, 'sii': 'yes'},
        {...preparation, 'territory': 'bizkaia'},
      ]) {
        await expectLater(
          generate([await record()], profile: profile),
          throwsA(isA<RuleException>()),
        );
      }
    },
  );
  test(
    'Deterministic AEAT business subset rejects invalid dates and IVA rates for the source date',
    () async {
      for (final source in [
        await record(date: '2026-10-08'),
        await record(date: '2024-10-27'),
        await record(calculation: savedCalculation(rate: 500)),
        await record(calculation: savedCalculation(rate: 700)),
        await record(calculation: savedCalculation(rate: 750)),
      ]) {
        await expectLater(generate([source]), throwsA(isA<RuleException>()));
      }
      final historical = await record(
        date: '2024-11-01',
        at: '2024-11-01T12:00:00+00:00',
        calculation: savedCalculation(rate: 750),
      );
      expect(
        (await generate([historical])).artifacts.single.xml,
        contains('<sf:TipoImpositivo>7.50</sf:TipoImpositivo>'),
      );
      final canary = await record(
        calculation: savedCalculation(tax: 'igic', rate: 700),
      );
      expect(
        (await generate([canary])).artifacts.single.xml,
        contains('<sf:Impuesto>03</sf:Impuesto>'),
      );
    },
  );
  test(
    'Invalid timestamps, reversed source chronology and excessive descriptions fail explicitly',
    () async {
      final first = await record();
      final second = await record(
        sequence: 2,
        number: 2,
        previous: first['ledger_hash'],
        at: '2026-10-07T11:59:59+00:00',
      );
      await expectLater(
        generate([first, second]),
        throwsA(isA<RuleException>()),
      );
      final invalid = await record(at: '2026-10-07T12:00:00');
      await expectLater(generate([invalid]), throwsA(isA<RuleException>()));
      final long = copy(savedCalculation());
      long['lines'][0]['description'] = 'a' * 300;
      long['lines'].add({...long['lines'][0], 'id': id(5)});
      for (final key in ['baseCents', 'taxCents', 'totalCents']) {
        long[key] *= 2;
      }
      await expectLater(
        generate([await record(calculation: long)]),
        throwsA(isA<RuleException>()),
      );
    },
  );
  test(
    'The conserved Spanish calendar handles midnight and DST without using the Mac timezone',
    () async {
      final nearMidnight = await record(
        date: '2026-10-08',
        at: '2026-10-07T22:30:00+00:00',
      );
      final chain = await generate([nearMidnight]);
      expect(
        chain.artifacts.single.snapshot['dateValidationZone'],
        'Europe/Madrid',
      );
      expect(
        chain.artifacts.single.xml,
        contains(
          '<sf:FechaExpedicionFactura>08-10-2026</sf:FechaExpedicionFactura>',
        ),
      );
      await expectLater(
        FiscalDraftXmlChain.generateGeneralRegime(
          confirmedRecords: [nearMidnight],
          preparation: preparation,
          issuer: issuer,
          system: system(),
          dateValidationZone: 'Atlantic/Canary',
        ),
        throwsA(isA<RuleException>()),
      );
      final afterDst = await record(
        date: '2026-10-26',
        at: '2026-10-25T23:30:00+00:00',
      );
      expect((await generate([afterDst])).artifacts.length, 1);
    },
  );
  test(
    'XML-valid line breaks are preserved; control characters cannot enter the XML',
    () async {
      final source = await record();
      source['body']['reason'] = 'Motivo ficticio\nConservado';
      source['body']['calculation']['lines'][0]['description'] =
          'Revisión\nCon & <detalle>';
      await rehash(source);
      final xml = (await generate([source])).artifacts.single.xml;
      expect(xml, contains('Revisión\nCon &amp; &lt;detalle&gt;'));
      source['body']['calculation']['lines'][0]['description'] =
          'Control\u0001';
      await rehash(source);
      await expectLater(generate([source]), throwsA(isA<RuleException>()));
    },
  );
}
