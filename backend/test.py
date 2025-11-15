from llm.transcriber import DiarizationTranscriber
from llm.detector import ScamDetector

def test():
    transcriber = DiarizationTranscriber()
    transcript = transcriber.transcribe_with_diarization("Recording.wav")
    formatted_transcript = transcriber.format_transcript(transcript)
    print(f"Transcript: {transcript}")
    print(f"Formatted Transcript: {formatted_transcript}")

    detector = ScamDetector()
    result = detector.detect(formatted_transcript)
    print(f"Scam: {result.is_scam}")
    print(f"Confidence: {result.confidence:.0%}")
    print(f"Type: {result.scam_type}")
    print(f"Risks: {result.risk_factors}")
    print(f"Reasoning: {result.reasoning}")

if __name__ == "__main__":
    test()
