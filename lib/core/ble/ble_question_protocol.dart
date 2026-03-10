class BleQuestionOption {
  final String id;
  final String label;

  const BleQuestionOption({
    required this.id,
    required this.label,
  });
}

class BleQuestionPrompt {
  final String questionId;
  final String question;
  final List<BleQuestionOption> options;

  const BleQuestionPrompt({
    required this.questionId,
    required this.question,
    required this.options,
  });
}

class BleQuestionResult {
  final String questionId;
  final String? answerId;
  final String? errorCode;

  const BleQuestionResult.answer({
    required this.questionId,
    required this.answerId,
  }) : errorCode = null;

  const BleQuestionResult.error({
    required this.questionId,
    required this.errorCode,
  }) : answerId = null;

  bool get isAnswer => answerId != null;
  bool get isError => errorCode != null;
}

const String bleQuestionHeader = 'QST';
const String bleQuestionAnswerHeader = 'QANS';
const String bleQuestionErrorHeader = 'QERR';
const int bleQuestionMaxOptions = 4;
const int bleQuestionMinOptions = 2;
const int bleQuestionMaxPayloadLength = 140;

String sanitizeBleQuestionText(
  String value, {
  int maxLength = 28,
}) {
  final collapsed = value
      .replaceAll('|', ' ')
      .replaceAll(':', ' ')
      .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  if (collapsed.length <= maxLength) {
    return collapsed;
  }

  return collapsed.substring(0, maxLength).trim();
}

String buildBleQuestionCommand(BleQuestionPrompt prompt) {
  final safeQuestionId = sanitizeBleQuestionText(prompt.questionId, maxLength: 18);
  final safeQuestion = sanitizeBleQuestionText(prompt.question, maxLength: 44);
  final optionTokens = prompt.options
      .take(bleQuestionMaxOptions)
      .map((option) {
        final safeId = sanitizeBleQuestionText(option.id, maxLength: 16);
        final safeLabel = sanitizeBleQuestionText(option.label, maxLength: 14);
        return '$safeId:$safeLabel';
      })
      .where((token) => token.contains(':'))
      .toList(growable: false);

  return <String>[
    bleQuestionHeader,
    safeQuestionId,
    safeQuestion,
    ...optionTokens,
  ].join('|');
}

BleQuestionPrompt? tryParseBleQuestionCommand(String content) {
  final raw = content.trim();
  if (!raw.startsWith('$bleQuestionHeader|')) {
    return null;
  }

  final parts = raw.split('|');
  if (parts.length < 5) {
    return null;
  }

  final questionId = parts[1].trim();
  final question = parts[2].trim();
  if (questionId.isEmpty || question.isEmpty) {
    return null;
  }

  final options = <BleQuestionOption>[];
  for (final token in parts.skip(3)) {
    final separator = token.indexOf(':');
    if (separator <= 0 || separator >= token.length - 1) {
      return null;
    }
    final id = token.substring(0, separator).trim();
    final label = token.substring(separator + 1).trim();
    if (id.isEmpty || label.isEmpty) {
      return null;
    }
    options.add(BleQuestionOption(id: id, label: label));
  }

  if (options.length < bleQuestionMinOptions) {
    return null;
  }

  return BleQuestionPrompt(
    questionId: questionId,
    question: question,
    options: options.take(bleQuestionMaxOptions).toList(growable: false),
  );
}

BleQuestionResult? tryParseBleQuestionResult(String content) {
  final raw = content.trim();
  if (raw.startsWith('$bleQuestionAnswerHeader|')) {
    final parts = raw.split('|');
    if (parts.length != 3) {
      return null;
    }
    final questionId = parts[1].trim();
    final answerId = parts[2].trim();
    if (questionId.isEmpty || answerId.isEmpty) {
      return null;
    }
    return BleQuestionResult.answer(
      questionId: questionId,
      answerId: answerId,
    );
  }

  if (raw.startsWith('$bleQuestionErrorHeader|')) {
    final parts = raw.split('|');
    if (parts.length != 3) {
      return null;
    }
    final questionId = parts[1].trim();
    final errorCode = parts[2].trim();
    if (questionId.isEmpty || errorCode.isEmpty) {
      return null;
    }
    return BleQuestionResult.error(
      questionId: questionId,
      errorCode: errorCode,
    );
  }

  return null;
}
