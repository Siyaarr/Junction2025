import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'incoming_call_overlay.dart';
import '../models/call_info.dart';
import '../services/alert_service.dart';

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

    // Start ringtone when showing the overlay (for non-Twilio/polling path)
    AlertService().startRingtone();

    _overlayEntry = OverlayEntry(
      builder: (context) => IncomingCallOverlay(
        callInfo: callInfo,
        onAnswer: () {
          AlertService().stopRingtone();
          onAnswer();
          hideOverlay();
        },
        onDecline: () {
          AlertService().stopRingtone();
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
    // Ensure ringtone is stopped when overlay is hidden
    AlertService().stopRingtone();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
}
