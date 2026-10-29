import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linkpad_controller/control_deck.dart';
import 'package:linkpad_controller/main.dart';
import 'package:linkpad_controller/peer_client.dart';
import 'package:linkpad_controller/cursor_settings.dart';
import 'package:linkpad_controller/relative_touchpad.dart';

class FakePeer extends PeerClient {
  FakePeer() {
    state = PeerState.connected;
  }
  final typed = <String>[];
  final keys = <({String key, Set<String> modifiers})>[];
  final volumeActions = <String>[];
  bool volumeSupported = true;
  @override
  bool get supportsVolume => volumeSupported;
  @override
  bool get canVolume => available && volumeSupported;
  @override
  bool volume(String action, {bool repeat = false}) {
    if (!canVolume) return false;
    volumeActions.add(action);
    return true;
  }

  bool available = true;
  bool standaloneSuper = true;
  bool responsePaused = false;
  @override
  bool get waitingForResponse => connected && responsePaused;
  final motionEvents = <Offset>[];

  @override
  void move(double dx, double dy) {
    if (available) motionEvents.add(Offset(dx, dy));
  }

  @override
  bool get ready => available;
  @override
  bool get canKeyboard => available;
  @override
  bool get supportsKeyboard => true;
  @override
  bool get supportsStandaloneSuper => standaloneSuper;
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

  void resume() {
    available = true;
    responsePaused = false;
    state = PeerState.connected;
    notifyListeners();
  }
}

void main() {
  testWidgets(
    'a slow response shows a network pause instead of a permission error',
    (tester) async {
      final peer = FakePeer();
      final settings = CursorSettings();
      addTearDown(peer.dispose);
      addTearDown(settings.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: linkpadTheme(Brightness.light),
          home: AnimatedBuilder(
            animation: peer,
            builder: (_, _) => ControlDeck(peer: peer, settings: settings),
          ),
        ),
      );
      peer.available = false;
      peer.responsePaused = true;
      peer.notifyListeners();
      await tester.pump();
      expect(find.text('Connection slow · Input paused'), findsOneWidget);
      expect(find.textContaining('desktop server permissions'), findsNothing);
      peer.resume();
      await tester.pump();
      expect(
        find.textContaining('Waiting for your computer to respond'),
        findsNothing,
      );
      peer.available = false;
      peer.notifyListeners();
      await tester.pump();
      expect(find.textContaining('desktop server permissions'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'held contact survives the reconnect warning appearing and disappearing',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final peer = FakePeer();
      final settings = CursorSettings();
      addTearDown(peer.dispose);
      addTearDown(settings.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: linkpadTheme(Brightness.light),
          home: AnimatedBuilder(
            animation: peer,
            builder: (_, _) => ControlDeck(peer: peer, settings: settings),
          ),
        ),
      );
      final origin = tester.getCenter(find.byType(RelativeTouchpad));
      final finger = await tester.createGesture();
      await finger.down(origin);
      await finger.moveTo(origin + const Offset(15, 5));
      expect(peer.motionEvents, [const Offset(15, 5)]);
      peer.pause();
      await tester.pump();
      await finger.moveTo(origin + const Offset(60, 20));
      expect(peer.motionEvents.length, 1);
      peer.resume();
      await tester.pump();
      await finger.moveTo(origin + const Offset(70, 25));
      expect(peer.motionEvents.length, 1);
      await finger.moveTo(origin + const Offset(77, 28));
      await finger.up();
      expect(peer.motionEvents, [const Offset(15, 5), const Offset(7, 3)]);
      expect(tester.takeException(), isNull);
    },
  );

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
            builder: (_, _) =>
                ControlDeck(peer: peer, settings: CursorSettings()),
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
            home: ControlDeck(
              key: ValueKey(size),
              peer: peer,
              settings: CursorSettings(),
            ),
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
