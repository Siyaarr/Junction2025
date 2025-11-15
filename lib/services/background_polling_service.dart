import 'package:workmanager/workmanager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'backend_service.dart';

/// Background service for polling /room endpoint
/// This runs even when the app is in the background or terminated
class BackgroundPollingService {
  static const String taskName = 'roomPollingTask';
  static const String callbackDispatcher = 'roomPollingCallback';

  /// Initialize background polling
  /// Returns true if initialization succeeded, false otherwise
  static Future<bool> initialize() async {
    try {
      await Workmanager().initialize(
        roomPollingCallback,
        isInDebugMode: const bool.fromEnvironment('dart.vm.product') == false,
      );
      return true;
    } catch (e) {
      print('Warning: Failed to initialize background polling: $e');
      print(
        'This is normal if the app needs a full rebuild (flutter clean && flutter run)',
      );
      return false;
    }
  }

  /// Start periodic background polling
  /// Note: Android minimum interval is 15 minutes, iOS is more restrictive
  /// For more frequent polling, we'll use 15 minutes as minimum
  /// In practice, FCM push notifications should be used for real-time call detection
  /// Returns true if polling started successfully, false otherwise
  static Future<bool> startPolling() async {
    try {
      // Cancel any existing task first
      await Workmanager().cancelByUniqueName(taskName);

      // Register periodic task
      // Minimum interval on Android is 15 minutes
      await Workmanager().registerPeriodicTask(
        taskName,
        callbackDispatcher,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingWorkPolicy.replace,
      );
      return true;
    } catch (e) {
      print('Warning: Failed to start background polling: $e');
      print('Background polling will not work until app is fully rebuilt');
      return false;
    }
  }

  /// Stop background polling
  static Future<void> stopPolling() async {
    await Workmanager().cancelByUniqueName(taskName);
  }
}

/// Top-level callback function for workmanager
/// This must be a top-level function, not a class method
@pragma('vm:entry-point')
void roomPollingCallback() {
  Workmanager().executeTask((task, inputData) async {
    try {
      // Get the last known room ID from shared preferences
      final prefs = await SharedPreferences.getInstance();
      final lastRoomId = prefs.getString('last_room_id');

      // Poll the backend
      final backendService = BackendService();
      final roomId = await backendService.checkForIncomingCall();

      // If we got a new room ID, store it
      if (roomId != null && roomId != lastRoomId) {
        await prefs.setString('last_room_id', roomId);

        // Note: We can't directly show UI from background isolate
        // The foreground polling (every 1 second) will catch it when app is active
        // For background detection, we should ideally use FCM push notifications
        // For now, this serves as a fallback
        print('Background: Incoming call detected with room ID: $roomId');

        // TODO: Send local notification to wake app and show incoming call UI
        // This would require flutter_local_notifications integration
      }

      return Future.value(true);
    } catch (e) {
      print('Background polling error: $e');
      return Future.value(false);
    }
  });
}
