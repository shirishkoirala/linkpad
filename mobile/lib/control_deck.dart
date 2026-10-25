import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'peer_client.dart';
import 'relative_touchpad.dart';
import 'cursor_settings.dart';
import 'settings_page.dart';
import 'hold_click_button.dart';
import 'remote_page.dart';

class ControlDeck extends StatefulWidget {
  const ControlDeck({super.key, required this.peer, required this.settings});
  final PeerClient peer;
  final CursorSettings settings;
  @override
  State<ControlDeck> createState() => _ControlDeckState();
}

class _ControlDeckState extends State<ControlDeck> {
  bool keyboard = false, arrows = true, shift = false, symbols = false;
  final modifiers = <String>{};
  PeerClient get peer => widget.peer;
  ColorScheme get colors => Theme.of(context).colorScheme;
  Future<void> _openRemote() async {
    peer.cancelDrag();
    final mode = await Navigator.of(context).push<RemoteSelection>(
      MaterialPageRoute(
        builder: (_) => RemotePage(
          peer: peer,
          onSettings: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => SettingsPage(settings: widget.settings),
            ),
          ),
        ),
      ),
    );
    if (!mounted || mode == null) return;
    setState(() {
      keyboard = mode.mode == 'keyboard';
      modifiers
        ..clear()
        ..addAll(
          keyboard ? mode.modifiers.where((m) => m != 'shift') : <String>[],
        );
      shift = keyboard && mode.modifiers.contains('shift');
    });
  }

  void _key(String key) {
    if (peer.keyboardKey(key, modifiers: {...modifiers, if (shift) 'shift'})) {
      setState(() {
        modifiers.clear();
        shift = false;
      });
    }
  }

  void _letter(String letter) {
    if (modifiers.isNotEmpty) {
      _key(letter);
      return;
    }
    if (peer.typeText(shift ? letter.toUpperCase() : letter)) {
      setState(() => shift = false);
    }
  }

  void _gestures() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => const SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Make yourself comfortable.',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 20),
            ListTile(
              leading: Icon(Icons.swipe),
              title: Text('One finger moves the pointer'),
            ),
            ListTile(
              leading: Icon(Icons.touch_app),
              title: Text('Tap to left click'),
            ),
            ListTile(
              leading: Icon(Icons.pan_tool_alt),
              title: Text('Two fingers scroll'),
            ),
            ListTile(
              leading: Icon(Icons.mouse_outlined),
              title: Text('Two-finger tap to right click'),
            ),
            ListTile(
              leading: Icon(Icons.open_with),
              title: Text('Hold Left click and move on the touchpad to drag'),
              subtitle: Text(
                'Release Left click to drop. Requires the updated desktop server.',
              ),
            ),
            SizedBox(height: 12),
            Text(
              'Modifiers apply to the next key only. Super is Command on Mac and the Windows key on Linux.',
            ),
          ],
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.settings,
    builder: (context, _) => _buildDeck(context),
  );

  Widget _buildDeck(BuildContext context) {
    if (!peer.canKeyboard) {
      modifiers.clear();
      shift = false;
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          if (keyboard) {
            setState(() => keyboard = false);
          } else {
            peer.disconnect();
          }
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final height = math.max(
                constraints.maxHeight,
                keyboard ? 730.0 : 480.0,
              );
              return SingleChildScrollView(
                physics: height > constraints.maxHeight
                    ? const ClampingScrollPhysics()
                    : const NeverScrollableScrollPhysics(),
                child: SizedBox(
                  height: height,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            IconButton(
                              onPressed: peer.disconnect,
                              tooltip: 'Disconnect and return to computers',
                              icon: const Icon(Icons.chevron_left),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    peer.desktopName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    peer.connectionSummary,
                                    maxLines: 2,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Tooltip(
                              message: peer.connectionDetails,
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Icon(
                                  peer.connected ? Icons.wifi : Icons.wifi_off,
                                  size: 20,
                                  color: colors.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        if (!peer.ready || peer.storageWarning != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: colors.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text(
                                peer.storageWarning ??
                                    (peer.waitingForResponse
                                        ? 'Connection is slow. Waiting for your computer to respond…'
                                        : peer.connected
                                        ? 'Desktop input unavailable. Check the desktop server permissions.'
                                        : 'Controls paused while we reconnect.'),
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          ),
                        Expanded(
                          key: const ValueKey('control-deck-touchpad'),
                          child: Semantics(
                            label:
                                'Touchpad. Drag to move, tap to click, two fingers to scroll or right click.',
                            enabled: peer.ready,
                            child: RelativeTouchpad(
                              enabled: peer.ready,
                              onMove: (dx, dy) => peer.move(
                                dx * widget.settings.sensitivity,
                                dy * widget.settings.sensitivity,
                              ),
                              onClick: peer.click,
                              onScroll: peer.canScroll ? peer.scroll : null,
                              child: CustomPaint(
                                painter: _Dots(colors.outlineVariant),
                                child: Container(
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: colors.outlineVariant,
                                    ),
                                    borderRadius: BorderRadius.circular(25),
                                  ),
                                  alignment: Alignment.center,
                                  child: Container(
                                    color: colors.surface,
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (!keyboard) ...[
                                          Icon(
                                            Icons.fingerprint,
                                            size: 32,
                                            color: colors.primary,
                                          ),
                                          const SizedBox(height: 14),
                                        ],
                                        Text(
                                          peer.ready
                                              ? 'Room to move.'
                                              : 'Waiting for your computer…',
                                          style: const TextStyle(fontSize: 16),
                                        ),
                                        if (!keyboard) ...[
                                          const SizedBox(height: 10),
                                          Text(
                                            'One finger moves · Tap to click\nTwo fingers scroll · Tap for right click',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: 12,
                                              height: 1.8,
                                              color: colors.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: HoldClickButton(
                                enabled: peer.ready,
                                supportsDrag: peer.supportsDrag,
                                holding: peer.dragging,
                                onStart: peer.startDrag,
                                onEnd: peer.endDrag,
                                onCancel: peer.cancelDrag,
                                onClick: () => peer.click('left'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _button(
                                'Right click',
                                () => peer.click('right'),
                                enabled: peer.ready,
                              ),
                            ),
                          ],
                        ),
                        if (arrows && !keyboard) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              for (final item in [
                                (Icons.arrow_back, 'left'),
                                (Icons.arrow_upward, 'up'),
                                (Icons.arrow_downward, 'down'),
                                (Icons.arrow_forward, 'right'),
                              ])
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 3,
                                    ),
                                    child: IconButton.filledTonal(
                                      onPressed: peer.canKey
                                          ? () => peer.pressKey(item.$2)
                                          : null,
                                      tooltip: '${item.$2} arrow',
                                      icon: Icon(item.$1),
                                      style: IconButton.styleFrom(
                                        minimumSize: const Size(44, 50),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            13,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                        if (keyboard) ...[
                          const SizedBox(height: 12),
                          if (!peer.supportsKeyboard)
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(
                                peer.connected
                                    ? 'Update your desktop server to enable the keyboard.'
                                    : 'Keyboard paused until the connection returns.',
                                style: TextStyle(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                          _keyboard(),
                        ],
                        const SizedBox(height: 12),
                        Divider(height: 1, color: colors.outlineVariant),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            _nav(
                              Icons.gamepad_outlined,
                              'Remote',
                              false,
                              _openRemote,
                            ),
                            _nav(
                              Icons.keyboard_outlined,
                              'Keyboard',
                              keyboard,
                              () => setState(() {
                                keyboard = !keyboard;
                                modifiers.clear();
                                shift = false;
                              }),
                            ),
                            _nav(
                              Icons.pan_tool_outlined,
                              'Gestures',
                              false,
                              _gestures,
                            ),
                            _nav(
                              Icons.desktop_windows_outlined,
                              'Computers',
                              false,
                              peer.disconnect,
                            ),
                            _nav(
                              Icons.settings_outlined,
                              'Settings',
                              false,
                              () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      SettingsPage(settings: widget.settings),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _nav(
    IconData icon,
    String label,
    bool selected,
    VoidCallback action,
  ) => Expanded(
    child: Semantics(
      selected: selected,
      child: TextButton(
        onPressed: action,
        style: TextButton.styleFrom(
          foregroundColor: selected ? colors.primary : colors.onSurfaceVariant,
          backgroundColor: selected ? colors.surfaceContainerHighest : null,
          padding: const EdgeInsets.symmetric(vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 21),
            const SizedBox(height: 5),
            Text(label, style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
    ),
  );
  Widget _button(
    String label,
    VoidCallback action, {
    bool enabled = true,
    bool selected = false,
  }) => FilledButton.tonal(
    onPressed: enabled ? action : null,
    style: FilledButton.styleFrom(
      minimumSize: const Size(0, 48),
      padding: const EdgeInsets.symmetric(horizontal: 2),
      backgroundColor: selected
          ? colors.primary
          : colors.surfaceContainerHighest,
      foregroundColor: selected ? colors.onPrimary : colors.onSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    child: Text(label, maxLines: 1, style: const TextStyle(fontSize: 13)),
  );
  Widget _keyboard() {
    final rows = symbols
        ? ['1234567890', '@#\$%&*()-', '!?/:;.,']
        : ['qwertyuiop', 'asdfghjkl', 'zxcvbnm'];
    Widget key(
      String label,
      VoidCallback action, {
      bool selected = false,
      int flex = 1,
    }) => Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Semantics(
          toggled: selected,
          child: _button(
            label,
            action,
            enabled: peer.canKeyboard,
            selected: selected,
          ),
        ),
      ),
    );
    return Column(
      children: [
        Row(
          children: [
            key('Esc', () => _key('escape')),
            key('Tab', () => _key('tab')),
            for (final mod in ['ctrl', 'alt', 'super'])
              key(
                mod == 'super'
                    ? 'Win / Cmd'
                    : mod == 'ctrl'
                    ? 'Ctrl'
                    : 'Alt',
                () => setState(() {
                  modifiers.contains(mod)
                      ? modifiers.remove(mod)
                      : modifiers.add(mod);
                }),
                selected: modifiers.contains(mod),
              ),
          ],
        ),
        for (var i = 0; i < rows.length; i++)
          Row(
            children: [
              if (i == 2)
                key('⇧', () => setState(() => shift = !shift), selected: shift),
              for (final char in rows[i].split(''))
                key(shift ? char.toUpperCase() : char, () => _letter(char)),
              if (i == 2)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: IconButton.filledTonal(
                      onPressed: peer.canKeyboard
                          ? () => _key('backspace')
                          : null,
                      tooltip: 'Backspace',
                      icon: const Icon(Icons.backspace_outlined, size: 17),
                      style: IconButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        Row(
          children: [
            key(
              symbols ? 'ABC' : '123',
              () => setState(() => symbols = !symbols),
            ),
            key('space', () => _key('space'), flex: 4),
            key('return', () => _key('enter'), flex: 2),
          ],
        ),
      ],
    );
  }
}

class _Dots extends CustomPainter {
  _Dots(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(25)),
    );
    final paint = Paint()..color = color;
    for (double x = 12; x < size.width; x += 18) {
      for (double y = 12; y < size.height; y += 18) {
        canvas.drawCircle(Offset(x, y), 0.8, paint);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Dots oldDelegate) => oldDelegate.color != color;
}
