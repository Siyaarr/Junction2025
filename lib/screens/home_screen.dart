import 'package:flutter/material.dart';
import 'package:junction_flutter_1/models/call_info.dart';
import 'package:provider/provider.dart';
import '../providers/call_provider.dart';
import '../widgets/call_overlay_manager.dart';
import '../services/backend_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isInitialized = false;
  bool _isInitializing = false;
  String? _initError;

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
      final backendService = BackendService();

      // Get Twilio access token from backend
      final accessToken = await backendService.getTwilioAccessToken();

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
    } catch (e) {
      setState(() {
        _isInitializing = false;
        _initError = e.toString();
      });
      print('Error initializing app: $e');
    }
  }

  void _handleCallUpdate() {
    final callProvider = Provider.of<CallProvider>(context, listen: false);
    final currentCall = callProvider.currentCall;

    if (currentCall != null && currentCall.status == CallStatus.ringing) {
      // Show incoming call overlay
      CallOverlayManager.showIncomingCall(
        context: context,
        callInfo: currentCall,
        onAnswer: () => callProvider.answerCall(),
        onDecline: () => callProvider.declineCall(),
      );
    } else if (currentCall == null ||
        currentCall.status != CallStatus.ringing) {
      // Hide overlay when call ends or is answered
      CallOverlayManager.hideOverlay();
    }
  }

  @override
  void dispose() {
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
        title: const Text('Anti-Scam Protection'),
        backgroundColor: Colors.grey[850],
        elevation: 0,
      ),
      body: _buildMainContent(),
    );
  }

  Widget _buildMainContent() {
    return Consumer<CallProvider>(
      builder: (context, callProvider, child) {
        if (_isInitializing) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text(
                  'Initializing Twilio...',
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
          );
        }

        if (_initError != null) {
          // Extract a user-friendly error message
          String errorMessage = _initError!;
          if (errorMessage.contains('endpoint not found') ||
              errorMessage.contains('404')) {
            errorMessage =
                'Backend API endpoint not available yet.\n\n'
                'The Twilio access token endpoint is being set up.\n'
                'Please wait for the backend to be deployed.';
          } else if (errorMessage.contains('redirect') ||
              errorMessage.contains('302')) {
            errorMessage =
                'Backend configuration issue.\n\n'
                'The API URL may be incorrect or the server is redirecting.';
          } else if (errorMessage.contains('Failed to get access token')) {
            errorMessage =
                'Unable to connect to backend.\n\n'
                'Please check your internet connection and ensure the backend is running.';
          }

          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  const Text(
                    'Initialization Error',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    errorMessage,
                    style: const TextStyle(color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _initializeApp,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }

        return Column(
          children: [
            // Status card
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: _isInitialized ? Colors.green : Colors.orange,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isInitialized
                              ? 'Ready to Receive Calls'
                              : 'Initializing...',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _isInitialized
                              ? 'Waiting for incoming calls via Twilio'
                              : 'Please wait...',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[400],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

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

            // Info section
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  const Icon(Icons.phone_in_talk, size: 64, color: Colors.blue),
                  const SizedBox(height: 16),
                  const Text(
                    'Ready to receive calls',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Calls will be received via Twilio. The app will alert you if a scam is detected.',
                    style: TextStyle(fontSize: 14, color: Colors.grey[400]),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

            const Spacer(),
          ],
        );
      },
    );
  }
}
