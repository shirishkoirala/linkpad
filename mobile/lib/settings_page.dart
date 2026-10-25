import 'package:flutter/material.dart';
import 'design_system.dart';
import 'cursor_settings.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.settings});
  final CursorSettings settings;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settings')),
    body: SafeArea(
      child: AnimatedBuilder(
        animation: settings,
        builder: (context, _) {
          final colors = Theme.of(context).colorScheme;
          return ListView(
            padding: LinkpadStyle.pagePadding,
            children: [
              Icon(Icons.tune, size: 32, color: colors.primary),
              const SizedBox(height: 24),
              const Text('Find your pace.', style: LinkpadStyle.pageTitle),
              const SizedBox(height: 12),
              Text(
                'Make the pointer feel right for you.',
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 32),
              LinkpadPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Cursor sensitivity',
                            style: LinkpadStyle.cardTitle,
                          ),
                        ),
                        Text(
                          settings.label,
                          style: TextStyle(
                            color: colors.primary,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Lower for precise movements. Higher to cover more distance with each swipe.',
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Slider(
                      value: settings.sensitivity,
                      min: CursorSettings.minimum,
                      max: CursorSettings.maximum,
                      divisions: 11,
                      label: settings.label,
                      semanticFormatterCallback: (value) =>
                          '${(value * 100).round()} percent cursor sensitivity',
                      onChanged: settings.setSensitivity,
                      onChangeEnd: (_) {
                        settings.save();
                      },
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Precise · 25%',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          'Fast · 300%',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    TextButton(
                      onPressed: () {
                        settings.setSensitivity(
                          CursorSettings.defaultSensitivity,
                        );
                        settings.save();
                      },
                      child: const Text('Reset to 100%'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Applies immediately to cursor movement on every paired computer. Scrolling speed stays the same.',
                style: TextStyle(color: colors.onSurfaceVariant, height: 1.6),
              ),
              if (settings.warning != null) ...[
                const SizedBox(height: 20),
                LinkpadNotice(message: settings.warning!, error: true),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: settings.save,
                    child: const Text('Try saving again'),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              LinkpadPanel(
                child: SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Keep screen awake',
                    style: LinkpadStyle.cardTitle,
                  ),
                  subtitle: const Text(
                    'Prevent automatic screen lock while Linkpad is open and connected to a computer.',
                  ),
                  value: settings.keepScreenAwake,
                  onChanged: (value) {
                    settings.setKeepScreenAwake(value);
                    settings.save();
                  },
                ),
              ),
              if (settings.awakeWarning != null) ...[
                const SizedBox(height: 16),
                LinkpadNotice(message: settings.awakeWarning!, error: true),
              ],
            ],
          );
        },
      ),
    ),
  );
}
