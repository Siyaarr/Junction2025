ARCHITECTURE.md
ElderGuard – AI Call & SMS Scam Shield

Protecting older adults from phone and text scams using an AI-first telephony middleware.

1. Project Description

ElderGuard is a mobile scam-protection system designed for older adults.
It uses a guardian phone number powered by a telephony middleware (Twilio or similar) to intercept calls and SMS, analyze their content with AI, and forward them to the user with real-time scam detection warnings.

The user's mobile app (React Native + Expo) acts as a scam guardian interface, showing loud, simple alerts during suspected scam interactions and optionally notifying trusted family members.

This architecture bypasses OS limitations (Android/iOS restrictions on call audio access) by handling calls and SMS in the cloud, where AI models have full visibility into transcripts and message content.

2. High-Level System Overview
Caller → Guardian Number (Twilio) → Backend → AI Analysis → ElderGuard App → User


Core components:

Mobile App (React Native + Expo)

Elder-facing interface

Simple warnings, noisy alerts

History of events

Receives push notifications from backend

Future: in-app VoIP call handling

Telephony Middleware (Twilio or equivalent)

Provides guardian phone numbers

Routes inbound SMS + calls

Streams call audio for transcription

Forwards calls to user’s real number or app

Backend API

Handles Twilio webhooks

Sends SMS/call content to AI

Maps guardian number → user

Sends alerts to user devices

Logs events and risk analysis results

Optional caregiver notifications

AI Analysis Service

Classifies SMS and call transcripts

Outputs structured risk levels

Supports realtime / streaming analysis

Detects typical scam patterns:

urgency

payment requests

bank login code requests

impersonation (family, government, bank)

Database

Users

Devices

Trusted contacts

Call logs

SMS logs

Risk history

Guardian number assignments

Notification Layer

Expo push notifications

Optional email/SMS to family contacts

3. Core Flows
3.1 Onboarding

User installs the ElderGuard app.

Backend assigns / provisions a guardian number from Twilio.

User (or caregiver) adds trusted contacts.

Device registers for push notifications.

User shares their guardian number with their important contacts.

The existing SIM number still works, but protection is strongest when people call/text the guardian number.

3.2 Incoming SMS Flow

Flow:

SMS → Twilio guardian number

Twilio sends webhook /twilio/sms with:

From, To, Body

Timestamp, metadata

Backend:

Resolves user from guardian number

Stores message

Sends text to AI analysis service

AI returns:

{
  "risk": 0.92,
  "label": "likely_scam",
  "reason": "Suspicious payment link + urgency.",
  "recommendedAction": "ignore"
}


Backend triggers:

Push notification to the RN app

UI banner: “⚠ Possible scam message”

Optional family notification

RN app shows the alert and explanation.

3.3 Incoming Call Flow (Middleware Approach)

Flow:

Caller → Guardian number

Twilio invokes /twilio/voice/incoming webhook

Backend replies with instructions:

Start audio recording or media streaming

Forward call to user’s SIM or VoIP client

STT engine converts audio → transcript

AI service processes transcript in chunks

AI updates risk levels during the call

Backend sends real-time alerts:

Push notification

WebSocket updates

RN app:

Shows live risk meter

Displays large text warnings (“They are asking for banking codes.”)

Plays loud sound/vibration

Provides BIG buttons:

HANG UP NOW

“Call my daughter”

4. Component Responsibilities
4.1 Mobile App (React Native + Expo)

Elder-friendly UI

Receive push notifications for scam alerts

Display warning banners + explanations

Show simple event history

Manage user preferences & trusted contacts

Connect to backend for:

login/registration

guardian number retrieval

logs and risk results

Optional: WebSocket for low latency call warnings

4.2 Backend API

Endpoints:

/twilio/sms – SMS webhook

/twilio/voice/incoming – inbound call

/twilio/voice/status – call state

/auth/* – user auth

/device/register – push token registration

Responsibilities:

Parse Twilio requests

Map guardian number → user

Call AI service

Record data in DB

Trigger Expo push notifications

Return call instructions (TwiML) including:

<Connect> (forward call)

<Start><Stream> (real-time audio)

User management and caregiver notifications

4.3 AI Analysis Service

Input:

SMS text

Call transcript segment

Caller metadata

User context

Output Format:

{
  "risk": 0 to 1,
  "label": "safe" | "unsure" | "likely_scam",
  "reason": "short human-friendly explanation",
  "recommendedAction": "ignore" | "be_cautious" | "hang_up",
  "features": {
    "contains_keywords": [...],
    "urgency_score": 0.8
  }
}


Capabilities:

Detect phishing elements

Detect impersonation scams

Detect emotional manipulation (urgency, threats)

Combine rule-based heuristics + LLM reasoning

4.4 Database Schema (initial)

users

id

name

real_phone_number

guardian_phone_number

trusted_contacts (JSON or relation)

created_at

devices

id

user_id

expo_push_token

platform

sms_messages

id

user_id

from_number

body

timestamp

risk

label

reason

calls

id

user_id

from_number

started_at

ended_at

final_risk

label

reason

call_transcripts

id

call_id

segment_index

text

timestamp

segment_risk

5. Technology Stack
Client

React Native (Expo)

Gluestack UI

Expo Notifications

Optional: WebSockets for live call warnings

Backend

Node.js (TypeScript) or Python

Express / Fastify or FastAPI

Twilio SDK

Postgres or SQLite (for hackathon)

Redis (optional) for streaming events

AI

LLM via OpenAI API or similar

Whisper / Deepgram / Twilio Media Streams for STT (optional for hackathon)

Telephony

Twilio Programmable SMS

Twilio Programmable Voice

Call Forwarding + Media Streams

6. MVP Scope (Hackathon)
Fully Implementable

Guardian number provisioning

Incoming SMS → AI → warning push

RN app with simple UI + warning modals

Logs of SMS + risk in app

Partial / Simulated

Simulated inbound call with transcribed text

AI call analysis loop

UI for live call warnings

Optional: real Twilio call route without live AI

Future Production Features

Real-time STT on calls

Automatic hang-up for high-risk calls

Trusted family dashboard

Number porting (optional)

7. Architecture Diagram (ASCII)
                  ┌────────────────┐
                  │     Caller     │
                  └───────┬────────┘
                          │
                          ▼
              ┌────────────────────────┐
              │  Guardian Number (Twilio) │
              └───────┬──────────────┘
            SMS Webhook│      Voice Webhook
                      │                  │
                      ▼                  ▼
             ┌────────────────┐   ┌─────────────────┐
             │  Backend API   │<->│ AI Analysis Svc │
             └───────┬────────┘   └─────────────────┘
        Push Alerts  │
                     ▼
          ┌─────────────────────┐
          │ ElderGuard RN App   │
          │ (React Native/Expo) │
          └─────────────────────┘

8. Guidance for AI Agents in the Codebase

Treat the guardian number as the primary entrypoint for all protected communication.

All SMS/calls must be processed through:
telephony → backend → AI → mobile app

For call analysis:

Use streaming transcript chunks where possible

Always output structured RiskResult objects

Ensure explanations are plain-language and elder-friendly

When building UI flows:

Prioritize clarity over density

Large text, high contrast, minimal actions