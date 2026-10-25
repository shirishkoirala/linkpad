import 'package:flutter/services.dart';

/// Opens only this app's settings; it never assumes a permission was granted.
Future<bool> openPhoneSettings() async {
  try {
    return await const MethodChannel(
          'linkpad/permissions',
        ).invokeMethod<bool>('openSettings') ??
        false;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}
