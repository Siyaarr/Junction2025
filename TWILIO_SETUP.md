# Twilio Voice SDK Setup Guide

## Overview
The app has been refactored to use Twilio Voice SDK for receiving VoIP calls instead of monitoring regular phone calls.

## Architecture

### Flow
1. **App Startup** → Initialize Firebase → Get FCM token
2. **Get Twilio Token** → Request access token from backend API
3. **Initialize Twilio** → Set tokens in Twilio Voice SDK
4. **Receive Call** → Backend sends FCM notification → Twilio SDK receives call
5. **Show UI** → Incoming call overlay appears
6. **Answer/Decline** → User interacts → Twilio SDK handles call
7. **Scam Detection** → Backend analyzes via Twilio middleware → Sends alerts
8. **Alert User** → Vibration + sound alarm

## Backend API Requirements

### 1. Get Twilio Access Token
**Endpoint:** `POST /api/twilio/access-token`

**Response:**
```json
{
  "accessToken": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

The backend should generate a Twilio access token using your Twilio credentials.

### 2. Register FCM Device Token
**Endpoint:** `POST /api/register-device`

**Request:**
```json
{
  "deviceToken": "fcm-token-here"
}
```

Backend stores this token to send FCM notifications for incoming calls.

### 3. Analyze Call for Scam
**Endpoint:** `POST /api/analyze-call`

**Request:**
```json
{
  "phoneNumber": "+1234567890",
  "timestamp": "2024-01-01T12:00:00Z",
  "callId": "call-sid-here"
}
```

**Response:**
```json
{
  "isScam": true
}
```

### 4. Check Scam Status (during call)
**Endpoint:** `GET /api/call-status/{callId}`

**Response:**
```json
{
  "isScam": true
}
```

## Firebase Setup

### 1. Create Firebase Project
1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Create a new project
3. Add Android app with package name: `com.example.junction_flutter_1`

### 2. Download google-services.json
1. Download `google-services.json` from Firebase Console
2. Place it in `android/app/` directory

### 3. Update build.gradle
The Firebase plugin should be automatically configured by Flutter.

## Android Configuration

### ProGuard Rules
Already added in `android/app/proguard-rules.pro`:
```
# Twilio Programmable Voice
-keep class com.twilio.** { *; }
-keep class tvo.webrtc.** { *; }
-dontwarn tvo.webrtc.**
-keep class com.twilio.voice.** { *; }
-keepattributes InnerClasses
```

### AndroidManifest.xml
Already configured with:
- Twilio FCM service
- Required permissions (Internet, Audio, Notifications)
- FCM messaging service

## Testing

### 1. Test Twilio Token
- Ensure backend returns valid Twilio access token
- Check app logs for initialization errors

### 2. Test Incoming Call
- Backend should send FCM notification with Twilio call data
- App should show incoming call UI
- Test answer/decline functionality

### 3. Test Scam Detection
- Backend should analyze call and return `isScam: true`
- App should vibrate and play alarm

## Troubleshooting

### App not receiving calls
- Check Firebase setup (google-services.json)
- Verify FCM token is registered with backend
- Check backend is sending FCM notifications correctly
- Review Twilio dashboard for call logs

### Twilio initialization fails
- Verify backend returns valid access token
- Check network connectivity
- Review app logs for specific errors

### Permissions issues
- Grant notification permission
- Grant microphone permission
- Grant overlay permission (for incoming call UI)

## Next Steps

1. **Set up Firebase** - Add google-services.json
2. **Configure Backend** - Implement Twilio token endpoint
3. **Test FCM** - Verify push notifications work
4. **Test Calls** - Make test call via Twilio
5. **Test Scam Detection** - Verify backend integration

