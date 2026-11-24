import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// Whether the browser has the Web Share API (phones, Safari, some desktops).
bool get webShareAvailable => (web.window.navigator as JSObject).has('share');
