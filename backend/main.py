from flask import Flask, jsonify, request, send_file
from flask_sock import Sock
from twilio.twiml.voice_response import VoiceResponse, Start
from twilio.jwt.access_token import AccessToken
from twilio.jwt.access_token.grants import VoiceGrant
import json
import base64
import threading
import time
import wave
import audioop
from dotenv import load_dotenv
import os

from llm.summarizer import ConversationSummarizer
from llm.detector import ScamDetector
from llm.transcriber import DiarizationTranscriber

load_dotenv()

domain = os.getenv('DOMAIN')

app = Flask(__name__)
sock = Sock(app)

# Global variables for simplicity
audio_buffer = []
chunk_number = 1
is_recording = False
transcript_buffer = ""
conference_name = ""

transcriber = DiarizationTranscriber()
detector = ScamDetector()
summarizer = ConversationSummarizer()

def save_chunk():
    """Save current buffer as WAV file."""
    global audio_buffer, chunk_number, transcript_buffer
    
    if not audio_buffer:
        return
    
    # Combine all audio data
    combined_audio = b''.join(audio_buffer)
    
    # Convert μ-law to PCM
    pcm_audio = audioop.ulaw2lin(combined_audio, 2)
    
    # Save as WAV
    filename = f"chunk_{chunk_number:03d}.wav"
    with wave.open(filename, 'wb') as wav_file:
        wav_file.setnchannels(1)      # Mono
        wav_file.setsampwidth(2)      # 16-bit
        wav_file.setframerate(8000)   # 8kHz
        wav_file.writeframes(pcm_audio)
    
    print(f"Saved: {filename}")
    
    # Reset
    audio_buffer = []
    chunk_number += 1

    transcript = transcriber.transcribe_with_diarization(filename)
    print(f"Transcript: {transcript}")
    transcript_buffer += transcriber.format_transcript(transcript) + "\n"

    result = detector.detect(transcript_buffer)
    print(f"Scam: {result.is_scam}")
    print(f"Confidence: {result.confidence:.0%}")
    print(f"Type: {result.scam_type}")
    print(f"Risks: {result.risk_factors}")
    print(f"Reasoning: {result.reasoning}")


def timer_worker():
    """Save chunks every 5 seconds."""
    global is_recording
    
    while is_recording:
        time.sleep(5)
        if is_recording:
            save_chunk()


@app.route("/room", methods=['GET'])
def room():
    return conference_name


@app.route("/beep.mp3", methods=['GET', "POST"])
def beep():
    return send_file('phone-call-14472.mp3')


@app.route("/wait", methods=['GET', 'POST'])
def wait():
    resp = VoiceResponse()
    
    resp.pause(length=2)

    for i in range(5):
        resp.play(f'https://{domain}/beep.mp3')
        resp.pause(length=2)  # 2-second pause between plays
            
    resp.hangup()

    return str(resp)


@app.route("/voice", methods=['POST'])
def voice():
    """Respond to incoming phone calls with a brief message."""
    global conference_name

    resp = VoiceResponse()
    
    call_sid = request.form.get('CallSid')
    
    # Create conference room name
    conference_name = f"room-{call_sid}"
    print(f"Conference name: {conference_name}")

    # Start streaming
    start = Start()
    start.stream(url=f'wss://{domain}/stream')
    resp.append(start)

    # Put caller in conference
    dial = resp.dial()
    dial.conference(
        conference_name,
        wait_url=f'https://{domain}/wait',
        start_conference_on_enter=False,
        end_conference_on_exit=True
    )
    
    return str(resp)


@app.route("/voice-sdk", methods=['POST'])  
def voice_sdk():
    """Handle Voice SDK calls from mobile app"""
    resp = VoiceResponse()
    
    # Get parameters from Voice SDK call
    conference_name = request.form.get('conference_name')
    action = request.form.get('action')
    from_identity = request.form.get('From')  # Will be "client:user_id"
    
    print(f"📱 Voice SDK call from {from_identity}")
    
    if action == 'join_conference' and conference_name:
        dial = resp.dial()
        dial.conference(
            conference_name,
            start_conference_on_enter=True,
            end_conference_on_exit=True
        )
    else:
        resp.say("Invalid conference room")
        resp.hangup()
    
    return str(resp)


@app.route("/get-access-token", methods=['POST'])
def generate_access_token():
    user_id = request.json.get('user_id')
    
    if not user_id:
        return jsonify({'error': 'User ID required'}), 400
    
    # Get TwiML App SID from environment
    twiml_app_sid = os.getenv('TWILIO_TWIML_APP_SID')
    api_key_sid = os.getenv('TWILIO_API_KEY_SID')
    api_key_secret = os.getenv('TWILIO_API_KEY_SECRET')
    account_sid = os.getenv('TWILIO_ACCOUNT_SID')
    
    # Generate access token
    token = AccessToken(account_sid, api_key_sid, api_key_secret, identity=user_id)
    
    # Add Voice grant with TwiML App SID
    voice_grant = VoiceGrant(
        incoming_allow=True,
        outgoing_application_sid=twiml_app_sid  # Your TwiML App SID
    )
    token.add_grant(voice_grant)
    
    return jsonify({
        'access_token': token.to_jwt(),
        'identity': user_id
    })


@app.route("/recording", methods=['POST'])
def recording():
    """Handle recording callbacks with transcription."""
    recording_url = request.values.get('RecordingUrl', '')
    transcription = request.values.get('TranscriptionText', '')
    caller = request.values.get('From', '')
    
    print(f"New recording from {caller}")
    print(f"Recording URL: {recording_url}")
    print(f"Transcription: {transcription}")
    
    # Here you could save to database, send email, etc.
    
    return '', 200

@sock.route('/stream')
def stream(ws):
    global is_recording, transcript_buffer
    
    while True:
        message = ws.receive()
        data = json.loads(message)
        
        if data['event'] == 'start':
            is_recording = True
            # Start timer
            threading.Thread(target=timer_worker, daemon=True).start()
            print("Recording started")
        
        elif data['event'] == 'media':
            if is_recording:
                audio_data = base64.b64decode(data['media']['payload'])
                audio_buffer.append(audio_data)
        
        elif data['event'] == 'stop':
            is_recording = False
            save_chunk()  # Save final chunk
            print("Recording stopped")
            print(transcript_buffer)
            summary = summarizer.summarize(transcript_buffer)
            print(f"Summary: {summary}")
            break


if __name__ == "__main__":
    app.run(debug=True, host='0.0.0.0', port=80)
