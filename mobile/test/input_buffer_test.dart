import 'package:flutter_test/flutter_test.dart';
import 'package:linkpad_controller/input_buffer.dart';
import 'package:linkpad_controller/peer_client.dart';

void main() {
  test('input older than 150ms is discarded, including clicks', () {
    final buffer = InputBuffer();
    buffer.move(100, 100, Duration.zero);
    buffer.click('left', Duration.zero);
    expect(buffer.take(const Duration(milliseconds: 150)), isNull);
    buffer.move(3, -2, const Duration(milliseconds: 151));
    final input = buffer.take(const Duration(milliseconds: 151))!;
    expect([input.dx, input.dy, input.button], [3, -2, null]);
  });

  test('movement and click ordering is preserved', () {
    final buffer = InputBuffer();
    buffer.move(10, 0, Duration.zero);
    buffer.click('left', Duration.zero);
    buffer.move(-20, 5, Duration.zero);
    buffer.click('right', Duration.zero);
    final a = buffer.take(Duration.zero)!;
    final b = buffer.take(Duration.zero)!;
    final c = buffer.take(Duration.zero)!;
    final d = buffer.take(Duration.zero)!;
    expect([a.dx, a.dy, a.button], [10, 0, null]);
    expect(b.button, 'left');
    expect([c.dx, c.dy, c.button], [-20, 5, null]);
    expect(d.button, 'right');
  });

  test('continuous new motion cannot renew stale queued motion', () {
    final buffer = InputBuffer();
    buffer.move(100, 0, Duration.zero);
    buffer.move(50, 0, const Duration(milliseconds: 140));
    buffer.move(2, 0, const Duration(milliseconds: 151));
    expect(buffer.take(const Duration(milliseconds: 151))!.dx, 2);
  });

  test(
    'input is bounded, fractional motion is retained, clear resets everything',
    () {
      final buffer = InputBuffer();
      buffer.move(0.5, 0, Duration.zero);
      expect(buffer.hasReady(Duration.zero), isFalse);
      buffer.move(0.5, 0, Duration.zero);
      expect(buffer.take(Duration.zero)!.dx, 1);
      buffer.move(double.infinity, 0, Duration.zero);
      expect(buffer.hasReady(Duration.zero), isFalse);
      buffer.move(1e20, -1e20, Duration.zero);
      final big = buffer.take(Duration.zero)!;
      expect([big.dx, big.dy], [500, -500]);
      for (var i = 0; i < 100; i++) {
        buffer.click('left', Duration.zero);
      }
      var count = 0;
      while (buffer.take(Duration.zero) != null) {
        count++;
      }
      expect(count, 8);
      buffer.click('right', Duration.zero);
      buffer.clear();
      expect(buffer.take(Duration.zero), isNull);
    },
  );

  test('reconnect delay grows and is capped', () {
    const timing = PeerTiming();
    expect(List.generate(7, (i) => timing.retryDelay(i).inSeconds), [
      1,
      2,
      4,
      8,
      15,
      15,
      15,
    ]);
  });
}
