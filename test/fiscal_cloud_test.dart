import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tallerflow/data/cloud.dart';

void main() {
  const workshop = 'fictional-workshop';
  const device = 'fictional-device';
  SupabaseRemote fixture(Future<http.Response> Function(http.Request) handler) {
    final client = SupabaseClient(
      'http://127.0.0.1:9',
      'fictional-public-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        final response = await handler(request);
        return http.Response.bytes(
          response.bodyBytes,
          response.statusCode,
          headers: response.headers,
          request: request,
          reasonPhrase: response.reasonPhrase,
        );
      }),
    );
    addTearDown(client.dispose);
    return SupabaseRemote(client, workshop)..bindDevice(device);
  }

  http.Response jsonResponse(Object? body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );

  test(
    'Ledger read preserves restored heads, series and immutable bodies',
    () async {
      final view = {
        'scope': 'sandbox',
        'emissionEnabled': false,
        'transmissionEnabled': false,
        'heads': [
          {
            'issuer_nif': 'A12345678',
            'installation': 'restored-installation',
            'last_sequence': 2,
            'last_hash': 'F' * 64,
            'restored': true,
          },
          {
            'issuer_nif': 'A12345678',
            'installation': 'fresh-installation',
            'last_sequence': 0,
            'last_hash': '',
            'restored': false,
          },
        ],
        'series': [
          {
            'issuer_nif': 'A12345678',
            'installation': 'restored-installation',
            'prefix': 'ENSAYO-2026',
            'last_number': 1,
          },
        ],
        'records': [
          {
            'id': 'fictional-record',
            'kind': 'withdrawal',
            'target_id': 'fictional-original',
            'body': {
              'scope': 'sandbox',
              'reason': 'Retirada ficticia',
              'originalLedgerHash': 'E' * 64,
            },
          },
        ],
      };
      final remote = fixture((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/rest/v1/rpc/fiscal_drafts');
        expect(jsonDecode(request.body), {
          'workshop_id': workshop,
          'device_id': device,
        });
        return jsonResponse(view);
      });
      expect(await remote.fiscalDrafts(), view);
    },
  );

  for (final action in ['fiscal_draft_append', 'fiscal_draft_withdraw']) {
    test(
      '$action keeps exact identity and payload on explicit retries',
      () async {
        final payload = {
          'issuerNif': 'A12345678',
          'installation': 'fictional-installation',
          'expectedSequence': 8,
          'expectedHash': 'D' * 64,
          'reason': 'Ensayo ficticio',
          if (action == 'fiscal_draft_append') ...{
            'prefix': 'ENSAYO-2026',
            'issueDate': '2026-10-07',
            'recipient': {'name': 'Cliente ficticio', 'nif': '12345678Z'},
            'lines': [
              {
                'id': '00000000-0000-4000-8000-000000000001',
                'description': 'Trabajo ficticio',
                'unitCents': 100,
                'quantityMilli': 1000,
                'discountBps': 0,
                'tax': 'iva',
                'taxBps': 2100,
                'treatment': 'taxable',
                'reason': '',
              },
            ],
          } else
            'targetId': 'fictional-original',
        };
        final result = {
          'saved': true,
          'id': 'stable-command-id',
          'sequence': 9,
          'prefix': 'ENSAYO-2026',
          'number': 4,
          'ledgerHash': 'F' * 64,
          'emissionEnabled': false,
          'transmissionEnabled': false,
        };
        var requests = 0;
        final remote = fixture((request) async {
          requests++;
          expect(request.method, 'POST');
          expect(request.url.path, '/rest/v1/rpc/fiscal_draft_command');
          expect(jsonDecode(request.body), {
            'workshop_id': workshop,
            'device_id': device,
            'command_id': 'stable-command-id',
            'action': action,
            'payload': payload,
          });
          return jsonResponse(result);
        });
        expect(
          await remote.command('stable-command-id', action, payload),
          result,
        );
        expect(
          await remote.command('stable-command-id', action, payload),
          result,
        );
        expect(requests, 2);
      },
    );
  }

  test(
    'A chain conflict remains a server error and is not silently retried',
    () async {
      var requests = 0;
      final remote = fixture((request) async {
        requests++;
        return jsonResponse({
          'code': 'P0001',
          'message': 'Draft chain conflict; refresh and review',
          'details': 'Changed head',
          'hint': null,
        }, 400);
      });
      await expectLater(
        remote.command('stable-command-id', 'fiscal_draft_append', {}),
        throwsA(
          isA<PostgrestException>()
              .having((e) => e.code, 'code', 'P0001')
              .having((e) => e.message, 'message', contains('chain conflict'))
              .having((e) => e.details, 'details', 'Changed head'),
        ),
      );
      expect(requests, 1);
    },
  );

  test(
    'A revoked or non-administrator read never becomes an empty ledger',
    () async {
      final remote = fixture(
        (request) async => jsonResponse({
          'code': '42501',
          'message': 'Administrator required',
          'details': null,
          'hint': null,
        }, 403),
      );
      await expectLater(
        remote.fiscalDrafts(),
        throwsA(
          isA<PostgrestException>().having((e) => e.code, 'code', '42501'),
        ),
      );
    },
  );

  test('A malformed successful ledger response is rejected', () async {
    final remote = fixture((request) async => jsonResponse(null));
    await expectLater(remote.fiscalDrafts(), throwsA(isA<TypeError>()));
  });
}
