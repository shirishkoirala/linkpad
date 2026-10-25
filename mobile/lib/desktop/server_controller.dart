import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class DesktopPeer {
  const DesktopPeer(this.id, this.connected);
  final String id;
  final bool connected;
}

/// Owns one bundled Go child. Pairing secrets remain in memory only.
class ServerController extends ChangeNotifier {
  ServerController({
    this.executable,
    this.stateDirectory,
    this.settingsDirectory,
    this.listenAddress = '0.0.0.0:4747',
  });
  final String? executable;
  final String? stateDirectory;
  final String? settingsDirectory;
  final String listenAddress;
  Process? _process;
  Future<void>? _operation;
  final Map<int, Completer<void>> _requests = {};
  int _nextRequest = 0;
  bool busy = false;
  bool running = false;
  bool inputAvailable = false;
  bool? inputPermissionGranted;
  int inputCount = 0;
  bool onboardingLoaded = false, setupCompleted = false, setupTested = false;
  bool _disposed = false;
  String address = '';
  String addressError = '';
  String fingerprint = '';
  String inputError = '';
  String? error;
  Map<String, dynamic>? pairing;
  List<DesktopPeer> peers = [];
  final List<String> _logs = [];
  Map<String, String> names = {};
  String? _settingsPath;

  String get diagnostics => [
    'Linkpad desktop · ${Platform.operatingSystem}',
    'Server: ${running ? "running" : "stopped"}',
    'Address: $address',
    'Input: ${inputAvailable ? "available" : inputError}',
    if (error != null) 'Error: $error',
    ..._logs,
  ].join('\n');

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() async {
    try {
      final dir = settingsDirectory == null
          ? await getApplicationSupportDirectory()
          : Directory(settingsDirectory!);
      await dir.create(recursive: true);
      _settingsPath = '${dir.path}/desktop-names.json';
      final file = File(_settingsPath!);
      if (await file.exists()) {
        names = Map<String, String>.from(
          jsonDecode(await file.readAsString()) as Map,
        );
      }
    } catch (_) {
      error = 'Could not load device names. Server trust is unaffected.';
      _changed();
    }
    var hadSetupFile = false;
    try {
      if (_settingsPath != null) {
        final file = File(
          '${File(_settingsPath!).parent.path}/desktop-setup.json',
        );
        hadSetupFile = await file.exists();
        if (hadSetupFile) {
          final saved = jsonDecode(await file.readAsString()) as Map;
          setupCompleted = saved['completed'] == true;
          setupTested = saved['tested'] == true;
        }
      }
    } catch (_) {
      error =
          'Could not load setup progress. Your phone pairings are unaffected.';
    }
    await start();
    // Existing installations with trusted phones keep their regular dashboard.
    if (!hadSetupFile) {
      setupCompleted = peers.isNotEmpty;
      try {
        // Record fresh setup before a phone pairs, so an interrupted setup is
        // distinguishable from an upgrade of a previously trusted installation.
        await _saveSetupState(completed: setupCompleted, tested: false);
      } catch (_) {
        error =
            'Could not save setup progress. Your phone pairings are unaffected.';
      }
    }
    onboardingLoaded = true;
    _changed();
  }

  void reviewSetup() {
    setupCompleted = false;
    _changed();
  }

  Future<void> completeSetup({required bool tested}) async {
    await _saveSetupState(completed: true, tested: tested);
    setupCompleted = true;
    setupTested = tested;
    _changed();
  }

  Future<void> _saveSetupState({
    required bool completed,
    required bool tested,
  }) async {
    if (_settingsPath == null) {
      throw StateError(
        'Setup progress could not be saved. Try reopening Linkpad.',
      );
    }
    final path = '${File(_settingsPath!).parent.path}/desktop-setup.json';
    final temporary = File('$path.tmp');
    await temporary.writeAsString(
      jsonEncode({'version': 1, 'completed': completed, 'tested': tested}),
      flush: true,
    );
    await temporary.rename(path);
  }

  String _binary() {
    if (executable != null) return executable!;
    final override = Platform.environment['LINKPAD_SERVER_BINARY'];
    if (override != null && override.isNotEmpty) return override;
    final base = File(Platform.resolvedExecutable).parent.path;
    return Platform.isMacOS
        ? '$base/../Resources/linkpad-server'
        : '$base/lib/linkpad-server';
  }

  Future<void> start() => _serialize(() async {
    if (_process != null) return;
    error = null;
    final ready = Completer<void>();
    try {
      final process = await Process.start(_binary(), [
        '-desktop',
        '-listen',
        listenAddress,
        '-allow-pointer',
        if (stateDirectory != null) ...['-state', stateDirectory!],
      ]);
      _process = process;
      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              if (_process != process) return;
              try {
                final value = jsonDecode(line) as Map<String, dynamic>;
                if (value['type'] != 'status') return;
                running = value['running'] == true;
                inputAvailable = value['inputAvailable'] == true;
                inputPermissionGranted =
                    value['inputPermissionGranted'] as bool?;
                inputCount = (value['inputCount'] as num?)?.toInt() ?? 0;
                address = value['address'] as String? ?? '';
                addressError = value['addressError'] as String? ?? '';
                fingerprint = value['fingerprint'] as String? ?? '';
                inputError = value['inputError'] as String? ?? '';
                pairing = value['pairing'] as Map<String, dynamic>?;
                peers = (value['peers'] as List)
                    .map(
                      (p) => DesktopPeer(
                        p['id'] as String,
                        p['connected'] == true,
                      ),
                    )
                    .toList();
                final message = value['error'] as String? ?? '';
                final request = _requests.remove(value['id']);
                if (message.isNotEmpty) {
                  error = message;
                  request?.completeError(StateError(message));
                } else {
                  request?.complete();
                }
                if (!ready.isCompleted) {
                  if ((value['addressError'] as String? ?? '').isNotEmpty) {
                    error = value['addressError'] as String;
                  }
                  ready.complete();
                }
                _changed();
              } catch (_) {
                error =
                    'The desktop server sent an invalid response. Restart Linkpad.';
                _changed();
              }
            },
            onError: (_) {
              error = 'Lost the desktop server control channel.';
              _changed();
            },
          );
      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            // The desktop protocol never prints invitations on stderr.
            _logs.add(line.length > 1000 ? line.substring(0, 1000) : line);
            if (_logs.length > 40) _logs.removeAt(0);
          });
      unawaited(
        process.exitCode.then((code) {
          if (_process != process) return;
          _process = null;
          running = false;
          pairing = null;
          peers = [];
          if (code != 0) {
            error = _logs.any((line) => line.contains('address already in use'))
                ? 'Another server is using port 4747. Stop it, then choose Start server.'
                : 'Server exited ($code). ${_logs.isEmpty ? "Check that port 4747 is free." : _logs.last}';
          }
          if (!ready.isCompleted) {
            ready.completeError(
              StateError(error ?? 'Server stopped before starting.'),
            );
          }
          _failRequests();
          _changed();
        }),
      );
      await ready.future.timeout(const Duration(seconds: 15));
    } catch (e) {
      error ??= 'Could not start the bundled server: $e';
      await _stop();
      _changed();
    }
  });

  Future<void> _serialize(Future<void> Function() action) async {
    final previous = _operation;
    final completion = Completer<void>();
    final task = completion.future;
    _operation = task;
    try {
      if (previous != null) await previous;
      if (_disposed) return;
      busy = true;
      _changed();
      await action();
    } finally {
      if (_operation == task) _operation = null;
      busy = false;
      completion.complete();
      _changed();
    }
  }

  Future<void> stop() => _serialize(_stop);
  Future<void> restart() async {
    await stop();
    await start();
  }

  Future<void> _stop() async {
    final process = _process;
    if (process == null) return;
    try {
      process.stdin.writeln(jsonEncode({'command': 'stop'}));
      await process.stdin.close();
      await process.exitCode.timeout(const Duration(seconds: 4));
    } catch (_) {
      process.kill();
      try {
        await process.exitCode.timeout(const Duration(seconds: 2));
      } catch (_) {
        process.kill(ProcessSignal.sigkill);
        await process.exitCode;
      }
    }
    if (_process == process) _process = null;
    running = false;
    pairing = null;
    peers = [];
    _failRequests();
    _changed();
  }

  void _failRequests() {
    for (final request in _requests.values) {
      if (!request.isCompleted) {
        request.completeError(StateError('Server stopped.'));
      }
    }
    _requests.clear();
  }

  Future<void> command(String command, {String? peer, String? address}) async {
    final process = _process;
    if (process == null || !running) {
      throw StateError('Start the server first.');
    }
    final id = ++_nextRequest;
    final done = Completer<void>();
    _requests[id] = done;
    error = null;
    try {
      process.stdin.writeln(
        jsonEncode({
          'id': id,
          'command': command,
          'peer': ?peer,
          'address': ?address,
        }),
      );
      await done.future.timeout(const Duration(seconds: 5));
    } finally {
      _requests.remove(id);
    }
  }

  String nameOf(String id) => names[id] ?? 'Phone · ${id.substring(0, 8)}';

  Future<void> rename(String id, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 60) {
      throw ArgumentError('Use a name between 1 and 60 characters.');
    }
    final next = {...names, id: trimmed};
    if (_settingsPath == null) {
      throw StateError('Device name storage is unavailable.');
    }
    final temp = File('$_settingsPath.tmp');
    await temp.writeAsString(jsonEncode(next), flush: true);
    await temp.rename(_settingsPath!);
    names = next;
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    // Closing the private pipe makes Go stop even if the Flutter window crashes.
    _process?.stdin.close();
    super.dispose();
  }
}
