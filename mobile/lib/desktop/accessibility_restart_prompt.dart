import 'package:flutter/material.dart';
import 'desktop_platform.dart';

class AccessibilityRestartPrompt extends StatelessWidget {
  const AccessibilityRestartPrompt({
    super.key,
    required this.platform,
    this.busy = false,
  });
  final DesktopPlatform platform;
  final bool busy;
  @override
  Widget build(BuildContext context) {
    if (!platform.isMacOS || !platform.restartRecommended) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Already enabled Accessibility? macOS may need Linkpad to restart before the change takes effect. Your pairings will be kept; connected phones will reconnect.',
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: busy || platform.restartBusy
                ? null
                : platform.restartApp,
            icon: const Icon(Icons.restart_alt),
            label: Text(
              platform.restartBusy ? 'Restarting…' : 'Restart Linkpad',
            ),
          ),
        ],
      ),
    );
  }
}
