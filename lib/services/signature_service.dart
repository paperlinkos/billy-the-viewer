import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import '../models/recognition_signature.dart';
import 'vision_service.dart';

/// Abstract contract for signature generators.
/// Allows swapping the underlying feature extraction (e.g. lightweight vision descriptor,
/// MobileNet neural embedding, ORB/SIFT local keypoints) without changing callers.
abstract class ISignatureGenerator {
  Future<RecognitionSignature> generate(Uint8List creativeBytes);
}

/// Default signature generator using Billy's 192-dimensional relative spatial
/// luminance and gradient descriptor.
class LightweightSignatureGenerator implements ISignatureGenerator {
  final VisionService _visionService;

  LightweightSignatureGenerator({VisionService? visionService})
      : _visionService = visionService ?? VisionService();

  @override
  Future<RecognitionSignature> generate(Uint8List creativeBytes) async {
    final stopwatch = Stopwatch()..start();
    final features = await _visionService.generateEmbeddingFromBytes(creativeBytes);
    stopwatch.stop();

    if (features.isEmpty) {
      throw StateError(
        'Failed to extract visual signature: creative is either unreadable or lacks sufficient visual contrast.',
      );
    }

    String dimensions = '';
    try {
      final decoded = img.decodeImage(creativeBytes);
      if (decoded != null) {
        dimensions = '${decoded.width}x${decoded.height}';
      }
    } catch (_) {}

    final now = DateTime.now();

    return RecognitionSignature(
      version: '1.0',
      perceptualFeatures: features,
      embedding: null, // Reserved for future TFLite / MobileNet neural embeddings
      keypointFeatures: null, // Reserved for future local visual keypoints
      metadata: {
        'dimension': features.length,
        'algorithm': 'relative_spatial_gradient_192',
        'signatureVersion': '1.0',
        'dimensions': dimensions,
        'processingTimestamp': now.toIso8601String(),
        'processingDurationMs': stopwatch.elapsedMilliseconds,
        'generatedAt': now.toIso8601String(),
        'processingTimeMs': stopwatch.elapsedMilliseconds,
      },
    );
  }
}

/// SignatureService is the standalone domain service responsible for converting
/// raw advertisement creative assets into a robust, invariant [RecognitionSignature].
///
/// It does NOT know about UI, user accounts, payments, or campaign presentation.
class SignatureService {
  final ISignatureGenerator _generator;

  SignatureService({ISignatureGenerator? generator})
      : _generator = generator ?? LightweightSignatureGenerator();

  /// Processes raw creative bytes (JPG, JPEG, PNG) and generates a [RecognitionSignature].
  Future<RecognitionSignature> generateSignature(Uint8List creativeBytes) async {
    if (creativeBytes.isEmpty) {
      throw ArgumentError('Creative bytes cannot be empty.');
    }
    return _generator.generate(creativeBytes);
  }
}
