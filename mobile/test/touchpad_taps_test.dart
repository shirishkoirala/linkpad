import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linkpad_controller/relative_touchpad.dart';

void main() {
  testWidgets('one finger clicks left; two fingers click right once', (
    tester,
  ) async {
    final clicks = <String>[];
    final moves = <Offset>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RelativeTouchpad(
            enabled: true,
            onClick: clicks.add,
            onMove: (dx, dy) => moves.add(Offset(dx, dy)),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    final first = await tester.createGesture(pointer: 1);
    await first.down(const Offset(50, 50));
    await first.up(timeStamp: const Duration(milliseconds: 100));
    expect(clicks, ['left']);

    final a = await tester.createGesture(pointer: 2);
    final b = await tester.createGesture(pointer: 3);
    await a.down(const Offset(50, 50));
    await b.down(
      const Offset(100, 50),
      timeStamp: const Duration(milliseconds: 30),
    );
    await a.up(timeStamp: const Duration(milliseconds: 80));
    expect(clicks, ['left']);
    await b.up(timeStamp: const Duration(milliseconds: 100));
    expect(clicks, ['left', 'right']);
    expect(moves, isEmpty);
  });

  testWidgets('movement, long holds and cancelled contacts do not click', (
    tester,
  ) async {
    final clicks = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RelativeTouchpad(
            enabled: true,
            onClick: clicks.add,
            onMove: (_, _) {},
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    final drag = await tester.createGesture(pointer: 1);
    await drag.down(const Offset(50, 50));
    await drag.moveTo(const Offset(100, 100));
    await drag.up();
    final hold = await tester.createGesture(pointer: 2);
    await hold.down(const Offset(50, 50));
    await hold.up(timeStamp: const Duration(milliseconds: 400));
    final cancelled = await tester.createGesture(pointer: 3);
    await cancelled.down(const Offset(50, 50));
    await cancelled.cancel();
    expect(clicks, isEmpty);
  });
}
