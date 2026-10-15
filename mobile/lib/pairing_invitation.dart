import 'dart:convert';
import 'protocol.dart';

class PairingInvitation {
  const PairingInvitation(
    this.address,
    this.fingerprint,
    this.secret,
    this.expiresAt,
  );
  final String address, fingerprint, secret;
  final DateTime expiresAt;

  factory PairingInvitation.parse(String raw, {DateTime? now}) {
    if (utf8.encode(raw).length > 4096) {
      throw const FormatException('This is not a Linkpad pairing code.');
    }
    dynamic data;
    try {
      data = jsonDecode(raw);
    } catch (_) {
      throw const FormatException('This is not a Linkpad pairing code.');
    }
    if (data is! Map<String, dynamic> ||
        data['type'] != 'linkpad-pairing' ||
        data['version'] != 1 ||
        data['address'] is! String ||
        data['fingerprint'] is! String ||
        data['secret'] is! String ||
        data['expiresAt'] is! String) {
      throw const FormatException(
        'This is not a supported Linkpad pairing code.',
      );
    }
    final rawAddress = (data['address'] as String).trim();
    final address = peerAddress(rawAddress);
    // Uri normalizes an explicit :0 away for the wss scheme; validate the raw
    // spelling too so a bad port cannot silently become a different endpoint.
    final explicitPort = RegExp(
      r':([0-9]+)/ws$',
    ).firstMatch(rawAddress)?.group(1);
    final port = explicitPort == null ? null : int.tryParse(explicitPort);
    if (explicitPort != null && (port == null || port < 1 || port > 65535)) {
      throw const FormatException(
        'The pairing code contains an invalid address.',
      );
    }
    if (address.hasPort && (address.port < 1 || address.port > 65535)) {
      throw const FormatException(
        'The pairing code contains an invalid address.',
      );
    }
    final fingerprint = (data['fingerprint'] as String).toLowerCase();
    final secret = data['secret'] as String;
    final hex = RegExp(r'^[0-9a-fA-F]{64}$');
    if (!hex.hasMatch(fingerprint) || !hex.hasMatch(secret)) {
      throw const FormatException(
        'The pairing code is incomplete. Generate a new code on your computer.',
      );
    }
    final expiresAt = DateTime.tryParse(data['expiresAt'] as String);
    if (expiresAt == null || !expiresAt.isUtc) {
      throw const FormatException(
        'The pairing code has an invalid expiry time.',
      );
    }
    if (!expiresAt.isAfter(now ?? DateTime.now())) {
      throw const FormatException(
        'This code has expired. Start a new pairing window on your computer.',
      );
    }
    return PairingInvitation(
      address.toString(),
      fingerprint,
      secret,
      expiresAt,
    );
  }
}
