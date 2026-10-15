import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'pairing_invitation.dart';

class PairingScanner extends StatefulWidget {
  const PairingScanner({super.key});
  @override
  State<PairingScanner> createState() => _PairingScannerState();
}

class _PairingScannerState extends State<PairingScanner> {
  bool _accepted = false;
  String? _error;

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
                onDetect: _detect,
                // Without an external controller the scanner owns camera lifecycle and
                // releases it when this route closes or the app leaves the foreground.
                errorBuilder: (context, error) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.no_photography_outlined, size: 40),
                        const SizedBox(height: 16),
                        const Text(
                          'Camera unavailable. Allow camera access for Linkpad in your phone settings, or enter the pairing details manually.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Enter manually'),
                        ),
                      ],
                    ),
                  ),
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
