# Refactor Plan: Twilio Voice SDK Integration

## Goal
Refactor app to receive calls via Twilio Voice SDK instead of monitoring regular phone calls. Simplify to MVP - just receive and handle Twilio VoIP calls.

## Changes Required

### 1. Dependencies (pubspec.yaml)
**Remove:**
- `phone_state` - no longer needed (we're using Twilio VoIP, not regular calls)
- `callkit_incoming` - Twilio Voice SDK handles this
- `flutter_callkit_incoming` - Twilio Voice SDK handles this
- `workmanager` - not needed for MVP
- `flutter_background_service` - Twilio handles background via FCM
- `flutter_background_service_android` - not needed

**Add:**
- `twilio_voice: ^0.3.2+2` - Twilio Voice SDK
- `firebase_messaging` - for FCM push notifications (required for Twilio on Android)

**Keep:**
- `flutter_local_notifications` - for notifications
- `permission_handler` - for permissions
- `vibration` - for scam alerts
- `audioplayers` - for alarm sounds
- `dio` - for backend API
- `provider` - for state management
- `shared_preferences` - for storing tokens
- `uuid` - for call IDs

### 2. Services Refactoring

**call_service.dart → twilio_call_service.dart**
- Replace phone_state monitoring with Twilio Voice SDK
- Listen to Twilio call events (incoming, connected, disconnected)
- Handle answer/decline via Twilio SDK
- Integrate with backend for scam detection

**backend_service.dart**
- Add method to get Twilio access token from backend
- Keep scam detection methods
- Add method to register FCM token with backend

### 3. Android Configuration

**AndroidManifest.xml**
- Add Twilio FCM service
- Remove regular phone call permissions (not needed for VoIP)
- Keep notification and internet permissions
- Add FCM permissions

**build.gradle**
- Add ProGuard rules for Twilio (already documented)

### 4. Simplified Architecture

**Flow:**
1. App starts → Initialize Twilio Voice SDK with access token from backend
2. Backend sends FCM notification → Twilio SDK receives call
3. App shows incoming call UI → User answers/declines
4. During call → Backend analyzes via Twilio middleware → Sends scam alerts
5. App shows scam alert → Vibration + sound

### 5. Files to Modify

- `pubspec.yaml` - Update dependencies
- `lib/services/call_service.dart` → `lib/services/twilio_call_service.dart` - Complete rewrite
- `lib/services/backend_service.dart` - Add Twilio token methods
- `lib/main.dart` - Initialize Twilio SDK
- `lib/providers/call_provider.dart` - Update to use Twilio service
- `android/app/src/main/AndroidManifest.xml` - Add Twilio FCM service
- `android/app/proguard-rules.pro` - Add Twilio ProGuard rules

### 6. Files to Remove/Simplify

- Can remove complex background service setup (Twilio handles this)
- Simplify home_screen.dart - just show status and incoming calls
- Keep alert_service.dart as-is
- Keep incoming_call_overlay.dart as-is (works with Twilio calls)

## MVP Scope

**What we're building:**
- ✅ Receive incoming Twilio VoIP calls
- ✅ Show incoming call UI
- ✅ Answer/Decline calls
- ✅ Receive scam alerts from backend during calls
- ✅ Vibrate and play alarm on scam detection

**What we're NOT building (for now):**
- ❌ Making outgoing calls
- ❌ Call history
- ❌ Contact management
- ❌ Complex UI features

