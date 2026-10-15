import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:linkpad_controller/pairing_invitation.dart';

void main() {
  late Map<String, dynamic> fixture;
  final now = DateTime.utc(2099, 1, 1);

  setUp(() {
    fixture =
        jsonDecode(File('../protocol/testdata/pairing.json').readAsStringSync())
            as Map<String, dynamic>;
  });

  test('reads the same invitation encoded by the Go QR renderer', () {
    final invitation = PairingInvitation.parse(jsonEncode(fixture), now: now);
    expect(invitation.address, 'wss://192.0.2.10:4747/ws');
    expect(invitation.fingerprint, List.filled(64, 'a').join());
    expect(invitation.secret, List.filled(64, 'b').join());
    expect(invitation.expiresAt, now.add(const Duration(minutes: 2)));
  });

  test('rejects expired codes including the exact expiry boundary', () {
    expect(
      () => PairingInvitation.parse(
        jsonEncode(fixture),
        now: now.add(const Duration(minutes: 2)),
      ),
      throwsFormatException,
    );
    expect(
      () => PairingInvitation.parse(
        jsonEncode(fixture),
        now: now.add(const Duration(minutes: 3)),
      ),
      throwsFormatException,
    );
  });

  test('rejects malformed and unsupported codes', () {
    for (final raw in [
      'not a code',
      '{}',
      '[]',
      List.filled(4097, 'a').join(),
    ]) {
      expect(
        () => PairingInvitation.parse(raw, now: now),
        throwsFormatException,
      );
    }
    for (final entry in <String, dynamic>{
      'version': 2,
      'type': 'other',
      'secret': null,
      'fingerprint': 'bad',
      'expiresAt': '2099-01-01T00:02:00',
    }.entries) {
      expect(
        () => PairingInvitation.parse(
          jsonEncode({...fixture, entry.key: entry.value}),
          now: now,
        ),
        throwsFormatException,
      );
    }
  });

  test('rejects unsafe endpoints and short or invalid credentials', () {
    for (final address in [
      'ws://host/ws',
      'wss://user@host/ws',
      'wss://host/ws?token=x',
      'wss://host/ws#fragment',
      'wss://host:0/ws',
      'wss://host:65536/ws',
    ]) {
      expect(
        () => PairingInvitation.parse(
          jsonEncode({...fixture, 'address': address}),
          now: now,
        ),
        throwsFormatException,
      );
    }
    for (final secret in ['123', List.filled(64, 'z').join()]) {
      expect(
        () => PairingInvitation.parse(
          jsonEncode({...fixture, 'secret': secret}),
          now: now,
        ),
        throwsFormatException,
      );
    }
  });
}
