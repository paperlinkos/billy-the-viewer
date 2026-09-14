/// RecognitionSignature encapsulates the invariant visual feature representation
/// of an advertisement creative used by Billy's matching engine.
///
/// Designed as an extensible multi-representation container:
/// - [perceptualFeatures]: Normalized relative spatial luminance/gradient descriptor (current lightweight engine)
/// - [embedding]: Dense vector from future neural vision models (e.g. MobileNet / TFLite)
/// - [keypointFeatures]: Local invariant keypoint coordinates / descriptors (future ORB/SIFT/SuperPoint)
/// - [metadata]: Feature dimensions, generation timestamp, quality checks, algorithm version
class RecognitionSignature {
  final String version;
  final List<double> perceptualFeatures;
  final List<double>? embedding;
  final Map<String, dynamic>? keypointFeatures;
  final Map<String, dynamic> metadata;

  const RecognitionSignature({
    this.version = '1.0',
    this.perceptualFeatures = const [],
    this.embedding,
    this.keypointFeatures,
    this.metadata = const {},
  });

  /// Primary feature vector used for similarity comparison in the current matching engine.
  List<double> get primaryFeatures {
    if (embedding != null && embedding!.isNotEmpty) {
      return embedding!;
    }
    return perceptualFeatures;
  }

  bool get isValid => primaryFeatures.isNotEmpty;

  /// Diagnostic metadata getters (non-technical summaries for diagnostics)
  String get algorithm => metadata['algorithm'] as String? ?? 'relative_spatial_gradient_192';
  String get signatureVersion => (metadata['signatureVersion'] ?? version) as String;
  String get dimensions => metadata['dimensions'] as String? ?? '';
  String? get processingTimestamp =>
      (metadata['processingTimestamp'] ?? metadata['generatedAt']) as String?;
  int get processingDurationMs =>
      (metadata['processingDurationMs'] ?? metadata['processingTimeMs'] ?? 0) as int;

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'perceptualFeatures': perceptualFeatures,
      if (embedding != null) 'embedding': embedding,
      if (keypointFeatures != null) 'keypointFeatures': keypointFeatures,
      'metadata': metadata,
    };
  }

  factory RecognitionSignature.fromJson(Map<String, dynamic> json) {
    return RecognitionSignature(
      version: json['version'] as String? ?? '1.0',
      perceptualFeatures: (json['perceptualFeatures'] as List<dynamic>?)
              ?.map((e) => (e as num).toDouble())
              .toList() ??
          const [],
      embedding: (json['embedding'] as List<dynamic>?)
          ?.map((e) => (e as num).toDouble())
          .toList(),
      keypointFeatures: json['keypointFeatures'] as Map<String, dynamic>?,
      metadata: (json['metadata'] as Map<String, dynamic>?) ?? const {},
    );
  }

  @override
  String toString() =>
      'RecognitionSignature(v: $version, perceptualDim: ${perceptualFeatures.length}, '
      'embeddingDim: ${embedding?.length ?? 0}, valid: $isValid)';
}
