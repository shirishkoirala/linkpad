import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linkpad_controller/control_deck.dart';
import 'package:linkpad_controller/cursor_settings.dart';
import 'package:linkpad_controller/main.dart';
import 'package:linkpad_controller/remote_page.dart';
import 'control_deck_test.dart' show FakePeer;

void main() {
  testWidgets('Remote sends Enter, arrow shortcuts and one-shot modifiers', (
    tester,
  ) async {
    final peer = FakePeer(), settings = CursorSettings();
    addTearDown(peer.dispose);
    addTearDown(settings.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: linkpadTheme(Brightness.light),
        home: ControlDeck(peer: peer, settings: settings),
      ),
    );
    await tester.tap(find.text('Remote'));
    await tester.pumpAndSettle();
    expect(find.byType(RemotePage), findsOneWidget);
    await tester.tap(find.text('Enter'));
    await tester.pump();
    expect(peer.keys.last.key, 'enter');
    await tester.tap(find.text('Win / Cmd'));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.keyboard_arrow_left));
    await tester.pump();
    expect(peer.keys.last.key, 'left');
    expect(peer.keys.last.modifiers, {'super'});
    await tester.tap(find.byIcon(Icons.keyboard_arrow_right));
    await tester.pump();
    expect(peer.keys.last.modifiers, isEmpty);
    await tester.ensureVisible(find.text('Previous'));
    await tester.tap(find.text('Previous'));
    await tester.pump();
    expect(peer.keys.last.key, 'tab');
    expect(peer.keys.last.modifiers, {'shift'});
    expect(tester.takeException(), isNull);
  });

  testWidgets('Remote carries a Windows or Command modifier to the keyboard', (
    tester,
  ) async {
    final peer = FakePeer(), settings = CursorSettings();
    addTearDown(peer.dispose);
    addTearDown(settings.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: linkpadTheme(Brightness.light),
        home: ControlDeck(peer: peer, settings: settings),
      ),
    );
    await tester.tap(find.text('Remote'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Win / Cmd'));
    await tester.pump();
    await tester.tap(find.text('Keyboard'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('c'));
    await tester.pump();
    expect(peer.keys.last.key, 'c');
    expect(peer.keys.last.modifiers, {'super'});
    await tester.tap(find.text('v'));
    await tester.pump();
    expect(peer.typed, ['v']);
  });

  testWidgets('holding an arrow repeats until release or connection loss', (
    tester,
  ) async {
    final peer = FakePeer();
    addTearDown(peer.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: linkpadTheme(Brightness.dark),
        home: RemotePage(peer: peer, onSettings: () {}),
      ),
    );
    final hold = await tester.startGesture(
      tester.getCenter(find.byIcon(Icons.keyboard_arrow_down)),
    );
    await tester.pump(const Duration(milliseconds: 650));
    await tester.pump(const Duration(milliseconds: 230));
    expect(peer.keys.length, greaterThan(1));
    await hold.up();
    await tester.pump();
    final released = peer.keys.length;
    await tester.pump(const Duration(milliseconds: 300));
    expect(peer.keys.length, released);
    final lost = await tester.startGesture(
      tester.getCenter(find.byIcon(Icons.keyboard_arrow_up)),
    );
    await tester.pump(const Duration(milliseconds: 650));
    peer.pause();
    await tester.pump();
    final paused = peer.keys.length;
    await tester.pump(const Duration(milliseconds: 300));
    expect(peer.keys.length, paused);
    await lost.up();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Remote fits a narrow phone and landscape', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final peer = FakePeer();
    addTearDown(peer.dispose);
    for (final size in [const Size(320, 640), const Size(740, 360)]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        MaterialApp(
          theme: linkpadTheme(Brightness.light),
          home: RemotePage(key: ValueKey(size), peer: peer, onSettings: () {}),
        ),
      );
      await tester.ensureVisible(find.text('Enter'));
      await tester.tap(find.text('Enter'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
  });
}
