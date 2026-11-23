/// Dev/testing transport: connects browser tabs on the same computer through
/// a BroadcastChannel instead of WebRTC. Enable with `?transport=local` on the
/// web build. On other platforms it is unavailable.
library;

export 'local_link_stub.dart' if (dart.library.js_interop) 'local_link_web.dart';
