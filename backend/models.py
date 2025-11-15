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
    def __init__(self, sid: str, conference_name: str, from_number: str, is_contact: bool):
        self.sid = sid
        self.conference_name = conference_name
        self.from_number = from_number
        self.is_contact = is_contact
        self.transcript = ""
        self.key_points: List[str] = []
        self.reminders: List[Reminder] = []
        self.scam_analysis: Optional[ScamAnalysis] = None

    def to_dict(self) -> Dict[str, object]:
        return {
            "sid": self.sid,
            "conference_name": self.conference_name,
            "from_number": self.from_number,
            "is_contact": self.is_contact,
            "key_points": self.key_points,
            "reminders": [reminder.to_dict() for reminder in self.reminders],
            "scam_analysis": self.scam_analysis.model_dump() if self.scam_analysis else None,
        }


class DataLayer():
    def __init__(self):
        self.recording_audio_buffer = []
        self.is_recording = False
        self.current_conversation_sid: Optional[str] = None
        self.conversations: Dict[str, Conversation] = {}
        self.contacts: List[Contact] = self._load_contacts()

    @property
    def current_conversation(self) -> Optional[Conversation]:
        if self.current_conversation_sid is None:
            return None
        return self.conversations[self.current_conversation_sid]

    def _load_contacts(self) -> List[Contact]:
        contacts_env = os.getenv("CONTACTS")

        contacts: List[Contact] = []

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
