/// Sharing a link: the system share sheet where there is one, otherwise
/// (desktop browsers) the link is copied to the clipboard.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import 'web_share_stub.dart' if (dart.library.js_interop) 'web_share_web.dart';

/// Returns true if the share sheet opened, false if the text was copied.
Future<bool> shareOrCopy(BuildContext context, {required String text, required String subject}) async {
  final box = context.findRenderObject() as RenderBox?;
  if (!kIsWeb || webShareAvailable) {
    try {
      await SharePlus.instance.share(ShareParams(
        text: text,
        subject: subject,
        sharePositionOrigin: box == null || !box.hasSize ? null : box.localToGlobal(Offset.zero) & box.size,
      ));
      return true;
    } catch (_) {
      // Fall through to copying.
    }
  }
  await Clipboard.setData(ClipboardData(text: text));
  return false;
}
