import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static const String _trustedPersonPhoneKey = 'trusted_person_phone';

  /// Get the saved trusted person phone number
  Future<String?> getTrustedPersonPhone() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_trustedPersonPhoneKey);
    } catch (e) {
      print('Error getting trusted person phone: $e');
      return null;
    }
  }

  /// Save the trusted person phone number
  Future<bool> saveTrustedPersonPhone(String phoneNumber) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.setString(_trustedPersonPhoneKey, phoneNumber);
    } catch (e) {
      print('Error saving trusted person phone: $e');
      return false;
    }
  }

  /// Clear the trusted person phone number
  Future<bool> clearTrustedPersonPhone() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.remove(_trustedPersonPhoneKey);
    } catch (e) {
      print('Error clearing trusted person phone: $e');
      return false;
    }
  }

  /// Validate phone number format (basic validation)
  /// Returns true if valid, false otherwise
  bool isValidPhoneNumber(String phoneNumber) {
    // Remove all non-digit characters for validation
    final digitsOnly = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');

    // Basic validation: should have at least 10 digits or start with +
    // Allow formats like: +1234567890, 1234567890, etc.
    if (digitsOnly.startsWith('+')) {
      return digitsOnly.length >= 11; // +country code + number
    }
    return digitsOnly.length >= 10; // At least 10 digits
  }

  /// Format phone number for display
  String formatPhoneNumber(String phoneNumber) {
    // Remove all non-digit characters except +
    final cleaned = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');
    return cleaned;
  }
}
