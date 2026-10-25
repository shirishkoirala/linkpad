import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linkpad_controller/control_deck.dart';
import 'package:linkpad_controller/cursor_settings.dart';
import 'package:linkpad_controller/main.dart';
import 'package:linkpad_controller/remote_page.dart';
import 'package:linkpad_controller/mobile_controls.dart';
import 'package:linkpad_controller/relative_touchpad.dart';
import 'control_deck_test.dart' show FakePeer;

void main() {
  testWidgets('Remote touchpad uses sensitivity without scrolling the page', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final peer = FakePeer(), settings = CursorSettings()..setSensitivity(2);
    addTearDown(peer.dispose);
    addTearDown(settings.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: linkpadTheme(Brightness.light),
        home: RemotePage(peer: peer, settings: settings, onSettings: () {}),
      ),
    );
    final touchpad = find.byKey(const ValueKey('remote-touchpad'));
    expect(
      tester.getBottomLeft(touchpad).dy,
      lessThan(tester.getTopLeft(find.byIcon(Icons.keyboard_arrow_up)).dy),
    );
    final scroll = Scrollable.of(tester.element(touchpad)).position;
    final finger = await tester.startGesture(tester.getCenter(touchpad));
    await finger.moveBy(const Offset(10, -20));
    await tester.pump();
    expect(peer.motionEvents.last, const Offset(20, -40));
    expect(scroll.pixels, 0);
    peer.pause();
    await tester.pump();
    final count = peer.motionEvents.length;
    await finger.moveBy(const Offset(10, 0));
    expect(peer.motionEvents.length, count);
    await finger.up();
    expect(tester.takeException(), isNull);
  });

  testWidgets('all mobile control modes keep the same header and navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final peer = FakePeer(), settings = CursorSettings();
    addTearDown(peer.dispose);
    addTearDown(settings.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: linkpadTheme(Brightness.light),
        home: ControlDeck(peer: peer, settings: settings),
      ),
    );
    await tester.pumpAndSettle();
    final navigation = tester.getRect(find.text('Remote'));
    expect(find.text('Computers'), findsNothing);
    expect(find.text('Settings'), findsNothing);
    expect(find.byTooltip('Computers'), findsOneWidget);
    expect(find.byTooltip('Settings'), findsOneWidget);
    final touchpadOrigin = tester.getTopLeft(find.byType(RelativeTouchpad));
    expect(
      tester
          .widget<MobileControlScaffold>(find.byType(MobileControlScaffold))
          .mode,
      MobileControlMode.touchpad,
    );
    await tester.tap(find.text('Remote'));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.text('Remote')), navigation);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('remote-touchpad'))),
      touchpadOrigin,
    );
    expect(find.text('Find your way.'), findsNothing);
    expect(find.byType(SegmentedButton<String>), findsNothing);
    expect(find.byTooltip('Gestures'), findsOneWidget);
    expect(
      tester
          .widget<MobileControlScaffold>(find.byType(MobileControlScaffold))
          .mode,
      MobileControlMode.remote,
    );
    await tester.tap(find.text('Keyboard'));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.text('Remote')), navigation);
    expect(
      tester
          .widget<MobileControlScaffold>(find.byType(MobileControlScaffold))
          .mode,
      MobileControlMode.keyboard,
    );
    await tester.tap(find.text('Touchpad'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<MobileControlScaffold>(find.byType(MobileControlScaffold))
          .mode,
      MobileControlMode.touchpad,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'dragging the touchpad cannot scroll the compact keyboard workspace',
    (tester) async {
      tester.view.physicalSize = const Size(320, 560);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final peer = FakePeer(), settings = CursorSettings();
      addTearDown(peer.dispose);
      addTearDown(settings.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: linkpadTheme(Brightness.light),
          home: ControlDeck(peer: peer, settings: settings),
        ),
      );
      await tester.tap(find.text('Keyboard'));
      await tester.pumpAndSettle();
      final touchpad = find.byType(RelativeTouchpad);
      final scroll = Scrollable.of(tester.element(touchpad)).position;
      expect(scroll.maxScrollExtent, greaterThan(0));
      final finger = await tester.startGesture(tester.getCenter(touchpad));
      await finger.moveBy(const Offset(0, -30));
      await tester.pump();
      await finger.up();
      expect(scroll.pixels, 0);
      expect(peer.motionEvents, isNotEmpty);
      expect(tester.takeException(), isNull);
    },
  );

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
    await tester.ensureVisible(find.text('Enter'));
    await tester.tap(find.text('Enter'));
    await tester.pump();
    expect(peer.keys.last.key, 'enter');
    await tester.ensureVisible(find.text('Win / Cmd'));
    await tester.tap(find.text('Win / Cmd'));
    await tester.pump();
    await tester.ensureVisible(find.byIcon(Icons.keyboard_arrow_left));
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
    await tester.ensureVisible(find.text('c'));
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
    await tester.ensureVisible(find.byIcon(Icons.keyboard_arrow_down));
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
    await tester.ensureVisible(find.byIcon(Icons.keyboard_arrow_up));
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
