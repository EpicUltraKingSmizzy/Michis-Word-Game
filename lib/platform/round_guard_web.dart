import 'dart:js_interop';
import 'dart:ui' show Rect;

import 'package:web/web.dart' as web;

bool _active = false;
JSFunction? _beforeUnload;
JSFunction? _touchStart;
JSFunction? _popState;
void Function()? _onBack;

/// True while our extra "guard" history entry sits on top of Flutter's.
bool _guardPushed = false;

/// Touches starting this close (CSS px) to the left/right screen edge are
/// cancelled during a round, so Safari doesn't start its back swipe.
const double _edge = 28;

/// Called when the player goes "back" during a round.
void setBackHandler(void Function()? onBack) => _onBack = onBack;

/// During a round an extra history entry (a copy of Flutter's own) sits on
/// top, so a back gesture or the back button lands on Flutter's entry inside
/// this page instead of leaving the site. Browsers skip history entries the
/// player never interacted with (Chrome and Firefox's "history manipulation
/// intervention"), which can make back jump straight past Flutter's own
/// entries; the guard entry is pushed after the player has used the page, so
/// back stops on it.
void _installPopListener() {
  if (_popState != null) return;
  _popState = ((web.Event e) {
    if (!_guardPushed) return;
    // Our guard entry was popped. Flutter must not see this: to Flutter it
    // looks like a forward navigation to a new route.
    _guardPushed = false;
    e.stopImmediatePropagation();
    if (_active) {
      _pushGuard();
      _onBack?.call();
    }
  }).toJS;
  // Capture listeners on the target run before Flutter's own listener.
  web.window.addEventListener('popstate', _popState, web.AddEventListenerOptions(capture: true));
}

void _pushGuard() {
  if (_guardPushed) return;
  try {
    web.window.history.pushState(web.window.history.state, '', web.window.location.href);
    _guardPushed = true;
  } catch (_) {}
}

void setRoundActive(bool active) {
  if (active == _active) return;
  _active = active;
  final w = web.window;
  if (active) {
    _installPopListener();
    _pushGuard();
    _beforeUnload = ((web.Event e) {
      e.preventDefault();
      // Older browsers need returnValue set to show the prompt.
      (e as web.BeforeUnloadEvent).returnValue = '';
    }).toJS;
    w.addEventListener('beforeunload', _beforeUnload);
    _touchStart = ((web.TouchEvent e) {
      final t = e.touches.item(0);
      if (t == null) return;
      final x = t.clientX.toDouble();
      if (x < _edge || x > w.innerWidth - _edge) e.preventDefault();
    }).toJS;
    w.addEventListener('touchstart', _touchStart, web.AddEventListenerOptions(passive: false, capture: true));
    web.document.documentElement?.classList.add('mwg-in-round');
  } else {
    if (_beforeUnload != null) w.removeEventListener('beforeunload', _beforeUnload);
    if (_touchStart != null) w.removeEventListener('touchstart', _touchStart, web.EventListenerOptions(capture: true));
    _beforeUnload = null;
    _touchStart = null;
    web.document.documentElement?.classList.remove('mwg-in-round');
    // Drop the guard entry again; the pop listener swallows this popstate.
    if (_guardPushed) w.history.back();
  }
}

void setGestureExclusion(List<Rect> rects) {}
