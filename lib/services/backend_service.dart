// import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import '../models/call_info.dart';

class BackendService {
  final Dio _dio;
  final String baseUrl;
  static const String _domain = 'junction.timohartikainen.fi';
  String? _currentIdentity; // Store the identity from access token response

  BackendService({String? baseUrl})
    : baseUrl = baseUrl ?? 'https://$_domain',
      _dio = Dio(
        BaseOptions(
          baseUrl: baseUrl ?? 'https://$_domain',
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
          followRedirects: true,
          validateStatus: (status) {
            // Accept status codes 200-399 (including redirects)
            return status != null && status >= 200 && status < 400;
          },
        ),
      );

  /// Test DNS resolution for the backend domain
  /// Returns detailed diagnostic information
  static Future<Map<String, dynamic>> testBackendDnsResolution() async {
    final result = <String, dynamic>{
      'success': false,
      'addresses': <String>[],
      'error': null,
    };

    try {
      print('Testing DNS resolution for $_domain...');
      final addresses = await InternetAddress.lookup(_domain);
      if (addresses.isNotEmpty) {
        result['success'] = true;
        result['addresses'] = addresses.map((a) => a.address).toList();
        print(
          '✓ DNS resolution successful: ${addresses.map((a) => a.address).join(", ")}',
        );
      } else {
        result['error'] = 'DNS lookup returned no addresses';
        print('✗ DNS lookup returned no addresses');
      }
    } catch (e) {
      result['error'] = e.toString();
      print('✗ DNS resolution failed: $e');

      // Provide helpful diagnostics
      if (e.toString().contains('Failed host lookup') ||
          e.toString().contains('No address associated with hostname')) {
        print('');
        print('DNS Resolution Failed - Troubleshooting Steps:');
        print('1. Check emulator network settings:');
        print('   - Settings → Network & internet → Private DNS → Off');
        print('   - Try setting manual DNS (8.8.8.8) in Wi-Fi settings');
        print('2. If using VPN on host machine, try disabling it');
        print('3. Verify domain resolves publicly:');
        print('   - From host: nslookup $_domain');
        print('   - From browser in emulator: https://$_domain');
        print('4. Restart emulator with cold boot');
        print('');
      }
    }
    return result;
  }

  /// Test general internet connectivity by making a request to a reliable endpoint
  /// Returns true if connectivity works, false otherwise
  static Future<bool> testInternetConnectivity() async {
    try {
      print('=== Testing Internet Connectivity ===');

      // Test DNS resolution first
      print('1. Testing DNS resolution to google.com...');
      try {
        final addresses = await InternetAddress.lookup('google.com');
        print('   ✓ DNS resolution successful: ${addresses.first.address}');
      } catch (e) {
        print('   ✗ DNS resolution failed: $e');
        return false;
      }

      // Test HTTP request to a reliable endpoint
      print('2. Testing HTTP request to httpbin.org/get...');
      final testDio = Dio(
        BaseOptions(
          baseUrl: 'https://httpbin.org',
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );

      try {
        final response = await testDio.get('/get');
        if (response.statusCode == 200) {
          print(
            '   ✓ HTTP request successful (Status: ${response.statusCode})',
          );
          print('   Response origin: ${response.data['origin']}');
          return true;
        } else {
          print('   ✗ HTTP request failed (Status: ${response.statusCode})');
          return false;
        }
      } catch (e) {
        print('   ✗ HTTP request failed: $e');
        return false;
      }
    } catch (e) {
      print('Internet connectivity test failed: $e');
      return false;
    } finally {
      print('=====================================');
    }
  }

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

  /// Fetch the current caller phone number from the public data endpoint.
  /// Returns the E.164 formatted phone number (e.g., "+358...") if available.
  Future<String?> getCurrentFromNumber() async {
    try {
      final response = await _dio.get('/data');
      if (response.statusCode == 200 && response.data is Map) {
        final data = response.data as Map<String, dynamic>;
        final current = data['current_conversation'] as Map<String, dynamic>?;
        final from = current?['from_number'] as String?;
        return (from != null && from.isNotEmpty) ? from : null;
      }
      return null;
    } catch (e) {
      print('Error fetching current from_number: $e');
      return null;
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
  /// Automatically falls back to IP address if DNS resolution fails
  Future<String> getTwilioAccessToken() async {
    // First, test general internet connectivity
    print('=== Pre-flight Connectivity Check ===');
    final hasInternet = await BackendService.testInternetConnectivity();
    if (!hasInternet) {
      throw Exception(
        'No internet connectivity detected. Please check:\n'
        '1. Device has internet connection (Wi-Fi or mobile data)\n'
        '2. Network settings are correct\n'
        '3. Firewall/VPN is not blocking connections\n'
        '4. If using emulator, check network adapter settings',
      );
    }

    // Test DNS resolution for our specific domain
    print('=== Testing Backend Domain DNS ===');
    final dnsResult = await BackendService.testBackendDnsResolution();
    if (!dnsResult['success']) {
      throw Exception(
        'DNS resolution failed for $_domain.\n\n'
        'The Android emulator cannot resolve your domain name.\n\n'
        'This is NOT a code issue - it\'s a DNS/network configuration problem.\n\n'
        'Quick Fixes:\n'
        '1. Emulator Settings → Network & internet → Private DNS → Off\n'
        '2. Set manual DNS (8.8.8.8) in emulator Wi-Fi settings\n'
        '3. Disable VPN on host machine and restart emulator\n'
        '4. Test in emulator browser: https://$_domain\n'
        '5. Verify domain resolves publicly: nslookup $_domain\n\n'
        'Note: IP fallback does NOT work with Cloudflare over HTTPS because\n'
        'Cloudflare requires SNI (Server Name Indication) in the TLS handshake,\n'
        'which cannot be set when connecting directly to an IP address.\n\n'
        'Error: ${dnsResult['error']}',
      );
    }

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

        // Store identity from response (backend returns 'identity' field)
        // This is the user_id that was used to generate the token
        final identity = data['identity'] as String?;
        if (identity != null) {
          _currentIdentity = identity;
          print('Stored identity from token response: $identity');
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
      print('Error: ${e.error}');
      print('==========================');

      // Handle DNS resolution failures
      if (e.type == DioExceptionType.connectionError) {
        final errorMsg = e.error?.toString() ?? '';
        if (errorMsg.contains('Failed host lookup') ||
            errorMsg.contains('No address associated with hostname')) {
          throw Exception(
            'DNS resolution failed for $baseUrl. '
            'Please check:\n'
            '1. Device has internet connectivity\n'
            '2. DNS servers are working (try opening a browser)\n'
            '3. If using emulator, check network settings\n'
            '4. Firewall/VPN is not blocking DNS\n'
            'Error: $errorMsg',
          );
        }
        throw Exception(
          'Connection error: ${e.error?.toString() ?? e.message}. '
          'Please check your internet connection and network settings.',
        );
      } else if (e.type == DioExceptionType.unknown) {
        final errorMsg = e.error?.toString() ?? '';
        if (errorMsg.contains('HandshakeException') ||
            errorMsg.contains('HANDSHAKE_FAILURE')) {
          throw Exception(
            'SSL handshake failed. This usually indicates:\n'
            '1. DNS resolution issue (domain not resolving)\n'
            '2. Certificate validation problem\n'
            '3. Network configuration blocking TLS\n\n'
            'If you see this after DNS resolution succeeded, check:\n'
            '- Certificate validity\n'
            '- Network security configuration\n'
            '- Firewall/VPN settings\n\n'
            'Error: $errorMsg',
          );
        }
      } else if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        throw Exception(
          'Connection timeout. Please check your internet connection and ensure the backend server is running at $fullUrl',
        );
      } else if (e.response?.statusCode == 521) {
        // Cloudflare error: Origin server is down
        throw Exception(
          'Backend server is down (Cloudflare Error 521).\n\n'
          'The backend server at $baseUrl is not responding.\n\n'
          'Please check:\n'
          '1. Backend server is running and accessible\n'
          '2. Server is not crashed or overloaded\n'
          '3. Firewall/security groups allow connections\n'
          '4. Server logs for errors\n\n'
          'This is a server-side issue, not a client issue.',
        );
      } else if (e.response?.statusCode == 502 ||
          e.response?.statusCode == 503) {
        // Cloudflare/Bad Gateway errors
        throw Exception(
          'Backend server error (${e.response?.statusCode}).\n\n'
          'The backend server is experiencing issues.\n\n'
          'Please check:\n'
          '1. Backend server is running\n'
          '2. Server is not overloaded\n'
          '3. Check server logs for errors\n\n'
          'Error: ${e.response?.data}',
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
      } else if (e.response != null) {
        // Handle other HTTP error status codes
        throw Exception(
          'Backend returned error ${e.response?.statusCode}.\n\n'
          'Response: ${e.response?.data}\n\n'
          'Please check backend server logs for details.',
        );
      }
      print('Error getting Twilio access token: $e');
      rethrow;
    } catch (e) {
      print('Error getting Twilio access token: $e');
      rethrow;
    }
  }

  /// Get the current identity (user_id) from the last access token response
  /// Returns null if no identity has been stored yet
  String? get currentIdentity => _currentIdentity;

  /// Register FCM device token with backend
  /// Backend will use this to send FCM notifications for incoming calls
  Future<void> registerDeviceToken(String deviceToken) async {
    try {
      await _dio.post('/register-device', data: {'deviceToken': deviceToken});
    } catch (e) {
      print('Error registering device token: $e');
    }
  }

  /// Make direct HTTP request to /voice-sdk endpoint
  /// This will return TwiML XML or whatever the endpoint returns
  Future<String> makeRequestToVoiceSdk({
    required String conferenceName,
    required String action,
    required String userId,
  }) async {
    try {
      print('=== Making request to /voice-sdk ===');
      print('Conference name: $conferenceName');
      print('Action: $action');
      print('User ID: $userId');

      // Make POST request with form data (as Twilio would send it)
      final response = await _dio.post(
        '/voice-sdk',
        data: {
          'conference_name': conferenceName,
          'action': action,
          'From': 'client:$userId',
        },
        options: Options(
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        ),
      );

      print('Response status: ${response.statusCode}');
      print('Response data: ${response.data}');
      print('===============================');

      return response.data.toString();
    } catch (e) {
      print('Error making request to /voice-sdk: $e');
      rethrow;
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
