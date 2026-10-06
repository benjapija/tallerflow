import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tallerflow/data/cloud.dart';
import 'package:tallerflow/data/photo_blobs.dart';

void main() {
  final original = Uint8List.fromList([255, 216, 255, 1, 255, 217]);
  for (final scenario in [
    'confirmed retry',
    'different bytes',
    'revoked read',
    'new upload',
  ]) {
    test('Storage $scenario requires a fresh authorized hash match', () async {
      final requests = <String>[];
      final client = SupabaseClient(
        'http://127.0.0.1:9',
        'fictional-public-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          requests.add(request.method);
          if (!request.url.path.contains('/functions/')) {
            if (scenario == 'new upload') {
              return http.Response('{"Key":"fixture.jpg"}', 200);
            }
            return http.Response(
              jsonEncode({
                'statusCode': '400',
                'error': 'Unauthorized',
                'message': 'new row violates row-level security policy',
              }),
              400,
              headers: {'content-type': 'application/json'},
            );
          }
          if (scenario == 'revoked read') {
            return http.Response(
              jsonEncode({
                'statusCode': '400',
                'error': 'Unauthorized',
                'message': 'Access revoked',
              }),
              400,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response.bytes(
            scenario == 'different bytes'
                ? [255, 216, 255, 2, 255, 217]
                : original,
            200,
            headers: {'content-type': 'application/octet-stream'},
          );
        }),
      );
      final remote = SupabaseRemote(client, 'fictional-workshop');
      remote.bindDevice('fictional-device');
      final metadata = {
        'id': 'fictional-photo',
        'path': 'fictional/fixture.jpg',
        'sha256': await PhotoBlobs.digest(original),
        'size': original.length,
      };
      final upload = remote.uploadPhoto(metadata, original);
      if (scenario == 'different bytes') {
        await expectLater(upload, throwsFormatException);
      } else if (scenario == 'revoked read') {
        await expectLater(upload, throwsA(isA<StorageException>()));
      } else {
        await upload;
      }
      expect(requests, scenario == 'new upload' ? ['POST'] : ['POST', 'POST']);
      await client.dispose();
    });
  }
}
