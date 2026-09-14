// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:billy_the_viewer/models/ad_target.dart';
import 'package:billy_the_viewer/services/matching_engine.dart';
import 'package:billy_the_viewer/services/vision_service.dart';

void main() {
  test('Phase 3.5 Benchmark: Evaluate feature separation between positive and negative test cases', () async {
    final vision = VisionService();
    await vision.initialize();

    final matchingEngine = const MatchingEngine(threshold: 0.70);

    final adBytes = await File('assets/campaigns/demo_ad.jpg').readAsBytes();
    final adDecoded = img.decodeImage(adBytes)!;
    final adEmbedding = await vision.generateEmbeddingFromBytes(adBytes);
    expect(adEmbedding.isNotEmpty, isTrue);

    final registeredTarget = AdTarget(
      id: 'demo_001',
      name: 'Studio Noir Architecture',
      brand: 'Studio Noir',
      destinationUrl: 'https://example.com/studio-noir',
      imageAsset: 'assets/campaigns/demo_ad.jpg',
      embedding: adEmbedding,
    );

    // 1. Uniform Wall (gray 180)
    final wallImg = img.Image(width: 128, height: 128);
    img.fill(wallImg, color: img.ColorRgb8(180, 180, 180));

    // 2. Dark Floor (dark gray 40)
    final floorImg = img.Image(width: 128, height: 128);
    img.fill(floorImg, color: img.ColorRgb8(40, 40, 40));

    // 3. Desk (wood tone gradient)
    final deskImg = img.Image(width: 128, height: 128);
    for (int y = 0; y < 128; y++) {
      for (int x = 0; x < 128; x++) {
        deskImg.setPixelRgb(x, y, (120 + y ~/ 2).clamp(0, 255), (80 + x ~/ 3).clamp(0, 255), 40);
      }
    }

    // 4. White ceiling with lamp
    final ceilingImg = img.Image(width: 128, height: 128);
    for (int y = 0; y < 128; y++) {
      for (int x = 0; x < 128; x++) {
        final dist = math.sqrt((x - 64) * (x - 64) + (y - 64) * (y - 64));
        final lum = (255 - dist * 2).round().clamp(180, 255);
        ceilingImg.setPixelRgb(x, y, lum, lum, lum);
      }
    }

    // 5. Random noisy room
    final noiseImg = img.Image(width: 128, height: 128);
    final rng = math.Random(42);
    for (int y = 0; y < 128; y++) {
      for (int x = 0; x < 128; x++) {
        final v = rng.nextInt(256);
        noiseImg.setPixelRgb(x, y, v, v, v);
      }
    }

    // 6. Completely Different Poster
    final posterImg = img.Image(width: 128, height: 128);
    for (int y = 0; y < 128; y++) {
      for (int x = 0; x < 128; x++) {
        final inCircle = ((x - 40) * (x - 40) + (y - 40) * (y - 40)) < 900;
        final inRect = (x > 60 && x < 110 && y > 60 && y < 110);
        posterImg.setPixelRgb(x, y, inCircle ? 255 : 0, inRect ? 255 : 0, 180);
      }
    }

    // 7. Different ad layout
    final otherAdImg = img.Image(width: 128, height: 128);
    for (int y = 0; y < 128; y++) {
      for (int x = 0; x < 128; x++) {
        final lum = (y * 2).clamp(0, 255);
        otherAdImg.setPixelRgb(x, y, lum, lum, lum);
      }
    }

    // 8. Positive sample (camera jittered)
    final positiveSample = img.copyResize(adDecoded, width: 128, height: 128);
    for (int y = 0; y < 128; y++) {
      for (int x = 0; x < 128; x++) {
        final p = positiveSample.getPixel(x, y);
        final jitter = rng.nextInt(15) - 7;
        positiveSample.setPixelRgb(
          x,
          y,
          (p.r + jitter).clamp(0, 255),
          (p.g + jitter).clamp(0, 255),
          (p.b + jitter).clamp(0, 255),
        );
      }
    }

    // 9. Positive rotated 90 degrees (camera held in portrait / sensor in landscape)
    final positiveRotated90 = img.copyRotate(positiveSample, angle: 90);

    final testCases = <String, img.Image>{
      'POSITIVE: demo_ad (identical)': adDecoded,
      'POSITIVE: demo_ad (camera-jittered)': positiveSample,
      'POSITIVE: demo_ad (90-deg rotated)': positiveRotated90,
      'NEGATIVE: plain wall': wallImg,
      'NEGATIVE: dark floor': floorImg,
      'NEGATIVE: wood desk gradient': deskImg,
      'NEGATIVE: ceiling with lamp': ceilingImg,
      'NEGATIVE: random noisy room': noiseImg,
      'NEGATIVE: different poster': posterImg,
      'NEGATIVE: different ad layout': otherAdImg,
    };

    print('\n========================================================================================');
    print('PHASE 3.5 DIAGNOSTIC TABLE: VisionService & MatchingEngine Empirical Benchmark');
    print('Image                                | Similarity | Expected | Quality Check | Result');
    print('========================================================================================');

    for (final entry in testCases.entries) {
      final emb = await vision.generateEmbeddingFromImage(entry.value);
      final isPos = entry.key.startsWith('POSITIVE');

      if (emb.isEmpty) {
        print('${entry.key.padRight(36)} | N/A (0.0000) | ${isPos ? "MATCH   " : "NO MATCH"} | REJECTED      | ${!isPos ? "PASS" : "FAIL"}');
        expect(isPos, isFalse, reason: 'Positive sample should not be rejected by quality check');
      } else {
        final match = matchingEngine.findBestMatch(emb, [registeredTarget]);
        final sim = MatchingEngine.maxSimilarityAcrossRotations(registeredTarget.embedding, emb);
        final pass = isPos ? (match != null && sim >= 0.70) : (match == null && sim < 0.70);
        print('${entry.key.padRight(36)} | ${sim.toStringAsFixed(4).padRight(10)} | ${isPos ? "MATCH   " : "NO MATCH"} | ACCEPTED      | ${pass ? "PASS" : "FAIL"}');
        if (isPos) {
          expect(match, isNotNull, reason: '$entry should match');
          expect(sim, greaterThanOrEqualTo(0.70));
        } else {
          expect(match, isNull, reason: '$entry should NOT match');
          expect(sim, lessThan(0.70));
        }
      }
    }
    print('========================================================================================\n');
  });
}
