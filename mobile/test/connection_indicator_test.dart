import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linkpad_controller/mobile_controls.dart';
import 'control_deck_test.dart' show FakePeer;

class QualityPeer extends FakePeer {
  Duration? latency;
  bool queueFull = false;
  @override
  bool get inputQueueFull => queueFull;
  void refresh() => notifyListeners();
  @override
  Duration? get roundTripTime => latency;
}

void main() {
  testWidgets(
    'connection bars follow response quality and retain timing details',
    (tester) async {
      final peer = QualityPeer();
      addTearDown(peer.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: AnimatedBuilder(
            animation: peer,
            builder: (_, _) => MobileControlScaffold(
              peer: peer,
              mode: MobileControlMode.touchpad,
              onModeChanged: (_) {},
              onComputers: () {},
              onSettings: () {},
              bodyBuilder: (_, _) => const SizedBox(),
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.wifi_find), findsOneWidget);
      for (final sample in [
        (50, Icons.wifi),
        (150, Icons.wifi_2_bar),
        (284, Icons.wifi_1_bar),
      ]) {
        peer.latency = Duration(milliseconds: sample.$1);
        peer.refresh();
        await tester.pump();
        expect(find.byIcon(sample.$2), findsOneWidget);
        expect(find.text('Connected · Ready to control'), findsOneWidget);
        expect(find.textContaining(' ms'), findsNothing);
        final details = tester.widgetList<Tooltip>(find.byType(Tooltip));
        expect(
          details.any((tip) => tip.message?.contains('Response time') ?? false),
          isTrue,
        );
      }
      peer.queueFull = true;
      peer.refresh();
      await tester.pump();
      expect(find.text('Sending queued keys… · Please wait'), findsOneWidget);
      expect(find.byIcon(Icons.wifi_1_bar), findsOneWidget);
      peer.queueFull = false;
      peer.responsePaused = true;
      peer.refresh();
      await tester.pump();
      expect(find.byIcon(Icons.wifi_off), findsOneWidget);
      peer.pause();
      await tester.pump();
      expect(find.byIcon(Icons.wifi_off), findsOneWidget);
      expect(find.text('Reconnecting… · Controls paused'), findsOneWidget);
      expect(find.text('Controls paused while we reconnect.'), findsNothing);
    },
  );
}
