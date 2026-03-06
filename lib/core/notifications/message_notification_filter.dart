class MessageNotificationFilter {
  static bool shouldNotify({
    required String content,
    required bool notificationsEnabled,
    required bool filterEnabled,
    required List<String> allowedPatterns,
  }) {
    if (!notificationsEnabled) {
      return false;
    }

    if (isTickMessage(content)) {
      return false;
    }

    if (!filterEnabled) {
      return true;
    }

    final activePatterns = allowedPatterns
        .map((pattern) => pattern.trim().toLowerCase())
        .where((pattern) => pattern.isNotEmpty)
        .toList(growable: false);

    if (activePatterns.isEmpty) {
      return false;
    }

    final normalized = normalize(content);
    for (final pattern in activePatterns) {
      if (normalized.contains(pattern)) {
        return true;
      }
    }
    return false;
  }

  static bool isTickMessage(String content) {
    final normalized = normalize(content);
    return normalized.startsWith('tick:') || normalized.startsWith('tick :');
  }

  static String normalize(String content) {
    return content
        .replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), ' ')
        .toLowerCase()
        .trim();
  }
}
