# Scam Warning System Implementation

## Overview

This document describes how the scam warning system works and what needs to be implemented on the backend.

## How It Works

### Flow

1. **Call Starts** → App receives incoming call via Twilio
2. **Initial Analysis** → App sends call info to `/api/analyze-call` endpoint
3. **Call Answered** → User answers the call
4. **Periodic Polling** → Every 5 seconds, app polls `/api/call-status/{callId}` for scam status
5. **Scam Detected** → When backend returns `isScam: true`:
   - App triggers visual/audio alert on device
   - App calls `/api/twilio/call-warning` to inject warning into call
6. **Backend Injects Warning** → Backend uses Twilio REST API to redirect call and play warning message

## Frontend Implementation (Already Done)

### Files Modified

1. **`lib/services/backend_service.dart`**
   - Added `triggerScamWarning()` method
   - Calls `/api/twilio/call-warning` endpoint

2. **`lib/services/twilio_call_service.dart`**
   - Modified `_startScamCheckTimer()` to call `_triggerCallWarning()` when scam detected
   - Added `_triggerCallWarning()` method to request warning injection

### How It Works in Flutter

```dart
// When scam is detected during polling:
if (scamStatus == true) {
  // 1. Trigger device alert (vibration + sound)
  await _alertService.triggerScamAlert();
  
  // 2. Request backend to inject warning into call
  await _triggerCallWarning();
}
```

## Backend Implementation Required

### Endpoint: `POST /api/twilio/call-warning`

**Request Body:**
```json
{
  "callId": "CA1234567890abcdef",
  "message": "Warning: This call has been flagged as potentially suspicious. Please be cautious and do not share personal information."
}
```

**Backend Implementation (Python/Flask):**

```python
from twilio.rest import Client
from flask import request, jsonify

@app.route('/api/twilio/call-warning', methods=['POST'])
def trigger_call_warning():
    data = request.json
    call_id = data.get('callId')
    message = data.get('message', 'Warning: This call has been flagged as suspicious.')
    
    # Initialize Twilio client
    account_sid = os.getenv('TWILIO_ACCOUNT_SID')
    auth_token = os.getenv('TWILIO_AUTH_TOKEN')
    client = Client(account_sid, auth_token)
    
    # Create TwiML URL that will inject the warning
    # This URL should return TwiML that:
    # 1. Pauses/mutes the caller
    # 2. Speaks the warning message to the user
    # 3. Optionally resumes or ends the call
    
    warning_url = f'https://{domain}/twilio/warning-voice?message={message}'
    
    try:
        # Redirect the call to inject the warning
        call = client.calls(call_id).update(
            url=warning_url,
            method='POST'
        )
        return jsonify({'success': True, 'callSid': call.sid}), 200
    except Exception as e:
        print(f'Error redirecting call: {e}')
        return jsonify({'success': False, 'error': str(e)}), 500

@app.route('/twilio/warning-voice', methods=['GET', 'POST'])
def warning_voice():
    """TwiML endpoint that injects warning message into call"""
    from twilio.twiml.voice_response import VoiceResponse
    
    message = request.args.get('message', 'Warning: This call has been flagged as suspicious.')
    
    resp = VoiceResponse()
    
    # Option 1: Mute the caller and speak to user
    # Note: This requires the call to be in a conference or using <Gather>
    # For simplicity, we'll just speak the message
    
    # Pause briefly
    resp.pause(length=1)
    
    # Speak the warning message
    resp.say(
        message,
        voice='alice',  # or 'man', 'woman', 'alice'
        language='en-US'
    )
    
    # Optionally pause again to let message sink in
    resp.pause(length=2)
    
    # Resume the call (or you could hang up with resp.hangup())
    # Note: To actually mute the caller, you'd need to use a Conference
    # or redirect to a new TwiML that handles the call differently
    
    return str(resp), 200, {'Content-Type': 'text/xml'}
```

## Alternative Approaches

### Option 1: Simple Redirect (Current Implementation)
- **Pros**: Simple, works immediately
- **Cons**: Interrupts the call flow, caller can still hear

### Option 2: Conference with Mute
- **Pros**: Can actually mute the caller
- **Cons**: More complex, requires conference setup

### Option 3: Media Streams
- **Pros**: Can inject audio without redirecting
- **Cons**: Most complex, requires WebSocket handling

## Recommended Approach

For MVP, use **Option 1** (Simple Redirect) because:
1. It's the easiest to implement
2. Works with existing Twilio setup
3. The warning message will be clearly heard
4. Can be enhanced later with conference/mute if needed

## Testing

1. Make a test call to your Twilio number
2. Answer the call
3. Manually trigger scam detection (or wait for AI to detect)
4. Verify warning message is played in the call
5. Verify device alert (vibration + sound) is triggered

## Future Enhancements

1. **Conference-based muting**: Put call in conference, mute caller, speak warning
2. **Customizable messages**: Allow different warning messages based on scam type
3. **User choice**: After warning, give user option to continue or hang up
4. **Recording**: Record the warning interaction for analysis

