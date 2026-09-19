import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import '../models/recognition_signature.dart';
import 'ocr_service.dart';
import 'vision_service.dart';

/// Abstract contract for signature generators.
/// Allows swapping the underlying feature extraction (e.g. lightweight vision descriptor,
/// MobileNet neural embedding, ORB/SIFT local keypoints) without changing callers.
abstract class ISignatureGenerator {
  Future<RecognitionSignature> generate(Uint8List creativeBytes);
}

/// Default signature generator using Billy's 192-dimensional relative spatial
/// luminance/gradient visual descriptor coupled with on-device OCR text extraction.
class LightweightSignatureGenerator implements ISignatureGenerator {
  final VisionService _visionService;
  final IOcrEngine _ocrEngine;

  LightweightSignatureGenerator({
    VisionService? visionService,
    IOcrEngine? ocrEngine,
  })  : _visionService = visionService ?? VisionService(),
        _ocrEngine = ocrEngine ?? OcrService();

  @override
  Future<RecognitionSignature> generate(Uint8List creativeBytes) async {
    final stopwatch = Stopwatch()..start();

    // 1. Visual feature extraction (192-dim relative spatial descriptor)
    final features = await _visionService.generateEmbeddingFromBytes(creativeBytes);

    if (features.isEmpty) {
      throw StateError(
        'Failed to extract visual signature: creative is either unreadable or lacks sufficient visual contrast.',
      );
    }

    // 2. Local OCR / text extraction
    OcrResult ocrResult = OcrResult.empty;
    try {
      ocrResult = await _ocrEngine.extractText(creativeBytes);
    } catch (e) {
      debugPrint('LightweightSignatureGenerator: OCR extraction warning: $e');
    }

    stopwatch.stop();

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
      ocrText: ocrResult.rawText,
      normalizedOcrText: ocrResult.normalizedText,
      ocrMetadata: ocrResult.metadata.isNotEmpty ? ocrResult.metadata : null,
      metadata: {
        'dimension': features.length,
        'algorithm': 'relative_spatial_gradient_192',
        'signatureVersion': '1.0',
        'dimensions': dimensions,
        'hasOcrText': ocrResult.hasText,
        'ocrWordsCount': ocrResult.words.length,
        'processingTimestamp': now.toIso8601String(),
        'processingDurationMs': stopwatch.elapsedMilliseconds,
        'generatedAt': now.toIso8601String(),
        'processingTimeMs': stopwatch.elapsedMilliseconds,
      },
    );
  }
}

/// SignatureService is the standalone domain service responsible for converting
/// raw advertisement creative assets into a robust, invariant [RecognitionSignature]
/// combining invariant visual spatial features and on-device text OCR.
///
/// It does NOT know about UI, user accounts, payments, or campaign presentation.
class SignatureService {
  final ISignatureGenerator _generator;

  SignatureService({
    ISignatureGenerator? generator,
    VisionService? visionService,
    IOcrEngine? ocrEngine,
  }) : _generator = generator ??
            LightweightSignatureGenerator(
              visionService: visionService,
              ocrEngine: ocrEngine,
            );

  /// Processes raw creative bytes (JPG, JPEG, PNG) and generates a [RecognitionSignature].
  Future<RecognitionSignature> generateSignature(Uint8List creativeBytes) async {
    if (creativeBytes.isEmpty) {
      throw ArgumentError('Creative bytes cannot be empty.');
    }
    return _generator.generate(creativeBytes);
  }
}
