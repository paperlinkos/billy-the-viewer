// tool/test_new_ad.dart
// Quick one-shot test: use the generated Billy ad as reference,
// embed it and compare against a transformed version of itself.
// Run with:
//   GEMINI_API_KEY="your_key" dart run tool/test_new_ad.dart
// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:math';
import 'package:image/image.dart' as img;
import 'package:billy_the_viewer/experimental/gemini_embedding_service.dart';

void main() async {
  final apiKey = Platform.environment['GEMINI_API_KEY'];
  final isLive = apiKey != null && apiKey.isNotEmpty;

  print('');
  print('BILLY AD RECOGNITION TEST');
  print('══════════════════════════════════════════════════');
  print('Mode: ${isLive ? 'LIVE Gemini API' : 'OFFLINE fallback'}');
  print('');

  const adPath = 'assets/recognition_benchmark/my_billy_ad.jpg';
  if (!File(adPath).existsSync()) {
    print('Error: $adPath not found.');
    exit(1);
  }

  final referenceBytes = File(adPath).readAsBytesSync();
  final baseImage = img.decodeImage(referenceBytes)!;

  // Create 4 realistic variations
  final variations = <String, List<int>>{};

  // 1. Slightly rotated (phone tilt)
  final rotated = img.copyRotate(baseImage, angle: 8);
  variations['slight_rotation'] = img.encodeJpg(rotated, quality: 85);

  // 2. Viewed on a phone screen (shrunk + black frame)
  final screenView = img.Image(width: 800, height: 700);
  img.fill(screenView, color: img.ColorRgb8(20, 20, 22));
  final inScreen = img.copyResize(baseImage, width: 560, height: 560);
  img.compositeImage(screenView, inScreen, dstX: 120, dstY: 70);
  variations['on_phone_screen'] = img.encodeJpg(screenView, quality: 85);

  // 3. Dim lighting
  final dimmed = img.copyResize(baseImage, width: 640, height: 640);
  img.adjustColor(dimmed, brightness: 0.45);
  variations['dim_lighting'] = img.encodeJpg(dimmed, quality: 85);

  // 4. Partial view (left 60% visible, rest cut off)
  final partial = img.copyCrop(baseImage,
      x: 0,
      y: 0,
      width: (baseImage.width * 0.6).toInt(),
      height: baseImage.height);
  variations['partial_60pct'] = img.encodeJpg(partial, quality: 85);

  // Negative: random noise image (not the ad)
  final noise = img.Image(width: 640, height: 640);
  final rnd = Random(99);
  for (int y = 0; y < 640; y++) {
    for (int x = 0; x < 640; x++) {
      noise.setPixelRgb(x, y, rnd.nextInt(256), rnd.nextInt(256), rnd.nextInt(256));
    }
  }
  variations['random_noise'] = img.encodeJpg(noise, quality: 85);

  final client = GeminiEmbeddingClient(apiKey: apiKey);
  final refEmbedding = await client.embedImageBytes(referenceBytes);

  const threshold = 0.65;
  print('Reference: my_billy_ad.jpg');
  print('Threshold: $threshold');
  print('');
  print('${'VARIATION'.padRight(22)} ${'SCORE'.padLeft(7)}  ${'RESULT'.padRight(10)} DECISION');
  print('─' * 65);

  for (final entry in variations.entries) {
    final testEmbedding = await client.embedImageBytes(entry.value);
    final score = cosineSimilarity(refEmbedding, testEmbedding);
    final isMatch = score >= threshold;
    final result = isMatch ? '✅ MATCH' : '❌ NO MATCH';
    final label = entry.key == 'random_noise'
        ? (isMatch ? '❌ FALSE POSITIVE' : '✅ CORRECT REJECT')
        : (isMatch ? '✅ CORRECT DETECT' : '❌ MISSED');
    print('${entry.key.padRight(22)} ${score.toStringAsFixed(4).padLeft(7)}  $result  $label');
  }

  print('─' * 65);
  print('');
  if (isLive) {
    print('✅ Key is working. Gemini can recognize the Billy ad.');
  } else {
    print('ℹ️  Running offline. Set GEMINI_API_KEY for real results.');
  }
  print('');

  client.dispose();
}
