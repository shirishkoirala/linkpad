import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'server_controller.dart';

bool macInstallationNeedsMove(String executable) =>
    executable.startsWith('/Volumes/') ||
    executable.contains('/AppTranslocation/');

class DesktopPlatform extends ChangeNotifier with TrayListener, WindowListener {
  DesktopPlatform(this.server) {
    server.addListener(_serverChanged);
  }
  final ServerController server;
  bool trayReady = false;
  bool loginEnabled = false;
  bool loginBusy = false;
  bool _quitting = false;
  String? error;
  bool? _menuRunning;
  String? _shownPairingSecret;
  int _shownPairingDisplay = 0;
  bool permissionCheckBusy = false;
  bool restartRecommended = false;
  bool restartBusy = false;
  bool _awaitingPermission = false;
  bool get isMacOS => Platform.isMacOS;
  bool get isWindows => Platform.isWindows;
  bool get launchedFromDiskImage =>
      isMacOS && macInstallationNeedsMove(Platform.resolvedExecutable);

  Future<void> initialize() async {
    await windowManager.ensureInitialized();
    windowManager.addListener(this);
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        size: Size(1020, 740),
        minimumSize: Size(720, 580),
        center: true,
        title: 'Linkpad',
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
    try {
      trayManager.addListener(this);
      await trayManager.setIcon(
        Platform.isWindows
            ? 'assets/branding/tray-icon.ico'
            : 'assets/branding/tray-icon.png',
        isTemplate: Platform.isMacOS,
      );
      if (Platform.isMacOS) await trayManager.setToolTip('Linkpad');
      await _updateMenu();
      trayReady = true;
      // Some Linux desktops have no visible tray host. Keep their window reachable.
      await windowManager.setPreventClose(true);
    } catch (_) {
      error =
          'The system tray is unavailable. Closing the window will quit Linkpad.';
      await windowManager.setPreventClose(true);
    }
    launchAtStartup.setup(
      appName: 'Linkpad',
      appPath: Platform.isLinux
          ? '"${Platform.resolvedExecutable.replaceAll(r'\', r'\\').replaceAll('"', r'\"').replaceAll(r'$', r'\$').replaceAll('`', r'\`').replaceAll('%', '%%')}"'
          : Platform.resolvedExecutable,
    );
    try {
      loginEnabled = await launchAtStartup.isEnabled();
    } catch (_) {
      error = 'Could not read the start-at-login setting.';
    }
    notifyListeners();
  }

  void _serverChanged() {
    final secret = server.pairing?['secret'] as String?;
    if (secret != _shownPairingSecret ||
        server.pairingDisplay != _shownPairingDisplay) {
      _shownPairingDisplay = server.pairingDisplay;
      _shownPairingSecret = secret;
      if (secret != null) {
        unawaited(
          show().catchError((Object _) {
            error =
                'Pairing code is ready. Open Linkpad from the dock or tray.';
            notifyListeners();
          }),
        );
      }
    }
    if (trayReady && _menuRunning != server.running) unawaited(_updateMenu());
    if (_awaitingPermission &&
        server.inputPermissionGranted == true &&
        !server.busy &&
        !permissionCheckBusy) {
      unawaited(checkInput());
    }
  }

  Future<void> requestInputPermission() async {
    if (!isMacOS) return;
    _awaitingPermission = true;
    restartRecommended = false;
    if (server.running) await server.command('requestInputPermission');
    await openPermissions();
  }

  Future<void> checkInput() async {
    if (permissionCheckBusy || server.busy || restartBusy) return;
    permissionCheckBusy = true;
    notifyListeners();
    try {
      if (!server.running) {
        await server.start();
      } else {
        await server.command('status');
        if (!server.inputAvailable &&
            (!isMacOS || server.inputPermissionGranted == true)) {
          // Capabilities are registered when the helper starts. Restart once,
          // rather than mutating a registry used by active network sessions.
          _awaitingPermission = false;
          await server.restart();
          if (!server.inputAvailable) {
            error =
                'Input is still unavailable. Quit and reopen Linkpad, then check again.';
          }
        }
      }
      restartRecommended = isMacOS && server.running && !server.inputAvailable;
      if (server.inputAvailable) {
        _awaitingPermission = false;
        error = null;
      }
    } catch (_) {
      error = 'Could not check desktop control. Try again or reopen Linkpad.';
    } finally {
      permissionCheckBusy = false;
      notifyListeners();
    }
  }

  @override
  void onWindowFocus() {
    if (_awaitingPermission ||
        (isMacOS && server.running && !server.inputAvailable)) {
      unawaited(checkInput());
    }
  }

  Future<void> openApplications() async {
    if (isMacOS) await Process.run('/usr/bin/open', ['/Applications']);
  }

  Future<void> _updateMenu() async {
    _menuRunning = server.running;
    try {
      await trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(key: 'show', label: 'Open Linkpad'),
            MenuItem.separator(),
            MenuItem(
              key: 'status',
              label: server.running ? 'Server running' : 'Server stopped',
              disabled: true,
            ),
            MenuItem(
              key: 'toggle',
              label: server.running ? 'Stop server' : 'Start server',
            ),
            MenuItem.separator(),
            MenuItem(key: 'quit', label: 'Quit Linkpad'),
          ],
        ),
      );
    } catch (_) {
      error =
          'Could not update the tray menu. Open Linkpad from the dock or launcher.';
      notifyListeners();
    }
  }

  Future<void> show() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> setLogin(bool enabled) async {
    if (loginBusy) return;
    loginBusy = true;
    notifyListeners();
    try {
      final success = enabled
          ? await launchAtStartup.enable()
          : await launchAtStartup.disable();
      if (!success) {
        throw StateError('The operating system rejected the change.');
      }
      loginEnabled = await launchAtStartup.isEnabled();
      if (loginEnabled != enabled) {
        throw StateError('Approve Linkpad in your system login settings.');
      }
      error = null;
    } catch (_) {
      error = Platform.isMacOS
          ? 'Approve Linkpad in System Settings → General → Login Items, then try again.'
          : 'Could not change start at login. Check your system login settings.';
    }
    loginBusy = false;
    notifyListeners();
  }

  Future<void> openPermissions() async {
    if (!isMacOS) return;
    await Process.run('/usr/bin/open', [
      'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility',
    ]);
  }

  Future<void> launchFreshInstance() async {
    final bundle = File(Platform.resolvedExecutable).parent.parent.parent.path;
    if (!bundle.endsWith('.app')) {
      throw StateError('Installed app bundle unavailable');
    }
    final result = await Process.run('/usr/bin/open', ['-n', bundle]);
    if (result.exitCode != 0) {
      throw StateError('macOS could not reopen Linkpad');
    }
  }

  Future<void> restartApp() async {
    if (!isMacOS || restartBusy || _quitting || server.busy) return;
    restartBusy = true;
    notifyListeners();
    final wasRunning = server.running;
    try {
      // Release the listener before the new application tries to bind it.
      await server.stop();
      await launchFreshInstance();
      await quit();
    } catch (_) {
      if (wasRunning && !server.running) {
        try {
          await server.start();
        } catch (_) {}
      }
      error =
          'Could not restart automatically. Quit and reopen Linkpad, then check access again.';
    } finally {
      if (!_quitting) {
        restartBusy = false;
        notifyListeners();
      }
    }
  }

  Future<void> quit() async {
    if (_quitting) return;
    _quitting = true;
    await server.stop();
    try {
      if (trayReady) await trayManager.destroy();
      await windowManager.destroy();
    } finally {
      // macOS keeps an application alive after its last window closes.
      // Explicit Quit must terminate after the child is stopped.
      exit(0);
    }
  }

  @override
  void onWindowClose() async {
    if (_quitting) return;
    if (trayReady) {
      await windowManager.hide();
    } else {
      await quit();
    }
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(show());
  }

  @override
  void onTrayIconRightMouseDown() {
    unawaited(trayManager.popUpContextMenu());
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        unawaited(show());
      case 'toggle':
        unawaited(server.running ? server.stop() : server.start());
      case 'quit':
        unawaited(quit());
    }
  }

  @override
  void dispose() {
    server.removeListener(_serverChanged);
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    super.dispose();
  }
}
