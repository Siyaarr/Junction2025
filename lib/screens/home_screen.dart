import 'dart:async';
import 'package:flutter/material.dart';
import 'package:junction_flutter_1/models/call_info.dart';
import 'package:provider/provider.dart';
import '../providers/call_provider.dart';
import '../widgets/call_overlay_manager.dart';
import '../widgets/animated_phone_icon.dart';
import '../services/backend_service.dart';
// import '../services/background_polling_service.dart';  // Disabled - workmanager has build errors
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isInitialized = false;
  bool _isInitializing = false;
  String? _initError;
  Timer? _roomPollTimer;
  String? _currentRoomId;
  final BackendService _backendService = BackendService();

  @override
  void initState() {
    super.initState();
    // Initialize immediately - Android will prompt for permissions when needed
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    if (_isInitialized || _isInitializing) return;

    setState(() {
      _isInitializing = true;
      _initError = null;
    });

    try {
      final callProvider = Provider.of<CallProvider>(context, listen: false);

      // Get Twilio access token from backend
      final accessToken = await _backendService.getTwilioAccessToken();
      print('Access token obtained, initializing SDK...');

      // Initialize Twilio with access token (no device token needed)
      await callProvider.initializeTwilio(
        accessToken: accessToken,
        deviceToken: null,
      );

      // Listen to call events
      callProvider.addListener(_handleCallUpdate);

      setState(() {
        _isInitialized = true;
        _isInitializing = false;
      });

      // Start polling /room endpoint every second for incoming calls (foreground)
      _startRoomPolling();

      // Also start background polling (runs when app is in background)
      // Currently disabled - using FCM push notifications instead
      // final bgPollingStarted = await BackgroundPollingService.startPolling();
      // if (!bgPollingStarted) {
      //   print(
      //     'Note: Background polling not started. Foreground polling is still active.',
      //   );
      // }
    } catch (e) {
      setState(() {
        _isInitializing = false;
        _initError = e.toString();
      });
      print('Error initializing app: $e');
    }
  }

  void _startRoomPolling() {
    // Stop any existing timer
    _stopRoomPolling();

    // Poll every second for incoming calls
    _roomPollTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }

      try {
        final roomId = await _backendService.checkForIncomingCall();

        if (roomId != null && roomId != _currentRoomId) {
          // New incoming call detected
          _currentRoomId = roomId;
          print('Incoming call detected with room ID: $roomId');

          // Create CallInfo for the incoming call
          // Try to fetch the latest caller number from the data endpoint
          final fetchedFrom =
              await _backendService.getCurrentFromNumber().catchError((_) => null);

          final callInfo = CallInfo(
            id: roomId,
            phoneNumber: fetchedFrom ?? 'Incoming Call',
            contactName: 'Unknown Caller',
            timestamp: DateTime.now(),
            type: CallType.incoming,
            status: CallStatus.ringing,
          );

          // Show incoming call overlay (this will start the ringtone)
          if (mounted) {
            final callProvider = Provider.of<CallProvider>(
              context,
              listen: false,
            );
            CallOverlayManager.showIncomingCall(
              context: context,
              callInfo: callInfo,
              onAnswer: () {
                // Ringtone will be stopped by CallOverlayManager
                // Pass roomId so call service can update status correctly
                callProvider.answerCall(roomId: roomId);
                // Don't reset roomId here - let it be cleared when call ends
              },
              onDecline: () {
                // Ringtone will be stopped by CallOverlayManager
                callProvider.declineCall();
                _currentRoomId = null; // Reset after declining
              },
            );
          }
        } else if (roomId != null && roomId == _currentRoomId) {
          // Same call still active - ringtone should continue playing
          // CallOverlayManager will handle keeping ringtone playing
          // No action needed here
        } else if (roomId == null && _currentRoomId != null) {
          // Call ended or caller stopped the call - stop ringtone and hide overlay
          print('Call ended - room ID cleared');
          _currentRoomId = null;
          if (mounted) {
            // Clear the call from provider as well
            final callProvider = Provider.of<CallProvider>(
              context,
              listen: false,
            );
            callProvider
                .declineCall(); // This will update call status and clear it
            CallOverlayManager.hideOverlay(); // This will stop the ringtone
          }
        }
      } catch (e) {
        print('Error polling for incoming calls: $e');
      }
    });
  }

  void _stopRoomPolling() {
    _roomPollTimer?.cancel();
    _roomPollTimer = null;
  }

  void _handleCallUpdate() {
    final callProvider = Provider.of<CallProvider>(context, listen: false);
    final currentCall = callProvider.currentCall;

    if (currentCall == null) {
      // No call - hide overlay
      CallOverlayManager.hideOverlay();
      return;
    }

    // Show appropriate overlay based on call status
    switch (currentCall.status) {
      case CallStatus.ringing:
        // Show incoming call overlay
        CallOverlayManager.showIncomingCall(
          context: context,
          callInfo: currentCall,
          onAnswer: () => callProvider.answerCall(),
          onDecline: () => callProvider.declineCall(),
        );
        break;

      case CallStatus.answered:
        // Show ongoing call overlay
        CallOverlayManager.showOngoingCall(
          context: context,
          callInfo: currentCall,
          onHangup: () => callProvider.declineCall(),
          // TODO: Add mute/speaker callbacks when implemented
        );
        break;

      case CallStatus.declined:
      case CallStatus.ended:
      case CallStatus.missed:
        // Hide overlay when call ends
        CallOverlayManager.hideOverlay();
        break;
    }
  }

  @override
  void dispose() {
    _stopRoomPolling();
    // Note: We keep background polling running even when screen is disposed
    // This ensures calls can be detected when app is in background
    final callProvider = Provider.of<CallProvider>(context, listen: false);
    callProvider.removeListener(_handleCallUpdate);
    CallOverlayManager.hideOverlay();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[900],
      appBar: AppBar(
        title: Image.asset('assets/images/logo.png', height: 28),
        backgroundColor: Colors.grey[850],
        elevation: 0,
        actions: [
          // Connection status indicator
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _isInitialized
                        ? Colors.green
                        : (_initError != null ? Colors.red : Colors.orange),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _isInitialized
                      ? 'Connected'
                      : (_initError != null ? 'Disconnected' : 'Connecting...'),
                  style: TextStyle(fontSize: 12, color: Colors.grey[300]),
                ),
              ],
            ),
          ),
          // Settings button
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
            tooltip: 'Settings',
          ),
        ],
      ),
      body: _buildMainContent(),
    );
  }

  Widget _buildMainContent() {
    return Consumer<CallProvider>(
      builder: (context, callProvider, child) {
        // Extract a user-friendly error message
        String? errorMessage;
        if (_initError != null) {
          if (_initError!.contains('endpoint not found') ||
              _initError!.contains('404')) {
            errorMessage =
                'Protection service is being set up. '
                'Please wait a moment and try again.';
          } else if (_initError!.contains('redirect') ||
              _initError!.contains('302')) {
            errorMessage =
                'Backend configuration issue. '
                'The API URL may be incorrect or the server is redirecting.';
          } else if (_initError!.contains('Failed to get access token')) {
            errorMessage =
                'Unable to connect to backend. '
                'Please check your internet connection and ensure the backend is running.';
          } else {
            errorMessage =
                'Initialization error: ${_initError!.split(':').first}';
          }
        }

        return Column(
          children: [
            // Error banner (non-blocking)
            if (errorMessage != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange[900],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning, color: Colors.white, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        errorMessage,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: _initializeApp,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'Retry',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Loading indicator (only show if initializing and no error)
            if (_isInitializing && errorMessage == null)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 12),
                    Text(
                      'Setting up protection...',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ],
                ),
              ),

            // Main content
            Expanded(
              child: Column(
                children: [
                  // Scam alert indicator
                  if (callProvider.isScamAlertActive)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red[900],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.warning, color: Colors.white, size: 32),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'SCAM ALERT ACTIVE',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  const Spacer(),

                  // Info section with animations
                  Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      children: [
                        AnimatedPhoneIcon(
                          size: 64,
                          color: Colors.blue,
                          isActive: _isInitialized,
                        ),
                        const SizedBox(height: 16),
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0.0, end: 1.0),
                          duration: const Duration(milliseconds: 800),
                          curve: Curves.easeOut,
                          builder: (context, value, child) {
                            return Opacity(
                              opacity: value,
                              child: Transform.translate(
                                offset: Offset(0, 20 * (1 - value)),
                                child: child,
                              ),
                            );
                          },
                          child: const Text(
                            'You\'re Protected',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0.0, end: 1.0),
                          duration: const Duration(milliseconds: 1000),
                          curve: Curves.easeOut,
                          builder: (context, value, child) {
                            return Opacity(
                              opacity: value,
                              child: Transform.translate(
                                offset: Offset(0, 20 * (1 - value)),
                                child: child,
                              ),
                            );
                          },
                          child: Text(
                            'Our AI system analyzes incoming calls in real-time to detect potential scams. '
                            'If a suspicious call is detected, you\'ll receive an immediate alert and warning.',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[400],
                              height: 1.4,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Spacer(),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
