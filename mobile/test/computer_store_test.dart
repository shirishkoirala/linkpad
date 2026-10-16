import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linkpad_controller/computer_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final a = List.filled(64, 'a').join(), b = List.filled(64, 'b').join();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
    'migrates existing pairing and forgetting it cannot resurrect the old entry',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'desktop_v1': jsonEncode({'address': 'wss://old-pc:4747/ws', 'pin': a}),
        'peer_identity_v1': 'keep-this-identity',
      });
      final store = ComputerStore();
      await store.load();
      expect(store.computers.single.fingerprint, a);
      expect(store.computers.single.name, 'old-pc');
      expect(store.computers.single.lastUsed, isNull);
      await store.forget(a);
      final restored = ComputerStore();
      await restored.load();
      expect(restored.computers, isEmpty);
      expect(
        await const FlutterSecureStorage().read(key: 'peer_identity_v1'),
        'keep-this-identity',
      );
      store.dispose();
      restored.dispose();
    },
  );
  test(
    'multiple computers survive reload with independent pins and names',
    () async {
      final store = ComputerStore();
      await store.saveVerified(
        'wss://linux:4747/ws',
        a,
        usedAt: DateTime.utc(2026, 10, 15),
      );
      await store.rename(a, 'Linux PC');
      await store.saveVerified(
        'wss://mac:4747/ws',
        b,
        usedAt: DateTime.utc(2026, 10, 16),
      );
      await store.rename(b, 'MacBook');
      final restored = ComputerStore();
      await restored.load();
      expect(restored.computers.map((c) => c.name), ['MacBook', 'Linux PC']);
      expect(restored.find(a)!.address, 'wss://linux:4747/ws');
      expect(restored.find(b)!.address, 'wss://mac:4747/ws');
      expect(restored.lastUsedId, b);
      store.dispose();
      restored.dispose();
    },
  );
  test(
    'verified address updates preserve custom names and do not create duplicates',
    () async {
      final store = ComputerStore();
      await store.saveVerified('wss://192.168.1.10:4747/ws', a);
      await store.rename(a, 'Office');
      await Future.wait([
        store.saveVerified('wss://192.168.1.20:4747/ws', a),
        store.rename(a, 'Office Linux'),
      ]);
      expect(store.computers.single.name, 'Office Linux');
      expect(store.computers.single.address, 'wss://192.168.1.20:4747/ws');
      await Future.wait([
        store.saveVerified('wss://192.168.1.20:4747/ws', a),
        store.forget(a),
      ]);
      final restored = ComputerStore();
      await restored.load();
      expect(restored.computers, isEmpty);
      store.dispose();
      restored.dispose();
    },
  );
  test(
    'same address with a different verified identity is a separate computer',
    () async {
      final store = ComputerStore();
      await store.saveVerified('wss://shared-ip:4747/ws', a);
      await store.saveVerified('wss://shared-ip:4747/ws', b);
      expect(store.computers.length, 2);
      await store.forget(a);
      expect(store.computers.single.id, b);
      store.dispose();
    },
  );
  test('corrupt saved data is never overwritten by a new connection', () async {
    FlutterSecureStorage.setMockInitialValues({
      'computers_v1': 'broken saved list',
    });
    final store = ComputerStore();
    await store.load();
    expect(store.warning, isNotNull);
    expect(await store.saveVerified('wss://new-pc:4747/ws', a), isFalse);
    expect(
      await const FlutterSecureStorage().read(key: 'computers_v1'),
      'broken saved list',
    );
    store.dispose();
  });
  test(
    'one-time pairing secrets are not part of saved computer records',
    () async {
      final store = ComputerStore();
      await store.saveVerified('wss://linux:4747/ws', a);
      final raw = await const FlutterSecureStorage().read(
        key: ComputerStore.storageKey,
      );
      expect(
        jsonDecode(raw!)['computers'].single.keys,
        unorderedEquals(['name', 'address', 'pin', 'lastUsed']),
      );
      store.dispose();
    },
  );
}
