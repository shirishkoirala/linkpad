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
import 'server_discovery.dart';

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
    this.responseTimeout = const Duration(seconds: 5),
    this.inputMaxAge = const Duration(milliseconds: 150),
    this.inputPauseAfter = const Duration(milliseconds: 500),
    this.maxMotionInFlight = 4,
    this.frameInterval = const Duration(milliseconds: 16),
    this.heartbeat = const Duration(seconds: 15),
    this.retryBase = const Duration(seconds: 1),
    this.retryMax = const Duration(seconds: 15),
  });
  final Duration connectTimeout, responseTimeout, inputMaxAge, frameInterval;
  final Duration inputPauseAfter;
  final int maxMotionInFlight;
  final Duration heartbeat, retryBase, retryMax;

  Duration retryDelay(int attempt) => Duration(
    milliseconds: (retryBase.inMilliseconds * (1 << attempt.clamp(0, 10)))
        .clamp(1, retryMax.inMilliseconds),
  );
}

class PeerClient extends ChangeNotifier {
  PeerClient({
    this.timing = const PeerTiming(),
    ComputerStore? computers,
    ServerDiscovery? discovery,
  }) : _discovery =
           discovery ??
           (Platform.isIOS || Platform.isAndroid
               ? BonjourServerDiscovery()
               : NoServerDiscovery()),
       _input = InputBuffer(maxAge: timing.inputMaxAge),
       computers = computers ?? ComputerStore(),
       _ownsComputers = computers == null {
    this.computers.addListener(_computersChanged);
  }

  static const storage = FlutterSecureStorage();
  final ServerDiscovery _discovery;
  Future<List<DiscoveredServer>>? _discoveryResult;
  final _recoveryAddresses = Queue<Uri>();
  Uri? _verifiedAddress;
  bool _knownPaired = false, _usingDiscoveryCandidate = false;
  bool findingComputer = false;
  String? discoveryWarning, _savedCertificateFailure;
  final PeerTiming timing;
  final ComputerStore computers;
  final bool _ownsComputers;
  final InputBuffer _input;
  final _commands = Queue<({String message, Duration? expiresAt})>();
  static const _commandCapacity = 64;
  bool get inputQueueFull => _commands.length >= _commandCapacity;
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
  bool _hadConnected = false, _pointer = false;
  final _outstanding = Queue<({Duration sent, bool motion})>();
  bool get _pending => _outstanding.isNotEmpty;
  bool _scroll = false, _keys = false;
  bool _keyboard = false;
  bool _volume = false;
  bool _standaloneSuper = false;
  bool _drag = false, _dragging = false, _dragSent = false;
  bool _releaseDragPending = false, _dragKeepalive = false;
  Timer? _dragHeartbeat;
  bool _stalled = false, _disposed = false;
  Duration? _lastSentAt, _roundTripTime, _latencyNotifiedAt;
  Duration? _peakRoundTripTime, _serverProcessingTime, _remainingResponseDelay;
  int _responseCount = 0, _slowResponseCount = 0, _inputPauseCount = 0;
  String _message = '';
  String? _lastConnectionIssue;
  int _reconnectCount = 0;
  String? storageWarning;
  PeerState state = PeerState.disconnected;

  bool get connected => state == PeerState.connected;
  bool get waitingForResponse => connected && _stalled;

  /// Smoothed acknowledgement round trip, including desktop processing time.
  Duration? get roundTripTime => _roundTripTime;
  Duration? get serverProcessingTime => _serverProcessingTime;
  Duration? get remainingResponseDelay => _remainingResponseDelay;
  String get connectionSummary =>
      connected && !_stalled && _roundTripTime != null
      ? '$status · ${_roundTripTime!.inMilliseconds} ms'
      : status;
  String? get lastConnectionIssue => _lastConnectionIssue;
  int get reconnectCount => _reconnectCount;
  String get connectionDetails => [
    connectionSummary,
    if (discoveryWarning != null) 'Discovery: $discoveryWarning',
    'Response time includes the network round trip and desktop processing.',
    if (_peakRoundTripTime != null)
      'Peak response: ${_peakRoundTripTime!.inMilliseconds} ms',
    'Slow replies (≥250 ms): $_slowResponseCount / $_responseCount',
    'Input pauses on this connection: $_inputPauseCount',
    if (_serverProcessingTime != null) ...[
      'Desktop input processing: ${(_serverProcessingTime!.inMicroseconds / 1000).toStringAsFixed(1)} ms (smoothed)',
      'Other response delay: ${(_remainingResponseDelay!.inMicroseconds / 1000).toStringAsFixed(1)} ms (smoothed; network + queues)',
    ] else
      'Desktop timing unavailable. Update the desktop server for processing diagnostics.',
    'Outstanding replies: ${_outstanding.length}',
    'Reconnect attempts this session: $_reconnectCount',
    if (_lastConnectionIssue != null)
      'Last interruption: $_lastConnectionIssue',
  ].join('\n');
  bool get ready => connected && _pointer && !_stalled;
  bool get canScroll => connected && _scroll && !_stalled;
  bool get canKey => connected && _keys && !_stalled && !inputQueueFull;
  bool get canKeyboard =>
      connected && _keyboard && !_stalled && !inputQueueFull;
  bool get supportsKeyboard => _keyboard;
  bool get supportsVolume => _volume;
  bool get canVolume => connected && _volume && !_stalled && !inputQueueFull;
  bool get supportsStandaloneSuper => _standaloneSuper;
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

  /// Requests only that the desktop display its QR; never enrolls this phone.
  Future<bool> requestPairingDisplay(DiscoveredServer server) async {
    HttpClient? client;
    try {
      final context = await (_identityFuture ??= _identity()).timeout(
        const Duration(seconds: 4),
      );
      final address = server.address;
      if (address.scheme != 'wss' || address.userInfo.isNotEmpty) return false;
      client = HttpClient(context: context)
        ..connectionTimeout = const Duration(seconds: 3)
        ..badCertificateCallback = (cert, host, port) {
          final now = DateTime.now();
          return host == address.host &&
              sha256.convert(cert.der).toString() == server.fingerprint &&
              !now.isBefore(cert.startValidity) &&
              !now.isAfter(cert.endValidity);
        };
      final http = client;
      Future<bool> send() async {
        final request = await http.postUrl(
          address.replace(
            scheme: 'https',
            path: '/pairing/request',
            query: null,
            fragment: null,
          ),
        );
        request.followRedirects = false;
        request.contentLength = 0;
        final response = await request.close();
        return response.statusCode == HttpStatus.accepted ||
            response.statusCode == HttpStatus.tooManyRequests;
      }

      return await send().timeout(const Duration(seconds: 3));
    } catch (_) {
      return false;
    } finally {
      client?.close(force: true);
    }
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
    final selectionGeneration = _generation;
    try {
      _address = peerAddress(address);
      _verifiedAddress = _address;
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
    _knownPaired = token.trim().isEmpty && computers.find(_pin) != null;
    if (!_foreground) {
      if (!_canRetry) {
        _fatal('Open the app and enter a fresh pairing secret to pair.');
      } else {
        state = PeerState.suspended;
        _notify();
      }
      return;
    }
    await computers.load();
    if (selectionGeneration != _generation || !_desired) return;
    _knownPaired = token.trim().isEmpty && computers.find(_pin) != null;
    await _attempt(token.trim());
  }

  Future<void> _attempt(String token) async {
    if (!_desired || !_foreground || _disposed) return;
    _closeTransport();
    final generation = _generation;
    _usingDiscoveryCandidate = _recoveryAddresses.isNotEmpty;
    _address = _usingDiscoveryCandidate
        ? _recoveryAddresses.removeFirst()
        : _verifiedAddress;
    if (!_usingDiscoveryCandidate) _beginDiscovery();
    if (const bool.fromEnvironment('LINKPAD_DIAGNOSTICS')) {
      debugPrint(
        'LP CONNECT address=$_address paired=$_knownPaired candidate=$_usingDiscoveryCandidate',
      );
      if (_retryAttempt == 0) {
        unawaited(
          NetworkInterface.list(type: InternetAddressType.IPv4)
              .then((items) {
                debugPrint(
                  'LP NETWORK ${items.map((i) => '${i.name}:${i.addresses.map((a) => a.address).join(',')}').join(' ')}',
                );
              })
              .catchError((Object _) {}),
        );
      }
    }

    state = _hadConnected || _retryAttempt > 0
        ? PeerState.reconnecting
        : PeerState.connecting;
    _message = _lastConnectionIssue == null
        ? 'Reconnecting…'
        : '$_lastConnectionIssue Reconnecting…';
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
        ..connectionTimeout =
            _usingDiscoveryCandidate &&
                timing.connectTimeout > const Duration(seconds: 3)
            ? const Duration(seconds: 3)
            : timing.connectTimeout
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
      if (const bool.fromEnvironment('LINKPAD_DIAGNOSTICS')) {
        debugPrint('LP CONNECT FAILED $error certificate=$certificateFailure');
      }
      if (generation != _generation) return;
      if (certificateFailure != null || error is HandshakeException) {
        final reason =
            certificateFailure ??
            'Secure connection failed. Verify the desktop fingerprint and certificate.';
        if (_knownPaired && _canRetry) {
          if (!_usingDiscoveryCandidate) _savedCertificateFailure = reason;
          _networkFailure(reason);
        } else {
          _fatal(reason);
        }
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
        _volume = capabilities.contains(volumeCapability);
        _standaloneSuper = capabilities.contains(superKeyCapability);
        _drag = capabilities.contains(dragCapability);
        _hadConnected = true;
        _canRetry = true;
        _retryAttempt = 0;
        _verifiedAddress = _address;
        _savedCertificateFailure = null;
        _cancelDiscovery();
        discoveryWarning = null;
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
        final now = _clock.elapsed;
        final sample = now - _outstanding.removeFirst().sent;
        _recordResponse(sample, message['server_processing_us']);
        final previous = _roundTripTime;
        _roundTripTime = previous == null
            ? sample
            : Duration(
                microseconds:
                    (previous.inMicroseconds * 3 + sample.inMicroseconds) ~/ 4,
              );
        // A slow reply does not make newer queued input stale. The buffer
        // expires each motion by its own age; a real stall discards pointer work.
        if (_stalled) {
          _input.clear();
        }
        final wasStalled = _stalled;
        // Drain every outstanding reply before resuming after a stall.
        _stalled = wasStalled && _pending;
        _armResponseTimers();
        // Keep high-rate acknowledgements off the widget rebuild path.
        if (wasStalled ||
            _latencyNotifiedAt == null ||
            now - _latencyNotifiedAt! >= const Duration(seconds: 1)) {
          _latencyNotifiedAt = now;
          _notify();
        }
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

  void _recordResponse(Duration sample, dynamic processingUS) {
    _responseCount++;
    if (sample >= const Duration(milliseconds: 250)) _slowResponseCount++;
    if (_peakRoundTripTime == null || sample > _peakRoundTripTime!) {
      _peakRoundTripTime = sample;
    }
    // Optional metadata must never disrupt input. Subtract only timings from
    // the same acknowledgement; the remainder also includes queueing delays.
    if (processingUS is! int ||
        processingUS < 0 ||
        processingUS > sample.inMicroseconds) {
      return;
    }
    Duration smooth(Duration? previous, int value) => Duration(
      microseconds: previous == null
          ? value
          : (previous.inMicroseconds * 3 + value) ~/ 4,
    );
    _serverProcessingTime = smooth(_serverProcessingTime, processingUS);
    _remainingResponseDelay = smooth(
      _remainingResponseDelay,
      sample.inMicroseconds - processingUS,
    );
  }

  Future<void> _saveDesktop(int generation) async {
    final address = _address.toString();
    final pin = _pin!;
    try {
      final saved = await computers.saveVerified(
        address,
        pin,
        stillCurrent: () =>
            generation == _generation && _desired && _pin == pin,
      );
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

  bool volume(String action, {bool repeat = false}) {
    if (!canVolume) return false;
    // A held button samples current intent; never build an audio burst behind
    // a slow ACK or earlier keyboard work. Ordinary taps stay ordered/reliable.
    if (repeat && (_pending || _commands.isNotEmpty)) return false;
    return _queueCommand(volumeMessage(action));
  }

  bool keyboardKey(String key, {Set<String> modifiers = const {}}) {
    if (!canKeyboard || (key == 'super' && !_standaloneSuper)) return false;
    return _queueCommand(keyboardMessage(key: key, modifiers: modifiers));
  }

  bool _queueCommand(String message) {
    _expireCommands();
    if (inputQueueFull) return false;
    // Seal earlier pointer work into the command stream. A focus-changing
    // click must reach the desktop before text entered after that click.
    final now = _clock.elapsed;
    PointerInput? input;
    // Held movement must stay on the drag path, including its release barrier.
    while (!_dragging && !_dragSent && (input = _input.take(now)) != null) {
      final event = input!;
      _commands.add((
        message: event.isScroll
            ? scrollMessage(event.dx, event.dy)
            : pointer(event.dx, event.dy, event.button),
        // Motion remains disposable; a click is a reliable ordering barrier.
        expiresAt: event.button == null
            ? event.created + timing.inputMaxAge
            : null,
      ));
    }
    _commands.add((message: message, expiresAt: null));
    if (inputQueueFull) _notify();
    _scheduleInput();
    return true;
  }

  void _expireCommands() {
    final wasFull = inputQueueFull;
    _commands.removeWhere(
      (event) => event.expiresAt != null && _clock.elapsed >= event.expiresAt!,
    );
    if (wasFull && !inputQueueFull) _notify();
  }

  bool get _hasDragWork =>
      _releaseDragPending || (_dragging && (!_dragSent || _dragKeepalive));

  // Only plain movement may pass an outstanding movement. Every other action
  // waits for the window to drain, retaining the existing input barriers.
  bool get _canPipelineMotion =>
      !_dragging &&
      !_dragSent &&
      !_hasDragWork &&
      _commands.isEmpty &&
      _outstanding.length < timing.maxMotionInFlight &&
      _outstanding.every((entry) => entry.motion) &&
      _input.hasMotionReady(_clock.elapsed);

  void _scheduleInput() {
    _expireCommands();
    if (!connected ||
        _stalled ||
        (_pending && !_canPipelineMotion) ||
        _frame != null ||
        (!_hasDragWork &&
            _commands.isEmpty &&
            (!ready || !_input.hasReady(_clock.elapsed)))) {
      return;
    }
    // Pace from the last transmission, not from its acknowledgement. Once a
    // slow round trip has already used the interval, fresh input can go now.
    final remaining = _lastSentAt == null
        ? Duration.zero
        : timing.frameInterval - (_clock.elapsed - _lastSentAt!);
    _frame = Timer(remaining.isNegative ? Duration.zero : remaining, () {
      _frame = null;
      if (!connected || _stalled || (_pending && !_canPipelineMotion)) return;
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
        final wasFull = inputQueueFull;
        _send(_commands.removeFirst().message);
        if (wasFull && !inputQueueFull) _notify();
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
            motion: !input.isScroll && input.button == null,
          );
        }
      } else if (_dragging && _dragKeepalive) {
        _dragKeepalive = false;
        _send(dragMessage('hold'));
      }
    });
  }

  void _send(String message, {bool motion = false}) {
    if (!connected ||
        _socket == null ||
        (_pending &&
            (!motion ||
                _outstanding.length >= timing.maxMotionInFlight ||
                !_outstanding.every((entry) => entry.motion)))) {
      return;
    }
    final sent = _clock.elapsed;
    _outstanding.add((sent: sent, motion: motion));
    _lastSentAt = sent;
    try {
      _socket!.add(message);
    } catch (_) {
      _networkFailure('Connection lost.');
      return;
    }
    _armResponseTimers();
    _scheduleInput();
  }

  Duration get _pauseBudget {
    final measured = (_roundTripTime?.inMicroseconds ?? 0) * 3;
    final ceiling = timing.inputPauseAfter > const Duration(seconds: 1)
        ? timing.inputPauseAfter.inMicroseconds
        : const Duration(seconds: 1).inMicroseconds;
    return Duration(
      microseconds: measured.clamp(
        timing.inputPauseAfter.inMicroseconds,
        ceiling,
      ),
    );
  }

  void _armResponseTimers() {
    _deadline?.cancel();
    _lag?.cancel();
    if (!_pending) return;
    final generation = _generation;
    final age = _clock.elapsed - _outstanding.first.sent;
    Duration remaining(Duration limit) =>
        age >= limit ? Duration.zero : limit - age;
    _lag = Timer(remaining(_pauseBudget), () {
      if (generation != _generation || !_pending) return;
      _input.clear();
      if (!_stalled) _inputPauseCount++;
      _stalled = true;
      cancelDrag();
      _notify();
    });
    _deadline = Timer(remaining(timing.responseTimeout), () {
      if (generation == _generation) {
        _networkFailure('Desktop stopped responding.');
      }
    });
  }

  void _computersChanged() {
    if (_desired &&
        _knownPaired &&
        computers.loaded &&
        computers.find(_pin) == null) {
      disconnect();
      return;
    }
    if (_desired && _canRetry && computers.find(_pin) != null) {
      _knownPaired = true;
    }
    _notify();
  }

  void _beginDiscovery() {
    if (!_knownPaired ||
        !_canRetry ||
        _pin == null ||
        _discoveryResult != null) {
      return;
    }
    final pin = _pin!;
    _discoveryResult = _discovery
        .find(pin, timeout: const Duration(seconds: 3))
        .then((found) {
          if (const bool.fromEnvironment('LINKPAD_DIAGNOSTICS')) {
            debugPrint(
              'LP DISCOVERED ${found.map((f) => f.address).join(',')}',
            );
          }
          return found;
        })
        .catchError((Object error) {
          if (const bool.fromEnvironment('LINKPAD_DIAGNOSTICS')) {
            debugPrint('LP DISCOVERY ERROR $error');
          }
          if (_desired && _pin == pin) {
            discoveryWarning =
                'Local discovery unavailable. Check Local Network permission or scan a new QR code.';
          }
          return <DiscoveredServer>[];
        });
  }

  void _cancelDiscovery() {
    _discoveryResult = null;
    _recoveryAddresses.clear();
    findingComputer = false;
    unawaited(_discovery.stop().catchError((Object _) {}));
  }

  void _networkFailure(String reason) {
    _lastConnectionIssue = reason;
    _closeTransport();
    if (_desired && _foreground && _canRetry) {
      _reconnectCount++;
      state = PeerState.reconnecting;
      _message = reason;
      final generation = _generation;
      _notify();
      unawaited(_recoverAndRetry(reason, generation));
    } else {
      _fatal(
        '$reason Reconnect without a secret if pairing completed, or start a new pairing window.',
      );
    }
  }

  Future<void> _recoverAndRetry(String reason, int generation) async {
    final search = _discoveryResult;
    if (_recoveryAddresses.isEmpty && search != null) {
      findingComputer = true;
      _notify();
      final found = await search;
      if (generation != _generation || !_desired || !_foreground) return;
      if (identical(_discoveryResult, search)) _discoveryResult = null;
      for (final candidate in found) {
        if (_recoveryAddresses.length >= 4) break;
        if (candidate.fingerprint != _pin ||
            candidate.address == _address ||
            _recoveryAddresses.contains(candidate.address)) {
          continue;
        }
        try {
          _recoveryAddresses.add(peerAddress(candidate.address.toString()));
        } on FormatException {
          continue;
        }
      }
    }
    if (generation != _generation || !_desired || !_foreground) return;
    findingComputer = false;
    if (_recoveryAddresses.isEmpty && _savedCertificateFailure != null) {
      _fatal(_savedCertificateFailure!);
      return;
    }
    final delay = _recoveryAddresses.isNotEmpty
        ? Duration.zero
        : timing.retryDelay(_retryAttempt++);
    _message = '$reason Reconnecting in ${delay.inSeconds.clamp(1, 15)}s…';
    _retry = Timer(delay, () {
      if (generation == _generation) unawaited(_attempt(''));
    });
    _notify();
  }

  void _fatal(String message) {
    _cancelDiscovery();
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
      _cancelDiscovery();
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
    _outstanding.clear();
    _stalled = _pointer = false;
    _lastSentAt = _roundTripTime = _latencyNotifiedAt = null;
    _peakRoundTripTime = _serverProcessingTime = _remainingResponseDelay = null;
    _responseCount = _slowResponseCount = _inputPauseCount = 0;
    _scroll = _keys = false;
    _keyboard = false;
    _volume = false;
    _standaloneSuper = false;
    _dragHeartbeat?.cancel();
    _dragHeartbeat = null;
    _drag = _dragging = _dragSent = _releaseDragPending = _dragKeepalive =
        false;
    _commands.clear();
    _input.clear();
  }

  void disconnect() {
    _cancelDiscovery();
    _knownPaired = false;
    _savedCertificateFailure = null;
    _lastConnectionIssue = null;
    _reconnectCount = 0;
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
    computers.removeListener(_computersChanged);
    if (_ownsComputers) computers.dispose();
    disconnect();
    super.dispose();
  }
}
