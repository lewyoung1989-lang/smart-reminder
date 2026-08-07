class VoiceTranscription {
  const VoiceTranscription({
    required this.requestId,
    required this.transcript,
    required this.audioDurationMs,
    required this.transcriptionLatencyMs,
    required this.provider,
  });

  factory VoiceTranscription.fromJson(Map<String, dynamic> json) {
    return VoiceTranscription(
      requestId: json['request_id'] as String,
      transcript: json['transcript'] as String,
      audioDurationMs: json['audio_duration_ms'] as int,
      transcriptionLatencyMs: json['transcription_latency_ms'] as int,
      provider: json['provider'] as String,
    );
  }

  final String requestId;
  final String transcript;
  final int audioDurationMs;
  final int transcriptionLatencyMs;
  final String provider;
}
