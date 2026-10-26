import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:linkpad_controller/keyboard_protocol.dart';

void main() {
  test('keyboard distinguishes printable text and shortcut keys', () {
    expect(jsonDecode(keyboardMessage(text: 'Hello é')), {
      'version': 1,
      'type': 'keyboard',
      'text': 'Hello é',
    });
    expect(
      jsonDecode(keyboardMessage(key: 'c', modifiers: {'super'}))['modifiers'],
      ['super'],
    );
    for (final invalid in ['', '\n', List.filled(129, 'a').join()]) {
      expect(() => keyboardMessage(text: invalid), throwsArgumentError);
    }
    expect(() => keyboardMessage(key: 'bogus'), throwsArgumentError);
    expect(
      () => keyboardMessage(text: 'a', modifiers: {'ctrl'}),
      throwsArgumentError,
    );
  });
  test('standalone Super is a key press without chord modifiers', () {
    expect(jsonDecode(keyboardMessage(key: 'super'))['key'], 'super');
    expect(
      () => keyboardMessage(key: 'super', modifiers: {'ctrl'}),
      throwsArgumentError,
    );
  });
}
