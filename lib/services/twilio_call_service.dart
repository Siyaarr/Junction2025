import 'dart:async';
import 'package:twilio_voice/twilio_voice.dart';
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
    print('Twilio event: $event');

    if (event is Map) {
      final eventType = event['event'] as String?;

      switch (eventType) {
        case 'incoming':
          _handleIncomingCall(event as Map<String, String>);
          break;
        case 'ringing':
          // Call is ringing
          break;
        case 'connected':
          _handleCallConnected();
          break;
        case 'callEnded':
        case 'declined':
        case 'missedCall':
          _handleCallEnded();
          break;
        default:
          break;
      }
    }
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

  /// Answer incoming Twilio call
  Future<void> answerCall() async {
    try {
      print('Answering call...');

      // Answer the call using Twilio SDK
      await TwilioVoice.instance.call.answer();
      print('Call answered successfully');

      // Update call status - the 'connected' event will also fire
      // but we update immediately for better UX
      if (_currentCall != null && _currentCall!.status == CallStatus.ringing) {
        _handleCallConnected();
      }
    } catch (e) {
      print('Error answering call: $e');
      rethrow;
    }
  }

  /// Decline incoming Twilio call (hangup)
  Future<void> declineCall() async {
    try {
      print('Declining call...');

      // Hang up the call using Twilio SDK
      await TwilioVoice.instance.call.hangUp();
      print('Call declined successfully');

      // Update call status - the 'callEnded' event will also fire
      // but we update immediately for better UX
      if (_currentCall != null) {
        // Stop any ongoing sounds
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
    } catch (e) {
      print('Error declining call: $e');
      // Even if hangup fails, update UI state to ensure UI is consistent
      if (_currentCall != null) {
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
      // Don't rethrow - we've handled the UI state, let the event handler deal with it
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
