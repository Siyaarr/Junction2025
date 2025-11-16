import os
from datetime import datetime
from typing import Dict, List, Optional

from llm.detector import ScamAnalysis

class Contact():
    def __init__(self, name: str, number: str):
        self.name = name
        self.number = number

    def to_dict(self) -> Dict[str, object]:
        return {
            "name": self.name,
            "number": self.number,
        }


class Reminder():
    def __init__(self, time: str, text: str):
        self.time = datetime.strptime(time, "%Y-%m-%d %H:%M")
        self.text = text
        self.sent = False

    def to_dict(self) -> Dict[str, object]:
        return {
            "time": self.time.isoformat(),
            "text": self.text,
            "sent": self.sent,
        }


class Conversation():
    def __init__(self, conference_name: str, from_number: str, is_contact: bool):
        self.timestamp = datetime.now()
        self.conference_name = conference_name
        self.from_number = from_number
        self.is_contact = is_contact
        self.transcript = ""
        self.key_points: List[str] = []
        self.reminders: List[Reminder] = []
        self.scam_analysis: Optional[ScamAnalysis] = None
        self.scam_alerted = False
        self.safe_contact_added = False

    def to_dict(self) -> Dict[str, object]:
        return {
            "timestamp": self.timestamp.isoformat(),
            "conference_name": self.conference_name,
            "from_number": self.from_number,
            "is_contact": self.is_contact,
            "key_points": self.key_points,
            "reminders": [reminder.to_dict() for reminder in self.reminders],
            "scam_analysis": self.scam_analysis.model_dump() if self.scam_analysis else None,
            "scam_alerted": self.scam_alerted,
            "safe_contact_added": self.safe_contact_added,
        }


class DataLayer():
    def __init__(self, seed: bool = False):
        self.recording_audio_buffer = []
        self.is_recording = False
        self.current_conversation_sid: Optional[str] = None
        self.conversations: Dict[str, Conversation] = {}
        self.contacts: List[Contact] = self._load_contacts()

        if seed:
            self._seed_conversations()

    @property
    def current_conversation(self) -> Optional[Conversation]:
        if self.current_conversation_sid is None:
            return None
        return self.conversations[self.current_conversation_sid]

    def _load_contacts(self) -> List[Contact]:
        contacts_env = os.getenv("CONTACTS")

        contacts: List[Contact] = []

        if not contacts_env:
            return contacts

        # Expected format: "Name:+123;Other:+456"
        for chunk in contacts_env.split(";"):
            part = chunk.strip()
            if not part or ":" not in part:
                continue

            name, number = part.split(":", 1)
            name = name.strip()
            number = number.strip()

            if name and number:
                contacts.append(Contact(name, number))

        return contacts

    def _seed_conversations(self) -> None:
        scenarios = [
            {
                "sid": "seed-1",
                "conference_name": "family-check-in",
                "from_number": "+15551230001",
                "is_contact": True,
                "timestamp": "2025-11-14 17:30",
                "transcript": (
                    "Emma: Hi Grandma, it's Emma! Just calling to let you know I'll swing by on Saturday "
                    "around noon with some groceries. Do you still need your prescription picked up?\n"
                    "Grandma: Oh hi sweetheart, yes please, that would be wonderful.\n"
                    "Emma: Great, I'll grab it Friday after work. Need anything else?\n"
                    "Grandma: No dear, that's all. Thank you.\n"
                    "Emma: Anytime! Love you, see you this weekend."
                ),
                "key_points": [
                    "Granddaughter Emma visiting Saturday at noon",
                    "Emma will pick up prescription Friday",
                ],
                "reminders": [
                    {"time": "2025-11-14 18:00", "text": "Emma picking up prescription"},
                    {"time": "2025-11-21 11:50", "text": "Prepare for Emma's visit"},
                ],
                "scam_analysis": {
                    "is_scam": False,
                    "confidence": 0.1,
                    "scam_type": None,
                    "risk_factors": [],
                    "reasoning": "Familiar family call with no threats or financial requests.",
                },
                "safe_contact_added": False,
            },
            {
                "sid": "seed-2",
                "conference_name": "clinic-reminder",
                "from_number": "+15559870002",
                "is_contact": False,
                "timestamp": "2025-11-14 14:15",
                "transcript": (
                    "Nurse Lopez: Good afternoon, Mrs. Harris. I'm calling from Lakeside Clinic to remind you "
                    "about your flu shot appointment tomorrow at 10 AM.\n"
                    "Grandma: Thank you for the reminder. Do I need to bring anything?\n"
                    "Nurse Lopez: Just your insurance card, and please arrive by 9:45 AM to complete paperwork.\n"
                    "Grandma: Perfect, I'll be there.\n"
                    "Nurse Lopez: Great, see you tomorrow!"
                ),
                "key_points": [
                    "Flu shot appointment tomorrow at 10 AM at Lakeside Clinic",
                    "Bring insurance card and arrive by 9:45 AM",
                ],
                "reminders": [
                    {"time": "2025-11-15 09:30", "text": "Leave for Lakeside Clinic appointment"},
                ],
                "scam_analysis": {
                    "is_scam": False,
                    "confidence": 0.2,
                    "scam_type": None,
                    "risk_factors": [],
                    "reasoning": "Routine healthcare reminder with verifiable details.",
                },
                "safe_contact_added": False,
            },
            {
                "sid": "seed-3",
                "conference_name": "ssa-urgent-alert",
                "from_number": "+18005550123",
                "is_contact": False,
                "timestamp": "2025-11-14 09:45",
                "transcript": (
                    "Caller: This is Agent Carter with the Social Security Administration. We found suspicious "
                    "activity with your number. If you don't verify your identity immediately, your benefits will be frozen.\n"
                    "Grandma: Oh my, what do I need to do?\n"
                    "Caller: You must confirm your Social Security number and purchase a $500 gift card today to secure your account.\n"
                    "Grandma: A gift card? That sounds strange.\n"
                    "Caller: Ma'am, this is urgent. Failure to comply means law enforcement involvement."
                ),
                "key_points": [
                    "Caller claimed to be SSA agent",
                    "Demanded SSN and $500 gift card under threat",
                ],
                "reminders": [],
                "scam_analysis": {
                    "is_scam": True,
                    "confidence": 0.95,
                    "scam_type": "Government impersonation",
                    "risk_factors": [
                        "Urgent threat of benefit loss",
                        "Request for gift card payment",
                        "Demand for sensitive personal information",
                    ],
                    "reasoning": "Classic SSA impersonation using threats and unusual payment method.",
                },
                "safe_contact_added": False,
            },
            {
                "sid": "seed-4",
                "conference_name": "tech-support-alert",
                "from_number": "+18887776666",
                "is_contact": False,
                "timestamp": "2025-11-15 11:05",
                "transcript": (
                    "Caller: Hello, this is Microsoft Support. Your computer is sending errors and will be disabled unless you pay for immediate fixes.\n"
                    "Grandma: I haven't noticed any problems.\n"
                    "Caller: It's very serious. You must let me remote into your computer and pay $300 via wire transfer now.\n"
                    "Grandma: I'd like to talk to my son first.\n"
                    "Caller: If you hang up, you'll lose access forever."
                ),
                "key_points": [
                    "Unsolicited tech support call asking for remote access",
                    "Demand for $300 wire transfer",
                ],
                "reminders": [],
                "scam_analysis": {
                    "is_scam": True,
                    "confidence": 0.9,
                    "scam_type": "Tech support scam",
                    "risk_factors": [
                        "Unsolicited claim of urgent computer issue",
                        "Pressure to grant remote access",
                        "Demand for immediate payment",
                    ],
                    "reasoning": "Matches known tech support scam patterns with urgency and payment request.",
                },
                "safe_contact_added": True,
            },
            {
                "sid": "seed-5",
                "conference_name": "bank-fraud-check",
                "from_number": "+15557654321",
                "is_contact": False,
                "timestamp": "2025-11-15 16:20",
                "transcript": (
                    "Specialist: Hello Mrs. Harris, this is Daniel from Sunrise Credit Union's fraud team. "
                    "We noticed a $120 charge at a hardware store in another state. Did you make this purchase?\n"
                    "Grandma: No, I didn't.\n"
                    "Specialist: We'll block the card and send a courier with a replacement card later this evening. "
                    "No need to share your PIN or account numbers.\n"
                    "Grandma: Thank you for helping.\n"
                    "Specialist: Of course. Expect a confirmation call tonight if anything changes."
                ),
                "key_points": [
                    "Bank spotted fraudulent charge and is replacing card",
                    "No personal information requested over the phone",
                ],
                "reminders": [
                    {"time": "2025-11-17 19:00", "text": "Expect courier with replacement card"},
                ],
                "scam_analysis": {
                    "is_scam": False,
                    "confidence": 0.25,
                    "scam_type": None,
                    "risk_factors": [],
                    "reasoning": "Legitimate bank fraud alert with no sensitive requests.",
                },
                "safe_contact_added": False,
            },
        ]

        for scenario in scenarios:
            conversation = Conversation(
                conference_name=scenario["conference_name"],
                from_number=scenario["from_number"],
                is_contact=scenario["is_contact"],
            )
            conversation.timestamp = datetime.strptime(
                scenario["timestamp"], "%Y-%m-%d %H:%M"
            )
            conversation.transcript = scenario["transcript"]
            conversation.key_points = scenario["key_points"]
            conversation.reminders = [
                Reminder(reminder["time"], reminder["text"])
                for reminder in scenario["reminders"]
            ]

            scam_analysis = scenario["scam_analysis"]
            conversation.scam_analysis = ScamAnalysis(**scam_analysis)
            conversation.scam_alerted = scam_analysis["is_scam"]
            conversation.safe_contact_added = scenario["safe_contact_added"]

            self.conversations[scenario["sid"]] = conversation
