import 'dpad_sector.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'cursor_settings.dart';
import 'design_system.dart';
import 'mobile_controls.dart';
import 'peer_client.dart';
import 'relative_touchpad.dart';

typedef RemoteSelection = ({String mode, Set<String> modifiers});

class RemotePage extends StatefulWidget {
  const RemotePage({
    super.key,
    required this.peer,
    required this.onSettings,
    this.settings,
  });
  final PeerClient peer;
  final VoidCallback onSettings;
  final CursorSettings? settings;
  @override
  State<RemotePage> createState() => _RemotePageState();
}

class _RemotePageState extends State<RemotePage> {
  PeerClient get peer => widget.peer;
  bool get arrowsEnabled => peer.canKey || peer.canKeyboard;
  void _send(String key, {Set<String> extra = const {}}) {
    if (peer.canKeyboard) {
      peer.keyboardKey(key, modifiers: extra);
    } else if (peer.canKey &&
        extra.isEmpty &&
        const {'left', 'right', 'up', 'down'}.contains(key)) {
      peer.pressKey(key);
    }
  }

  void _switchMode(String mode) =>
      Navigator.pop(context, (mode: mode, modifiers: <String>{}));

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([peer, widget.settings]),
    builder: (context, _) {
      final colors = Theme.of(context).colorScheme;
      return MobileControlScaffold(
        peer: peer,
        mode: MobileControlMode.remote,
        onModeChanged: (mode) {
          if (mode != MobileControlMode.remote) _switchMode(mode.name);
        },
        onComputers: () {
          peer.disconnect();
          Navigator.pop(context);
        },
        onSettings: widget.onSettings,
        bodyBuilder: (context, constraints) => Column(
          children: [
            MobileControlNotice(peer: peer, keyboardRequired: true),
            Expanded(
              child: LayoutBuilder(
                builder: (context, space) {
                  final padHeight = _directionPadHeight(space.maxWidth);
                  final touchpadHeight = math.max(
                    200.0,
                    space.maxHeight - padHeight - 72,
                  );
                  return SingleChildScrollView(
                    child: Column(
                      children: [
                        SizedBox(
                          height: touchpadHeight,
                          child: _touchpad(colors),
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: _volumeControls(),
                        ),
                        const SizedBox(height: 8),
                        _directionPad(space.maxWidth),
                        const SizedBox(height: 8),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            _shortcuts(),
          ],
        ),
      );
    },
  );

  Widget _touchpad(ColorScheme colors) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 192),
    child: Semantics(
      label:
          'Remote touchpad. Drag to move, tap to click, two fingers to scroll or right click.',
      enabled: peer.ready,
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: {
          EagerGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
                () => EagerGestureRecognizer(),
                (_) {},
              ),
        },
        child: RelativeTouchpad(
          key: const ValueKey('remote-touchpad'),
          enabled: peer.ready,
          onMove: (dx, dy) {
            final sensitivity = widget.settings?.sensitivity ?? 1;
            peer.move(dx * sensitivity, dy * sensitivity);
          },
          onClick: peer.click,
          onScroll: peer.canScroll ? peer.scroll : null,
          child: MobileControlSurface(child: TouchpadHint(ready: peer.ready)),
        ),
      ),
    ),
  );

  Widget _volumeControls() => Row(
    children: [
      for (final control in [
        ('down', Icons.volume_down_outlined, 'Volume down', 'Vol−'),
        ('mute', Icons.volume_off_outlined, 'Mute', 'Mute'),
        ('up', Icons.volume_up_outlined, 'Volume up', 'Vol+'),
      ])
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Tooltip(
              message: peer.supportsVolume
                  ? control.$3
                  : 'Update Linkpad on your computer for volume controls.',
              child: _RemoteKey(
                label: control.$3,
                shortLabel: control.$4,
                icon: control.$2,
                enabled: peer.canVolume,
                onPressed: () => peer.volume(control.$1),
                onRepeat: () => peer.volume(control.$1, repeat: true),
                repeat: control.$1 != 'mute',
                minimumSize: const Size(0, 48),
              ),
            ),
          ),
        ),
    ],
  );

  Widget _shortcuts() => Row(
    children: [
      for (final shortcut in [
        (Icons.first_page, 'Previous', 'tab'),
        (Icons.space_bar, 'Space', 'space'),
        (Icons.last_page, 'Next', 'tab'),
      ])
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: FilledButton.tonal(
              onPressed: peer.canKeyboard
                  ? () => _send(
                      shortcut.$3,
                      extra: shortcut.$2 == 'Previous' ? {'shift'} : {},
                    )
                  : null,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: const RoundedRectangleBorder(
                  borderRadius: LinkpadStyle.keyRadius,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(shortcut.$1, size: 21),
                  const SizedBox(height: 4),
                  Text(shortcut.$2, style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ),
        ),
    ],
  );

  double _directionPadHeight(double width) => (width - 128).clamp(156.0, 220.0);

  Widget _directionPad(double width) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      height: _directionPadHeight(width),
      child: LayoutBuilder(
        builder: (context, space) {
          final diameter = math
              .min(space.maxWidth - 128, space.maxHeight)
              .clamp(140.0, 220.0);
          Widget side(String label, String key, IconData? icon) => _RemoteKey(
            label: label,
            icon: icon,
            enabled: peer.canKeyboard,
            onPressed: () => _send(key),
            repeat: true,
          );
          Widget arrow(IconData icon, String key, Alignment alignment) =>
              Positioned.fill(
                child: DpadSector(
                  direction: key,
                  innerRadius: math.max(72.0, diameter * .36) / 2,
                  child: _RemoteKey(
                    label: 'Arrow $key',
                    icon: icon,
                    enabled: arrowsEnabled,
                    onPressed: () => _send(key),
                    repeat: true,
                    transparent: true,
                    alignment: alignment,
                  ),
                ),
              );
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 56,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    side('Esc', 'escape', null),
                    const SizedBox(height: 10),
                    side('Backspace', 'backspace', Icons.backspace_outlined),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Semantics(
                label: 'D-pad. Arrow keys with Enter in the center.',
                child: SizedBox(
                  width: diameter,
                  height: diameter,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHighest,
                      shape: BoxShape.circle,
                      border: Border.all(color: colors.outlineVariant),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        arrow(
                          Icons.keyboard_arrow_up,
                          'up',
                          const Alignment(0, -.8),
                        ),
                        arrow(
                          Icons.keyboard_arrow_right,
                          'right',
                          const Alignment(.8, 0),
                        ),
                        arrow(
                          Icons.keyboard_arrow_down,
                          'down',
                          const Alignment(0, .8),
                        ),
                        arrow(
                          Icons.keyboard_arrow_left,
                          'left',
                          const Alignment(-.8, 0),
                        ),
                        SizedBox(
                          width: math.max(72.0, diameter * .36),
                          height: math.max(72.0, diameter * .36),
                          child: ClipOval(
                            child: FilledButton(
                              onPressed: peer.canKeyboard
                                  ? () => _send('enter')
                                  : null,
                              style: FilledButton.styleFrom(
                                padding: EdgeInsets.zero,
                                shape: const CircleBorder(),
                              ),
                              child: const Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.keyboard_return, size: 19),
                                  SizedBox(height: 4),
                                  Text('Enter', style: TextStyle(fontSize: 14)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 56,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    side('Page up', 'pageup', Icons.keyboard_double_arrow_up),
                    const SizedBox(height: 10),
                    side(
                      'Page down',
                      'pagedown',
                      Icons.keyboard_double_arrow_down,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RemoteKey extends StatefulWidget {
  const _RemoteKey({
    required this.label,
    required this.enabled,
    required this.onPressed,
    this.icon,
    this.repeat = false,
    this.transparent = false,
    this.alignment = Alignment.center,
    this.shortLabel,
    this.onRepeat,
    this.minimumSize = const Size(56, 56),
  });
  final String label;
  final bool enabled, repeat, transparent;
  final Alignment alignment;
  final String? shortLabel;
  final Size minimumSize;
  final VoidCallback onPressed;
  final VoidCallback? onRepeat;
  final IconData? icon;
  @override
  State<_RemoteKey> createState() => _RemoteKeyState();
}

class _RemoteKeyState extends State<_RemoteKey> {
  Timer? timer;
  void stop() {
    timer?.cancel();
    timer = null;
  }

  @override
  void didUpdateWidget(_RemoteKey old) {
    super.didUpdateWidget(old);
    if (!widget.enabled) stop();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return GestureDetector(
      onLongPressStart: widget.enabled && widget.repeat
          ? (_) {
              (widget.onRepeat ?? widget.onPressed)();
              timer = Timer.periodic(const Duration(milliseconds: 110), (_) {
                if (widget.enabled) {
                  (widget.onRepeat ?? widget.onPressed)();
                } else {
                  stop();
                }
              });
            }
          : null,
      onLongPressEnd: widget.enabled && widget.repeat ? (_) => stop() : null,
      onLongPressCancel: widget.enabled && widget.repeat ? stop : null,
      child: TextButton(
        onPressed: widget.enabled ? widget.onPressed : null,
        style: TextButton.styleFrom(
          minimumSize: widget.minimumSize,
          padding: EdgeInsets.zero,
          backgroundColor: widget.transparent
              ? Colors.transparent
              : colors.surfaceContainerHighest,
          foregroundColor: colors.onSurface,
          shape: RoundedRectangleBorder(borderRadius: LinkpadStyle.keyRadius),
        ),
        child: Align(
          alignment: widget.alignment,
          widthFactor: widget.transparent ? null : 1,
          heightFactor: widget.transparent ? null : 1,
          child: widget.shortLabel != null
              ? Semantics(
                  label: widget.label,
                  excludeSemantics: true,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(widget.icon, size: 20),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          widget.shortLabel!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                )
              : widget.icon == null
              ? Text(widget.label, style: const TextStyle(fontSize: 12))
              : Semantics(
                  label: widget.label,
                  child: Icon(widget.icon, size: 23),
                ),
        ),
      ),
    );
  }
}
