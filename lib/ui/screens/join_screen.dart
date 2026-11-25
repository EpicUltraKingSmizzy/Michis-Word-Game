import 'package:material_ui/material_ui.dart';

import '../../logic/room_code.dart';
import '../../platform/native_bridge.dart' as native;
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/mascot.dart';
import 'scan_screen.dart';

/// Players scan the host's QR code (with the phone's camera app on Android,
/// or the in-app scanner on iPhone and the web) or type the room code.
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

  /// Android: opens the camera app, which reads the QR code and opens the
  /// join link (bringing the player back here). Elsewhere, or if that fails,
  /// uses the in-app scanner.
  Future<void> _scan() async {
    if (native.canOpenCameraApp && await native.openCameraApp()) return;
    if (mounted) await _scanInApp();
  }

  Future<void> _scanInApp() async {
    final text = await ScanScreen.open(context);
    if (text == null || !mounted) return;
    final uri = Uri.tryParse(text);
    if (uri != null && uri.hasScheme) {
      widget.app.handleLink(uri);
    } else {
      _code.text = normalizeRoomCode(text);
      _join();
    }
  }

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
            text: "Scan the host's QR code or type in the room code below!",
          ),
          const SizedBox(height: 20),
          ChunkyButton(
            label: native.canOpenCameraApp ? 'Open camera' : 'Scan QR code',
            icon: native.canOpenCameraApp ? Icons.photo_camera_rounded : Icons.qr_code_scanner_rounded,
            color: const Color(0xFFFFD34E),
            onPressed: app.busy ? null : _scan,
          ),
          if (native.canOpenCameraApp)
            Center(
              child: TextButton(
                onPressed: app.busy ? null : _scanInApp,
                child: Text('Scan here instead', style: uiText(16, weight: FontWeight.w600, color: Colors.white)),
              ),
            ),
          const SizedBox(height: 16),
          GlassCard(
            child: Column(
              children: [
                Text('Room code', style: uiText(20, weight: FontWeight.w700)),
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
            MascotBubble(
              text: app.joinWaiting
                  ? "Waiting for the host… If they switched apps to send the invite, ask them to come back to the game. I'll keep knocking on room ${app.joinCodeDraft} for 2 minutes!"
                  : 'Knocking on room ${app.joinCodeDraft}…',
            ),
            if (app.joinWaiting) ...[
              const SizedBox(height: 12),
              Center(
                child: PillButton(
                  onTap: app.cancelJoin,
                  child: const Text('Stop waiting'),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
