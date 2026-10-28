import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linkpad_controller/nearby_computers.dart';
import 'package:linkpad_controller/server_discovery.dart';

class NearbyFixture extends BonjourServerDiscovery {
  NearbyFixture(this.servers);
  final List<DiscoveredServer> servers;
  @override
  Future<List<DiscoveredServer>> browse({required Duration timeout}) async =>
      servers;
  @override
  Future<void> stop() async {}
}

void main() {
  testWidgets(
    'saved identities are hidden and forgotten servers can be paired',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final pin = List.filled(64, 'a').join();
      final discovery = NearbyFixture([
        DiscoveredServer(pin, Uri.parse('wss://192.168.1.12:4747/ws')),
      ]);
      DiscoveredServer? selected;
      var saved = {pin};
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return NearbyComputers(
                  discovery: discovery,
                  savedIds: saved,
                  onPair: (server) => selected = server,
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('192.168.1.12'), findsNothing);
      update(() => saved = {});
      await tester.pump();
      expect(find.text('192.168.1.12'), findsOneWidget);
      await tester.tap(find.text('Pair'));
      expect(selected?.fingerprint, pin);
      expect(selected?.address.toString(), 'wss://192.168.1.12:4747/ws');
      await tester.pumpWidget(const SizedBox());
    },
  );
}
