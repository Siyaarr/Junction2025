class Conversation {
  final String conferenceName;
  final String fromNumber;
  final bool isContact;
  final List<String> keyPoints;
  final List<Reminder> reminders;
  final bool safeContactAdded;
  final bool scamAlerted;
  final ScamAnalysis? scamAnalysis;
  final DateTime timestamp;

  Conversation({
    required this.conferenceName,
    required this.fromNumber,
    required this.isContact,
    required this.keyPoints,
    required this.reminders,
    required this.safeContactAdded,
    required this.scamAlerted,
    this.scamAnalysis,
    required this.timestamp,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      conferenceName: json['conference_name'] as String? ?? '',
      fromNumber: json['from_number'] as String? ?? '',
      isContact: json['is_contact'] as bool? ?? false,
      keyPoints: (json['key_points'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      reminders: (json['reminders'] as List<dynamic>?)
              ?.map((e) => Reminder.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      safeContactAdded: json['safe_contact_added'] as bool? ?? false,
      scamAlerted: json['scam_alerted'] as bool? ?? false,
      scamAnalysis: json['scam_analysis'] != null
          ? ScamAnalysis.fromJson(json['scam_analysis'] as Map<String, dynamic>)
          : null,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'conference_name': conferenceName,
      'from_number': fromNumber,
      'is_contact': isContact,
      'key_points': keyPoints,
      'reminders': reminders.map((r) => r.toJson()).toList(),
      'safe_contact_added': safeContactAdded,
      'scam_alerted': scamAlerted,
      'scam_analysis': scamAnalysis?.toJson(),
      'timestamp': timestamp.toIso8601String(),
    };
  }
}

class Reminder {
  final bool sent;
  final String text;
  final String time;

  Reminder({
    required this.sent,
    required this.text,
    required this.time,
  });

  factory Reminder.fromJson(Map<String, dynamic> json) {
    return Reminder(
      sent: json['sent'] as bool? ?? false,
      text: json['text'] as String? ?? '',
      time: json['time'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sent': sent,
      'text': text,
      'time': time,
    };
  }
}

class ScamAnalysis {
  final double confidence;
  final bool isScam;
  final String reasoning;
  final List<String> riskFactors;
  final String? scamType;

  ScamAnalysis({
    required this.confidence,
    required this.isScam,
    required this.reasoning,
    required this.riskFactors,
    this.scamType,
  });

  factory ScamAnalysis.fromJson(Map<String, dynamic> json) {
    return ScamAnalysis(
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      isScam: json['is_scam'] as bool? ?? false,
      reasoning: json['reasoning'] as String? ?? '',
      riskFactors: (json['risk_factors'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      scamType: json['scam_type'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'confidence': confidence,
      'is_scam': isScam,
      'reasoning': reasoning,
      'risk_factors': riskFactors,
      'scam_type': scamType,
    };
  }
}

