from flask import Flask, request
from flask_sock import Sock
from twilio.twiml.voice_response import VoiceResponse, Start
import json
import base64
import threading
import time
import wave
import audioop
from dotenv import load_dotenv
import os

# Load environment variables from .env file
load_dotenv()

domain = os.getenv('DOMAIN')

app = Flask(__name__)
sock = Sock(app)

# Global variables for simplicity
audio_buffer = []
chunk_number = 1
is_recording = False

def save_chunk():
    """Save current buffer as WAV file."""
    global audio_buffer, chunk_number
    
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

def timer_worker():
    """Save chunks every 5 seconds."""
    global is_recording
    
    while is_recording:
        time.sleep(5)
        if is_recording:
            save_chunk()

@app.route("/voice", methods=['GET', 'POST'])
def voice():
    """Respond to incoming phone calls with a brief message."""
    # Start our TwiML response
    resp = VoiceResponse()
    
    resp.say("Recording in 5 second chunks")
    
    start = Start()
    start.stream(url=f'wss://{domain}/stream')
    resp.append(start)
    
    resp.pause(length=60)
    
    return str(resp)

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
    global is_recording
    
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
            break

if __name__ == "__main__":
    app.run(debug=True, host='0.0.0.0', port=80)
