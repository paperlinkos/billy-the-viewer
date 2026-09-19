import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:billy_the_viewer/models/ad_target.dart';
import 'package:billy_the_viewer/services/matching_engine.dart';
import 'package:billy_the_viewer/services/multi_scale_photo_analyzer.dart';
import 'package:billy_the_viewer/services/ocr_service.dart';
import 'package:billy_the_viewer/services/vision_service.dart';

// ────────────────────────────────────────────────────────────────────────────
// Test doubles
// ────────────────────────────────────────────────────────────────────────────

/// Mock VisionService that returns a fixed embedding every call.
class _FixedVisionService extends VisionService {
  final List<double> _embedding;

  _FixedVisionService(this._embedding);

  @override
  Future<List<double>> generateEmbeddingFromBytes(Uint8List bytes) async =>
      _embedding;
}

/// Mock OcrService that returns configurable OCR results per call.
class _CallSequenceOcrService extends OcrService {
  final List<String> _sequence;
  int _callIndex = 0;

  _CallSequenceOcrService(this._sequence);

  @override
  Future<OcrResult> extractText(Uint8List imageBytes) async {
    final text = _callIndex < _sequence.length ? _sequence[_callIndex] : '';
    _callIndex++;
    final norm = OcrService.normalizeText(text);
    return OcrResult(
      rawText: text,
      normalizedText: norm,
      words: OcrService.extractWords(norm),
    );
  }
}

/// Mock OcrService that returns the same text every call.
class _FixedOcrService extends OcrService {
  final String _text;

  _FixedOcrService(this._text);

  @override
  Future<OcrResult> extractText(Uint8List imageBytes) async {
    final norm = OcrService.normalizeText(_text);
    return OcrResult(
      rawText: _text,
      normalizedText: norm,
      words: OcrService.extractWords(norm),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Helpers
// ────────────────────────────────────────────────────────────────────────────

/// Creates a normalized 192-dim vector uniquely pointing in direction [seed].
List<double> makeEmbedding(int seed) {
  final list = List<double>.generate(192, (i) {
    final angle = (i * seed * 2 * math.pi) / 192.0;
    return math.cos(angle) + math.sin(angle * 0.5);
  });
  double normSq = 0.0;
  for (final v in list) {
    normSq += v * v;
  }
  final norm = math.sqrt(normSq);
  return list.map((v) => norm > 0 ? v / norm : 0.0).toList();
}

/// Creates a 192-dim vector that has approximately [targetSim] cosine similarity
/// with [reference] by mixing reference with an orthogonal vector.
List<double> makeEmbeddingWithSim(List<double> reference, double targetSim, {int orthSeed = 99}) {
  final orth = makeEmbedding(orthSeed);
  final c = targetSim.clamp(0.0, 1.0);
  final s = math.sqrt(1.0 - c * c);
  final mixed = List<double>.generate(192, (i) => c * reference[i] + s * orth[i]);
  double normSq = 0.0;
  for (final v in mixed) {
    normSq += v * v;
  }
  final norm = math.sqrt(normSq);
  return mixed.map((v) => norm > 0 ? v / norm : 0.0).toList();
}

/// Creates a tiny valid JPEG image (16×16 gradient) for use as test image bytes.
img.Image makeTestImage({int width = 480, int height = 720}) {
  final image = img.Image(width: width, height: height);
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final lum = ((x + y) % 200 + 30).clamp(0, 255);
      image.setPixelRgb(x, y, lum, lum, lum);
    }
  }
  return image;
}

AdTarget makeTarget({
  required String id,
  required String name,
  required List<double> embedding,
  String? normalizedOcrText,
}) =>
    AdTarget(
      id: id,
      name: name,
      brand: 'TestBrand',
      destinationUrl: 'https://test.com',
      imageAsset: 'assets/test.jpg',
      embedding: embedding,
      normalizedOcrText: normalizedOcrText,
    );

// ────────────────────────────────────────────────────────────────────────────
// Tests
// ────────────────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const engine = MatchingEngine(threshold: 0.60);

  // ──────────────────────────────────────────────────────────────────────────
  // Unit tests for MultiScalePhotoAnalyzer.extractScaleRegions
  // ──────────────────────────────────────────────────────────────────────────
  group('MultiScalePhotoAnalyzer.extractScaleRegions', () {
    test('produces 8 named regions for a standard portrait image', () {
      final image = makeTestImage(width: 480, height: 720);
      final regions = MultiScalePhotoAnalyzer.extractScaleRegions(image);

      expect(regions.keys, containsAll([
        'full_center',
        'center_75',
        'center_1_5x',
        'center_2x',
        'top',
        'bottom',
        'left',
        'right',
      ]));
      expect(regions.length, equals(8));
    });

    test('full_center is a square with side == min(width, height)', () {
      final image = makeTestImage(width: 480, height: 720);
      final regions = MultiScalePhotoAnalyzer.extractScaleRegions(image);
      final fc = regions['full_center']!;
      expect(fc.width, equals(fc.height));
      expect(fc.width, equals(480)); // min(480,720)
    });

    test('center_2x is smaller than center_1_5x which is smaller than center_75', () {
      final image = makeTestImage(width: 480, height: 720);
      final regions = MultiScalePhotoAnalyzer.extractScaleRegions(image);
      final c75 = regions['center_75']!;
      final c15 = regions['center_1_5x']!;
      final c2x = regions['center_2x']!;

      expect(c75.width, greaterThan(c15.width));
      expect(c15.width, greaterThan(c2x.width));
    });

    test('returns empty map for an image smaller than 64x64', () {
      final tiny = img.Image(width: 32, height: 32);
      final regions = MultiScalePhotoAnalyzer.extractScaleRegions(tiny);
      expect(regions, isEmpty);
    });

    test('square image produces full_center equal to the whole image', () {
      final square = makeTestImage(width: 256, height: 256);
      final regions = MultiScalePhotoAnalyzer.extractScaleRegions(square);
      final fc = regions['full_center']!;
      expect(fc.width, equals(256));
      expect(fc.height, equals(256));
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Integration tests for MultiScalePhotoAnalyzer.analyze
  // ──────────────────────────────────────────────────────────────────────────
  group('MultiScalePhotoAnalyzer.analyze', () {
    // Test 1: Close range — high visual on primary implies recognize without needing multi-scale
    test('1. Close-range: high visual similarity produces confident aggregated match', () async {
      final targetEmb = makeEmbedding(1);

      // Vision service returns high-similarity embedding for all regions
      final visionService = _FixedVisionService(targetEmb);
      final ocrService = _FixedOcrService('');

      final target = makeTarget(id: 'ad_close', name: 'Close Ad', embedding: targetEmb);

      final analyzer = MultiScalePhotoAnalyzer(
        visionService: visionService,
        ocrService: ocrService,
        matchingEngine: engine,
      );

      final image = makeTestImage();
      final result = await analyzer.analyze(
        image: image,
        candidates: [target],
        testTag: 'TEST_CLOSE',
      );

      expect(result.bestCandidate, isNotNull);
      expect(result.bestCandidate!.candidate.id, equals('ad_close'));
      // With 8 regions all returning cosine=1.0, corroboration bonus should apply
      expect(result.bestCandidate!.aggregatedScore, greaterThanOrEqualTo(0.60));
      expect(result.hasConfidentMatch, isTrue);
    });

    // Test 2: Far range — primary visual is 0.43 (fail), but 1.5x/2x zoom boosts visual across multiple regions → aggregated passes
    test('2. Far-range visual-only: repeated corroboration across scales pushes aggregated score over threshold', () async {
      final targetEmb = makeEmbedding(2);

      // At primary scale visual ~ 0.43. Simulate consistent moderate visual across all 8 regions.
      // With corroboration bonus (+0.05) when same candidate wins ≥3 regions: 0.43+0.05=0.48 (still below).
      // So we need a better visual signal at zoom. Use 0.55 simulated.
      final highVisEmb = makeEmbeddingWithSim(targetEmb, 0.56, orthSeed: 7);

      final visionService = _FixedVisionService(highVisEmb);
      final ocrService = _FixedOcrService('');

      final target = makeTarget(id: 'ad_far', name: 'Far Ad', embedding: targetEmb);
      // Distracting competitor
      final other = makeTarget(id: 'ad_other', name: 'Other Ad', embedding: makeEmbedding(50));

      final analyzer = MultiScalePhotoAnalyzer(
        visionService: visionService,
        ocrService: ocrService,
        matchingEngine: engine,
      );

      final image = makeTestImage();
      final result = await analyzer.analyze(
        image: image,
        candidates: [target, other],
        testTag: 'TEST_FAR',
      );

      expect(result.bestCandidate, isNotNull);
      expect(result.bestCandidate!.candidate.id, equals('ad_far'));
      // 8 regions × 0.56 visual pure score → ~0.56 + 0.05 corroboration = ~0.61
      expect(result.bestCandidate!.aggregatedScore, greaterThanOrEqualTo(0.60));
      expect(result.hasConfidentMatch, isTrue);
    });

    // Test 3: Small/partial OCR — OCR fails on primary (empty), succeeds at 2x zoom for same campaign
    test('3. OCR failure at primary scale, success at zoom scale produces correct candidate', () async {
      final targetEmb = makeEmbedding(3);
      final liveEmb = makeEmbeddingWithSim(targetEmb, 0.35, orthSeed: 11);

      // 8 regions analyzed: all return same visual embedding (moderate),
      // OCR sequence: primary empty, then zones return the distinctive text
      final ocrSequence = [
        '',                             // full_center
        '',                             // center_75
        'singular living infinite prestige', // center_1_5x → distinctive hit!
        'singular living',              // center_2x → another distinctive hit
        '',                             // top
        'singular living infinite',     // bottom
        '',                             // left
        '',                             // right
      ];

      final visionService = _FixedVisionService(liveEmb);
      final ocrService = _CallSequenceOcrService(ocrSequence);

      final target = makeTarget(
        id: 'ad_singular',
        name: 'Singular Living',
        embedding: targetEmb,
        normalizedOcrText: 'singular living infinite prestige unmatched exclusivity prestigious location',
      );
      final other = makeTarget(id: 'ad_other', name: 'Other Ad', embedding: makeEmbedding(55));

      final analyzer = MultiScalePhotoAnalyzer(
        visionService: visionService,
        ocrService: ocrService,
        matchingEngine: engine,
      );

      final image = makeTestImage();
      final result = await analyzer.analyze(
        image: image,
        candidates: [target, other],
        testTag: 'TEST_OCR_ZOOM',
      );

      expect(result.bestCandidate, isNotNull);
      // The distinctive text evidence should push Singular Living to the top
      expect(result.bestCandidate!.candidate.id, equals('ad_singular'));
      // Distinctive hits should be counted
      expect(result.bestCandidate!.distinctiveHits, greaterThan(0));
    });

    // Test 4: OCR failure at one scale, success at another
    test('4. Combined visual + partial OCR evidence at different scales identifies correct campaign', () async {
      final targetEmb = makeEmbedding(4);
      final liveEmb = makeEmbeddingWithSim(targetEmb, 0.40, orthSeed: 13);

      // Mixed OCR — succeeds at center_1_5x and bottom
      final ocrSequence = List.filled(8, '');
      ocrSequence[2] = 'modern interior design'; // center_1_5x
      ocrSequence[5] = 'modern interior';        // bottom

      final visionService = _FixedVisionService(liveEmb);
      final ocrService = _CallSequenceOcrService(ocrSequence);

      final target = makeTarget(
        id: 'ad_modern',
        name: 'Modern Interior',
        embedding: targetEmb,
        normalizedOcrText: 'modern interior design luxury spaces crafted',
      );

      final analyzer = MultiScalePhotoAnalyzer(
        visionService: visionService,
        ocrService: ocrService,
        matchingEngine: engine,
      );

      final image = makeTestImage();
      final result = await analyzer.analyze(
        image: image,
        candidates: [target],
        testTag: 'TEST_OCR_MULTI_SCALE',
      );

      expect(result.bestCandidate, isNotNull);
      expect(result.bestCandidate!.candidate.id, equals('ad_modern'));
      expect(result.bestCandidate!.distinctiveHits, greaterThan(0));
    });

    // Test 5: Visual evidence survives when OCR fails everywhere
    test('5. Visual evidence alone (OCR empty everywhere) identifies candidate when visual is consistently high', () async {
      final targetEmb = makeEmbedding(5);
      final liveEmb = makeEmbeddingWithSim(targetEmb, 0.57, orthSeed: 17);

      // All OCR calls return empty
      final visionService = _FixedVisionService(liveEmb);
      final ocrService = _FixedOcrService('');

      final target = makeTarget(id: 'ad_visual', name: 'Visual Only Ad', embedding: targetEmb);

      final analyzer = MultiScalePhotoAnalyzer(
        visionService: visionService,
        ocrService: ocrService,
        matchingEngine: engine,
      );

      final image = makeTestImage();
      final result = await analyzer.analyze(
        image: image,
        candidates: [target],
        testTag: 'TEST_VISUAL_ONLY',
      );

      expect(result.bestCandidate, isNotNull);
      expect(result.bestCandidate!.candidate.id, equals('ad_visual'));
      // With 8 regions all at ~0.57 visual, corroboration bonus → 0.62 ≥ 0.60
      expect(result.hasConfidentMatch, isTrue);
    });

    // Test 6: Unrelated image remains NO MATCH
    test('6. Completely unrelated image produces NO MATCH across all scales', () async {
      final targetEmb = makeEmbedding(6);
      // Live embedding points in opposite direction (cosine ~ -0.3 with target)
      final liveEmb = makeEmbedding(99); // Very different direction

      final visionService = _FixedVisionService(liveEmb);
      final ocrService = _FixedOcrService('lorem ipsum dolor');

      final target = makeTarget(
        id: 'ad_real',
        name: 'Real Ad',
        embedding: targetEmb,
        normalizedOcrText: 'singular living infinite prestige',
      );

      final analyzer = MultiScalePhotoAnalyzer(
        visionService: visionService,
        ocrService: ocrService,
        matchingEngine: engine,
      );

      final image = makeTestImage();
      final result = await analyzer.analyze(
        image: image,
        candidates: [target],
        testTag: 'TEST_UNRELATED',
      );

      // Visual plausibility guard must reject low-visual candidates
      // or the combined score must remain below threshold
      if (result.bestCandidate != null) {
        expect(result.hasConfidentMatch, isFalse,
            reason: 'Unrelated image should never produce a confident match');
        expect(result.bestCandidate!.aggregatedScore, lessThan(0.60));
      } else {
        // No candidate survived visual plausibility guard — also acceptable
        expect(result.hasConfidentMatch, isFalse);
      }
    });

    // Test 7: Visually similar competing ad — wrong-ad protection holds
    test('7. Visually similar competitor does NOT steal a confirmed match from the correct ad', () async {
      final correctEmb = makeEmbedding(7);
      final liveEmb = makeEmbeddingWithSim(correctEmb, 0.58, orthSeed: 21);

      // Competitor is visually similar but distinctly different
      final competitorEmb = makeEmbeddingWithSim(correctEmb, 0.45, orthSeed: 22);

      // All 8 regions return the live embedding
      final visionService = _FixedVisionService(liveEmb);
      final ocrService = _FixedOcrService('');

      final correctAd = makeTarget(id: 'ad_correct', name: 'Correct Ad', embedding: correctEmb);
      final competitor = makeTarget(id: 'ad_competitor', name: 'Competitor Ad', embedding: competitorEmb);

      final analyzer = MultiScalePhotoAnalyzer(
        visionService: visionService,
        ocrService: ocrService,
        matchingEngine: engine,
      );

      final image = makeTestImage();
      final result = await analyzer.analyze(
        image: image,
        candidates: [correctAd, competitor],
        testTag: 'TEST_COMPETITOR',
      );

      expect(result.bestCandidate, isNotNull);
      // The correct ad should score higher than the competitor
      expect(result.bestCandidate!.candidate.id, equals('ad_correct'),
          reason: 'The correct ad (higher cosine similarity) must rank first');
      // Competitor must not be promoted above the correct ad
      if (result.rankedCandidates.length > 1) {
        expect(
          result.rankedCandidates[0].aggregatedScore,
          greaterThan(result.rankedCandidates[1].aggregatedScore),
        );
      }
    });

    // Test 8: Ambiguous candidates — per-region margin is ~0 for identical embeddings
    // The caller (home_screen) routes to Gemini when the MatchResult is ambiguous.
    test('8. Two equally-scored candidates show per-region margin ≈ 0 (triggering Gemini in caller)', () async {
      final sharedEmb = makeEmbedding(8);

      // Both candidates have the exact same embedding → cosine similarity = 1.0 for both
      final visionService = _FixedVisionService(sharedEmb);
      final ocrService = _FixedOcrService('');

      final candidateA = makeTarget(id: 'ad_a', name: 'Ad Alpha', embedding: sharedEmb);
      final candidateB = makeTarget(id: 'ad_b', name: 'Ad Beta', embedding: sharedEmb);

      final analyzer = MultiScalePhotoAnalyzer(
        visionService: visionService,
        ocrService: ocrService,
        matchingEngine: engine,
      );

      final image = makeTestImage();
      final result = await analyzer.analyze(
        image: image,
        candidates: [candidateA, candidateB],
        testTag: 'TEST_AMBIGUOUS',
      );

      // Both candidates must be tracked
      expect(result.rankedCandidates.length, equals(2));

      // With identical embeddings, EVERY per-region margin between #1 and #2 is 0.
      // The ScaleRegionResult.margin reflects this — the caller uses this to decide Gemini.
      final nonEmptyRegions = result.regionResults.where((r) => !r.failedQuality).toList();
      expect(nonEmptyRegions, isNotEmpty);
      for (final r in nonEmptyRegions) {
        expect(r.margin, lessThanOrEqualTo(0.001),
            reason: 'Per-region margin must be ~0.0 when candidates have identical embeddings');
      }

      // The top candidate should score at or above threshold (visual=1.0).
      expect(result.bestCandidate!.aggregatedScore, greaterThanOrEqualTo(0.60));
    });

    // Test 9: Empty candidate list returns empty result
    test('9. Empty candidate list returns empty result safely', () async {
      final visionService = _FixedVisionService(makeEmbedding(9));
      final ocrService = _FixedOcrService('');

      final analyzer = MultiScalePhotoAnalyzer(
        visionService: visionService,
        ocrService: ocrService,
        matchingEngine: engine,
      );

      final image = makeTestImage();
      final result = await analyzer.analyze(
        image: image,
        candidates: [],
        testTag: 'TEST_EMPTY',
      );

      expect(result.regionResults, isEmpty);
      expect(result.rankedCandidates, isEmpty);
      expect(result.hasConfidentMatch, isFalse);
      expect(result.bestCandidate, isNull);
    });

    // Test 10: Corroboration bonus is applied when ≥3 regions agree
    test('10. Corroboration bonus (+0.05) is applied when ≥3 regions vote the same candidate', () async {
      final targetEmb = makeEmbedding(10);
      // Use embedding with ~0.55 similarity to trigger corroboration bonus to push over 0.60
      final liveEmb = makeEmbeddingWithSim(targetEmb, 0.55, orthSeed: 33);

      final visionService = _FixedVisionService(liveEmb);
      final ocrService = _FixedOcrService('');

      final target = makeTarget(id: 'ad_corr', name: 'Corroborated Ad', embedding: targetEmb);

      final analyzer = MultiScalePhotoAnalyzer(
        visionService: visionService,
        ocrService: ocrService,
        matchingEngine: engine,
      );

      final image = makeTestImage();
      final result = await analyzer.analyze(
        image: image,
        candidates: [target],
        testTag: 'TEST_CORR',
      );

      expect(result.bestCandidate, isNotNull);
      // Should win in multiple regions
      expect(result.bestCandidate!.evidenceCount, greaterThanOrEqualTo(3));
      // Aggregated should be bestCombined + 0.05
      final expectedMin = result.bestCandidate!.bestCombinedScore + 0.04; // approximate
      expect(result.bestCandidate!.aggregatedScore, greaterThanOrEqualTo(expectedMin));
    });

    // Test 11: AggregatedRecognitionResult.formatSummary produces expected fields
    test('11. formatSummary output contains all required MULTISCALE SUMMARY fields', () async {
      final targetEmb = makeEmbedding(11);
      final liveEmb = makeEmbeddingWithSim(targetEmb, 0.70, orthSeed: 44);

      final visionService = _FixedVisionService(liveEmb);
      final ocrService = _FixedOcrService('luxury tower prestige');

      final target = makeTarget(
        id: 'ad_summary',
        name: 'Summary Test Ad',
        embedding: targetEmb,
        normalizedOcrText: 'luxury tower prestige location',
      );

      final analyzer = MultiScalePhotoAnalyzer(
        visionService: visionService,
        ocrService: ocrService,
        matchingEngine: engine,
      );

      final image = makeTestImage();
      final result = await analyzer.analyze(
        image: image,
        candidates: [target],
        testTag: 'TEST_SUMMARY',
      );

      final summary = result.formatSummary(threshold: engine.threshold);
      expect(summary, contains('MULTISCALE SUMMARY'));
      expect(summary, contains('Best candidate'));
      expect(summary, contains('Evidence sources'));
      expect(summary, contains('Best visual score'));
      expect(summary, contains('Best text score'));
      expect(summary, contains('Aggregated score'));
      expect(summary, contains('Margin'));
      expect(summary, contains('Final decision'));
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // MatchingEngine unit tests that must remain unaffected
  // ──────────────────────────────────────────────────────────────────────────
  group('MatchingEngine: thresholds and protections unchanged', () {
    test('threshold is still 0.60 for MatchingEngine default photo scan instance', () {
      expect(engine.threshold, equals(0.60));
    });

    test('separationMargin is still 0.08', () {
      expect(engine.separationMargin, equals(0.08));
    });

    test('plausibleThreshold is still 0.52', () {
      expect(engine.plausibleThreshold, equals(0.52));
    });

    test('visual plausibility guard in MultiScalePhotoAnalyzer is 0.10', () {
      expect(MultiScalePhotoAnalyzer.minPlausibleVisual, equals(0.10));
    });

    test('corroboration bonus is 0.05 (cannot fully substitute for genuine evidence)', () {
      expect(MultiScalePhotoAnalyzer.corroborationBonus, equals(0.05));
    });
  });
}
