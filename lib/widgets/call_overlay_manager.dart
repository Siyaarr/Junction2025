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
  static CallInfo?
  _lastCallInfo; // Track last call info to detect changes (e.g., isScam)

  /// Dev helper: simulate scam alert on the active ongoing call overlay
  static void simulateScamAlert() {
    // This calls into the overlay's public hook if it's mounted
    OngoingCallOverlay.simulateScam?.call();
  }

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
      // Same call still ringing: update the overlay content without restarting ringtone
      if (_overlayEntry != null && _overlayState != null) {
        // Replace the overlay entry with updated props
        final previousEntry = _overlayEntry!;
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
        previousEntry.remove();
        _overlayState!.insert(_overlayEntry!);
      }
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
    VoidCallback? onHold,
    VoidCallback? onResume,
    VoidCallback? onCallSafetyContact,
    bool isMuted = false,
    bool isSpeakerOn = false,
    bool isOnHold = false,
  }) {
    // Only show ongoing call overlay if call is answered
    if (callInfo.status != CallStatus.answered) {
      return;
    }

    // If already showing ongoing call, check if we need to update it
    // (e.g., scam status changed)
    if (_currentCallStatus == CallStatus.answered && _overlayEntry != null) {
      // Check if callInfo has changed (especially isScam flag)
      // If it has, recreate the overlay to show updated scam status
      final currentCallId = _currentCallId;
      final callInfoChanged =
          currentCallId != callInfo.id ||
          (_lastCallInfo?.isScam != callInfo.isScam);

      if (callInfoChanged) {
        // CallInfo changed (e.g., scam detected) - recreate overlay
        print(
          '🔄 CallInfo changed (isScam: ${callInfo.isScam}) - recreating overlay to show scam alert',
        );
        hideOverlay(); // Remove old overlay
        // Continue to create new overlay below
      } else {
        // Same callInfo - but we still need to ensure overlay is on top
        // Remove and reinsert to bring it to the front (important when app comes back to foreground)
        final previousEntry = _overlayEntry!;
        final overlayState = _overlayState;
        
        // Create new overlay entry with updated callInfo
        _overlayEntry = OverlayEntry(
          opaque: true,
          builder: (context) => OngoingCallOverlay(
            callInfo: callInfo,
            onHangup: () {
              onHangup();
              hideOverlay();
            },
            onMute: onMute,
            onSpeaker: onSpeaker,
            onHold: onHold,
            onResume: onResume,
            onCallSafetyContact: onCallSafetyContact,
            isMuted: isMuted,
            isSpeakerOn: isSpeakerOn,
            isOnHold: isOnHold,
          ),
        );
        
        // Remove old and insert new to bring to top
        previousEntry.remove();
        overlayState?.insert(_overlayEntry!);
        _lastCallInfo = callInfo; // Update stored callInfo
        
        // Ensure system UI mode is set
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        
        print('✅ Ongoing call overlay brought to top');
        return;
      }
    }

    // Hide any existing overlay before creating new one
    hideOverlay();
    _currentCallStatus = callInfo.status;
    _currentCallId = callInfo.id;
    _lastCallInfo = callInfo; // Store for comparison

    _overlayState = Overlay.of(context);

    // Ensure ringtone is stopped
    AlertService().stopRingtone();

    // Create overlay entry with opaque: true to ensure it's on top
    _overlayEntry = OverlayEntry(
      opaque: true, // Make overlay opaque to ensure it covers everything
      builder: (context) => OngoingCallOverlay(
        callInfo: callInfo,
        onHangup: () {
          onHangup();
          hideOverlay();
        },
        onMute: onMute,
        onSpeaker: onSpeaker,
        onHold: onHold,
        onResume: onResume,
        onCallSafetyContact: onCallSafetyContact,
        isMuted: isMuted,
        isSpeakerOn: isSpeakerOn,
        isOnHold: isOnHold,
      ),
    );

    // Insert overlay at the end to ensure it's on top
    _overlayState?.insert(_overlayEntry!);

    // Prevent back button from dismissing overlay
    // Use immersiveSticky to hide system UI and ensure our overlay is visible
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    print('✅ Ongoing call overlay shown - should appear above Android call UI');
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
    _lastCallInfo = null; // Clear last call info
    // Ensure ringtone is stopped when overlay is hidden
    AlertService().stopRingtone();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
}
