import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'incoming_call_overlay.dart';
import '../models/call_info.dart';

class CallOverlayManager {
  static OverlayEntry? _overlayEntry;
  static OverlayState? _overlayState;

  /// Show incoming call overlay
  static void showIncomingCall({
    required BuildContext context,
    required CallInfo callInfo,
    required VoidCallback onAnswer,
    required VoidCallback onDecline,
  }) {
    hideOverlay();

    _overlayState = Overlay.of(context);

    _overlayEntry = OverlayEntry(
      builder: (context) => IncomingCallOverlay(
        callInfo: callInfo,
        onAnswer: () {
          onAnswer();
          hideOverlay();
        },
        onDecline: () {
          onDecline();
          hideOverlay();
        },
        isScam: callInfo.isScam ?? false,
      ),
    );

    _overlayState?.insert(_overlayEntry!);

    // Prevent back button from dismissing overlay
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  /// Update overlay with scam status
  static void updateScamStatus(CallInfo callInfo) {
    if (_overlayEntry != null && _overlayState != null) {
      _overlayEntry!.markNeedsBuild();
    }
  }

  /// Hide overlay
  static void hideOverlay() {
    if (_overlayEntry != null) {
      _overlayEntry!.remove();
      _overlayEntry = null;
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
}
