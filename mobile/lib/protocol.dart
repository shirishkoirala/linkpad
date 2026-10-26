import 'dart:convert';
import 'drag_protocol.dart';

const pointerCapability = 'pointer.v1';
const scrollCapability = 'scroll.v1';
const keyCapability = 'key.v1';
const keyboardCapability = 'keyboard.v1';
const superKeyCapability = 'keyboard.super.v1';

List<String> readyCapabilities(Map<String, dynamic> message) {
  // The Go desktop omits this field when no capabilities are available.
  if (!message.containsKey('capabilities')) return [];
  final value = message['capabilities'];
  if (value is! List || value.any((item) => item is! String)) {
    throw const FormatException('Invalid capabilities');
  }
  return value.cast<String>();
}

String hello(String token) => jsonEncode({
  'version': 1,
  'type': token.isEmpty ? 'hello' : 'pair',
  if (token.isNotEmpty) 'token': token,
  'capabilities': [
    pointerCapability,
    scrollCapability,
    keyCapability,
    keyboardCapability,
    superKeyCapability,
    dragCapability,
  ],
});

String pointer(int dx, int dy, [String? button]) {
  if (dx.abs() > 500 ||
      dy.abs() > 500 ||
      (button != null && button != 'left' && button != 'right')) {
    throw ArgumentError('Invalid pointer input');
  }
  return jsonEncode({
    'version': 1,
    'type': 'pointer',
    'dx': dx,
    'dy': dy,
    if (button != null) 'button': button,
  });
}

String scrollMessage(int dx, int dy) {
  if (dx.abs() > 500 || dy.abs() > 500) {
    throw ArgumentError('Invalid scroll input');
  }
  return jsonEncode({'version': 1, 'type': 'scroll', 'dx': dx, 'dy': dy});
}

String keyMessage(String key) {
  if (key != 'up' && key != 'down' && key != 'left' && key != 'right') {
    throw ArgumentError('Invalid key input');
  }
  return jsonEncode({'version': 1, 'type': 'key', 'key': key});
}

Map<String, dynamic> parseMessage(dynamic data) {
  if (data is! String || utf8.encode(data).length > 4096) {
    throw const FormatException('Invalid or oversized message');
  }
  final value = jsonDecode(data);
  if (value is! Map<String, dynamic> ||
      value['version'] != 1 ||
      value['type'] is! String) {
    throw const FormatException('Unsupported protocol message');
  }
  return value;
}

Uri peerAddress(String address) {
  final uri = Uri.parse(address.trim());
  if (uri.scheme != 'wss' ||
      uri.host.isEmpty ||
      uri.path != '/ws' ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw const FormatException('Use wss://HOST:4747/ws');
  }
  return uri;
}
