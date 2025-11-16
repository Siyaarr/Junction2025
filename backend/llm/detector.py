from typing import List, Optional
from langchain_openai import ChatOpenAI
from langchain_core.prompts import ChatPromptTemplate
from pydantic import BaseModel, Field
from dotenv import load_dotenv

load_dotenv()


class ScamAnalysis(BaseModel):
    """Structured output for scam detection"""
    is_scam: bool = Field(description="Whether this is likely a scam call")
    confidence: float = Field(description="Confidence score 0-1", ge=0.0, le=1.0)
    scam_type: Optional[str] = Field(description="Type of scam if detected", default=None)
    risk_factors: List[str] = Field(description="Identified risk indicators")
    reasoning: str = Field(description="Brief explanation of decision")


class ScamDetector:
    def __init__(self, model: str = "gpt-4o", temperature: float = 0.1):
        self.llm = ChatOpenAI(model=model, temperature=temperature)
        
        self.prompt = ChatPromptTemplate.from_messages([
            ("system", """You are a scam detection expert. Analyze phone transcripts for scam indicators.

            Common scam signs:
            - Urgency ("act now", "limited time")
            - Threats (arrest, account closure)
            - Requests for personal info (SSN, passwords)
            - Unusual payments (gift cards, wire transfer)
            - Impersonation (IRS, tech support, banks)

            Return structured analysis."""),
            ("human", "Analyze this transcript:\n\n{transcript}")
        ])
        
        self.chain = self.prompt | self.llm.with_structured_output(ScamAnalysis)
    
    def detect(self, transcript: str) -> ScamAnalysis:
        """Detect if transcript contains scam indicators"""
        return self.chain.invoke({"transcript": transcript})


# Usage example
if __name__ == "__main__":
    detector = ScamDetector()
    
    # Test with scam transcript
    scam_text = """
    Caller: This is IRS Agent Smith. Your tax return has errors and you will be arrested 
    in 24 hours unless you pay $2000 in gift cards immediately. Do not hang up.
    
    Recipient: This doesn't sound right...
    
    Caller: Ma'am, this is urgent! Stay on the line and go buy iTunes gift cards now!
    """
    
    result = detector.detect(scam_text)
    
    print(f"Scam: {result.is_scam}")
    print(f"Confidence: {result.confidence:.0%}")
    print(f"Type: {result.scam_type}")
    print(f"Risks: {result.risk_factors}")
    print(f"Reasoning: {result.reasoning}")
