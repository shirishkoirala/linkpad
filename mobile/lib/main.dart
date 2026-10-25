import 'package:flutter/material.dart';
import 'design_system.dart';
export 'design_system.dart' show linkpadTheme;
import 'dart:io';
import 'controller_page.dart';
import 'desktop/desktop_page.dart';
import 'desktop/desktop_platform.dart';
import 'desktop/server_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isMacOS || Platform.isLinux) {
    final server = ServerController();
    final desktop = DesktopPlatform(server);
    runApp(LinkpadApp(desktopServer: server, desktopPlatform: desktop));
    await desktop.initialize();
    await server.initialize();
  } else {
    runApp(const LinkpadApp());
  }
}

class LinkpadApp extends StatelessWidget {
  const LinkpadApp({super.key, this.desktopServer, this.desktopPlatform});
  final ServerController? desktopServer;
  final DesktopPlatform? desktopPlatform;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Linkpad',
    debugShowCheckedModeBanner: false,
    theme: linkpadTheme(Brightness.light),
    darkTheme: linkpadTheme(Brightness.dark),
    home: desktopServer == null
        ? const ControllerPage()
        : DesktopPage(server: desktopServer!, platform: desktopPlatform),
  );
}
