import datetime
from typing import List, Optional
from langchain_openai import ChatOpenAI
from langchain_core.prompts import ChatPromptTemplate
from pydantic import BaseModel, Field
from dotenv import load_dotenv

load_dotenv()


class ReminderItem(BaseModel):
    """Reminder details tailored for an elderly listener."""

    short_text: str = Field(
        description=(
            "Short, specific reminder phrased kindly and clearly so the user knows "
            "what to do ahead of time"
        )
    )
    reminder_time: str = Field(
        description=(
            "Date and time to display the reminder in YYYY-MM-DD HH:MM 24-hour format; "
            "should be scheduled before the related event or action and align with the "
            "reference datetime context"
        )
    )


class ConversationSummary(BaseModel):
    """Structured conversation summary output."""

    key_points: List[str] = Field(
        description="Bullet-sized key points from the conversation"
    )
    reminders: List[ReminderItem] = Field(
        default_factory=list,
        description="Helpful reminders with associated times for the user",
    )


class ConversationSummarizer:
    """Summarize conversations and suggest timely reminders."""

    def __init__(self, model: str = "gpt-4o", temperature: float = 0.2):
        self.llm = ChatOpenAI(model=model, temperature=temperature)

        self.prompt = ChatPromptTemplate.from_messages(
            [
                (
                    "system",
                    """You are an assistant helping summarize phone conversations
                    for an elderly person. Write friendly, plain-language key points.

                    Reference conversation datetime (local time): {reference_datetime}

                    When proposing reminders:
                    - Keep them short, specific, and supportive
                    - Include only reminders still relevant in the future
                    - Set reminder_time using YYYY-MM-DD HH:MM in 24-hour format (e.g., 2025-11-15 14:30)
                    - Ensure reminder_time gives the user advance notice before the related action
                    - For appointments with explicit times, schedule the reminder 1-2 hours earlier
                    - For next-day or morning tasks without an exact time, use the prior evening around 20:00
                    - For medication tied to meals, remind shortly before the meal (e.g., dinner at 18:00)
                    - If reference_datetime is 'unspecified' or details are missing, do NOT fabricate dates.
                    Skip any reminders that cannot be grounded precisely.


                    If no reminder is needed, return an empty reminders list.""",
                ),
                (
                    "human",
                    "Conversation transcript:\n\n{transcript}\n\n"
                    "Ensure reminder timing reflects the reference datetime.",
                ),
            ]
        )

        self.chain = self.prompt | self.llm.with_structured_output(ConversationSummary)

    def summarize(
        self, transcript: str, reference_datetime: Optional[str] = None
    ) -> ConversationSummary:
        """
        Generate key points and elderly-friendly reminders.

        Args:
            transcript: Conversation transcript to analyze.
            reference_datetime: ISO-like string (YYYY-MM-DD HH:MM) indicating when the
                conversation took place. Used to ground relative dates (e.g., "tomorrow")
                in reminders. If omitted, reminders requiring absolute dates are skipped.
        """
        grounded_reference = reference_datetime or datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
        return self.chain.invoke(
            {
                "transcript": transcript,
                "reference_datetime": grounded_reference,
            }
        )


if __name__ == "__main__":
    sample_transcript = """
    Granddaughter: Hi Grandma, the doctor appointment is on Tuesday at 3 PM.
    Please take the new medication tonight with dinner.

    Grandma: Thank you dear, I will. Anything else I should remember?

    Granddaughter: Yes, don't forget to call me tomorrow morning if you feel dizzy.
    """

    summarizer = ConversationSummarizer()
    summary = summarizer.summarize(sample_transcript, "2025-11-15 14:30")

    print("Key Points:")
    for point in summary.key_points:
        print(f"- {point}")

    if summary.reminders:
        print("\nReminders:")
        for reminder in summary.reminders:
            print(f"- {reminder.reminder_time} : {reminder.short_text}")
    else:
        print("\nReminders: None needed.")

