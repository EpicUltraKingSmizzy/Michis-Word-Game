import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('mwg/native');
bool _active = false;

/// Web only; back is handled by PopScope in the app.
void setBackHandler(void Function()? onBack) {}

bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

void setRoundActive(bool active) {
  if (active == _active) return;
  _active = active;
  if (!_isAndroid && !_isIOS) return;
  try {
    if (active) {
      // First swipe from an edge only shows the bars; a second one acts.
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      setGestureExclusion(const []);
    }
  } catch (_) {}
}

List<List<int>> _last = const [];

void setGestureExclusion(List<Rect> rects) {
  if (!_isAndroid) return;
  final list = [
    for (final r in rects) [r.left.round(), r.top.round(), r.right.round(), r.bottom.round()],
  ];
  if (listEquals(list.expand((e) => e).toList(), _last.expand((e) => e).toList())) return;
  _last = list;
  _channel.invokeMethod<bool>('setGestureExclusion', {'rects': list}).catchError((_) => false);
}
