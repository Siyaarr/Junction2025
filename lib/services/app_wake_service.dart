import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:io';

/// Service to wake app and bring it to foreground when incoming call detected
class AppWakeService {
  static const MethodChannel _channel = MethodChannel(
    'com.example.junction_flutter_1/app_wake',
  );
  static FlutterLocalNotificationsPlugin? _notifications;

  /// Initialize the wake service
  /// Returns true if initialization succeeded, false otherwise
  static Future<bool> initialize() async {
    try {
      _notifications = FlutterLocalNotificationsPlugin();

      // Android initialization settings
      const androidSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );
      const initializationSettings = InitializationSettings(
        android: androidSettings,
      );

      await _notifications!.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      // Request notification permissions
      if (Platform.isAndroid) {
        final androidPlugin = _notifications!
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        await androidPlugin?.requestNotificationsPermission();

        // Create notification channel for incoming calls
        await androidPlugin?.createNotificationChannel(
          const AndroidNotificationChannel(
            'incoming_call',
            'Incoming Calls',
            description: 'Notifications for incoming calls',
            importance: Importance.high,
            playSound: true,
            enableVibration: true,
          ),
        );
      }
      return true;
    } catch (e) {
      print('Warning: Failed to initialize app wake service: $e');
      print(
        'This is normal if the app needs a full rebuild (flutter clean && flutter run)',
      );
      _notifications = null;
      return false;
    }
  }

  /// Handle notification tap - brings app to foreground
  static void _onNotificationTapped(NotificationResponse response) {
    // App will be brought to foreground automatically
    print('Notification tapped, app should be in foreground');
  }

  /// Wake app and bring to foreground
  /// Shows a full-screen notification on Android that brings the app to foreground
  /// Returns true if successful, false otherwise
  static Future<bool> wakeAppForIncomingCall({
    required String callerName,
    required String phoneNumber,
  }) async {
    try {
      if (Platform.isAndroid) {
        // Use platform channel to bring app to foreground
        try {
          await _channel.invokeMethod('bringToForeground');
        } catch (e) {
          print(
            'Warning: Could not bring app to foreground via platform channel: $e',
          );
          // Continue anyway - notification might still work
        }

        // Also show a high-priority notification that can wake the screen
        await _showWakeNotification(callerName, phoneNumber);
        return true;
      }
      return false;
    } catch (e) {
      print('Error waking app: $e');
      // Try fallback: just show notification
      try {
        await _showWakeNotification(callerName, phoneNumber);
        return true;
      } catch (e2) {
        print('Error showing wake notification: $e2');
        return false;
      }
    }
  }

  /// Show a notification that can wake the app
  static Future<void> _showWakeNotification(
    String callerName,
    String phoneNumber,
  ) async {
    if (_notifications == null) {
      print(
        'Warning: Notifications not initialized, cannot show wake notification',
      );
      return;
    }

    try {
      const androidDetails = AndroidNotificationDetails(
        'incoming_call',
        'Incoming Calls',
        channelDescription: 'Notifications for incoming calls',
        importance: Importance.high,
        priority: Priority.high,
        fullScreenIntent: true, // This wakes the app and shows full-screen
        category: AndroidNotificationCategory.call,
        showWhen: false,
        ongoing: true,
        autoCancel: false,
      );

      const notificationDetails = NotificationDetails(android: androidDetails);

      await _notifications!.show(
        1001, // Unique ID for incoming call notification
        'Incoming Call',
        '$callerName ($phoneNumber)',
        notificationDetails,
      );
    } catch (e) {
      print('Error showing wake notification: $e');
      // Don't rethrow - app should continue working without notification
    }
  }

  /// Cancel the wake notification
  static Future<void> cancelWakeNotification() async {
    try {
      await _notifications?.cancel(1001);
    } catch (e) {
      print('Error canceling wake notification: $e');
      // Don't rethrow - not critical
    }
  }
}
