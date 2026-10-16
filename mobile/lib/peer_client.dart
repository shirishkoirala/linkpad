import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'input_buffer.dart';
import 'protocol.dart';
import 'keyboard_protocol.dart';
import 'drag_protocol.dart';
import 'computer_store.dart';

String generateIdentity() {
  final pair = CryptoUtils.generateEcKeyPair();
  final privateKey = pair.privateKey as ECPrivateKey;
  final publicKey = pair.publicKey as ECPublicKey;
  final csr = X509Utils.generateEccCsrPem(
    {'CN': 'Linkpad Flutter peer'},
    privateKey,
    publicKey,
  );
  final cert = X509Utils.generateSelfSignedCertificate(privateKey, csr, 3650);
  return jsonEncode({
    'key': CryptoUtils.encodeEcPrivateKeyToPem(privateKey),
    'cert': cert,
  });
}

enum PeerState {
  disconnected,
  connecting,
  connected,
  reconnecting,
  suspended,
  failed,
}

class PeerTiming {
  const PeerTiming({
    this.connectTimeout = const Duration(seconds: 10),
    this.responseTimeout = const Duration(seconds: 2),
    this.inputMaxAge = const Duration(milliseconds: 150),
    this.frameInterval = const Duration(milliseconds: 16),
    this.heartbeat = const Duration(seconds: 15),
    this.retryBase = const Duration(seconds: 1),
    this.retryMax = const Duration(seconds: 15),
  });
  final Duration connectTimeout, responseTimeout, inputMaxAge, frameInterval;
  final Duration heartbeat, retryBase, retryMax;

  Duration retryDelay(int attempt) => Duration(
    milliseconds: (retryBase.inMilliseconds * (1 << attempt.clamp(0, 10)))
        .clamp(1, retryMax.inMilliseconds),
  );
}

class PeerClient extends ChangeNotifier {
  PeerClient({this.timing = const PeerTiming(), ComputerStore? computers})
    : _input = InputBuffer(maxAge: timing.inputMaxAge),
      computers = computers ?? ComputerStore(),
      _ownsComputers = computers == null {
    this.computers.addListener(_notify);
  }

  static const storage = FlutterSecureStorage();
  final PeerTiming timing;
  final ComputerStore computers;
  final bool _ownsComputers;
  final InputBuffer _input;
  final _commands = Queue<({String message, Duration created})>();
  final _clock = Stopwatch()..start();
  Future<SecurityContext>? _identityFuture;
  WebSocket? _socket;
  HttpClient? _http;
  StreamSubscription<dynamic>? _subscription;
  Timer? _deadline, _heartbeat, _retry, _frame, _lag;
  int _generation = 0;
  int _retryAttempt = 0;
  Uri? _address;
  String? _pin;
  void Function()? _onPaired;
  bool _desired = false, _foreground = true, _canRetry = false;
  bool _hadConnected = false, _pointer = false, _pending = false;
  bool _scroll = false, _keys = false;
  bool _keyboard = false;
  bool _drag = false, _dragging = false, _dragSent = false;
  bool _releaseDragPending = false, _dragKeepalive = false;
  Timer? _dragHeartbeat;
  bool _stalled = false, _disposed = false;
  Duration _pendingSince = Duration.zero;
  String _message = '';
  String? storageWarning;
  PeerState state = PeerState.disconnected;

  bool get connected => state == PeerState.connected;
  bool get ready => connected && _pointer && !_stalled;
  bool get canScroll => connected && _scroll && !_stalled;
  bool get canKey => connected && _keys && !_stalled;
  bool get canKeyboard => connected && _keyboard && !_stalled;
  bool get supportsKeyboard => _keyboard;
  bool get supportsDrag => _drag;
  bool get canDrag => ready && _drag;
  bool get dragging => _dragging;
  String? get activeComputerId => _pin;
  String get desktopName =>
      computers.find(_pin)?.name ?? _address?.host ?? 'Your computer';
  bool get busy =>
      state == PeerState.connecting ||
      state == PeerState.reconnecting ||
      state == PeerState.suspended;
  bool get showControls => _desired && _hadConnected;

  String get status => switch (state) {
    PeerState.disconnected => 'Disconnected',
    PeerState.connecting => 'Connecting…',
    PeerState.reconnecting => _message,
    PeerState.suspended => 'Paused while the app is inactive',
    PeerState.failed => _message,
    PeerState.connected =>
      _stalled
          ? 'Connection slow • input paused'
          : _pointer
          ? 'Connected'
          : 'Connected • desktop input unavailable',
  };

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<SecurityContext> _identity() async {
    var saved = await storage.read(key: 'peer_identity_v1');
    if (saved == null) {
      saved = generateIdentity();
      await storage.write(key: 'peer_identity_v1', value: saved);
    }
    final identity = jsonDecode(saved) as Map<String, dynamic>;
    return SecurityContext(withTrustedRoots: false)
      ..minimumTlsProtocolVersion = TlsProtocolVersion.tls1_3
      ..useCertificateChainBytes(utf8.encode(identity['cert'] as String))
      ..usePrivateKeyBytes(utf8.encode(identity['key'] as String));
  }

  Future<void> connect(
    String address,
    String fingerprint,
    String token,
    void Function() onPaired,
  ) async {
    if (_disposed) return;
    disconnect();
    try {
      _address = peerAddress(address);
      final pin = fingerprint.trim().toLowerCase();
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(pin)) {
        throw const FormatException(
          'Fingerprint must be 64 hexadecimal characters',
        );
      }
      _pin = pin;
    } on FormatException catch (error) {
      _fatal(error.message);
      return;
    }
    _desired = true;
    _canRetry = token.trim().isEmpty;
    _onPaired = onPaired;
    storageWarning = null;
    if (!_foreground) {
      if (!_canRetry) {
        _fatal('Open the app and enter a fresh pairing secret to pair.');
      } else {
        state = PeerState.suspended;
        _notify();
      }
      return;
    }
    await _attempt(token.trim());
  }

  Future<void> _attempt(String token) async {
    if (!_desired || !_foreground || _disposed) return;
    _closeTransport();
    final generation = _generation;
    state = _hadConnected || _retryAttempt > 0
        ? PeerState.reconnecting
        : PeerState.connecting;
    _message = 'Reconnecting…';
    _notify();
    late SecurityContext context;
    try {
      context = await (_identityFuture ??= _identity());
    } catch (_) {
      _identityFuture = null;
      if (generation == _generation) {
        _fatal(
          'Could not read the device identity. Unlock your phone and try again.',
        );
      }
      return;
    }
    if (generation != _generation) return;
    final address = _address!;
    final pin = _pin!;
    String? certificateFailure;
    try {
      final http = HttpClient(context: context)
        ..connectionTimeout = timing.connectTimeout
        ..badCertificateCallback = (cert, host, port) {
          final now = DateTime.now();
          if (host != address.host ||
              sha256.convert(cert.der).toString() != pin) {
            certificateFailure =
                'Desktop fingerprint changed. Verify it on your computer before reconnecting.';
            return false;
          }
          if (now.isBefore(cert.startValidity) ||
              now.isAfter(cert.endValidity)) {
            certificateFailure =
                'Desktop certificate is not valid now. Check both devices’ clocks and certificate expiry.';
            return false;
          }
          return true;
        };
      _http = http;
      final opening = WebSocket.connect(address.toString(), customClient: http);
      // A timeout does not cancel a Future; close any late socket explicitly.
      unawaited(
        opening.then<void>((socket) {
          if (generation != _generation) unawaited(socket.close());
        }, onError: (Object _) {}),
      );
      final socket = await opening.timeout(timing.connectTimeout);
      if (generation != _generation) {
        unawaited(socket.close());
        return;
      }
      _socket = socket;
      socket.pingInterval = timing.heartbeat;
      _deadline = Timer(timing.connectTimeout, () {
        if (generation == _generation) {
          _networkFailure('Desktop handshake timed out.');
        }
      });
      _subscription = socket.listen(
        (data) {
          if (generation == _generation) _receive(data, generation);
        },
        onError: (Object _) {
          if (generation == _generation) _networkFailure('Connection lost.');
        },
        onDone: () {
          if (generation == _generation) {
            _networkFailure('Desktop disconnected.');
          }
        },
      );
      socket.add(hello(token));
    } catch (error) {
      if (generation != _generation) return;
      if (certificateFailure != null || error is HandshakeException) {
        _fatal(
          certificateFailure ??
              'Secure connection failed. Verify the desktop fingerprint and certificate.',
        );
      } else {
        _networkFailure(
          'Cannot reach your computer. Check its server and Wi-Fi connection.',
        );
      }
    }
  }

  void _receive(dynamic data, int generation) {
    try {
      final message = parseMessage(data);
      if (message['type'] == 'error') {
        final reason = message['error'];
        _fatal(switch (reason) {
          'pairing rejected' =>
            'Pairing secret expired, was already used, or is incorrect. Start a new pairing window on your computer.',
          'unpaired device' =>
            'This device is not paired. Start pairing on your computer and enter its new secret.',
          'capability not negotiated' =>
            'Input was not enabled for this connection. Enable input on the desktop server and reconnect.',
          _ =>
            'Desktop rejected the request. Check the desktop server and reconnect.',
        });
      } else if (message['type'] == 'ready' && !connected) {
        final capabilities = readyCapabilities(message);
        _deadline?.cancel();
        _pointer = capabilities.contains(pointerCapability);
        _scroll = capabilities.contains(scrollCapability);
        _keys = capabilities.contains(keyCapability);
        _keyboard = capabilities.contains(keyboardCapability);
        _drag = capabilities.contains(dragCapability);
        _hadConnected = true;
        _canRetry = true;
        _retryAttempt = 0;
        state = PeerState.connected;
        final onPaired = _onPaired;
        _onPaired = null;
        onPaired?.call();
        if (generation != _generation) return;
        unawaited(_saveDesktop(generation));
        _heartbeat = Timer.periodic(timing.heartbeat, (_) {
          if (generation == _generation && !_pending) _send(hello(''));
        });
        _notify();
      } else if (message['type'] == 'ack' && connected && _pending) {
        _deadline?.cancel();
        _lag?.cancel();
        if (_clock.elapsed - _pendingSince >= timing.inputMaxAge) {
          _input.clear();
        }
        _pending = false;
        final wasStalled = _stalled;
        _stalled = false;
        if (wasStalled) _notify();
        _scheduleInput();
      } else {
        _fatal(
          'Unexpected desktop response. Update both apps before reconnecting.',
        );
      }
    } catch (_) {
      _fatal('Invalid desktop response. Update both apps before reconnecting.');
    }
  }

  Future<void> _saveDesktop(int generation) async {
    final address = _address.toString();
    final pin = _pin!;
    try {
      final saved = await computers.saveVerified(address, pin);
      if (!saved) throw StateError('Could not save computer');
    } catch (_) {
      if (generation == _generation) {
        storageWarning =
            'Connected, but the desktop could not be saved for next time.';
        _notify();
      }
    }
  }

  void move(double dx, double dy) {
    if (!ready) return;
    _input.move(dx, dy, _clock.elapsed);
    _scheduleInput();
  }

  void click(String button) {
    if (!ready || _dragging || _dragSent) return;
    _input.click(button, _clock.elapsed);
    _scheduleInput();
  }

  void scroll(double dx, double dy) {
    if (!canScroll || _dragging || _dragSent) return;
    _input.scroll(dx, dy, _clock.elapsed);
    _scheduleInput();
  }

  void pressKey(String key) {
    if (!canKey) return;
    _queueCommand(keyMessage(key));
  }

  bool startDrag() {
    if (!canDrag || _dragging || _releaseDragPending) return false;
    _dragging = true;
    _input.clear();
    _dragHeartbeat = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!_dragging) return;
      _dragKeepalive = true;
      _scheduleInput();
    });
    _scheduleInput();
    _notify();
    return true;
  }

  void cancelDrag() => endDrag(cancelled: true);

  void endDrag({bool cancelled = false}) {
    if (!_dragging) return;
    _dragging = false;
    _dragHeartbeat?.cancel();
    _dragHeartbeat = null;
    _dragKeepalive = false;
    _releaseDragPending = _dragSent;
    if (!_dragSent) {
      _input.clear();
      // A tap released before the next frame is still a normal left click.
      if (ready && !cancelled) _input.click('left', _clock.elapsed);
    }
    _scheduleInput();
    _notify();
  }

  bool typeText(String text) {
    if (!canKeyboard) return false;
    return _queueCommand(keyboardMessage(text: text));
  }

  bool keyboardKey(String key, {Set<String> modifiers = const {}}) {
    if (!canKeyboard) return false;
    return _queueCommand(keyboardMessage(key: key, modifiers: modifiers));
  }

  bool _queueCommand(String message) {
    _expireCommands();
    if (_commands.length >= 32) return false;
    _commands.add((message: message, created: _clock.elapsed));
    _scheduleInput();
    return true;
  }

  void _expireCommands() {
    while (_commands.isNotEmpty &&
        _clock.elapsed - _commands.first.created >= timing.inputMaxAge) {
      _commands.removeFirst();
    }
  }

  bool get _hasDragWork =>
      _releaseDragPending || (_dragging && (!_dragSent || _dragKeepalive));

  void _scheduleInput() {
    _expireCommands();
    if (!connected ||
        _stalled ||
        _pending ||
        _frame != null ||
        (!_hasDragWork &&
            _commands.isEmpty &&
            (!ready || !_input.hasReady(_clock.elapsed)))) {
      return;
    }
    _frame = Timer(timing.frameInterval, () {
      _frame = null;
      if (!connected || _stalled || _pending) return;
      _expireCommands();
      if (_releaseDragPending) {
        // Flush the last fresh movement before releasing, never replay stale input.
        final input = _input.take(_clock.elapsed);
        if (input != null && input.button == null && !input.isScroll) {
          _send(dragMessage('move', input.dx, input.dy));
        } else {
          _releaseDragPending = false;
          _dragSent = false;
          _input.clear();
          _send(dragMessage('end'));
        }
        return;
      }
      if (_dragging && !_dragSent) {
        _dragSent = true;
        _dragKeepalive = false;
        _send(dragMessage('start'));
        return;
      }
      if (_commands.isNotEmpty) {
        _send(_commands.removeFirst().message);
        return;
      }
      if (!ready) return;
      final input = _input.take(_clock.elapsed);
      if (input != null) {
        if (_dragging && _dragSent) {
          _dragKeepalive = false;
          _send(dragMessage('move', input.dx, input.dy));
        } else {
          _send(
            input.isScroll
                ? scrollMessage(input.dx, input.dy)
                : pointer(input.dx, input.dy, input.button),
          );
        }
      } else if (_dragging && _dragKeepalive) {
        _dragKeepalive = false;
        _send(dragMessage('hold'));
      }
    });
  }

  void _send(String message) {
    if (!connected || _pending || _socket == null) return;
    final generation = _generation;
    _pending = true;
    _pendingSince = _clock.elapsed;
    _deadline?.cancel();
    _lag?.cancel();
    try {
      _socket!.add(message);
    } catch (_) {
      _networkFailure('Connection lost.');
      return;
    }
    _lag = Timer(timing.inputMaxAge, () {
      if (generation != _generation || !_pending) return;
      _input.clear();
      _stalled = true;
      cancelDrag();
      _notify();
    });
    _deadline = Timer(timing.responseTimeout, () {
      if (generation == _generation) {
        _networkFailure('Desktop stopped responding.');
      }
    });
  }

  void _networkFailure(String reason) {
    _closeTransport();
    if (_desired && _foreground && _canRetry) {
      final delay = timing.retryDelay(_retryAttempt++);
      state = PeerState.reconnecting;
      _message = '$reason Reconnecting in ${delay.inSeconds.clamp(1, 15)}s…';
      final generation = _generation;
      _retry = Timer(delay, () {
        if (generation == _generation) unawaited(_attempt(''));
      });
      _notify();
    } else {
      _fatal(
        '$reason Reconnect without a secret if pairing completed, or start a new pairing window.',
      );
    }
  }

  void _fatal(String message) {
    _desired = false;
    _onPaired = null;
    _closeTransport();
    state = PeerState.failed;
    _message = message;
    _notify();
  }

  void setForeground(bool active) {
    if (_foreground == active || _disposed) return;
    _foreground = active;
    if (!_desired) return;
    if (!active) {
      _closeTransport();
      if (!_canRetry) {
        _fatal(
          'Pairing interrupted. Reconnect without a secret if pairing completed, or start a new pairing window.',
        );
      } else {
        state = PeerState.suspended;
        _notify();
      }
    } else {
      _retryAttempt = 0;
      unawaited(_attempt(''));
    }
  }

  void _closeTransport() {
    _generation++;
    for (final timer in [_deadline, _heartbeat, _retry, _frame, _lag]) {
      timer?.cancel();
    }
    _deadline = _heartbeat = _retry = _frame = _lag = null;
    unawaited(_subscription?.cancel());
    _subscription = null;
    unawaited(_socket?.close());
    _http?.close(force: true);
    _socket = null;
    _http = null;
    _pending = _stalled = _pointer = false;
    _scroll = _keys = false;
    _keyboard = false;
    _dragHeartbeat?.cancel();
    _dragHeartbeat = null;
    _drag = _dragging = _dragSent = _releaseDragPending = _dragKeepalive =
        false;
    _commands.clear();
    _input.clear();
  }

  void disconnect() {
    _desired = false;
    _hadConnected = false;
    _canRetry = false;
    _retryAttempt = 0;
    _onPaired = null;
    _closeTransport();
    state = PeerState.disconnected;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    computers.removeListener(_notify);
    if (_ownsComputers) computers.dispose();
    disconnect();
    super.dispose();
  }
}
