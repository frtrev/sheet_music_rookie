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
    this.smoothingWindow = 3,
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
  final int smoothingWindow;

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
    int? smoothingWindow,
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
      smoothingWindow: smoothingWindow ?? this.smoothingWindow,
    );
  }
}
