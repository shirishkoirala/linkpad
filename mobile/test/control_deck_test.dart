import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linkpad_controller/control_deck.dart';
import 'package:linkpad_controller/main.dart';
import 'package:linkpad_controller/peer_client.dart';

class FakePeer extends PeerClient {
  FakePeer() {
    state = PeerState.connected;
  }
  final typed = <String>[];
  final keys = <({String key, Set<String> modifiers})>[];
  bool available = true;
  @override
  bool get ready => available;
  @override
  bool get canKeyboard => available;
  @override
  bool get supportsKeyboard => true;
  @override
  bool get canKey => available;
  @override
  bool typeText(String text) {
    if (!available) return false;
    typed.add(text);
    return true;
  }

  @override
  bool keyboardKey(String key, {Set<String> modifiers = const {}}) {
    if (!available) return false;
    keys.add((key: key, modifiers: {...modifiers}));
    return true;
  }

  void pause() {
    available = false;
    state = PeerState.reconnecting;
    notifyListeners();
  }
}

void main() {
  testWidgets(
    'keyboard types text and applies modifiers to only the next key',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final peer = FakePeer();
      addTearDown(peer.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: linkpadTheme(Brightness.light),
          home: AnimatedBuilder(
            animation: peer,
            builder: (_, _) => ControlDeck(peer: peer),
          ),
        ),
      );
      await tester.tap(find.text('Keyboard'));
      await tester.pump();
      await tester.tap(find.text('q'));
      await tester.pump();
      await tester.tap(find.text('Ctrl'));
      await tester.pump();
      await tester.tap(find.text('c'));
      await tester.pump();
      await tester.tap(find.text('v'));
      await tester.pump();
      expect(peer.typed, ['q', 'v']);
      expect(peer.keys.single.key, 'c');
      expect(peer.keys.single.modifiers, {'ctrl'});
      peer.pause();
      await tester.pump();
      await tester.tap(find.text('q'));
      await tester.pump();
      expect(peer.typed, ['q', 'v']);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'control deck fits a narrow phone and landscape with keyboard open',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final peer = FakePeer();
      addTearDown(peer.dispose);
      for (final size in [const Size(320, 640), const Size(740, 360)]) {
        tester.view.physicalSize = size;
        await tester.pumpWidget(
          MaterialApp(
            theme: linkpadTheme(Brightness.dark),
            home: ControlDeck(key: ValueKey(size), peer: peer),
          ),
        );
        await tester.ensureVisible(find.text('Keyboard'));
        await tester.tap(find.text('Keyboard'));
        await tester.pump();
        await tester.ensureVisible(find.text('return'));
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
    },
  );
}
