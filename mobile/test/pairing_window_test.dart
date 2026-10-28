import 'package:flutter_test/flutter_test.dart';
import 'package:linkpad_controller/desktop/desktop_platform.dart';
import 'package:linkpad_controller/desktop/server_controller.dart';

class WindowFixture extends DesktopPlatform {
  WindowFixture(super.server);
  int shown = 0;
  @override
  Future<void> show() async {
    shown++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'new pairing invitation opens desktop once without repeated focus stealing',
    () async {
      final server = ServerController();
      final platform = WindowFixture(server);
      server.pairing = {'secret': 'test-code'};
      server.notifyListeners();
      await Future<void>.delayed(Duration.zero);
      expect(platform.shown, 1);
      server.notifyListeners();
      await Future<void>.delayed(Duration.zero);
      expect(platform.shown, 1);
      server.pairing = null;
      server.notifyListeners();
      server.pairing = {'secret': 'another-code'};
      server.notifyListeners();
      await Future<void>.delayed(Duration.zero);
      expect(platform.shown, 2);
      server.pairingDisplay = 1;
      server.notifyListeners();
      await Future<void>.delayed(Duration.zero);
      expect(platform.shown, 3);
      server.notifyListeners();
      await Future<void>.delayed(Duration.zero);
      expect(platform.shown, 3);
      platform.dispose();
      server.dispose();
    },
  );
}
