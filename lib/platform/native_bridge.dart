/// Calls into the small bits of native code in MainActivity.kt / AppDelegate.swift.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('mwg/native');

bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

/// Whether this platform can open the phone's own camera app.
bool get canOpenCameraApp => _isAndroid;

/// Opens the camera app (Android). Returns false if it couldn't.
Future<bool> openCameraApp() async {
  if (!canOpenCameraApp) return false;
  try {
    return await _channel.invokeMethod<bool>('openCameraApp') ?? false;
  } catch (_) {
    return false;
  }
}

/// Tells the OS we're hosting a room so it keeps us connected in the
/// background: a foreground service on Android, a background task on iOS.
Future<void> setHosting(bool hosting, {String code = ''}) async {
  if (!_isAndroid && !_isIOS) return;
  try {
    await _channel.invokeMethod<bool>(hosting ? 'startHosting' : 'stopHosting', {'code': code});
  } catch (_) {
    // Tests or a platform without the channel: nothing to keep alive.
  }
}
