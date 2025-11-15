from openai import OpenAI
from dotenv import load_dotenv
import os

load_dotenv()

class DiarizationTranscriber:
    def __init__(self):
        self.openai_client = OpenAI(api_key=os.getenv("OPENAI_API_KEY"))
    
    def transcribe_with_diarization(self, audio_path):
        with open(audio_path, "rb") as audio_file:
            transcript = self.openai_client.audio.transcriptions.create(
                model="gpt-4o-transcribe-diarize",
                file=audio_file,
                response_format="diarized_json"
            )
        
        return transcript
    
    def format_transcript(self, transcript):
        """Format the diarized transcript for readability"""
        formatted_lines = []
        for segment in transcript.segments:
            timestamp = f"[{segment.start:.1f}s - {segment.end:.1f}s]"
            formatted_lines.append(f"{segment.speaker}: {segment.text} {timestamp}")
        
        return "\n".join(formatted_lines)
    
    def extract_speakers(self, transcript):
        """Extract unique speakers from transcript"""
        speakers = set()
        for segment in transcript.segments:
            speakers.add(segment.speaker)
        return list(speakers)

if __name__ == "__main__":
    transcriber = DiarizationTranscriber()
    transcript = transcriber.transcribe_with_diarization("Recording.wav")
    formatted_transcript = transcriber.format_transcript(transcript)
    print(f"Transcript: {transcript}")
    print(f"Formatted Transcript: {formatted_transcript}")
