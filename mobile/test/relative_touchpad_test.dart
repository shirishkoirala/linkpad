import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linkpad_controller/relative_touchpad.dart';

void main() {
  testWidgets(
    'held finger resumes after a pause without a new touch or cursor jump',
    (tester) async {
      final enabled = ValueNotifier(true);
      addTearDown(enabled.dispose);
      final moves = <Offset>[];
      final clicks = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<bool>(
            valueListenable: enabled,
            builder: (_, active, _) => RelativeTouchpad(
              enabled: active,
              onMove: (dx, dy) => moves.add(Offset(dx, dy)),
              onClick: clicks.add,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );
      final finger = await tester.createGesture();
      await finger.down(const Offset(50, 50));
      await finger.moveTo(const Offset(65, 55));
      expect(moves, [const Offset(15, 5)]);
      enabled.value = false;
      await tester.pump();
      await finger.moveTo(const Offset(300, 200));
      expect(moves.length, 1);
      enabled.value = true;
      await tester.pump();
      await finger.moveTo(
        const Offset(310, 205),
      ); // Rebase, never replay the gap.
      expect(moves.length, 1);
      await finger.moveTo(const Offset(317, 208));
      await finger.up();
      expect(moves, [const Offset(15, 5), const Offset(7, 3)]);
      expect(clicks, isEmpty);
    },
  );

  testWidgets('a contact placed while paused can move after recovery', (
    tester,
  ) async {
    final enabled = ValueNotifier(false);
    addTearDown(enabled.dispose);
    final moves = <Offset>[];
    final clicks = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<bool>(
          valueListenable: enabled,
          builder: (_, active, _) => RelativeTouchpad(
            enabled: active,
            onMove: (dx, dy) => moves.add(Offset(dx, dy)),
            onClick: clicks.add,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    final finger = await tester.createGesture();
    await finger.down(const Offset(50, 50));
    await finger.moveTo(const Offset(100, 100));
    enabled.value = true;
    await tester.pump();
    await finger.moveTo(const Offset(110, 100));
    await finger.moveTo(const Offset(115, 103));
    await finger.up();
    expect(moves, [const Offset(5, 3)]);
    expect(clicks, isEmpty);
  });

  testWidgets(
    'two-finger scrolling rebases after recovery without a right click',
    (tester) async {
      final enabled = ValueNotifier(true);
      addTearDown(enabled.dispose);
      final scrolls = <Offset>[];
      final clicks = <String>[];
      final moves = <Offset>[];
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<bool>(
            valueListenable: enabled,
            builder: (_, active, _) => RelativeTouchpad(
              enabled: active,
              onMove: (dx, dy) => moves.add(Offset(dx, dy)),
              onClick: clicks.add,
              onScroll: (dx, dy) => scrolls.add(Offset(dx, dy)),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );
      final first = await tester.createGesture(pointer: 1);
      final second = await tester.createGesture(pointer: 2);
      await first.down(const Offset(50, 50));
      await second.down(const Offset(100, 50));
      await first.moveTo(const Offset(50, 70));
      expect(scrolls, [const Offset(0, 10)]);
      enabled.value = false;
      await tester.pump();
      await first.moveTo(const Offset(50, 200));
      await second.moveTo(const Offset(100, 200));
      enabled.value = true;
      await tester.pump();
      await first.moveTo(const Offset(50, 210));
      expect(scrolls.length, 1);
      await second.moveTo(const Offset(100, 210));
      await first.up();
      await second.up();
      expect(scrolls, [const Offset(0, 10), const Offset(0, 5)]);
      expect(clicks, isEmpty);
      expect(moves, isEmpty);
    },
  );

  testWidgets(
    'an interrupted tap cannot click on recovery, but a fresh tap works',
    (tester) async {
      final enabled = ValueNotifier(true);
      addTearDown(enabled.dispose);
      final clicks = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<bool>(
            valueListenable: enabled,
            builder: (_, active, _) => RelativeTouchpad(
              enabled: active,
              onMove: (_, _) {},
              onClick: clicks.add,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );
      final first = await tester.createGesture(pointer: 1);
      await first.down(const Offset(50, 50));
      enabled.value = false;
      await tester.pump();
      enabled.value = true;
      await tester.pump();
      await first.up(timeStamp: const Duration(milliseconds: 100));
      expect(clicks, isEmpty);
      final fresh = await tester.createGesture(pointer: 2);
      await fresh.down(const Offset(50, 50));
      await fresh.up(timeStamp: const Duration(milliseconds: 100));
      expect(clicks, ['left']);
    },
  );

  testWidgets('lifting and landing elsewhere never moves the cursor', (
    tester,
  ) async {
    final deltas = <Offset>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RelativeTouchpad(
            enabled: true,
            onMove: (dx, dy) => deltas.add(Offset(dx, dy)),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    final first = await tester.createGesture(pointer: 1);
    await first.down(const Offset(50, 50));
    await first.moveTo(const Offset(60, 55));
    await first.up();
    final second = await tester.createGesture(pointer: 2);
    await second.down(const Offset(300, 300));
    expect(deltas, [const Offset(10, 5)]);
    await second.moveTo(const Offset(310, 305));
    await second.up();
    expect(deltas, [const Offset(10, 5), const Offset(10, 5)]);
  });
}
