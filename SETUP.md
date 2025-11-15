# Setup Guide

## Quick Start

1. **Install Dependencies**
   ```bash
   flutter pub get
   ```

2. **Configure Backend URL**
   Edit `lib/services/backend_service.dart` and update:
   ```dart
   baseUrl = baseUrl ?? 'https://your-backend-url.com/api'
   ```

3. **Add Alarm Sound (Optional)**
   Place `alarm.mp3` in `assets/sounds/` directory

4. **Run the App**
   ```bash
   flutter run
   ```

## Android Setup

### Permissions
The app will request these permissions on first launch:
- Phone (required)
- Notifications (required)
- System Overlay (for incoming call UI)

### Set as Default Dialer
1. Open Android Settings
2. Go to Apps > Default Apps > Phone app
3. Select "Anti-Scam Dialer"

### Battery Optimization
To ensure the app works in background:
1. Go to Settings > Apps > Anti-Scam Dialer
2. Tap Battery
3. Select "Unrestricted"

## Backend Integration

The app expects a backend API with the following endpoints:

- `POST /api/analyze-call` - Analyze call for scam
- `POST /api/stream-audio` - Register audio stream
- `GET /api/call-status/{callId}` - Get scam status
- `POST /api/register-device` - Register device

See `README.md` for detailed API specifications.

## Testing

### Test Call Detection
1. Grant all permissions
2. Make a test call to the device
3. Verify incoming call UI appears
4. Check that call events are logged

### Test Scam Alert
1. Configure backend to return `isScam: true` for test number
2. Make a call from that number
3. Verify vibration and alarm sound trigger

## Troubleshooting

### Dependencies Not Found
Run `flutter pub get` to install packages.

### Permissions Not Working
- Check AndroidManifest.xml has all required permissions
- Verify app has permission to draw over other apps
- Check if battery optimization is disabled

### Calls Not Detected
- Ensure app is running in background
- Check phone_state package is working
- Verify permissions are granted

### Backend Connection Issues
- Verify backend URL is correct
- Check network connectivity
- Review backend logs for errors

