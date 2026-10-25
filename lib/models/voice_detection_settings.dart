enum PracticeDifficulty {
  beginner('Beginner', 'Keeps earned progress when the pitch is missed.'),
  medium('Medium', 'Resets progress for the current note.'),
  advanced('Advanced', 'Returns to the beginning of the score.');

  const PracticeDifficulty(this.label, this.description);
  final String label;
  final String description;
}

class VoiceDetectionSettings {
  const VoiceDetectionSettings({
    this.minimumFrequency = 65,
    this.maximumFrequency = 1200,
    this.minimumConfidence = 0.80,
    this.minimumNoteDurationMs = 100,
    this.pitchStabilityMs = 70,
    this.silenceThresholdDb = -40,
    this.silenceDurationMs = 180,
    this.articulationGapMs = 35,
    this.pitchToleranceCents = 45,
    this.practiceDifficulty = PracticeDifficulty.beginner,
    this.cursorFollowFraction = .40,
    this.smoothingWindow = 3,
    this.voicePolish = .35,
  });

  final double minimumFrequency;
  final double maximumFrequency;
  final double minimumConfidence;
  final int minimumNoteDurationMs;
  final int pitchStabilityMs;
  final double silenceThresholdDb;
  final int silenceDurationMs;
  final int articulationGapMs;
  final double pitchToleranceCents;
  final PracticeDifficulty practiceDifficulty;
  final double cursorFollowFraction;
  final int smoothingWindow;
  final double voicePolish;

  VoiceDetectionSettings copyWith({
    double? minimumFrequency,
    double? maximumFrequency,
    double? minimumConfidence,
    int? minimumNoteDurationMs,
    int? pitchStabilityMs,
    double? silenceThresholdDb,
    int? silenceDurationMs,
    int? articulationGapMs,
    double? pitchToleranceCents,
    PracticeDifficulty? practiceDifficulty,
    double? cursorFollowFraction,
    int? smoothingWindow,
    double? voicePolish,
  }) {
    return VoiceDetectionSettings(
      minimumFrequency: minimumFrequency ?? this.minimumFrequency,
      maximumFrequency: maximumFrequency ?? this.maximumFrequency,
      minimumConfidence: minimumConfidence ?? this.minimumConfidence,
      minimumNoteDurationMs:
          minimumNoteDurationMs ?? this.minimumNoteDurationMs,
      pitchStabilityMs: pitchStabilityMs ?? this.pitchStabilityMs,
      silenceThresholdDb: silenceThresholdDb ?? this.silenceThresholdDb,
      silenceDurationMs: silenceDurationMs ?? this.silenceDurationMs,
      articulationGapMs: articulationGapMs ?? this.articulationGapMs,
      pitchToleranceCents: pitchToleranceCents ?? this.pitchToleranceCents,
      practiceDifficulty: practiceDifficulty ?? this.practiceDifficulty,
      cursorFollowFraction: cursorFollowFraction ?? this.cursorFollowFraction,
      smoothingWindow: smoothingWindow ?? this.smoothingWindow,
      voicePolish: voicePolish ?? this.voicePolish,
    );
  }
}
