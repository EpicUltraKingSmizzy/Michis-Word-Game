import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../theme.dart';
import '../widgets/common.dart';

/// Full-screen QR scanner. Pops with the first Michi's Word Game link it sees
/// (or any QR text, if [acceptAny]). Asks for camera permission on first use.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key, this.acceptAny = false});
  final bool acceptAny;

  static Future<String?> open(BuildContext context) =>
      Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const ScanScreen()));

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _done = false;
  String? _hint;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final b in capture.barcodes) {
      final v = b.rawValue;
      if (v == null || v.isEmpty) continue;
      final ours = v.contains('michiswordgame.github.io') || RegExp(r'^[A-Za-z]{4}$').hasMatch(v.trim());
      if (ours || widget.acceptAny) {
        _done = true;
        Navigator.of(context).pop(v.trim());
        return;
      }
      setState(() => _hint = "That QR code isn't a game invite. Point me at the host's screen!");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  error.errorCode == MobileScannerErrorCode.permissionDenied
                      ? 'I need the camera to scan the code. Allow camera access in your settings, or type the room code instead.'
                      : "The camera isn't available here. Type the room code instead!",
                  textAlign: TextAlign.center,
                  style: uiText(18, weight: FontWeight.w600),
                ),
              ),
            ),
          ),
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.white, width: 4),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(children: [
                    PillButton(
                      tooltip: 'Back',
                      onTap: () => Navigator.of(context).pop(),
                      child: const Icon(Icons.arrow_back_rounded),
                    ),
                  ]),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xAA000000),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(
                      _hint ?? "Point the camera at the QR code on the host's screen.",
                      textAlign: TextAlign.center,
                      style: uiText(17, weight: FontWeight.w600, color: MwgColors.gold),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
