import 'package:material_ui/material_ui.dart';

import '../../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/mascot.dart';
import '../widgets/profile_editor.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key, required this.app});
  final AppState app;

  Future<void> _edit(BuildContext context) async {
    final r = await showProfileEditor(context, name: app.name, avatar: app.avatar);
    if (r != null) await app.updateProfile(r.$1, r.$2);
  }

  @override
  Widget build(BuildContext context) {
    final ready = app.ready && !app.busy;
    return GradientScaffold(
      child: LayoutBuilder(builder: (context, c) {
        final face = (c.maxHeight * 0.26).clamp(120.0, 220.0);
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: c.maxHeight - 48),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  children: [
                    _Bouncy(child: MascotFace(size: face)),
                    const SizedBox(height: 14),
                    const BubbleText("Michi's", size: 40),
                    const BubbleText('Word Game', size: 50),
                  ],
                ),
                const SizedBox(height: 24),
                Column(
                  children: [
                    ProfileCard(name: app.name, avatar: app.avatar, onEdit: () => _edit(context)),
                    const SizedBox(height: 22),
                    if (app.loadError != null)
                      MascotBubble(text: app.loadError!)
                    else if (!app.ready)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: MascotBubble(text: 'Sharpening my pencils… loading the dictionary!'),
                      ),
                    ChunkyButton(
                      label: app.busy ? 'Opening room…' : 'Host Game',
                      icon: Icons.wifi_tethering_rounded,
                      onPressed: ready ? app.hostGame : null,
                    ),
                    const SizedBox(height: 14),
                    ChunkyButton(
                      label: 'Join Game',
                      icon: Icons.qr_code_scanner_rounded,
                      color: const Color(0xFFFFD34E),
                      onPressed: ready ? () => app.showJoin() : null,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

class _Bouncy extends StatefulWidget {
  const _Bouncy({required this.child});
  final Widget child;
  @override
  State<_Bouncy> createState() => _BouncyState();
}

class _BouncyState extends State<_Bouncy> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))
    ..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, child) => Transform.translate(
          offset: Offset(0, -8 * Curves.easeInOut.transform(_c.value)),
          child: Transform.rotate(angle: 0.04 * (Curves.easeInOut.transform(_c.value) - 0.5), child: child),
        ),
        child: widget.child,
      );
}
