// import 'dart:convert';
import 'package:dio/dio.dart';
import '../models/call_info.dart';

class BackendService {
  final Dio _dio;
  final String baseUrl;

  BackendService({String? baseUrl})
    : baseUrl = baseUrl ?? 'https://junction.timohartikainen.fi/api',
      _dio = Dio(
        BaseOptions(
          baseUrl: baseUrl ?? 'https://junction.timohartikainen.fi/api',
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
          followRedirects: true,
          validateStatus: (status) {
            // Accept status codes 200-399 (including redirects)
            return status != null && status >= 200 && status < 400;
          },
        ),
      );

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
      final response = await _dio.post('/twilio/access-token');
      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        return data['accessToken'] as String;
      }
      throw Exception(
        'Failed to get access token: Status ${response.statusCode}',
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        throw Exception(
          'Twilio access token endpoint not found. Please ensure the backend API is deployed.',
        );
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
