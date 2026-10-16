import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:linkpad_controller/control_deck.dart';
import 'package:linkpad_controller/cursor_settings.dart';
import 'package:linkpad_controller/main.dart';
import 'package:linkpad_controller/relative_touchpad.dart';
import 'package:linkpad_controller/settings_page.dart';
import 'control_deck_test.dart' show FakePeer;

class MotionPeer extends FakePeer {
  final moves = <Offset>[], scrolls = <Offset>[];
  @override
  bool get canScroll => true;
  @override
  void move(double dx, double dy) => moves.add(Offset(dx, dy));
  @override
  void scroll(double dx, double dy) => scrolls.add(Offset(dx, dy));
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets('settings opens without disconnecting and saves slider changes', (
    tester,
  ) async {
    final settings = CursorSettings(), peer = MotionPeer();
    addTearDown(settings.dispose);
    addTearDown(peer.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: linkpadTheme(Brightness.light),
        home: ControlDeck(peer: peer, settings: settings),
      ),
    );
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);
    final slider = find.byType(Slider);
    await tester.drag(slider, const Offset(70, 0));
    await tester.pumpAndSettle();
    expect(settings.sensitivity, greaterThan(1));
    final saved = CursorSettings();
    await saved.load();
    expect(saved.sensitivity, settings.sensitivity);
    saved.dispose();
    await tester.tap(find.text('Reset to 100%'));
    await tester.pumpAndSettle();
    expect(settings.sensitivity, 1);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(peer.connected, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'sensitivity scales cursor deltas while leaving two-finger scroll unchanged',
    (tester) async {
      final settings = CursorSettings()..setSensitivity(2), peer = MotionPeer();
      addTearDown(settings.dispose);
      addTearDown(peer.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: linkpadTheme(Brightness.light),
          home: ControlDeck(peer: peer, settings: settings),
        ),
      );
      final point = tester.getCenter(find.byType(RelativeTouchpad));
      final one = await tester.startGesture(point, pointer: 1);
      await one.moveBy(const Offset(20, 10));
      await one.up();
      expect(peer.moves, [const Offset(40, 20)]);
      final a = await tester.startGesture(point, pointer: 2),
          b = await tester.startGesture(
            point + const Offset(40, 0),
            pointer: 3,
          );
      await a.moveBy(const Offset(0, 20));
      await b.moveBy(const Offset(0, 20));
      await a.up();
      await b.up();
      expect(
        peer.scrolls.fold(Offset.zero, (a, b) => a + b),
        const Offset(0, 20),
      );
      expect(peer.moves.length, 1);
    },
  );
}
