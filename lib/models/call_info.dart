class CallInfo {
  final String id;
  final String phoneNumber;
  final String? contactName;
  final DateTime timestamp;
  final CallType type;
  final CallStatus status;
  final bool? isScam;

  CallInfo({
    required this.id,
    required this.phoneNumber,
    this.contactName,
    required this.timestamp,
    required this.type,
    required this.status,
    this.isScam,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'phoneNumber': phoneNumber,
      'contactName': contactName,
      'timestamp': timestamp.toIso8601String(),
      'type': type.toString(),
      'status': status.toString(),
      'isScam': isScam,
    };
  }

  factory CallInfo.fromJson(Map<String, dynamic> json) {
    return CallInfo(
      id: json['id'] as String,
      phoneNumber: json['phoneNumber'] as String,
      contactName: json['contactName'] as String?,
      timestamp: DateTime.parse(json['timestamp'] as String),
      type: CallType.values.firstWhere(
        (e) => e.toString() == json['type'],
        orElse: () => CallType.incoming,
      ),
      status: CallStatus.values.firstWhere(
        (e) => e.toString() == json['status'],
        orElse: () => CallStatus.ringing,
      ),
      isScam: json['isScam'] as bool?,
    );
  }
}

enum CallType { incoming, outgoing }

enum CallStatus { ringing, answered, declined, ended, missed }
