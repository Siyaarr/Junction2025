import 'package:flutter/material.dart';
import '../models/call_info.dart';
import '../services/twilio_call_service.dart';

class CallProvider extends ChangeNotifier {
  final TwilioCallService _callService;
  CallInfo? _currentCall;
  bool _isScamAlertActive = false;

  CallProvider({TwilioCallService? callService})
    : _callService = callService ?? TwilioCallService() {
    _initialize();
  }

  CallInfo? get currentCall => _currentCall;
  bool get isScamAlertActive => _isScamAlertActive;

  void _initialize() {
    _callService.callStream.listen((callInfo) {
      _currentCall = callInfo;
      notifyListeners();
    });

    _callService.scamAlertStream.listen((isScam) {
      _isScamAlertActive = isScam;
      notifyListeners();
    });
  }

  /// Initialize Twilio with access token and device token
  Future<void> initializeTwilio({
    required String accessToken,
    String? deviceToken,
  }) async {
    await _callService.initialize(
      accessToken: accessToken,
      deviceToken: deviceToken,
    );
  }

  Future<void> answerCall({String? roomId}) async {
    await _callService.answerCall(roomId: roomId);
  }

  Future<void> declineCall() async {
    await _callService.declineCall();
    _currentCall = null;
    _isScamAlertActive = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _callService.dispose();
    super.dispose();
  }
}
