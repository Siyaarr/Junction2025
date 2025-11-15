import 'package:permission_handler/permission_handler.dart'
    as permission_handler;
import 'package:flutter/services.dart';
import 'dart:io';

class AppPermissionHandler {
  /// Check if permission handler plugin is available
  /// Returns true if plugin is available, false if MissingPluginException occurs
  static Future<bool> _isPluginAvailable() async {
    try {
      // Try to check a simple permission status to verify plugin is available
      // This will throw MissingPluginException if plugin isn't registered
      await permission_handler.Permission.microphone.status;
      return true;
    } on MissingPluginException {
      return false;
    } catch (e) {
      // Other errors mean plugin is available but permission check had an issue
      // The actual permission methods will handle their own errors
      return true;
    }
  }

  /// Request all necessary permissions
  static Future<
    Map<permission_handler.Permission, permission_handler.PermissionStatus>
  >
  requestAllPermissions() async {
    if (!await _isPluginAvailable()) {
      print('Permission handler plugin not available');
      return <
        permission_handler.Permission,
        permission_handler.PermissionStatus
      >{};
    }

    try {
      final permissions = [
        permission_handler.Permission.phone,
        permission_handler.Permission.notification,
        permission_handler.Permission.systemAlertWindow,
      ];

      final statuses =
          <
            permission_handler.Permission,
            permission_handler.PermissionStatus
          >{};
      for (final permission in permissions) {
        try {
          statuses[permission] = await permission.request();
        } catch (e) {
          print('Error requesting permission $permission: $e');
        }
      }
      return statuses;
    } on MissingPluginException {
      print('Permission handler plugin not available');
      return <
        permission_handler.Permission,
        permission_handler.PermissionStatus
      >{};
    } catch (e) {
      print('Error requesting permissions: $e');
      return <
        permission_handler.Permission,
        permission_handler.PermissionStatus
      >{};
    }
  }

  /// Check if all permissions are granted
  static Future<bool> areAllPermissionsGranted() async {
    if (!await _isPluginAvailable()) {
      // If plugin not available, assume permissions are granted to allow app to continue
      print(
        'Permission handler plugin not available, assuming permissions granted',
      );
      return true;
    }

    try {
      final phoneStatus = await permission_handler.Permission.phone.status;
      final notificationStatus =
          await permission_handler.Permission.notification.status;
      final overlayStatus =
          await permission_handler.Permission.systemAlertWindow.status;

      return phoneStatus.isGranted &&
          notificationStatus.isGranted &&
          overlayStatus.isGranted;
    } on MissingPluginException {
      print(
        'Permission handler plugin not available, assuming permissions granted',
      );
      return true;
    } catch (e) {
      print('Error checking permissions: $e');
      return false;
    }
  }

  /// Request phone permission (used for microphone on some devices)
  static Future<bool> requestPhonePermission() async {
    if (!await _isPluginAvailable()) {
      print('Permission handler plugin not available');
      return false;
    }

    try {
      // For Twilio VoIP, we need microphone permission
      final micStatus = await permission_handler.Permission.microphone
          .request();
      if (micStatus.isGranted) return true;

      // Fallback to phone permission if microphone not available
      final phoneStatus = await permission_handler.Permission.phone.request();
      return phoneStatus.isGranted;
    } on MissingPluginException {
      print('Permission handler plugin not available');
      return false;
    } catch (e) {
      print('Error requesting phone/microphone permission: $e');
      return false;
    }
  }

  /// Request notification permission
  static Future<bool> requestNotificationPermission() async {
    if (!await _isPluginAvailable()) {
      print('Permission handler plugin not available');
      return false;
    }

    try {
      final status = await permission_handler.Permission.notification.request();
      return status.isGranted;
    } on MissingPluginException {
      print('Permission handler plugin not available');
      return false;
    } catch (e) {
      print('Error requesting notification permission: $e');
      return false;
    }
  }

  /// Request overlay permission (for incoming call UI)
  static Future<bool> requestOverlayPermission() async {
    if (!await _isPluginAvailable()) {
      print('Permission handler plugin not available');
      return false;
    }

    try {
      final status = await permission_handler.Permission.systemAlertWindow
          .request();
      return status.isGranted;
    } on MissingPluginException {
      print('Permission handler plugin not available');
      return false;
    } catch (e) {
      print('Error requesting overlay permission: $e');
      return false;
    }
  }

  /// Open app settings
  /// Falls back to platform channel if permission_handler plugin is not available
  static Future<bool> openAppSettings() async {
    // Try permission_handler first
    if (await _isPluginAvailable()) {
      try {
        return await permission_handler.openAppSettings();
      } catch (e) {
        print('Error opening app settings with permission_handler: $e');
        // Fall through to platform channel fallback
      }
    }

    // Fallback: Use platform channel to open Android settings directly
    if (Platform.isAndroid) {
      try {
        const platform = MethodChannel(
          'com.example.junction_flutter_1/settings',
        );
        await platform.invokeMethod('openAppSettings');
        return true;
      } on MissingPluginException {
        print(
          'Platform channel not registered. App needs full rebuild after native code changes.',
        );
        print('Please rebuild the app: flutter clean && flutter run');
        // Return false so UI can show a message
        return false;
      } catch (e) {
        print('Error opening app settings via platform channel: $e');
        return false;
      }
    } else if (Platform.isIOS) {
      // For iOS, try to use permission_handler even if check failed
      try {
        return await permission_handler.openAppSettings();
      } catch (e) {
        print('Error opening iOS app settings: $e');
        return false;
      }
    }

    return false;
  }
}
