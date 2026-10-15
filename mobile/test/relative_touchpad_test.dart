import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linkpad_controller/relative_touchpad.dart';

void main() {
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
