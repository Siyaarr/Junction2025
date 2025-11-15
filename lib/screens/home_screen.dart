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
  Timer? _reminderPollTimer;
  String? _currentRoomId;
  final BackendService _backendService = BackendService();
  List<Map<String, dynamic>> _reminders = [];
  final Set<String> _completedReminders = {}; // Track completed reminders by unique ID

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
      
      // Start polling for reminders
      _startReminderPolling();

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
            contactName: fetchedFrom, // Use phone number as contact name if no name available
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
                // Refetch reminders after call ends
                _fetchReminders();
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
            // Refetch reminders after call ends
            _fetchReminders();
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

  void _startReminderPolling() {
    // Stop any existing timer
    _stopReminderPolling();
    
    // Fetch immediately
    _fetchReminders();

    // Poll every 30 seconds for reminders
    _reminderPollTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      _fetchReminders();
    });
  }

  void _stopReminderPolling() {
    _reminderPollTimer?.cancel();
    _reminderPollTimer = null;
  }

  Future<void> _fetchReminders() async {
    try {
      final reminders = await _backendService.getReminders();
      if (mounted) {
        setState(() {
          _reminders = reminders;
        });
      }
    } catch (e) {
      print('Error fetching reminders: $e');
    }
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
          onDecline: () {
            callProvider.declineCall();
            // Refetch reminders after declining call
            _fetchReminders();
          },
        );
        break;

      case CallStatus.answered:
        // Show ongoing call overlay
        CallOverlayManager.showOngoingCall(
          context: context,
          callInfo: currentCall,
          onHangup: () {
            callProvider.declineCall();
            // Refetch reminders after hanging up
            _fetchReminders();
          },
          onMute: () => callProvider.toggleMute(!currentCall.isMuted),
          onSpeaker: () => callProvider.toggleSpeaker(!currentCall.isSpeakerOn),
          onCallSafetyContact: () async {
            // Add security contact to the call
            final success = await _backendService.addSecurityContactToCall();
            if (success && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Security contact has been added to the call'),
                  backgroundColor: Colors.green,
                  duration: Duration(seconds: 3),
                ),
              );
            } else if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Failed to add security contact'),
                  backgroundColor: Colors.red,
                  duration: Duration(seconds: 3),
                ),
              );
            }
          },
          isMuted: currentCall.isMuted,
          isSpeakerOn: currentCall.isSpeakerOn,
        );
        break;

      case CallStatus.declined:
      case CallStatus.ended:
      case CallStatus.missed:
        // Hide overlay when call ends
        CallOverlayManager.hideOverlay();
        // Refetch reminders after call ends
        _fetchReminders();
        break;
    }
  }

  @override
  void dispose() {
    _stopRoomPolling();
    _stopReminderPolling();
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
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    // Scam alert indicator
                    if (callProvider.isScamAlertActive)
                      Container(
                        margin: const EdgeInsets.all(16),
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

                    // Reminders section
                    if (_reminders.isNotEmpty) _buildRemindersSection(),

                    const SizedBox(height: 24),

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

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildRemindersSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey[850],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.withOpacity(0.3), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.notifications_active,
                    color: Colors.blue,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Reminders',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_reminders.length}',
                    style: const TextStyle(
                      color: Colors.blue,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Divider
          Divider(color: Colors.grey[800], height: 1),
          
          // Reminder list
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.all(12),
            itemCount: _reminders.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final reminder = _reminders[index];
              return _buildReminderCard(reminder);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildReminderCard(Map<String, dynamic> reminder) {
    final text = reminder['text'] as String? ?? '';
    final timeStr = reminder['time'] as String? ?? '';
    final fromNumber = reminder['from_number'] as String? ?? '';
    final isContact = reminder['is_contact'] as bool? ?? false;
    
    // Create unique ID for this reminder
    final reminderId = '$text-$timeStr';
    final isCompleted = _completedReminders.contains(reminderId);
    
    final reminderTime = DateTime.tryParse(timeStr);
    final now = DateTime.now();
    final isPast = reminderTime != null && reminderTime.isBefore(now);
    final isToday = reminderTime != null && 
        reminderTime.year == now.year &&
        reminderTime.month == now.month &&
        reminderTime.day == now.day;
    
    String formattedTime = '';
    if (reminderTime != null) {
      final hour = reminderTime.hour.toString().padLeft(2, '0');
      final minute = reminderTime.minute.toString().padLeft(2, '0');
      
      if (isToday) {
        formattedTime = 'Today at $hour:$minute';
      } else if (reminderTime.difference(now).inDays == 1) {
        formattedTime = 'Tomorrow at $hour:$minute';
      } else {
        final month = reminderTime.month.toString().padLeft(2, '0');
        final day = reminderTime.day.toString().padLeft(2, '0');
        formattedTime = '$day.$month at $hour:$minute';
      }
    }
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (isPast || isCompleted)
            ? Colors.grey[800]?.withOpacity(0.5)
            : Colors.grey[800],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCompleted
              ? Colors.green.withOpacity(0.5)
              : (isPast 
                  ? Colors.grey[700]!
                  : (isToday ? Colors.orange.withOpacity(0.5) : Colors.blue.withOpacity(0.3))),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Checkbox
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: isCompleted,
                onChanged: (value) {
                  setState(() {
                    if (value == true) {
                      _completedReminders.add(reminderId);
                    } else {
                      _completedReminders.remove(reminderId);
                    }
                  });
                },
                activeColor: Colors.green,
                checkColor: Colors.white,
                side: BorderSide(
                  color: isCompleted
                      ? Colors.green
                      : (isPast ? Colors.grey[600]! : Colors.blue),
                  width: 2,
                ),
              ),
            ),
          ),
          
          const SizedBox(width: 12),
          
          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Time and status
                Row(
                  children: [
                    Icon(
                      isPast ? Icons.history : Icons.schedule,
                      color: isCompleted
                          ? Colors.green
                          : (isPast 
                              ? Colors.grey[500]
                              : (isToday ? Colors.orange : Colors.blue)),
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        formattedTime,
                        style: TextStyle(
                          color: isCompleted
                              ? Colors.green
                              : (isPast ? Colors.grey[500] : Colors.blue),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (isContact)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.person,
                              color: Colors.green,
                              size: 10,
                            ),
                            SizedBox(width: 2),
                            Text(
                              'Contact',
                              style: TextStyle(
                                color: Colors.green,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                
                const SizedBox(height: 8),
                
                // Reminder text
                Text(
                  text,
                  style: TextStyle(
                    color: isCompleted ? Colors.grey[500] : (isPast ? Colors.grey[400] : Colors.white),
                    fontSize: 14,
                    height: 1.3,
                    decoration: isCompleted ? TextDecoration.lineThrough : null,
                  ),
                ),
                
                // From number (if not a contact)
                if (fromNumber.isNotEmpty && !isContact) ...[
                  const SizedBox(height: 6),
                  Text(
                    'From: $fromNumber',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
