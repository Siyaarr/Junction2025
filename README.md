# Anti-Scam Dialer App

An Android Flutter application designed to protect elderly users from phone scams by monitoring calls in real-time using AI analysis via Twilio middleware.

## Features

- **Background Monitoring**: Continuously monitors phone calls in the background
- **Default Dialer**: Can be set as the default dialer app on Android
- **Incoming Call UI**: Beautiful overlay interface for incoming calls with answer/decline buttons
- **Real-time Scam Detection**: Analyzes calls via backend AI integration
- **Alert System**: Vibrates phone and plays alarm sound when scam is detected
- **Minimal UI**: Small, unobtrusive interface that runs in the background

## Architecture

The app consists of several key components:

- **Call Service**: Monitors phone state and handles call events
- **Backend Service**: Communicates with backend API for scam analysis
- **Alert Service**: Manages vibration and sound alerts
- **Background Service**: Ensures continuous monitoring even when app is closed
- **Call Overlay**: Full-screen UI for incoming calls

## Setup Instructions

### 1. Install Dependencies

```bash
flutter pub get
```

### 2. Configure Backend URL

Update the backend URL in `lib/services/backend_service.dart`:

```dart
final String baseUrl = 'https://your-backend-url.com/api';
```

### 3. Add Alarm Sound (Optional)

Create an alarm sound file and place it in:
```
assets/sounds/alarm.mp3
```

If no alarm sound is provided, the app will use the system alert sound as a fallback.

### 4. Android Permissions

The app requires the following permissions (already configured in AndroidManifest.xml):
- Phone state access
- Call phone
- Answer phone calls
- Notification
- System overlay (for incoming call UI)
- Vibration

### 5. Set as Default Dialer

After installing the app:
1. Go to Android Settings
2. Navigate to Apps > Default Apps > Phone app
3. Select "Anti-Scam Dialer"

## Backend API Requirements

The backend should provide the following endpoints:

### POST /api/analyze-call
Analyze a call to determine if it's a scam.

**Request:**
```json
{
  "phoneNumber": "+1234567890",
  "timestamp": "2024-01-01T12:00:00Z",
  "callId": "uuid-here"
}
```

**Response:**
```json
{
  "isScam": true
}
```

### POST /api/stream-audio
Register audio stream URL for real-time analysis (used with Twilio).

**Request:**
```json
{
  "callId": "uuid-here",
  "audioStreamUrl": "wss://twilio-stream-url"
}
```

### GET /api/call-status/{callId}
Get real-time scam status during an active call.

**Response:**
```json
{
  "isScam": true
}
```

### POST /api/register-device
Register device for push notifications.

**Request:**
```json
{
  "deviceToken": "fcm-token-here"
}
```

## Development

### Running the App

```bash
flutter run
```

### Building for Release

```bash
flutter build apk --release
```

## Project Structure

```
lib/
├── main.dart                 # App entry point
├── models/
│   └── call_info.dart       # Call data model
├── services/
│   ├── backend_service.dart # Backend API integration
│   ├── call_service.dart    # Call monitoring service
│   ├── alert_service.dart   # Alert system
│   └── background_service.dart # Background service
├── providers/
│   └── call_provider.dart   # State management
├── screens/
│   └── home_screen.dart      # Main UI screen
├── widgets/
│   ├── incoming_call_overlay.dart # Incoming call UI
│   └── call_overlay_manager.dart  # Overlay management
└── utils/
    └── permission_handler.dart    # Permission utilities
```

## Important Notes

1. **Minimum SDK**: The app requires Android API level 23 (Android 6.0) or higher
2. **Permissions**: Users must grant all required permissions for the app to function
3. **Background Service**: The app runs a foreground service to ensure continuous monitoring
4. **Battery Optimization**: Users may need to disable battery optimization for the app
5. **Default Dialer**: Setting the app as default dialer is optional but recommended

## Troubleshooting

### App not detecting calls
- Ensure all permissions are granted
- Check if battery optimization is disabled for the app
- Verify the app is set as default dialer (optional)

### Alerts not working
- Check notification permissions
- Verify vibration permission is granted
- Ensure device volume is not muted

### Backend connection issues
- Verify backend URL is correct in `backend_service.dart`
- Check network connectivity
- Review backend API logs

## License

[Your License Here]
