import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linkpad_controller/hold_click_button.dart';
import 'package:linkpad_controller/relative_touchpad.dart';

void main() {
  testWidgets(
    'holding left click allows a second finger to move the touchpad',
    (tester) async {
      final events = <String>[], moves = <Offset>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Expanded(
                  child: RelativeTouchpad(
                    enabled: true,
                    onMove: (dx, dy) => moves.add(Offset(dx, dy)),
                    child: const SizedBox.expand(),
                  ),
                ),
                HoldClickButton(
                  enabled: true,
                  supportsDrag: true,
                  holding: false,
                  onStart: () => events.add('down'),
                  onEnd: () => events.add('up'),
                  onCancel: () => events.add('cancel'),
                  onClick: () => events.add('click'),
                ),
              ],
            ),
          ),
        ),
      );
      final hold = await tester.startGesture(
        tester.getCenter(find.text('Left click')),
        pointer: 1,
      );
      expect(events, ['down']);
      final motion = await tester.startGesture(
        tester.getCenter(find.byType(RelativeTouchpad)),
        pointer: 2,
      );
      await motion.moveBy(const Offset(25, 10));
      await motion.up();
      expect(moves, [const Offset(25, 10)]);
      expect(events, ['down']);
      await hold.up();
      await tester.pump();
      expect(events, ['down', 'up']);
      final cancelled = await tester.startGesture(
        tester.getCenter(find.text('Left click')),
        pointer: 3,
      );
      await cancelled.cancel();
      await tester.pump();
      expect(events, ['down', 'up', 'down', 'cancel']);
    },
  );
  testWidgets('older servers retain ordinary single-click behavior', (
    tester,
  ) async {
    var clicks = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HoldClickButton(
            enabled: true,
            supportsDrag: false,
            holding: false,
            onStart: () => fail('unsupported drag started'),
            onEnd: () => fail('unsupported drag ended'),
            onCancel: () => fail('unsupported drag cancelled'),
            onClick: () => clicks++,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Left click'));
    expect(clicks, 1);
  });
}
