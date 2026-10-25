import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'pairing_invitation.dart';
import 'phone_permissions.dart';

enum PairingScannerAction { enterManually }

class PairingScanner extends StatefulWidget {
  const PairingScanner({super.key});
  @override
  State<PairingScanner> createState() => _PairingScannerState();
}

class _PairingScannerState extends State<PairingScanner>
    with WidgetsBindingObserver {
  bool _accepted = false;
  String? _error;
  int _cameraAttempt = 0;
  bool _waitingForSettings = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _waitingForSettings && mounted) {
      _waitingForSettings = false;
      setState(() => _cameraAttempt++);
    }
  }

  Future<void> _settings() async {
    _waitingForSettings = true;
    final opened = await openPhoneSettings();
    if (!opened && mounted) {
      _waitingForSettings = false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Open your phone settings and select Linkpad to change Camera access.',
          ),
        ),
      );
    }
  }

  void _detect(BarcodeCapture capture) {
    if (_accepted || !mounted) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (barcode.format != BarcodeFormat.qrCode || raw == null) continue;
      try {
        final invitation = PairingInvitation.parse(raw);
        _accepted = true;
        Navigator.of(context).pop(invitation);
        return;
      } on FormatException catch (error) {
        if (_error != error.message) setState(() => _error = error.message);
      } catch (_) {
        const message =
            'This pairing code could not be read. Generate a new code on your computer.';
        if (_error != message) setState(() => _error = message);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Scan pairing code')),
    body: SafeArea(
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text(
              'Scan the QR code shown on your computer. Linkpad will connect automatically.',
            ),
          ),
          Expanded(
            child: ClipRect(
              child: MobileScanner(
                key: ValueKey(_cameraAttempt),
                onDetect: _detect,
                // Without an external controller the scanner owns camera lifecycle and
                // releases it when this route closes or the app leaves the foreground.
                errorBuilder: (context, error) => ScannerRecovery(
                  denied:
                      error.errorCode ==
                      MobileScannerErrorCode.permissionDenied,
                  unsupported:
                      error.errorCode == MobileScannerErrorCode.unsupported,
                  onSettings: _settings,
                  onRetry: () => setState(() {
                    _error = null;
                    _cameraAttempt++;
                  }),
                  onManual: () => Navigator.of(
                    context,
                  ).pop(PairingScannerAction.enterManually),
                ),
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    ),
  );
}

class ScannerRecovery extends StatelessWidget {
  const ScannerRecovery({
    super.key,
    required this.denied,
    required this.unsupported,
    required this.onSettings,
    required this.onRetry,
    required this.onManual,
  });
  final bool denied, unsupported;
  final VoidCallback onSettings, onRetry, onManual;
  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.no_photography_outlined, size: 40),
          const SizedBox(height: 16),
          Text(
            denied
                ? 'Camera access is off. Allow Camera for Linkpad in your phone settings to scan this code.'
                : unsupported
                ? 'This device does not have a supported camera. Enter the pairing details manually.'
                : 'The camera could not start. Try again, or enter the pairing details manually.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          if (denied)
            FilledButton(
              onPressed: onSettings,
              child: const Text('Open Settings'),
            ),
          if (!unsupported)
            TextButton(onPressed: onRetry, child: const Text('Try again')),
          OutlinedButton(
            onPressed: onManual,
            child: const Text('Enter manually'),
          ),
        ],
      ),
    ),
  );
}
