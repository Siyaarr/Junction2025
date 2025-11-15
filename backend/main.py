from flask import Flask, jsonify, request, send_file
from flask_sock import Sock
from twilio.rest import Client
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
from models import Conversation, DataLayer, Reminder

load_dotenv()

CHUNK_SIZE = 5 # seconds

domain = os.getenv('DOMAIN')

app = Flask(__name__)
sock = Sock(app)

client = Client(os.getenv('TWILIO_ACCOUNT_SID'), os.getenv('TWILIO_AUTH_TOKEN'))

data_layer = DataLayer()
transcriber = DiarizationTranscriber()
detector = ScamDetector()
summarizer = ConversationSummarizer()


def handle_chunk():
    """Save current buffer as WAV file run analysis."""
    
    if not data_layer.recording_audio_buffer:
        return
    
    # Combine all audio data
    combined_audio = b''.join(data_layer.recording_audio_buffer)
    
    # Reset recording buffer
    data_layer.recording_audio_buffer = []

    # Convert μ-law to PCM
    pcm_audio = audioop.ulaw2lin(combined_audio, 2)
    
    # Save as WAV
    filename = f"chunk.wav"
    with wave.open(filename, 'wb') as wav_file:
        wav_file.setnchannels(1)      # Mono
        wav_file.setsampwidth(2)      # 16-bit
        wav_file.setframerate(8000)   # 8kHz
        wav_file.writeframes(pcm_audio)
    
    print(f"Saved: {filename}")
    
    # Transcribe
    transcript = transcriber.transcribe_with_diarization(filename)
    data_layer.current_conversation.transcript += transcriber.format_transcript(transcript) + "\n"
    print(f"Transcript: {transcript}")

    # Analyze
    scam_result = detector.detect(data_layer.current_conversation.transcript)
    data_layer.current_conversation.scam_analysis = scam_result
    print(f"Scam: {scam_result.is_scam}")
    print(f"Confidence: {scam_result.confidence:.0%}")
    print(f"Type: {scam_result.scam_type}")
    print(f"Risks: {scam_result.risk_factors}")
    print(f"Reasoning: {scam_result.reasoning}")


def timer_worker():
    """Save chunks every CHUNK_SIZE seconds."""

    while data_layer.is_recording:
        time.sleep(CHUNK_SIZE)
        if data_layer.is_recording:
            handle_chunk()


@app.route("/data", methods=['GET'])
def data():
    return {
        "current_conversation": data_layer.current_conversation.to_dict() if data_layer.current_conversation else None,
        "conversations": [conversation.to_dict() for conversation in data_layer.conversations.values()],
        "contacts": [contact.to_dict() for contact in data_layer.contacts],
    }

@app.route("/room", methods=['GET'])
def room():
    return data_layer.current_conversation.conference_name if data_layer.current_conversation else ""


@app.route("/beep.mp3", methods=['GET', "POST"])
def beep():
    return send_file('phone-call-14472.mp3')


@app.route("/wait", methods=['GET', 'POST'])
def wait():
    resp = VoiceResponse()
    
    resp.pause(length=2)

    for i in range(20):
        resp.play(f'https://{domain}/beep.mp3')
        resp.pause(length=2)  # 2-second pause between plays
            
    resp.hangup()

    return str(resp)


@app.route("/voice", methods=['POST'])
def voice():
    """Handle incoming phone calls."""

    resp = VoiceResponse()

    if data_layer.current_conversation is not None:
        resp.say("The line is busy. Please try again later.")
        resp.hangup()
        return str(resp)
    
    call_sid = request.form.get('CallSid')
    from_number = request.form.get('From')
    conference_name = f"room-{call_sid}"
    
    conversation = Conversation(call_sid, conference_name, from_number, is_contact(from_number))
    data_layer.conversations[call_sid] = conversation
    data_layer.current_conversation_sid = call_sid

    print(f"Conference name: {conference_name}")

    # Start streaming
    # NOTE: Start streaming only if unknown caller.
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
    
    print(f"📱 Voice SDK call from {from_identity}", conference_name, action)
    
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
    while True:
        message = ws.receive()
        data = json.loads(message)
        
        if data['event'] == 'start':
            data_layer.is_recording = True
            # Start timer
            threading.Thread(target=timer_worker, daemon=True).start()
            print("Recording started")
        
        elif data['event'] == 'media':
            if data_layer.is_recording:
                audio_data = base64.b64decode(data['media']['payload'])
                data_layer.recording_audio_buffer.append(audio_data)
        
        elif data['event'] == 'stop':
            handle_call_end()
            break


@app.route('/add', methods=["GET"])
def add_safe_contact():
    participant = client.conferences(data_layer.current_conversation.conference_name) \
        .participants \
        .create(
            to=os.getenv('SAFE_CONTACT_PHONE_NUMBER'),
            from_=os.getenv('TWILIO_PHONE_NUMBER'),
            # early_media=True,
            end_conference_on_exit=False
        )

    return f"Participant SID: {participant.sid}"


def handle_call_end():
    data_layer.is_recording = False
    handle_chunk()  # Save final chunk
    print("Recording stopped")

    print(f"Transcript: {data_layer.current_conversation.transcript}")

    summary = summarizer.summarize(data_layer.current_conversation.transcript)
    data_layer.current_conversation.key_points = summary.key_points
    data_layer.current_conversation.reminders = [
        Reminder(reminder.reminder_time, reminder.short_text) for reminder in summary.reminders
    ]

    print(f"Summary: {summary}")

    data_layer.current_conversation_sid = None


def is_contact(number: str) -> bool:
    number = number.replace(" ", "")

    return any(contact.number == number for contact in data_layer.contacts)


if __name__ == "__main__":
    app.run(debug=True, host='0.0.0.0', port=80)
