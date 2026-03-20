class LocationQuestionOption {
  final String id;
  final String label;

  const LocationQuestionOption({required this.id, required this.label});

  factory LocationQuestionOption.fromJson(Map<String, dynamic> json) {
    return LocationQuestionOption(
      id: json['id'] as String,
      label: json['label'] as String,
    );
  }
}

class LocationQuestion {
  final String id;
  final String prompt;
  final String? locationId;
  final List<LocationQuestionOption> options;

  const LocationQuestion({
    required this.id,
    required this.prompt,
    this.locationId,
    required this.options,
  });

  factory LocationQuestion.fromJson(Map<String, dynamic> json) {
    final optList = (json['options'] as List<dynamic>?) ?? [];
    return LocationQuestion(
      id: json['id'] as String,
      prompt: json['prompt'] as String,
      locationId: json['locationId'] as String?,
      options: optList
          .map((o) => LocationQuestionOption.fromJson(o as Map<String, dynamic>))
          .toList(),
    );
  }
}
