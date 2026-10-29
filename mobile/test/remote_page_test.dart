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
  testWidgets(
    'Remote has volume controls instead of modifiers and keeps Keyboard shortcuts',
    (tester) async {
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
      for (final label in ['Ctrl', 'Alt', 'Shift', 'Win / Cmd']) {
        expect(find.text(label), findsNothing);
      }
      for (final icon in [
        Icons.volume_down_outlined,
        Icons.volume_off_outlined,
        Icons.volume_up_outlined,
      ]) {
        await tester.ensureVisible(find.byIcon(icon));
        await tester.tap(find.byIcon(icon));
        await tester.pump();
      }
      expect(peer.volumeActions, ['down', 'mute', 'up']);
      expect(peer.keys, isEmpty);
      await tester.tap(find.text('Keyboard'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Win / Cmd'));
      expect(find.text('Ctrl'), findsOneWidget);
      expect(find.text('Alt'), findsOneWidget);
      expect(find.text('Win / Cmd'), findsOneWidget);
    },
  );

  testWidgets('volume buttons stay disabled for old servers', (tester) async {
    final peer = FakePeer()..volumeSupported = false;
    addTearDown(peer.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: linkpadTheme(Brightness.light),
        home: RemotePage(peer: peer, onSettings: () {}),
      ),
    );
    final mute = find.byIcon(Icons.volume_off_outlined);
    await tester.ensureVisible(mute);
    await tester.tap(mute);
    await tester.pump();
    expect(peer.volumeActions, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Pro Max gives spare Remote height to touchpad and keeps controls compact',
    (tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final peer = FakePeer();
      addTearDown(peer.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: linkpadTheme(Brightness.light),
          home: RemotePage(peer: peer, onSettings: () {}),
        ),
      );
      final touchpad = find.byKey(const ValueKey('remote-touchpad'));
      final ring = find.byWidgetPredicate(
        (w) =>
            w is Semantics && (w.properties.label ?? '').startsWith('D-pad.'),
      );
      expect(tester.getSize(touchpad).height, greaterThan(260));
      expect(tester.getSize(ring).width, lessThanOrEqualTo(220));
      final escape = find.widgetWithText(TextButton, 'Esc');
      expect(tester.getSize(escape).width, greaterThanOrEqualTo(56));
      expect(tester.getSize(escape).height, greaterThanOrEqualTo(56));
      final shortcuts = find.widgetWithText(FilledButton, 'Previous');
      expect(
        tester.getTopLeft(shortcuts).dy - tester.getBottomLeft(ring).dy,
        lessThanOrEqualTo(20),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'D-pad arrows fill ring sectors and exclude center and outer corners',
    (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final peer = FakePeer();
      addTearDown(peer.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: linkpadTheme(Brightness.light),
          home: RemotePage(peer: peer, onSettings: () {}),
        ),
      );
      final ring = find.byWidgetPredicate(
        (w) =>
            w is Semantics && (w.properties.label ?? '').startsWith('D-pad.'),
      );
      await tester.scrollUntilVisible(
        find.byIcon(Icons.keyboard_arrow_up),
        150,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(ring);
      await tester.pumpAndSettle();
      final center = tester.getCenter(ring);
      final diameter = tester.getSize(ring).width;
      final points = <String, Offset>{
        'up': const Offset(.22, -.34),
        'right': const Offset(.34, .22),
        'down': const Offset(-.22, .34),
        'left': const Offset(-.34, -.22),
      };
      for (final entry in points.entries) {
        final count = peer.keys.length;
        await tester.tapAt(center + entry.value * diameter);
        await tester.pump();
        expect(peer.keys.length, count + 1, reason: entry.key);
        expect(peer.keys.last.key, entry.key);
      }
      await tester.tapAt(center + Offset(diameter * .14, diameter * .16));
      await tester.pump();
      expect(
        peer.keys.last.key,
        'down',
        reason: 'Enter must not steal touches outside its circle',
      );
      final count = peer.keys.length;
      await tester.tapAt(center + Offset(diameter * .46, diameter * .46));
      await tester.pump();
      expect(peer.keys.length, count);
      await tester.tapAt(center);
      await tester.pump();
      expect(peer.keys.length, count + 1);
      expect(peer.keys.last.key, 'enter');
      final hold = await tester.startGesture(center + points['up']! * diameter);
      await tester.pump(const Duration(milliseconds: 750));
      expect(peer.keys.last.key, 'up');
      expect(peer.keys.length, greaterThan(count + 2));
      await hold.up();
      final stopped = peer.keys.length;
      await tester.pump(const Duration(milliseconds: 400));
      expect(peer.keys.length, stopped);
    },
  );

  testWidgets('older servers retain tap-to-latch Super shortcuts in Keyboard', (
    tester,
  ) async {
    final peer = FakePeer()..standaloneSuper = false;
    final settings = CursorSettings();
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
    await tester.ensureVisible(find.text('Win / Cmd'));
    await tester.tap(find.text('Win / Cmd'));
    await tester.pump();
    expect(peer.keys, isEmpty);
    await tester.ensureVisible(find.text('a'));
    await tester.tap(find.text('a'));
    await tester.pump();
    expect(peer.keys.last.key, 'a');
    expect(peer.keys.last.modifiers, {'super'});
  });

  testWidgets(
    'Keyboard Win Command tap sends standalone and hold prepares a shortcut',
    (tester) async {
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
      await tester.ensureVisible(find.text('Win / Cmd'));
      await tester.tap(find.text('Win / Cmd'));
      await tester.pump();
      expect(peer.keys.last.key, 'super');
      expect(peer.keys.last.modifiers, isEmpty);
      await tester.longPress(find.text('Win / Cmd'));
      await tester.pump();
      await tester.ensureVisible(find.text('e'));
      await tester.tap(find.text('e'));
      await tester.pump();
      expect(peer.keys.last.key, 'e');
      expect(peer.keys.last.modifiers, {'super'});
    },
  );

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

  testWidgets('Remote sends navigation without modifier controls', (
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
    await tester.ensureVisible(find.text('Enter'));
    await tester.tap(find.text('Enter'));
    await tester.pump();
    expect(peer.keys.last.key, 'enter');
    expect(peer.keys.last.modifiers, isEmpty);
    await tester.ensureVisible(find.byIcon(Icons.keyboard_arrow_left));
    await tester.tap(find.byIcon(Icons.keyboard_arrow_left));
    await tester.pump();
    expect(peer.keys.last.key, 'left');
    expect(peer.keys.last.modifiers, isEmpty);
    await tester.ensureVisible(find.text('Previous'));
    await tester.tap(find.text('Previous'));
    await tester.pump();
    expect(peer.keys.last.key, 'tab');
    expect(peer.keys.last.modifiers, {'shift'});
  });

  testWidgets(
    'volume hold repeats, mute stays single-shot, and disconnect cancels repeats',
    (tester) async {
      final peer = FakePeer();
      addTearDown(peer.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: linkpadTheme(Brightness.light),
          home: RemotePage(peer: peer, onSettings: () {}),
        ),
      );
      final up = find.byIcon(Icons.volume_up_outlined);
      await tester.ensureVisible(up);
      final hold = await tester.startGesture(tester.getCenter(up));
      await tester.pump(const Duration(milliseconds: 750));
      expect(peer.volumeActions.length, greaterThan(1));
      expect(peer.volumeActions.every((a) => a == 'up'), isTrue);
      peer.pause();
      await tester.pump();
      final stopped = peer.volumeActions.length;
      await tester.pump(const Duration(milliseconds: 400));
      expect(peer.volumeActions.length, stopped);
      await hold.up();
      peer.resume();
      await tester.pump();
      final mute = find.byIcon(Icons.volume_off_outlined);
      await tester.ensureVisible(mute);
      await tester.longPress(mute);
      await tester.pump();
      final muteHeld = peer.volumeActions.where((a) => a == 'mute').length;
      // A long hold may show the tooltip, but must never repeat Mute.
      expect(muteHeld, lessThanOrEqualTo(1));
      await tester.tap(mute);
      await tester.pump();
      expect(peer.volumeActions.where((a) => a == 'mute').length, muteHeld + 1);
    },
  );

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
