import 'package:material_ui/material_ui.dart';

import '../../logic/room_code.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/mascot.dart';

/// No in-app camera: players scan the host's QR code with their phone's own
/// camera, which opens the join link. Typing the code is the fallback.
class JoinScreen extends StatefulWidget {
  const JoinScreen({super.key, required this.app});
  final AppState app;

  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  late final _code = TextEditingController(text: widget.app.joinCodeDraft);

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _join() => widget.app.joinGame(_code.text);

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    return GradientScaffold(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            children: [
              PillButton(
                tooltip: 'Back',
                onTap: app.busy ? null : app.showSplash,
                child: const Icon(Icons.arrow_back_rounded),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const MascotBubble(
            faceSize: 72,
            fontSize: 19,
            text: "Open your phone's camera and point it at the QR code on the host's screen. "
                "Tap the link that pops up and you'll hop right into the game!",
          ),
          const SizedBox(height: 28),
          GlassCard(
            child: Column(
              children: [
                Text('Or type the room code', style: uiText(20, weight: FontWeight.w700)),
                const SizedBox(height: 12),
                TextField(
                  controller: _code,
                  autofocus: false,
                  maxLength: roomCodeLength,
                  textAlign: TextAlign.center,
                  textCapitalization: TextCapitalization.characters,
                  style: uiText(40, weight: FontWeight.w700).copyWith(letterSpacing: 10),
                  decoration: InputDecoration(
                    hintText: 'ABCD',
                    hintStyle: uiText(40, color: Colors.white24).copyWith(letterSpacing: 10),
                    counterText: '',
                    filled: true,
                    fillColor: const Color(0x33000000),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                  ),
                  onSubmitted: (_) => _join(),
                ),
                const SizedBox(height: 16),
                ChunkyButton(
                  label: app.busy ? 'Joining…' : 'Join',
                  icon: Icons.login_rounded,
                  onPressed: app.busy ? null : _join,
                ),
              ],
            ),
          ),
          if (app.busy) ...[
            const SizedBox(height: 24),
            MascotBubble(text: 'Knocking on room ${app.joinCodeDraft}…'),
          ],
        ],
      ),
    );
  }
}
