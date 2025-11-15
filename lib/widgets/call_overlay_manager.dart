import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'incoming_call_overlay.dart';
import 'ongoing_call_overlay.dart';
import '../models/call_info.dart';
import '../services/alert_service.dart';

class CallOverlayManager {
  static OverlayEntry? _overlayEntry;
  static OverlayState? _overlayState;
  static CallStatus? _currentCallStatus;
  static String?
  _currentCallId; // Track current call ID to prevent restarting ringtone

  /// Show incoming call overlay
  static void showIncomingCall({
    required BuildContext context,
    required CallInfo callInfo,
    required VoidCallback onAnswer,
    required VoidCallback onDecline,
  }) {
    // Only show incoming call overlay if call is ringing
    if (callInfo.status != CallStatus.ringing) {
      return;
    }

    // If this is the same call, don't restart ringtone or recreate overlay
    if (_currentCallId == callInfo.id &&
        _currentCallStatus == CallStatus.ringing) {
      // Call is still ringing, ringtone should continue playing
      return;
    }

    // Different call or first time showing - hide previous overlay
    hideOverlay();
    _currentCallStatus = callInfo.status;
    _currentCallId = callInfo.id;

    _overlayState = Overlay.of(context);

    // Start ringtone when showing the overlay (only if not already ringing)
    AlertService().startRingtone();

    _overlayEntry = OverlayEntry(
      builder: (context) => IncomingCallOverlay(
        callInfo: callInfo,
        onAnswer: () {
          AlertService().stopRingtone();
          onAnswer();
          // Don't hide overlay here - it will transition to ongoing call screen
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

  /// Show ongoing call overlay
  static void showOngoingCall({
    required BuildContext context,
    required CallInfo callInfo,
    required VoidCallback onHangup,
    VoidCallback? onMute,
    VoidCallback? onSpeaker,
    bool isMuted = false,
    bool isSpeakerOn = false,
  }) {
    // Only show ongoing call overlay if call is answered
    if (callInfo.status != CallStatus.answered) {
      return;
    }

    // If already showing ongoing call, just update it
    if (_currentCallStatus == CallStatus.answered && _overlayEntry != null) {
      _overlayEntry!.markNeedsBuild();
      return;
    }

    hideOverlay();
    _currentCallStatus = callInfo.status;

    _overlayState = Overlay.of(context);

    // Ensure ringtone is stopped
    AlertService().stopRingtone();

    _overlayEntry = OverlayEntry(
      builder: (context) => OngoingCallOverlay(
        callInfo: callInfo,
        onHangup: () {
          onHangup();
          hideOverlay();
        },
        onMute: onMute,
        onSpeaker: onSpeaker,
        isMuted: isMuted,
        isSpeakerOn: isSpeakerOn,
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
    _currentCallStatus = null;
    _currentCallId = null;
    // Ensure ringtone is stopped when overlay is hidden
    AlertService().stopRingtone();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
}
