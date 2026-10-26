import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:linkpad_controller/protocol.dart';

void main() {
  test('accepts Go ready messages with omitted empty capabilities', () {
    expect(
      readyCapabilities(parseMessage('{"version":1,"type":"ready"}')),
      isEmpty,
    );
    expect(readyCapabilities({'capabilities': []}), isEmpty);
    expect(
      readyCapabilities({
        'capabilities': ['pointer.v1'],
      }),
      ['pointer.v1'],
    );
    expect(
      () => readyCapabilities({'capabilities': null}),
      throwsFormatException,
    );
    expect(
      () => readyCapabilities({
        'capabilities': [1],
      }),
      throwsFormatException,
    );
  });
  test('pair and reconnect use desktop wire format', () {
    expect(jsonDecode(hello('secret')), {
      'version': 1,
      'type': 'pair',
      'token': 'secret',
      'capabilities': [
        'pointer.v1',
        'scroll.v1',
        'key.v1',
        'keyboard.v1',
        'keyboard.super.v1',
        'drag.v1',
      ],
    });
    expect(jsonDecode(hello(''))['type'], 'hello');
  });
  test('pointer bounds and buttons are validated', () {
    expect(jsonDecode(pointer(500, -500, 'left'))['button'], 'left');
    expect(() => pointer(501, 0), throwsArgumentError);
    expect(() => pointer(0, 0, 'middle'), throwsArgumentError);
  });
  test('arrow keys are validated', () {
    expect(jsonDecode(keyMessage('up')), {
      'version': 1,
      'type': 'key',
      'key': 'up',
    });
    expect(() => keyMessage('enter'), throwsArgumentError);
  });
  test('rejects malformed, oversized and unsupported responses', () {
    expect(() => parseMessage('{'), throwsFormatException);
    expect(
      () => parseMessage('{"version":2,"type":"hello"}'),
      throwsFormatException,
    );
    expect(
      () => parseMessage(List.filled(4097, 'a').join()),
      throwsFormatException,
    );
    expect(() => parseMessage([1, 2]), throwsFormatException);
  });
  test('allows only explicit TLS websocket endpoints', () {
    expect(peerAddress('wss://192.168.1.2:4747/ws').host, '192.168.1.2');
    for (final url in [
      'ws://host/ws',
      'wss://host/',
      'wss://user@host/ws',
      'wss://host/ws?secret=x',
      'wss://host/ws#fragment',
    ]) {
      expect(() => peerAddress(url), throwsFormatException);
    }
  });
}
