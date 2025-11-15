import 'dart:async';
import 'package:twilio_voice/twilio_voice.dart';
import 'package:twilio_voice/models/call_event.dart';
import '../models/call_info.dart';
import 'backend_service.dart';
import 'alert_service.dart';

class TwilioCallService {
  final BackendService _backendService;
  final AlertService _alertService;
  StreamSubscription? _callEventsSubscription;
  CallInfo? _currentCall;
  Timer? _scamCheckTimer;
  final _callController = StreamController<CallInfo>.broadcast();
  final _scamAlertController = StreamController<bool>.broadcast();
  bool _isPlacingCall = false; // Track if we're currently placing a call

  TwilioCallService({
    BackendService? backendService,
    AlertService? alertService,
  }) : _backendService = backendService ?? BackendService(),
       _alertService = alertService ?? AlertService();

  /// Stream of call events
  Stream<CallInfo> get callStream => _callController.stream;

  /// Stream of scam alerts
  Stream<bool> get scamAlertStream => _scamAlertController.stream;

  /// Initialize Twilio Voice SDK
  /// Call this with access token from backend
  /// deviceToken is optional (for push notifications, not currently used)
  /// Note: Twilio SDK requires deviceToken to be non-null, so we pass empty string if not provided
  Future<void> initialize({
    required String accessToken,
    String? deviceToken,
  }) async {
    try {
      // Register phone account (required for Android before making calls)
      try {
        await TwilioVoice.instance.registerPhoneAccount();
        print('Phone account registered successfully');
      } catch (e) {
        print(
          'Error registering phone account (may already be registered): $e',
        );
        // Continue anyway - might already be registered
      }

      // Set tokens for Twilio
      // Twilio SDK requires deviceToken to be non-null, use empty string if not provided
      await TwilioVoice.instance.setTokens(
        accessToken: accessToken,
        deviceToken: deviceToken ?? '',
      );

      // Listen to Twilio call events
      _callEventsSubscription = TwilioVoice.instance.callEventsListener.listen(
        _handleTwilioEvent,
        onError: (error) {
          print('Twilio call event error: $error');
        },
      );
    } catch (e) {
      print('Error initializing Twilio: $e');
      rethrow;
    }
  }

  /// Handle Twilio call events
  void _handleTwilioEvent(dynamic event) {
    print('=== Twilio event received ===');
    print('Event: $event');
    print('Event type: ${event.runtimeType}');

    // Handle CallEvent objects (they have a 'name' property)
    if (event is CallEvent) {
      final eventName = event.name;
      print('CallEvent name: $eventName');

      switch (eventName) {
        case 'incoming':
          print('→ Handling incoming call');
          // Extract data from CallEvent if available
          _handleIncomingCall({'from': 'Unknown', 'callSid': ''});
          break;
        case 'ringing':
          print('→ Call is ringing...');
          break;
        case 'connected':
        case 'accept':
          print('→ Call connected/accepted - should be in conference now');
          _handleCallConnected();
          break;
        case 'callEnded':
        case 'disconnected':
        case 'declined':
        case 'missedCall':
          print('→ Call ended/declined/missed');
          _handleCallEnded();
          break;
        case 'log':
          print('→ Log event: ${event.toString()}');
          // Just a log event, ignore
          break;
        default:
          print('→ Unknown/unhandled CallEvent: $eventName');
          break;
      }
    } else if (event is Map) {
      print('Event keys: ${event.keys.toList()}');
      final eventType = event['event'] as String?;
      print('Event type string: $eventType');

      // Log all event properties for debugging
      event.forEach((key, value) {
        print('  $key: $value');
      });

      switch (eventType) {
        case 'incoming':
          print('→ Handling incoming call');
          _handleIncomingCall(event as Map<String, String>);
          break;
        case 'ringing':
          print('→ Call is ringing...');
          break;
        case 'connected':
        case 'accept':
          print('→ Call connected/accepted - should be in conference now');
          _handleCallConnected();
          break;
        case 'callEnded':
        case 'disconnected':
        case 'declined':
        case 'missedCall':
          print('→ Call ended/declined/missed');
          _handleCallEnded();
          break;
        default:
          print('→ Unknown/unhandled event type: $eventType');
          break;
      }
    } else {
      print('Event is not a Map or CallEvent, it is: ${event.runtimeType}');
      print('Event toString: ${event.toString()}');
    }
    print('============================');
  }

  /// Handle incoming Twilio call
  void _handleIncomingCall(Map<String, dynamic> event) {
    final from = event['from'] as String? ?? 'Unknown';
    final callSid = event['callSid'] as String? ?? '';

    // Extract caller info from TwiML parameters if available
    final params = event['parameters'] as Map<String, dynamic>?;
    final callerName = params?['__TWI_CALLER_NAME'] as String? ?? from;

    final callInfo = CallInfo(
      id: callSid.isNotEmpty
          ? callSid
          : DateTime.now().millisecondsSinceEpoch.toString(),
      phoneNumber: from,
      contactName: callerName,
      timestamp: DateTime.now(),
      type: CallType.incoming,
      status: CallStatus.ringing,
    );

    _currentCall = callInfo;
    _callController.add(callInfo);

    // Start ringtone for incoming call
    _alertService.startRingtone();

    // Start analyzing call for scam
    _analyzeCallForScam(callInfo);
  }

  /// Handle call connected (answered)
  void _handleCallConnected() {
    _isPlacingCall = false; // Call is now connected, not placing anymore
    if (_currentCall != null) {
      // Stop ringtone when call connects
      _alertService.stopRingtone();

      _currentCall = CallInfo(
        id: _currentCall!.id,
        phoneNumber: _currentCall!.phoneNumber,
        contactName: _currentCall!.contactName,
        timestamp: _currentCall!.timestamp,
        type: _currentCall!.type,
        status: CallStatus.answered,
        isScam: _currentCall!.isScam,
      );

      _callController.add(_currentCall!);
      _startScamCheckTimer();
    }
  }

  /// Handle call ended
  void _handleCallEnded() {
    _isPlacingCall = false; // Call ended, reset flag
    if (_currentCall != null) {
      // Stop any ongoing sounds
      _alertService.stopRingtone();
      _currentCall = CallInfo(
        id: _currentCall!.id,
        phoneNumber: _currentCall!.phoneNumber,
        contactName: _currentCall!.contactName,
        timestamp: _currentCall!.timestamp,
        type: _currentCall!.type,
        status: CallStatus.ended,
        isScam: _currentCall!.isScam,
      );

      _callController.add(_currentCall!);
      _stopScamCheckTimer();
      _alertService.stopAlert();
      _currentCall = null;
    }
  }

  /// Analyze call for scam detection
  Future<void> _analyzeCallForScam(CallInfo callInfo) async {
    try {
      final isScam = await _backendService.analyzeCallForScam(callInfo);

      if (isScam) {
        _currentCall = CallInfo(
          id: callInfo.id,
          phoneNumber: callInfo.phoneNumber,
          contactName: callInfo.contactName,
          timestamp: callInfo.timestamp,
          type: callInfo.type,
          status: callInfo.status,
          isScam: true,
        );

        _callController.add(_currentCall!);
        _scamAlertController.add(true);
        await _alertService.triggerScamAlert();
      }
    } catch (e) {
      print('Error analyzing call: $e');
    }
  }

  /// Start periodic scam check during active call
  void _startScamCheckTimer() {
    _stopScamCheckTimer();

    _scamCheckTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (_currentCall != null && _currentCall!.status == CallStatus.answered) {
        final scamStatus = await _backendService.checkScamStatus(
          _currentCall!.id,
        );

        if (scamStatus == true && _currentCall!.isScam != true) {
          _currentCall = CallInfo(
            id: _currentCall!.id,
            phoneNumber: _currentCall!.phoneNumber,
            contactName: _currentCall!.contactName,
            timestamp: _currentCall!.timestamp,
            type: _currentCall!.type,
            status: _currentCall!.status,
            isScam: true,
          );

          _callController.add(_currentCall!);
          _scamAlertController.add(true);

          // Trigger visual/audio alert on device
          await _alertService.triggerScamAlert();

          // Request backend to inject warning message into the call
          await _triggerCallWarning();
        }
      }
    });
  }

  /// Stop scam check timer
  void _stopScamCheckTimer() {
    _scamCheckTimer?.cancel();
    _scamCheckTimer = null;
  }

  /// Trigger warning message injection into the active call
  /// This requests the backend to redirect the call and inject a warning
  Future<void> _triggerCallWarning() async {
    if (_currentCall == null || _currentCall!.id.isEmpty) {
      print('Cannot trigger warning: no active call');
      return;
    }

    try {
      final success = await _backendService.triggerScamWarning(
        _currentCall!.id,
        warningMessage:
            'Warning: This call has been flagged as potentially suspicious. '
            'Please be cautious and do not share personal information.',
      );

      if (success) {
        print('Scam warning injected into call successfully');
      } else {
        print('Failed to inject scam warning into call');
      }
    } catch (e) {
      print('Error triggering call warning: $e');
    }
  }

  /// Answer incoming call by making outbound call to join conference
  /// For room-polling calls: Makes HTTP request to /voice-sdk then joins conference
  /// For Twilio SDK calls: Answers the active call
  Future<void> answerCall({String? roomId}) async {
    try {
      print('Answering call - roomId: $roomId');

      // If roomId is provided, this is a room-polling call
      // Skip Twilio call.answer() and go straight to joining conference
      if (roomId != null) {
        print('Room-polling call detected - skipping Twilio call.answer()');
        // Continue to room-polling logic below
      } else {
        // No roomId - this might be a direct Twilio SDK call
        // Try to answer active Twilio call if exists
        try {
          await TwilioVoice.instance.call.answer();
          print('Twilio call answered successfully');

          // Update call status - the 'connected' event will also fire
          if (_currentCall != null &&
              _currentCall!.status == CallStatus.ringing) {
            _handleCallConnected();
          }
          return;
        } catch (e) {
          // No active Twilio call
          print('No active Twilio call to answer: $e');
          throw Exception(
            'Cannot answer call: No active call and no roomId provided',
          );
        }
      }

      // Handle room-polling call - make HTTP request to join conference
      // roomId is guaranteed to be non-null here due to check above

      // Extract conference name from room ID (format: "room-CA..." or just "CA...")
      final conferenceName = roomId.startsWith('room-')
          ? roomId
          : 'room-$roomId';
      print('Joining conference: $conferenceName');

      // Make direct HTTP POST request to /voice-sdk endpoint
      // This will return TwiML or a token that we can use
      try {
        const userId = '123'; // TODO: Extract from access token

        print('Making HTTP request to /voice-sdk endpoint...');
        print('Conference name: $conferenceName');

        // Make POST request to /voice-sdk with conference_name and action
        final response = await _backendService.makeRequestToVoiceSdk(
          conferenceName: conferenceName,
          action: 'join_conference',
          userId: userId,
        );

        print('Response from /voice-sdk: $response');
        print('Response type: ${response.runtimeType}');

        // Now make the actual Twilio call to join the conference
        // The call will route through TwiML App to /voice-sdk endpoint
        // Backend will return TwiML that joins us to the conference
        print('Making Twilio call to join conference...');
        print('Calling from: client:$userId');
        print('Calling to: client:$userId');
        print('Conference name: $conferenceName');
        print(
          'Extra options: {conference_name: $conferenceName, action: join_conference}',
        );

        _isPlacingCall = true; // Mark that we're placing a call
        try {
          await TwilioVoice.instance.call.place(
            from: 'client:$userId',
            to: 'client:$userId', // This routes through TwiML App → /voice-sdk
            extraOptions: {
              'conference_name': conferenceName,
              'action': 'join_conference',
            },
          );

          print('Twilio call placed successfully - waiting for connection...');
          print('The call should route through TwiML App to /voice-sdk');
          print(
            'Backend should receive conference_name and action as form parameters',
          );
        } catch (e) {
          print('Error placing Twilio call: $e');
          rethrow;
        } finally {
          // Reset flag after a short delay to allow call to initialize
          Future.delayed(const Duration(seconds: 2), () {
            _isPlacingCall = false;
          });
        }

        // Update call status to "answered" so UI shows ongoing call screen
        // The 'connected' event will fire when the call actually connects to the conference
        // This confirms we're in the conference, but UI can show "answered" state immediately
        print(
          'Call placed - updating status to answered, waiting for "connected" event to confirm conference join...',
        );

        // Update call status to "answered" so UI switches to ongoing call screen
        if (_currentCall != null &&
            _currentCall!.status == CallStatus.ringing) {
          _handleCallConnected(); // This updates status to answered
        } else if (_currentCall == null) {
          final callInfo = CallInfo(
            id: roomId,
            phoneNumber: 'Incoming Call',
            contactName: 'Unknown Caller',
            timestamp: DateTime.now(),
            type: CallType.incoming,
            status: CallStatus.answered, // Mark as answered so UI updates
          );
          _currentCall = callInfo;
          _callController.add(callInfo);
        }
      } catch (e) {
        print('Error placing outbound call: $e');
        print('This might be because:');
        print('1. Cannot call self (client:userId to client:userId)');
        print('2. extraOptions format is incorrect');
        print('3. SDK method signature is different');

        // Fallback: Update status anyway
        if (_currentCall != null &&
            _currentCall!.status == CallStatus.ringing) {
          _handleCallConnected();
        } else if (_currentCall == null) {
          final callInfo = CallInfo(
            id: roomId,
            phoneNumber: 'Incoming Call',
            contactName: 'Unknown Caller',
            timestamp: DateTime.now(),
            type: CallType.incoming,
            status: CallStatus.answered,
          );
          _currentCall = callInfo;
          _callController.add(callInfo);
        }
        rethrow;
      }
    } catch (e) {
      print('Error answering call: $e');
      rethrow;
    }
  }

  /// Decline/hangup call
  /// For room-polling calls: Updates status and clears call
  /// For Twilio SDK calls: Hangs up the active call
  Future<void> declineCall() async {
    try {
      print('Declining/hanging up call...');

      // Only try to hang up if we have an active call that's been answered
      // Don't hang up if we're still placing a call (call object might not be ready)
      // For room-polling calls that are still ringing, there's no Twilio call to hang up yet
      final shouldHangupTwilioCall =
          !_isPlacingCall &&
          _currentCall != null &&
          _currentCall!.status == CallStatus.answered;

      if (shouldHangupTwilioCall) {
        try {
          await TwilioVoice.instance.call.hangUp();
          print('Twilio call hung up successfully');
        } catch (e) {
          // Error hanging up - check if it's the "missing EXTRA_CALL_HANDLE" error
          final errorStr = e.toString();
          if (errorStr.contains('EXTRA_CALL_HANDLE') ||
              errorStr.contains('ACTION_HANGUP')) {
            // This is expected when there's no active Twilio call - ignore it
            print(
              'Twilio hangup skipped - no active call handle (this is OK for room-polling calls)',
            );
          } else {
            // Other errors - log them
            print('Error hanging up Twilio call: $e');
          }
        }
      } else {
        print(
          'Skipping Twilio hangup - no active connected call (status: ${_currentCall?.status})',
        );
      }

      // Update call status - always update UI state
      if (_currentCall != null) {
        // Stop any ongoing sounds
        _alertService.stopRingtone();

        final wasAnswered = _currentCall!.status == CallStatus.answered;

        _currentCall = CallInfo(
          id: _currentCall!.id,
          phoneNumber: _currentCall!.phoneNumber,
          contactName: _currentCall!.contactName,
          timestamp: _currentCall!.timestamp,
          type: _currentCall!.type,
          status: wasAnswered ? CallStatus.ended : CallStatus.declined,
          isScam: _currentCall!.isScam,
        );

        _callController.add(_currentCall!);
        _stopScamCheckTimer();
        _alertService.stopAlert();
        _currentCall = null;
      }
    } catch (e) {
      print('Error declining call: $e');
      // Even if hangup fails, update UI state to ensure UI is consistent
      if (_currentCall != null) {
        _alertService.stopRingtone();
        _currentCall = CallInfo(
          id: _currentCall!.id,
          phoneNumber: _currentCall!.phoneNumber,
          contactName: _currentCall!.contactName,
          timestamp: _currentCall!.timestamp,
          type: _currentCall!.type,
          status: CallStatus.declined,
          isScam: _currentCall!.isScam,
        );
        _callController.add(_currentCall!);
        _stopScamCheckTimer();
        _alertService.stopAlert();
        _currentCall = null;
      }
    }
  }

  /// Get current call
  CallInfo? get currentCall => _currentCall;

  /// Dispose resources
  void dispose() {
    _callEventsSubscription?.cancel();
    _stopScamCheckTimer();
    _alertService.stopAlert();
    _callController.close();
    _scamAlertController.close();
  }
}
