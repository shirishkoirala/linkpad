import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'input_buffer.dart';
import 'protocol.dart';

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
  PeerClient({this.timing = const PeerTiming()})
    : _input = InputBuffer(maxAge: timing.inputMaxAge);

  static const storage = FlutterSecureStorage();
  final PeerTiming timing;
  final InputBuffer _input;
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
  bool _stalled = false, _disposed = false;
  Duration _pendingSince = Duration.zero;
  String _message = '';
  String? storageWarning;
  PeerState state = PeerState.disconnected;

  bool get connected => state == PeerState.connected;
  bool get ready => connected && _pointer && !_stalled;
  bool get canScroll => connected && _scroll && !_stalled;
  bool get canKey => connected && _keys && !_stalled;
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
          : 'Connected • enable Accessibility on your Mac, then restart its server',
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
                'Desktop fingerprint changed. Verify it on your Mac before reconnecting.';
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
          'Cannot reach your Mac. Check its server and Wi-Fi connection.',
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
            'Pairing secret expired, was already used, or is incorrect. Start a new pairing window on your Mac.',
          'unpaired device' =>
            'This device is not paired. Start pairing on your Mac and enter its new secret.',
          'capability not negotiated' =>
            'Pointer permission is unavailable. Enable Accessibility on your Mac and restart its server.',
          _ =>
            'Desktop rejected the request. Check the Mac server and reconnect.',
        });
      } else if (message['type'] == 'ready' && !connected) {
        final capabilities = readyCapabilities(message);
        _deadline?.cancel();
        _pointer = capabilities.contains(pointerCapability);
        _scroll = capabilities.contains(scrollCapability);
        _keys = capabilities.contains(keyCapability);
        _hadConnected = true;
        _canRetry = true;
        _retryAttempt = 0;
        state = PeerState.connected;
        final onPaired = _onPaired;
        _onPaired = null;
        onPaired?.call();
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
    try {
      await storage.write(
        key: 'desktop_v1',
        value: jsonEncode({'address': _address.toString(), 'pin': _pin}),
      );
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
    if (!ready) return;
    _input.click(button, _clock.elapsed);
    _scheduleInput();
  }

  void scroll(double dx, double dy) {
    if (!canScroll) return;
    _input.scroll(dx, dy, _clock.elapsed);
    _scheduleInput();
  }

  void pressKey(String key) {
    if (!canKey) return;
    // ponytail: keys bypass the motion buffer; one ack-gated send like heartbeat.
    _send(keyMessage(key));
  }

  void _scheduleInput() {
    if (!ready ||
        _pending ||
        _frame != null ||
        !_input.hasReady(_clock.elapsed)) {
      return;
    }
    _frame = Timer(timing.frameInterval, () {
      _frame = null;
      if (!ready || _pending) return;
      final input = _input.take(_clock.elapsed);
      if (input != null) {
        _send(input.isScroll ? scrollMessage(input.dx, input.dy)
          : pointer(input.dx, input.dy, input.button));
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
    disconnect();
    super.dispose();
  }
}
