import 'package:permission_handler/permission_handler.dart'
    as permission_handler;

class AppPermissionHandler {
  /// Request all necessary permissions
  static Future<
    Map<permission_handler.Permission, permission_handler.PermissionStatus>
  >
  requestAllPermissions() async {
    final permissions = [
      permission_handler.Permission.phone,
      permission_handler.Permission.notification,
      permission_handler.Permission.systemAlertWindow,
    ];

    final statuses =
        <permission_handler.Permission, permission_handler.PermissionStatus>{};
    for (final permission in permissions) {
      statuses[permission] = await permission.request();
    }
    return statuses;
  }

  /// Check if all permissions are granted
  static Future<bool> areAllPermissionsGranted() async {
    final phoneStatus = await permission_handler.Permission.phone.status;
    final notificationStatus =
        await permission_handler.Permission.notification.status;
    final overlayStatus =
        await permission_handler.Permission.systemAlertWindow.status;

    return phoneStatus.isGranted &&
        notificationStatus.isGranted &&
        overlayStatus.isGranted;
  }

  /// Request phone permission (used for microphone on some devices)
  static Future<bool> requestPhonePermission() async {
    // For Twilio VoIP, we need microphone permission
    final micStatus = await permission_handler.Permission.microphone.request();
    if (micStatus.isGranted) return true;
    
    // Fallback to phone permission if microphone not available
    final phoneStatus = await permission_handler.Permission.phone.request();
    return phoneStatus.isGranted;
  }

  /// Request notification permission
  static Future<bool> requestNotificationPermission() async {
    final status = await permission_handler.Permission.notification.request();
    return status.isGranted;
  }

  /// Request overlay permission (for incoming call UI)
  static Future<bool> requestOverlayPermission() async {
    final status = await permission_handler.Permission.systemAlertWindow
        .request();
    return status.isGranted;
  }

  /// Open app settings
  static Future<bool> openAppSettings() async {
    return await permission_handler.openAppSettings();
  }
}
