// tool/run_ai_benchmark.dart
//
// Phase 10 — AI Recognition Benchmark Runner (OFFLINE/LIVE)
// ─────────────────────────────────────────────────────────────────────────────
// Usage (offline / no API key):
//   dart run tool/run_ai_benchmark.dart
//
// Usage (with live Gemini API):
//   GEMINI_API_KEY=<your_key> dart run tool/run_ai_benchmark.dart
//   — or —
//   dart run tool/run_ai_benchmark.dart --api-key=<your_key>
//
// The API key is NEVER hardcoded. Supply it via environment variable or flag.
// ─────────────────────────────────────────────────────────────────────────────
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:billy_the_viewer/experimental/gemini_embedding_service.dart';

void main(List<String> args) async {
  // ── 1. Resolve API key (env var or --api-key flag) ──────────────────────
  String? apiKey = Platform.environment['GEMINI_API_KEY'];
  for (final arg in args) {
    if (arg.startsWith('--api-key=')) {
      apiKey = arg.substring('--api-key='.length).trim();
      if (apiKey.isEmpty) apiKey = null;
    }
  }

  final isLive = apiKey != null && apiKey.isNotEmpty;

  print('');
  print('BILLY THE VIEWER — Phase 10: AI Recognition Benchmark');
  print('══════════════════════════════════════════════════════');
  print('Model    : ${GeminiEmbeddingClient.modelId}');
  print('API mode : ${isLive ? 'LIVE (Gemini API)' : 'OFFLINE (no GEMINI_API_KEY — using perceptual fallback)'}');
  if (!isLive) {
    print('');
    print('  ℹ️  To run with live Gemini embeddings, set GEMINI_API_KEY:');
    print('     GEMINI_API_KEY=<your_key> dart run tool/run_ai_benchmark.dart');
  }
  print('');

  // ── 2. Verify paths ──────────────────────────────────────────────────────
  const referenceImagePath = 'assets/campaigns/demo_ad.jpg';
  const benchmarkDir = 'assets/recognition_benchmark';
  const manifestPath = '$benchmarkDir/benchmark_manifest.json';

  for (final path in [referenceImagePath, manifestPath]) {
    if (!File(path).existsSync()) {
      print('Error: Required file not found: $path');
      print('       Run `dart run tool/generate_benchmark_assets.dart` first.');
      exit(1);
    }
  }
  if (!Directory(benchmarkDir).existsSync()) {
    print('Error: Benchmark directory not found: $benchmarkDir');
    print('       Run `dart run tool/generate_benchmark_assets.dart` first.');
    exit(1);
  }

  // ── 3. Load manifest ─────────────────────────────────────────────────────
  final manifestJson = File(manifestPath).readAsStringSync();
  final manifest = jsonDecode(manifestJson) as Map<String, dynamic>;
  final testCases = (manifest['tests'] as List).cast<Map<String, dynamic>>();
  final threshold = (manifest['threshold'] as num).toDouble();

  print('Reference Ad  : $referenceImagePath');
  print('Benchmark Dir : $benchmarkDir');
  print('Threshold     : ${threshold.toStringAsFixed(2)}');
  print('Test Cases    : ${testCases.length}');
  print('');
  print('Running embeddings…');

  // ── 4. Run benchmark ─────────────────────────────────────────────────────
  final client = GeminiEmbeddingClient(apiKey: apiKey);
  final benchmark = AiRecognitionBenchmark(client: client, threshold: threshold);

  try {
    final report = await benchmark.run(
      referenceImagePath: referenceImagePath,
      benchmarkManifest: testCases,
      benchmarkDir: benchmarkDir,
    );

    // ── 5. Print report ────────────────────────────────────────────────────
    print(AiRecognitionBenchmark.formatReport(report));

    // ── 6. Exit with non-zero if any failures (useful in CI) ──────────────
    if (report.failCount > 0 && isLive) {
      print('⚠️  ${report.failCount} test(s) failed. Review the results above.');
      // In offline/fallback mode failures are expected — only exit(1) for live runs.
      exit(1);
    }
  } on GeminiEmbeddingException catch (e) {
    print('');
    print('Gemini API Error: ${e.message}');
    print('');
    print('Check that your GEMINI_API_KEY is valid and has quota remaining.');
    exit(2);
  } finally {
    client.dispose();
  }
}
