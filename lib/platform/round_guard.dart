/// Keeps stray system gestures from throwing players out of a round.
///
/// What each platform allows:
/// - Android app: during a round the app goes "immersive sticky", so a swipe
///   up from the bottom (or down from the top) only reveals the system bars;
///   it takes a second swipe to go home. The grid is also registered as a
///   system-gesture exclusion area, so an edge swipe that starts on the grid
///   is a drag, not "back". Android never lets apps exclude the bottom (home)
///   gesture, and caps exclusion at 200dp of height per side edge.
///   Back gestures that still happen are caught by a PopScope (see
///   RoundGuard) and open the quit dialog.
/// - Web: the page blocks the browser's own pull/overscroll gestures, cancels
///   touches that start right at the left/right screen edge (this stops the
///   iOS Safari back swipe on most versions), asks before reloading or
///   closing the tab, and turns any "back" into the quit dialog (an extra
///   history entry during the round keeps back on the page). iOS and
///   Android's system-level gestures (Android back, the iOS home bar) can't
///   be blocked by a web page.
library;

import 'dart:ui' show Rect;

import 'round_guard_io.dart' if (dart.library.js_interop) 'round_guard_web.dart' as impl;

/// Turns the round protections on or off.
void setRoundActive(bool active) => impl.setRoundActive(active);

/// Android only: areas (in physical pixels) where edge swipes should reach
/// the app instead of the system's back gesture.
void setGestureExclusion(List<Rect> rects) => impl.setGestureExclusion(rects);

/// Web only: called when the browser goes back during a round.
void setBackHandler(void Function()? onBack) => impl.setBackHandler(onBack);
