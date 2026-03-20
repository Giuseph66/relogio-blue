enum SyncStatus { pending, synced, failed }

/// Lifecycle state of the question sent (or not sent) to the watch.
enum QuestionStatus {
  /// Watch was offline when the visit was detected – nothing was sent.
  watchOffline,

  /// Question was sent to the watch but no answer was received (yet).
  questionSent,

  /// The watch answered the question.
  answered,
}

class WatchResponse {
  final String id;
  final String locationId;
  final String locationName;
  final String questionId;
  /// Null when [questionStatus] is [watchOffline] or [questionSent].
  final String? answerId;
  final DateTime timestamp;
  final SyncStatus syncStatus;
  final QuestionStatus questionStatus;
  /// The full BLE command string (e.g. QST|id|prompt|opt1:lbl1|opt2:lbl2).
  /// Used to display the question text and to resend without re-fetching server.
  final String? questionCommand;

  const WatchResponse({
    required this.id,
    required this.locationId,
    required this.locationName,
    required this.questionId,
    this.answerId,
    required this.timestamp,
    required this.syncStatus,
    this.questionStatus = QuestionStatus.answered,
    this.questionCommand,
  });

  /// Human-readable question prompt extracted from [questionCommand].
  String? get questionText {
    if (questionCommand == null) return null;
    final parts = questionCommand!.split('|');
    if (parts.length >= 3) return parts[2];
    return null;
  }

  /// Human-readable answer label extracted from [questionCommand] for [answerId].
  /// Falls back to [answerId] itself if no label is found.
  String? get answerLabel {
    if (answerId == null || answerId!.isEmpty) return null;
    if (questionCommand == null) return answerId;
    final parts = questionCommand!.split('|');
    // Options start at index 3: "optId:label"
    for (int i = 3; i < parts.length; i++) {
      final sep = parts[i].indexOf(':');
      if (sep <= 0) continue;
      final optId = parts[i].substring(0, sep);
      if (optId == answerId) return parts[i].substring(sep + 1);
    }
    return answerId;
  }

  WatchResponse copyWith({SyncStatus? syncStatus, QuestionStatus? questionStatus, String? answerId}) {
    return WatchResponse(
      id: id,
      locationId: locationId,
      locationName: locationName,
      questionId: questionId,
      answerId: answerId ?? this.answerId,
      timestamp: timestamp,
      syncStatus: syncStatus ?? this.syncStatus,
      questionStatus: questionStatus ?? this.questionStatus,
      questionCommand: questionCommand,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'location_id': locationId,
      'location_name': locationName,
      'question_id': questionId,
      'answer_id': answerId ?? '',
      'timestamp': timestamp.toIso8601String(),
      'sync_status': syncStatus.name,
      'question_status': questionStatus.name,
      'question_command': questionCommand ?? '',
    };
  }

  factory WatchResponse.fromMap(Map<String, dynamic> map) {
    final answerRaw = map['answer_id'] as String? ?? '';
    return WatchResponse(
      id: map['id'] as String,
      locationId: map['location_id'] as String,
      locationName: map['location_name'] as String,
      questionId: map['question_id'] as String,
      answerId: answerRaw.isEmpty ? null : answerRaw,
      timestamp: DateTime.parse(map['timestamp'] as String),
      syncStatus: SyncStatus.values.firstWhere(
        (s) => s.name == map['sync_status'],
        orElse: () => SyncStatus.pending,
      ),
      questionStatus: QuestionStatus.values.firstWhere(
        (s) => s.name == (map['question_status'] ?? 'answered'),
        orElse: () => QuestionStatus.answered,
      ),
      questionCommand: (() {
        final v = map['question_command'] as String? ?? '';
        return v.isEmpty ? null : v;
      })(),
    );
  }
}
