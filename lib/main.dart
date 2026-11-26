import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'net/local_link.dart';
import 'net/ice_servers.dart';
import 'net/peer_link.dart' show verbosePeerLogs;
import 'state/app_state.dart';
import 'state/session.dart';
import 'ui/widgets/round_guard.dart';
import 'ui/screens/challenge_screen.dart';
import 'ui/screens/countdown_screen.dart';
import 'ui/screens/host_screen.dart';
import 'ui/screens/join_screen.dart';
import 'ui/screens/play_screen.dart';
import 'ui/screens/results_screen.dart';
import 'ui/screens/splash_screen.dart';
import 'ui/screens/waiting_screen.dart';
import 'ui/theme.dart';
import 'ui/widgets/mascot_toast.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  // `?transport=local` (web only) plays between tabs of one browser without
  // WebRTC — handy for testing on a single computer.
  final local = kIsWeb && localLinkSupported && Uri.base.queryParameters['transport'] == 'local';
  final app = local
      ? AppState(hostLinkFactory: createLocalHostLink, clientLinkFactory: createLocalClientLink)
      : AppState();
  app.watchLifecycle();
  unawaited(loadIceServers());
  _listenForJoinLinks(app);
  unawaited(app.init());
  runApp(MichisWordGame(app: app));
}

/// Join links look like https://michiswordgame.github.io/join?code=ABCD.
/// On the web the code is in the page URL; on phones it arrives as an app link.
void _listenForJoinLinks(AppState app) {
  if (kIsWeb) {
    verbosePeerLogs = Uri.base.queryParameters['debug'] == '1';
    forceRelay = Uri.base.queryParameters['ice'] == 'relay';
    app.handleLink(Uri.base);
    return;
  }
  try {
    AppLinks().uriLinkStream.listen(app.handleLink, onError: (_) {});
  } catch (_) {
    // App links unavailable (e.g. tests); manual code entry still works.
  }
}

class MichisWordGame extends StatelessWidget {
  const MichisWordGame({super.key, required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Michi's Word Game",
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      builder: (context, child) => MascotToastHost(messages: app.mascotMessages, child: child!),
      home: Material(
        color: MwgColors.purpleBottom,
        child: ListenableBuilder(
          listenable: app,
          builder: (context, _) {
            final s = app.session;
            if (s == null) return RoundGuard(active: false, app: app, child: _switch(_noSession()));
            return ListenableBuilder(
              listenable: s,
              builder: (context, _) => RoundGuard(
                active: _inRound(s.phase),
                app: app,
                session: s,
                child: _switch(_inSession(s)),
              ),
            );
          },
        ),
      ),
    );
  }

  static bool _inRound(SessionPhase p) =>
      p == SessionPhase.countdown || p == SessionPhase.playing || p == SessionPhase.waitingForResults;

  Widget _switch(Widget child) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: child,
      );

  Widget _noSession() => switch (app.screen) {
        AppScreen.splash => SplashScreen(key: const ValueKey('splash'), app: app),
        AppScreen.join => JoinScreen(key: const ValueKey('join'), app: app),
      };

  Widget _inSession(GameSession s) {
    switch (s.phase) {
      case SessionPhase.lobby:
        if (s is SoloSession) return ChallengeScreen(key: const ValueKey('challenge'), app: app, session: s);
        return s is HostSession
            ? HostScreen(key: const ValueKey('host'), app: app, session: s)
            : WaitingScreen(key: const ValueKey('waiting'), app: app, session: s);
      case SessionPhase.countdown:
        return CountdownScreen(key: ValueKey('countdown${s.countdownStart}'), session: s);
      case SessionPhase.playing:
      case SessionPhase.waitingForResults:
        return PlayScreen(key: ValueKey('play${s.countdownStart}'), app: app, session: s);
      case SessionPhase.results:
        return ResultsScreen(
            key: ValueKey('results${s.countdownStart}'), app: app, session: s, results: s.results!);
    }
  }
}
