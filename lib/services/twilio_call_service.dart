import 'dart:async';
import 'package:twilio_voice/twilio_voice.dart';
import 'package:twilio_voice/models/call_event.dart';
import '../models/call_info.dart';
import 'backend_service.dart';
import 'alert_service.dart';

/// Custom exception for phone account issues
class PhoneAccountNotEnabledException implements Exception {
  final String message;
  final bool settingsOpened;

  PhoneAccountNotEnabledException(this.message, {this.settingsOpened = false});

  @override
  String toString() => message;
}

class TwilioCallService {
  final BackendService _backendService;
  final AlertService _alertService;
  StreamSubscription? _callEventsSubscription;
  CallInfo? _currentCall;
  Timer? _scamCheckTimer;
  final _callController = StreamController<CallInfo>.broadcast();
  final _scamAlertController = StreamController<bool>.broadcast();
  final _phoneAccountErrorController = StreamController<String>.broadcast();
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

  /// Stream of phone account errors (for UI to show dialogs)
  Stream<String> get phoneAccountErrorStream =>
      _phoneAccountErrorController.stream;

  /// Initialize Twilio Voice SDK
  /// Call this with access token from backend
  /// deviceToken is optional (for push notifications, not currently used)
  /// Note: Twilio SDK requires deviceToken to be non-null, so we pass empty string if not provided
  Future<void> initialize({
    required String accessToken,
    String? deviceToken,
  }) async {
    try {
      // Step 1: Check and request microphone permission
      // Required for receiving and placing calls
      print('Checking microphone permission...');
      try {
        final hasMic = await TwilioVoice.instance.hasMicAccess();
        if (!hasMic) {
          print('Microphone permission not granted, requesting...');
          await TwilioVoice.instance.requestMicAccess();
          print('Microphone permission requested');
        } else {
          print('✅ Microphone permission already granted');
        }
      } catch (e) {
        print('Error checking/requesting microphone permission: $e');
        // Continue - permission might be automatically requested when receiving a call
      }

      // Step 2: Request READ_PHONE_NUMBERS permission (required before registering Phone Account)
      print('Requesting READ_PHONE_NUMBERS permission...');
      try {
        await TwilioVoice.instance.requestReadPhoneNumbersPermission();
        print('READ_PHONE_NUMBERS permission granted');
      } catch (e) {
        print('Error requesting READ_PHONE_NUMBERS permission: $e');
        // Continue - might already be granted
      }

      // Step 3: Request CALL_PHONE permission (required for placing calls)
      print('Requesting CALL_PHONE permission...');
      try {
        await TwilioVoice.instance.requestCallPhonePermission();
        print('CALL_PHONE permission granted');
      } catch (e) {
        print('Error requesting CALL_PHONE permission: $e');
        // Continue - might already be granted
      }

      // Step 4: Request READ_PHONE_STATE permission (required for ConnectionService)
      print('Requesting READ_PHONE_STATE permission...');
      try {
        await TwilioVoice.instance.requestReadPhoneStatePermission();
        print('READ_PHONE_STATE permission granted');
      } catch (e) {
        print('Error requesting READ_PHONE_STATE permission: $e');
        // Continue - might already be granted
      }

      // Step 5: Request MANAGE_OWN_CALLS permission (required for outbound calls)
      // Note: This permission is required in manifest, but we can request it here too
      print('Requesting MANAGE_OWN_CALLS permission...');
      try {
        await TwilioVoice.instance.requestManageOwnCallsPermission();
        print('MANAGE_OWN_CALLS permission granted');
      } catch (e) {
        print('Error requesting MANAGE_OWN_CALLS permission: $e');
        // Continue - might already be granted or not available on this platform
      }

      // Step 6: Register phone account (required for Android before making calls)
      print('Registering phone account...');
      try {
        await TwilioVoice.instance.registerPhoneAccount();
        print('Phone account registered successfully');
      } catch (e) {
        print(
          'Error registering phone account (may already be registered): $e',
        );
        // Continue anyway - might already be registered
      }

      // Step 7: Check if phone account is enabled
      print('Checking if phone account is enabled...');
      try {
        final isEnabled = await TwilioVoice.instance.isPhoneAccountEnabled();
        print('Phone account enabled: $isEnabled');
        if (!isEnabled) {
          print(
            '⚠️ Phone account is not enabled - user may need to enable it in settings',
          );
          // Optionally open settings for user to enable manually
          // await TwilioVoice.instance.openPhoneAccountSettings();
        }
      } catch (e) {
        print('Error checking phone account status: $e');
      }

      // Step 8: Check if device requires background permissions (Xiaomi, etc.)
      print('Checking if device requires background permissions...');
      try {
        final requiresBg = await TwilioVoice.instance
            .requiresBackgroundPermissions();
        if (requiresBg) {
          print(
            '⚠️ Device requires background permissions for receiving calls',
          );
          print(
            'User will be taken to app settings to enable background permissions',
          );
          // Note: This will open app settings - you might want to show a dialog first
          await TwilioVoice.instance.requestBackgroundPermissions();
        } else {
          print('✅ Background permissions not required on this device');
        }
      } catch (e) {
        print('Error checking background permissions: $e');
        // Continue - might not be available on this platform/version
      }

      // Step 9: Configure call rejection behavior if permissions not granted
      // If permissions aren't granted, reject calls instead of showing UI
      // Note: This is Android-only feature
      print('Configuring call rejection behavior...');
      try {
        // Configure to reject calls if permissions not granted (Android only)
        // The method signature may vary - check SDK docs for exact parameters
        await TwilioVoice.instance.rejectCallOnNoPermissions();
        final isRejecting = await TwilioVoice.instance
            .isRejectingCallOnNoPermissions();
        print('Call rejection on no permissions: $isRejecting');
      } catch (e) {
        print('Error configuring call rejection (may not be available): $e');
        // Continue - might not be available on this platform or version
      }

      print('\n${"=" * 60}');
      print('🔑 SETTING TWILIO TOKENS');
      print('${"=" * 60}');
      print(
        'Access Token (first 50 chars): ${accessToken.length > 50 ? accessToken.substring(0, 50) + "..." : accessToken}',
      );
      print('Access Token length: ${accessToken.length}');
      print('Device Token: ${deviceToken ?? "null (using empty string)"}');
      print('${"=" * 60}\n');

      // Set tokens for Twilio
      // Twilio SDK requires deviceToken to be non-null, use empty string if not provided
      await TwilioVoice.instance.setTokens(
        accessToken: accessToken,
        deviceToken: deviceToken ?? '',
      );

      print('✅ Tokens set successfully');

      // Register client so incoming calls display names instead of user IDs
      // This must be done after setting tokens and before receiving calls
      // The clientId should match the identity from the access token
      // For now, we'll use a default name - in a real app, you'd get this from user profile
      try {
        // Extract identity from access token if available, or use fallback
        // Note: In a real app, you'd want to get the actual user's name from your backend/user profile
        final clientId = _backendService.currentIdentity ?? '123';
        final clientName =
            'User $clientId'; // TODO: Get actual user name from profile/backend

        await TwilioVoice.instance.registerClient(clientId, clientName);
        print('✅ Registered client: $clientId ($clientName)');
      } catch (e) {
        print('⚠️ Error registering client (may already be registered): $e');
        // Continue - client registration might fail if already registered or not needed
      }

      // Listen to Twilio call events
      print('\n${"=" * 60}');
      print('👂 SETTING UP EVENT LISTENER');
      print('${"=" * 60}');
      print('Listening to: TwilioVoice.instance.callEventsListener');
      _callEventsSubscription = TwilioVoice.instance.callEventsListener.listen(
        _handleTwilioEvent,
        onError: (error) {
          print('\n${"=" * 60}');
          print('❌ TWILIO EVENT LISTENER ERROR');
          print('${"=" * 60}');
          print('Error: $error');
          print('Error type: ${error.runtimeType}');
          print('${"=" * 60}\n');
        },
      );
      print('✅ Event listener set up successfully');
      print('   Will log all Twilio events (ringing, connected, etc.)');
      print('${"=" * 60}\n');
    } catch (e) {
      print('Error initializing Twilio: $e');
      rethrow;
    }
  }

  /// Handle Twilio call events
  void _handleTwilioEvent(dynamic event) {
    print('\n${"=" * 60}');
    print('📡 TWILIO EVENT RECEIVED');
    print('${"=" * 60}');
    print('Timestamp: ${DateTime.now().toIso8601String()}');
    print('Event: $event');
    print('Event type: ${event.runtimeType}');

    // Handle CallEvent objects (they have a 'name' property)
    if (event is CallEvent) {
      final eventName = event.name;
      print('CallEvent name: $eventName');

      switch (eventName) {
        case 'incoming':
          print('→ Handling incoming call');
          // CallEvent doesn't have 'from' field, so pass empty string
          // The data endpoint fetch will get the actual number
          _handleIncomingCall({'from': '', 'callSid': ''});
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
      print('⚠️  Event is not a Map or CallEvent, it is: ${event.runtimeType}');
      print('Event toString: ${event.toString()}');
    }
    print('${"=" * 60}\n');
  }

  /// Handle incoming Twilio call
  void _handleIncomingCall(Map<String, dynamic> event) {
    // Start with empty string - we'll fetch from data endpoint
    final from = event['from'] as String? ?? '';
    final callSid = event['callSid'] as String? ?? '';

    // Extract caller info from TwiML parameters if available
    final params = event['parameters'] as Map<String, dynamic>?;
    final callerName = params?['__TWI_CALLER_NAME'] as String? ?? from;

    // Use phone number as contact name if no caller name is available
    // callerName is never null due to null-coalescing, so check if it's different from 'from'
    final effectiveContactName = (callerName.isNotEmpty && callerName != from)
        ? callerName
        : (from.isNotEmpty ? from : null);
    
    // If we don't have a number yet, fetch it immediately before creating CallInfo
    // This ensures we show the actual number right away
    if (from.isEmpty) {
      // Fetch the number synchronously if possible, or at least start the fetch
      _backendService.getCurrentFromNumber().then((fromNumber) {
        if (fromNumber != null && fromNumber.isNotEmpty && _currentCall != null) {
          // Use phone number as contact name if no name is available
          final effectiveContactName = (_currentCall!.contactName != null && 
              _currentCall!.contactName!.isNotEmpty &&
              _currentCall!.contactName != _currentCall!.phoneNumber)
              ? _currentCall!.contactName
              : fromNumber;
          
          _currentCall = CallInfo(
            id: _currentCall!.id,
            phoneNumber: fromNumber,
            contactName: effectiveContactName,
            timestamp: _currentCall!.timestamp,
            type: _currentCall!.type,
            status: _currentCall!.status,
            isScam: _currentCall!.isScam,
          );
          _callController.add(_currentCall!);
        }
      });
    }
    
    final callInfo = CallInfo(
      id: callSid.isNotEmpty
          ? callSid
          : DateTime.now().millisecondsSinceEpoch.toString(),
      phoneNumber: from.isNotEmpty ? from : '', // Empty string, will be updated by fetch
      contactName: effectiveContactName,
      timestamp: DateTime.now(),
      type: CallType.incoming,
      status: CallStatus.ringing,
    );

    _currentCall = callInfo;
    _callController.add(callInfo);

    // Start ringtone for incoming call
    _alertService.startRingtone();

    // Always try to fetch the caller number from the public data endpoint and update
    // This ensures we get the number even if 'from' was provided but might be wrong
    _backendService.getCurrentFromNumber().then((fromNumber) {
      try {
        if (fromNumber != null &&
            fromNumber.isNotEmpty &&
            _currentCall != null &&
            _currentCall!.id == callInfo.id &&
            _currentCall!.phoneNumber != fromNumber) {
          // Use phone number as contact name if no name is available
          final effectiveContactName = (_currentCall!.contactName != null && 
              _currentCall!.contactName!.isNotEmpty &&
              _currentCall!.contactName != _currentCall!.phoneNumber)
              ? _currentCall!.contactName
              : fromNumber;
          
          _currentCall = CallInfo(
            id: _currentCall!.id,
            phoneNumber: fromNumber,
            contactName: effectiveContactName,
            timestamp: _currentCall!.timestamp,
            type: _currentCall!.type,
            status: _currentCall!.status,
            isScam: _currentCall!.isScam,
          );
          _callController.add(_currentCall!);
        }
      } catch (e) {
        print('Error updating call with fetched from_number: $e');
      }
    });

    // Start analyzing call for scam
    _analyzeCallForScam(callInfo);
  }

  /// Handle call connected (answered)
  void _handleCallConnected() {
    _isPlacingCall = false; // Call is now connected, not placing anymore
    if (_currentCall != null) {
      // Stop ringtone when call connects
      _alertService.stopRingtone();

      // Try to fetch the caller number if we don't have it yet
      final currentNumber = _currentCall!.phoneNumber;
      if (currentNumber.isEmpty || currentNumber == 'Incoming Call') {
        _backendService.getCurrentFromNumber().then((fromNumber) {
          if (fromNumber != null &&
              fromNumber.isNotEmpty &&
              _currentCall != null &&
              _currentCall!.status == CallStatus.answered &&
              _currentCall!.phoneNumber != fromNumber) {
            // Use phone number as contact name if no name is available
            final effectiveContactName = (_currentCall!.contactName != null && 
                _currentCall!.contactName!.isNotEmpty &&
                _currentCall!.contactName != _currentCall!.phoneNumber)
                ? _currentCall!.contactName
                : fromNumber;
            
            _currentCall = CallInfo(
              id: _currentCall!.id,
              phoneNumber: fromNumber,
              contactName: effectiveContactName,
              timestamp: _currentCall!.timestamp,
              type: _currentCall!.type,
              status: _currentCall!.status,
              isScam: _currentCall!.isScam,
            );
            _callController.add(_currentCall!);
          }
        });
      }

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

      // Get user identity from backend service (stored when we got the access token)
      // According to Twilio docs: 'from' should be "your own identifier" (the identity from access token)
      final userId =
          _backendService.currentIdentity ??
          '123'; // Fallback to '123' if not available

      if (_backendService.currentIdentity == null) {
        print(
          '⚠️ Warning: No identity stored from access token, using fallback: $userId',
        );
      } else {
        print('✅ Using identity from access token: $userId');
      }

      print('Making HTTP request to /voice-sdk endpoint...');
      print('Conference name: $conferenceName');

      // Make POST request to /voice-sdk with conference_name and action
      // final response = await _backendService.makeRequestToVoiceSdk(
      //   conferenceName: conferenceName,
      //   action: 'join_conference',
      //   userId: userId,
      // );

      // print('Response from /voice-sdk: $response');
      // print('Response type: ${response.runtimeType}');

      // Now make the actual Twilio call to join the conference
      // Strategy: Use the conference name directly as the 'to' parameter
      // The TwiML App will route this to /voice-sdk endpoint
      // Backend will use the 'To' parameter as the conference name

      print('\n${"=" * 60}');
      print('📞 PLACING TWILIO CALL TO JOIN CONFERENCE');
      print('${"=" * 60}');
      print('Conference Name: $conferenceName');
      print('User Identity: $userId');
      print('From: $userId (will be sent as "client:$userId")');
      print('To: $conferenceName');
      print(
        'Extra Options: {conference_name: $conferenceName, action: join_conference}',
      );
      print('${"=" * 60}\n');

      _isPlacingCall = true; // Mark that we're placing a call
      try {
        // PRE-FLIGHT CHECKS
        print('\n${"=" * 60}');
        print('🔍 PRE-FLIGHT CHECKS');
        print('${"=" * 60}');

        // CRITICAL: Ensure phone account is registered before placing call
        print('📱 Checking phone account registration...');
        try {
          final isEnabled = await TwilioVoice.instance.isPhoneAccountEnabled();
          print('   Phone account enabled: $isEnabled');

          if (!isEnabled) {
            print(
              '   ⚠️  Phone account not enabled - attempting to register...',
            );
            try {
              await TwilioVoice.instance.registerPhoneAccount();
              print('   ✅ Phone account registered');

              // Check again after registration
              final isEnabledNow = await TwilioVoice.instance
                  .isPhoneAccountEnabled();
              print('   Phone account enabled now: $isEnabledNow');

              if (!isEnabledNow) {
                print(
                  '   ❌ Phone account still not enabled after registration!',
                );
                print(
                  '   Attempting to open phone account settings for user...',
                );

                // Try to open phone account settings
                bool settingsOpened = false;
                try {
                  await TwilioVoice.instance.openPhoneAccountSettings();
                  settingsOpened = true;
                  print('   ✅ Opened phone account settings');
                  print(
                    '   ⚠️  User must enable the phone account in settings',
                  );
                  print('   ⚠️  After enabling, try answering the call again');

                  // Emit error to stream for UI to handle
                  _phoneAccountErrorController.add(
                    'Phone account needs to be enabled. Settings have been opened. '
                    'Please enable the phone account and try again.',
                  );
                } catch (settingsError) {
                  print('   ⚠️  Could not open settings: $settingsError');
                  print('   User must manually enable phone account in:');
                  print(
                    '   Settings → Apps → Your App → Default apps → Phone app',
                  );

                  // Emit error to stream for UI to handle
                  _phoneAccountErrorController.add(
                    'Phone account not enabled. Please go to:\n'
                    'Settings → Apps → Your App → Default apps → Phone app\n'
                    'Enable the phone account, then try again.',
                  );
                }

                // Throw custom exception with context
                throw PhoneAccountNotEnabledException(
                  'Phone account not enabled. ${settingsOpened ? "Settings have been opened. " : ""}'
                  'Please enable it in Android settings and try again.',
                  settingsOpened: settingsOpened,
                );
              }
            } catch (e) {
              print('   ❌ Failed to register phone account: $e');
              // If it's already our custom exception, rethrow it
              if (e is PhoneAccountNotEnabledException) {
                rethrow;
              }
              throw Exception(
                'Cannot place call: Phone account registration failed: $e',
              );
            }
          } else {
            print('   ✅ Phone account is already enabled');
          }
        } catch (e) {
          print('   ❌ Phone account check failed: $e');
          rethrow; // Don't proceed if phone account isn't ready
        }

        // Check if SDK is initialized
        try {
          final isOnCall = await TwilioVoice.instance.call.isOnCall();
          print('📞 Is currently on call: $isOnCall');
        } catch (e) {
          print('⚠️  Could not check call status: $e');
        }

        // Check active call
        try {
          final activeCall = TwilioVoice.instance.call.activeCall;
          print('📞 Active call: $activeCall');
        } catch (e) {
          print('⚠️  Could not get active call: $e');
        }

        // Check call SID (if any)
        try {
          final callSid = await TwilioVoice.instance.call.getSid();
          print('📞 Current call SID: ${callSid ?? "None"}');
        } catch (e) {
          print('⚠️  Could not get call SID: $e');
        }

        print('${"=" * 60}\n');

        // Using place() method - more reliable on Android
        // connect() on Android internally calls placeCall() and has issues extracting 'To' from extraOptions
        print('📞 CALLING TwilioVoice.instance.call.place()...');
        print('   Parameters:');
        print('     from: "$userId" (SDK will add "client:" prefix)');
        print('     to: "$conferenceName"');
        print(
          '     extraOptions: {conference_name: "$conferenceName", action: "join_conference"}',
        );
        print('   Timestamp: ${DateTime.now().toIso8601String()}');

        final placeResult = await TwilioVoice.instance.call.place(
          from: userId, // SDK automatically adds "client:" prefix
          to: conferenceName, // Conference room name
          extraOptions: {
            // Custom parameters for backend
            // Note: These may or may not pass through reliably, but backend should use 'To' parameter
            'conference_name': conferenceName,
            'action': 'join_conference',
          },
        );

        print('\n${"=" * 60}');
        print('✅ place() CALL COMPLETED');
        print('${"=" * 60}');
        print('Return value: $placeResult');
        print('Return type: ${placeResult.runtimeType}');

        // Check if call was actually placed
        if (placeResult == false) {
          print('\n❌ CRITICAL: place() returned false - call was NOT placed!');
          print('This usually means:');
          print('  1. Phone account not registered/enabled');
          print('  2. Missing permissions (CALL_PHONE, MANAGE_OWN_CALLS)');
          print('  3. Invalid access token');
          print('  4. Network connectivity issue');
          throw Exception(
            'Failed to place call: place() returned false. Check phone account registration and permissions.',
          );
        }

        print('${"=" * 60}\n');

        // POST-PLACEMENT CHECKS
        print('${"=" * 60}');
        print('🔍 POST-PLACEMENT CHECKS');
        print('${"=" * 60}');

        // Wait a moment for call to initialize
        await Future.delayed(const Duration(milliseconds: 500));

        try {
          final isOnCallNow = await TwilioVoice.instance.call.isOnCall();
          print('📞 Is now on call: $isOnCallNow');
        } catch (e) {
          print('⚠️  Could not check call status: $e');
        }

        try {
          final callSidNow = await TwilioVoice.instance.call.getSid();
          print('📞 Call SID now: ${callSidNow ?? "None"}');
          if (callSidNow != null) {
            print('   ✅ Call was created! SID: $callSidNow');
          } else {
            print('   ⚠️  No call SID yet - call may not have been created');
          }
        } catch (e) {
          print('⚠️  Could not get call SID: $e');
        }

        try {
          final activeCallNow = TwilioVoice.instance.call.activeCall;
          print('📞 Active call now: $activeCallNow');
        } catch (e) {
          print('⚠️  Could not get active call: $e');
        }

        print('${"=" * 60}\n');

        print('${"=" * 60}');
        print('✅ TWILIO CALL PLACED SUCCESSFULLY');
        print('${"=" * 60}');
        print('Method: place()');
        print('From: $userId (SDK will send as "client:$userId")');
        print('To: $conferenceName');
        print('Extra Options:');
        print('  - conference_name: $conferenceName');
        print('  - action: join_conference');
        print('Expected flow:');
        print('  1. Twilio receives call from client:$userId');
        print('  2. Twilio looks up TwiML App from access token');
        print('  3. Twilio POSTs to /voice-sdk with:');
        print('     - From: client:$userId');
        print('     - To: $conferenceName (backend should use this!)');
        print('  4. Backend returns TwiML with <Conference>');
        print('  5. Twilio joins user to conference');
        print('${"=" * 60}\n');

        print('⏳ Waiting for Twilio events (ringing, connected, etc.)...');
        print('   If backend is not receiving requests, check:');
        print('   1. TwiML App Voice URL in Twilio Console');
        print('   2. Access token includes outgoing.application_sid');
        print('   3. Twilio Console → Monitor → Logs for call attempts');

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
          // Try to fetch the caller number from the data endpoint
          String? fetchedFrom;
          try {
            fetchedFrom = await _backendService.getCurrentFromNumber();
          } catch (e) {
            print('Error fetching from_number for room call: $e');
          }
          
          final callInfo = CallInfo(
            id: roomId,
            phoneNumber: fetchedFrom ?? 'Incoming Call',
            contactName: fetchedFrom, // Use phone number as contact name if no name available
            timestamp: DateTime.now(),
            type: CallType.incoming,
            status: CallStatus.answered, // Mark as answered so UI updates
          );
          _currentCall = callInfo;
          _callController.add(callInfo);
        }
      } catch (e, stackTrace) {
        print('\n${"=" * 60}');
        print('❌ ERROR PLACING TWILIO CALL');
        print('${"=" * 60}');
        print('Method: place()');
        print('Error: $e');
        print('Error Type: ${e.runtimeType}');
        print('Stack Trace: $stackTrace');
        print('${"=" * 60}');

        // Analyze error type
        final errorStr = e.toString().toLowerCase();
        if (e is PhoneAccountNotEnabledException) {
          print('⚠️  DIAGNOSIS: Phone Account Not Enabled');
          print('   - Phone account is registered but not enabled');
          print(
            '   - Android requires manual user action to enable phone accounts',
          );
          if (e.settingsOpened) {
            print('   - ✅ Settings have been opened automatically');
            print(
              '   - Please enable the phone account in the settings screen',
            );
          } else {
            print('   - ⚠️  Could not open settings automatically');
            print(
              '   - Please go to: Settings → Apps → Your App → Default apps → Phone app',
            );
          }
          print('   - After enabling, try answering the call again');
        } else if (errorStr.contains('phone account') ||
            errorStr.contains('phoneaccount')) {
          print('⚠️  DIAGNOSIS: Phone Account Not Enabled');
          print('   - Phone account is registered but not enabled');
          print(
            '   - Android requires manual user action to enable phone accounts',
          );
          print('   - Settings should have opened automatically');
          print(
            '   - If not, go to: Settings → Apps → Your App → Default apps → Phone app',
          );
          print(
            '   - Enable the phone account, then try answering the call again',
          );
        } else if (errorStr.contains('token') || errorStr.contains('auth')) {
          print('⚠️  DIAGNOSIS: Access token issue');
          print('   - Token may be missing, expired, or invalid');
          print('   - Check backend /get-access-token endpoint');
          print('   - Verify TWILIO_TWIML_APP_SID is set in backend');
        } else if (errorStr.contains('permission')) {
          print('⚠️  DIAGNOSIS: Permission issue');
          print('   - Check CALL_PHONE permission');
          print('   - Check MANAGE_OWN_CALLS permission');
          print('   - Check phone account is registered and enabled');
        } else if (errorStr.contains('twiml') || errorStr.contains('app')) {
          print('⚠️  DIAGNOSIS: TwiML App configuration issue');
          print('   - Verify TwiML App SID in backend environment variables');
          print('   - Check TwiML App Voice URL in Twilio Console');
        } else if (errorStr.contains('network') ||
            errorStr.contains('connection')) {
          print('⚠️  DIAGNOSIS: Network issue');
          print('   - Check internet connectivity');
          print('   - Verify backend is accessible');
        } else {
          print('⚠️  DIAGNOSIS: Unknown error');
          print('   - Check Twilio Console → Monitor → Logs');
          print('   - Check backend logs for /voice-sdk calls');
        }
        print('${"=" * 60}\n');

        // Fallback: Update status anyway
        if (_currentCall != null &&
            _currentCall!.status == CallStatus.ringing) {
          _handleCallConnected();
        } else if (_currentCall == null) {
          // Try to fetch the caller number from the data endpoint
          String? fetchedFrom;
          try {
            fetchedFrom = await _backendService.getCurrentFromNumber();
          } catch (e) {
            print('Error fetching from_number for room call fallback: $e');
          }
          
          final callInfo = CallInfo(
            id: roomId,
            phoneNumber: fetchedFrom ?? 'Incoming Call',
            contactName: fetchedFrom, // Use phone number as contact name if no name available
            timestamp: DateTime.now(),
            type: CallType.incoming,
            status: CallStatus.answered,
          );
          _currentCall = callInfo;
          _callController.add(callInfo);
        }
        rethrow;
      } finally {
        // Reset flag after a short delay to allow call to initialize
        Future.delayed(const Duration(seconds: 2), () {
          _isPlacingCall = false;
        });
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
    _phoneAccountErrorController.close();
  }
}
