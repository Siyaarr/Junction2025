// import 'dart:convert';
import 'package:dio/dio.dart';
import '../models/call_info.dart';

class BackendService {
  final Dio _dio;
  final String baseUrl;

  BackendService({String? baseUrl})
    : baseUrl = baseUrl ?? 'https://junction.timohartikainen.fi',
      _dio = Dio(
        BaseOptions(
          baseUrl: baseUrl ?? 'https://junction.timohartikainen.fi',
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
          followRedirects: true,
          validateStatus: (status) {
            // Accept status codes 200-399 (including redirects)
            return status != null && status >= 200 && status < 400;
          },
        ),
      );

  /// Poll /room endpoint to check for incoming calls
  /// Returns room ID if a call is incoming, null if no call
  /// This should be polled every second after SDK initialization
  Future<String?> checkForIncomingCall() async {
    try {
      final response = await _dio.get('/room');
      if (response.statusCode == 200) {
        // If response is empty or null, no call is incoming
        if (response.data == null || response.data == '') {
          return null;
        }

        // Response should be the room ID as a string (e.g., "room-CA02d5f736f5b39f8b66e3a1ac4a3b5bf0")
        if (response.data is String) {
          final roomId = response.data as String;
          return roomId.isEmpty ? null : roomId;
        } else if (response.data is Map) {
          // If it's JSON, try to get the 'id' or 'roomId' field
          final data = response.data as Map<String, dynamic>;
          final roomId =
              data['id'] as String? ??
              data['roomId'] as String? ??
              data['room_id'] as String? ??
              '';
          return roomId.isEmpty ? null : roomId;
        }
        return null;
      }
      // 404 or other status means no call
      return null;
    } catch (e) {
      // If error (like 404), no call is incoming
      return null;
    }
  }

  /// Analyze a call to check if it's a scam
  /// This should be called when a call starts
  Future<bool> analyzeCallForScam(CallInfo callInfo) async {
    try {
      final response = await _dio.post(
        '/analyze-call',
        data: {
          'phoneNumber': callInfo.phoneNumber,
          'timestamp': callInfo.timestamp.toIso8601String(),
          'callId': callInfo.id,
        },
      );

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        return data['isScam'] as bool? ?? false;
      }
      return false;
    } catch (e) {
      print('Error analyzing call: $e');
      return false;
    }
  }

  /// Stream call audio to backend for real-time analysis
  /// This would be used with Twilio middleware
  Future<void> streamCallAudio(String callId, String audioStreamUrl) async {
    try {
      await _dio.post(
        '/stream-audio',
        data: {'callId': callId, 'audioStreamUrl': audioStreamUrl},
      );
    } catch (e) {
      print('Error streaming audio: $e');
    }
  }

  /// Get real-time scam detection updates
  /// Poll this endpoint during an active call
  Future<bool?> checkScamStatus(String callId) async {
    try {
      final response = await _dio.get('/call-status/$callId');
      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        return data['isScam'] as bool?;
      }
      return null;
    } catch (e) {
      print('Error checking scam status: $e');
      return null;
    }
  }

  /// Get Twilio access token from backend
  /// This should be called when app starts or token expires
  Future<String> getTwilioAccessToken() async {
    try {
      // Use hardcoded user ID for testing
      const userId = '123';
      final endpoint = '/get-access-token';
      final fullUrl = '$baseUrl$endpoint';
      // Explicitly ensure user_id is a String in the request data
      final requestData = <String, String>{'user_id': userId};

      print('=== BackendService Debug ===');
      print('Request Method: POST');
      print('Full URL: $fullUrl');
      print('Endpoint: $endpoint');
      print('Base URL: $baseUrl');
      print('Request Data: $requestData');
      print('User ID: $userId (type: ${userId.runtimeType})');
      print('User ID value type check: ${requestData['user_id'] is String}');
      print('===========================');

      final response = await _dio.post(endpoint, data: requestData);

      print('TOKEN Response Status: ${response.statusCode}');
      print('TOKEN Response Data: ${response.data}');
      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        // Backend returns 'access_token' (snake_case), handle both formats
        final accessToken =
            data['access_token'] as String? ?? data['accessToken'] as String?;

        if (accessToken == null || accessToken.isEmpty) {
          throw Exception(
            'Invalid response: access_token field missing or empty',
          );
        }

        return accessToken;
      }
      throw Exception(
        'Failed to get access token: Status ${response.statusCode}',
      );
    } on DioException catch (e) {
      final endpoint = '/get-access-token';
      final fullUrl = '$baseUrl$endpoint';

      print('=== DioException Debug ===');
      print('Exception Type: ${e.type}');
      print('Failed URL: $fullUrl');
      print('Base URL: $baseUrl');
      print('Endpoint: $endpoint');
      if (e.response != null) {
        print('Response Status: ${e.response?.statusCode}');
        print('Response Data: ${e.response?.data}');
      }
      print('Error Message: ${e.message}');
      print('==========================');

      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        throw Exception(
          'Connection timeout. Please check your internet connection and ensure the backend server is running at $fullUrl',
        );
      } else if (e.response?.statusCode == 404) {
        throw Exception(
          'Access token endpoint not found. Please ensure the backend API is deployed at $fullUrl',
        );
      } else if (e.response?.statusCode == 400) {
        final errorMsg = e.response?.data is Map
            ? (e.response?.data as Map)['error']?.toString() ?? 'Bad request'
            : 'Bad request';
        throw Exception('Backend error: $errorMsg');
      } else if (e.response?.statusCode == 302) {
        throw Exception(
          'Backend returned redirect. Please check the API URL configuration.',
        );
      }
      print('Error getting Twilio access token: $e');
      rethrow;
    } catch (e) {
      print('Error getting Twilio access token: $e');
      rethrow;
    }
  }

  /// Register FCM device token with backend
  /// Backend will use this to send FCM notifications for incoming calls
  Future<void> registerDeviceToken(String deviceToken) async {
    try {
      await _dio.post('/register-device', data: {'deviceToken': deviceToken});
    } catch (e) {
      print('Error registering device token: $e');
    }
  }

  /// Trigger scam warning during active call
  /// Backend will redirect the call to inject a warning message
  Future<bool> triggerScamWarning(
    String callId, {
    String? warningMessage,
  }) async {
    try {
      final response = await _dio.post(
        '/twilio/call-warning',
        data: {
          'callId': callId,
          'message':
              warningMessage ??
              'Warning: This call has been flagged as potentially suspicious. Please be cautious.',
        },
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Error triggering scam warning: $e');
      return false;
    }
  }
}
