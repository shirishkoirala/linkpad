import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'protocol.dart';

class SavedComputer {
  const SavedComputer({
    required this.name,
    required this.address,
    required this.fingerprint,
    this.lastUsed,
  });
  final String name, address, fingerprint;
  final DateTime? lastUsed;
  String get id => fingerprint;

  static SavedComputer fromJson(Map<String, dynamic> json) {
    final address = peerAddress(json['address'] as String).toString();
    final pin = (json['pin'] as String).toLowerCase();
    final name = (json['name'] as String).trim();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(pin) ||
        name.isEmpty ||
        name.length > 60) {
      throw const FormatException('Invalid saved computer');
    }
    final used = json['lastUsed'];
    return SavedComputer(
      name: name,
      address: address,
      fingerprint: pin,
      lastUsed: used == null ? null : DateTime.parse(used as String).toUtc(),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'address': address,
    'pin': fingerprint,
    if (lastUsed != null) 'lastUsed': lastUsed!.toUtc().toIso8601String(),
  };
}

/// Serializes secure-storage mutations so reconnects cannot undo rename/forget.
class ComputerStore extends ChangeNotifier {
  ComputerStore({FlutterSecureStorage storage = const FlutterSecureStorage()})
    : _storage = storage;
  static const storageKey = 'computers_v1';
  final FlutterSecureStorage _storage;
  final _computers = <String, SavedComputer>{};
  Future<void>? _loading;
  Future<void> _writes = Future<void>.value();
  bool loaded = false, _readSucceeded = false, _disposed = false;
  String? warning;
  String? lastUsedId;

  List<SavedComputer> get computers {
    final result = _computers.values.toList()
      ..sort((a, b) {
        final time = (b.lastUsed?.millisecondsSinceEpoch ?? 0).compareTo(
          a.lastUsed?.millisecondsSinceEpoch ?? 0,
        );
        return time != 0
            ? time
            : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return List.unmodifiable(result);
  }

  SavedComputer? find(String? id) => _computers[id];
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final raw = await _storage.read(key: storageKey);
      final restored = <String, SavedComputer>{};
      if (raw != null) {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        if (json['version'] != 1 || json['computers'] is! List) {
          throw const FormatException('Invalid computer list');
        }
        for (final item in json['computers'] as List) {
          final computer = SavedComputer.fromJson(item as Map<String, dynamic>);
          if (restored.containsKey(computer.id)) {
            throw const FormatException('Duplicate computer');
          }
          restored[computer.id] = computer;
        }
        final last = json['lastUsedId'];
        if (last != null && last is! String) {
          throw const FormatException('Invalid last computer');
        }
        lastUsedId = last is String && restored.containsKey(last) ? last : null;
      } else {
        final legacy = await _storage.read(key: 'desktop_v1');
        if (legacy != null) {
          final json = jsonDecode(legacy) as Map<String, dynamic>;
          final address = peerAddress(json['address'] as String);
          final computer = SavedComputer.fromJson({
            'name': address.host,
            'address': address.toString(),
            'pin': json['pin'],
          });
          restored[computer.id] = computer;
          lastUsedId = computer.id;
        }
      }
      _computers
        ..clear()
        ..addAll(restored);
      _readSucceeded = true;
      warning = null;
      // Keep the old key until the new list has been written successfully.
      if (raw == null && restored.isNotEmpty && await _persist()) {
        try {
          await _storage.delete(key: 'desktop_v1');
        } catch (_) {
          /* New list remains authoritative. */
        }
      }
    } catch (_) {
      warning =
          'Could not read saved computers. Unlock your phone and try again.';
    } finally {
      loaded = true;
      _notify();
    }
  }

  Future<void> retryLoad() {
    if (!loaded && _loading != null) return _loading!;
    if (_readSucceeded) return Future<void>.value();
    _loading = null;
    loaded = false;
    warning = null;
    _notify();
    return load();
  }

  Future<bool> _persist() async {
    try {
      await _storage.write(
        key: storageKey,
        value: jsonEncode({
          'version': 1,
          'computers': _computers.values.map((c) => c.toJson()).toList(),
          if (lastUsedId != null) 'lastUsedId': lastUsedId,
        }),
      );
      warning = null;
      return true;
    } catch (_) {
      warning =
          'Changes are available for now, but could not be saved. Try saving again.';
      return false;
    }
  }

  Future<bool> _change(void Function() edit) {
    final result = _writes.then((_) async {
      await load();
      if (!_readSucceeded) {
        _notify();
        return false;
      }
      edit();
      _notify();
      final saved = await _persist();
      _notify();
      return saved;
    });
    // A failed operation must not poison later writes.
    _writes = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<bool> saveVerified(
    String address,
    String fingerprint, {
    DateTime? usedAt,
  }) {
    final uri = peerAddress(address);
    final pin = fingerprint.toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(pin)) {
      throw const FormatException('Invalid desktop fingerprint');
    }
    return _change(() {
      _computers[pin] = SavedComputer(
        name:
            _computers[pin]?.name ??
            (uri.host.length > 60 ? uri.host.substring(0, 60) : uri.host),
        address: uri.toString(),
        fingerprint: pin,
        lastUsed: (usedAt ?? DateTime.now()).toUtc(),
      );
      lastUsedId = pin;
    });
  }

  Future<bool> rename(String id, String name) {
    final clean = name.trim();
    if (clean.isEmpty || clean.length > 60) {
      throw ArgumentError('Use a name between 1 and 60 characters');
    }
    return _change(() {
      final computer = _computers[id];
      if (computer == null) return;
      _computers[id] = SavedComputer(
        name: clean,
        address: computer.address,
        fingerprint: computer.fingerprint,
        lastUsed: computer.lastUsed,
      );
    });
  }

  Future<bool> forget(String id) => _change(() {
    _computers.remove(id);
    if (lastUsedId == id) lastUsedId = null;
  });
  Future<bool> retrySave() => _change(() {});
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
