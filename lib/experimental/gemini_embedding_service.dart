// lib/experimental/gemini_embedding_service.dart
//
// PHASE 10 — EXPERIMENTAL ONLY
// ─────────────────────────────────────────────────────────────────────────────
// This file is COMPLETELY ISOLATED from the production recognition pipeline.
// It does NOT touch HomeScreen, InlineCameraView, CameraService, MatchingEngine,
// CampaignRepository, or any viewer/advertiser flows.
//
// The Gemini API key is NEVER hardcoded here. It must be supplied at runtime
// via the GEMINI_API_KEY environment variable.
//
// Model: gemini-embedding-2 (multimodal, unified text+image vector space)
// Endpoint: https://generativelanguage.googleapis.com/v1beta/models/gemini-embedding-2:embedContent
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:io';
import 'dart:math';

// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;

/// A single benchmark test result.
class BenchmarkResult {
  final String imageName;
  final double similarityScore;
  final String expectedLabel; // "TRUE MATCH" | "FALSE MATCH"
  final String predictedLabel; // "TRUE MATCH" | "FALSE MATCH"
  final bool pass;

  const BenchmarkResult({
    required this.imageName,
    required this.similarityScore,
    required this.expectedLabel,
    required this.predictedLabel,
    required this.pass,
  });

  @override
  String toString() =>
      'BenchmarkResult(image: $imageName, score: ${similarityScore.toStringAsFixed(4)}, '
      'expected: $expectedLabel, predicted: $predictedLabel, pass: $pass)';
}

/// Result of a full benchmark run.
class BenchmarkReport {
  final List<BenchmarkResult> results;
  final double threshold;
  final String modelUsed;
  final bool liveApiUsed;

  const BenchmarkReport({
    required this.results,
    required this.threshold,
    required this.modelUsed,
    required this.liveApiUsed,
  });

  int get totalTests => results.length;
  int get passCount => results.where((r) => r.pass).length;
  int get failCount => results.where((r) => !r.pass).length;
  double get accuracy => totalTests == 0 ? 0 : passCount / totalTests;
  int get truePositives =>
      results.where((r) => r.expectedLabel == 'TRUE MATCH' && r.pass).length;
  int get falseNegatives =>
      results.where((r) => r.expectedLabel == 'TRUE MATCH' && !r.pass).length;
  int get trueNegatives =>
      results.where((r) => r.expectedLabel == 'FALSE MATCH' && r.pass).length;
  int get falsePositives =>
      results.where((r) => r.expectedLabel == 'FALSE MATCH' && !r.pass).length;
}

/// Generates an offline perceptual embedding from raw image bytes.
/// Used as a fallback when GEMINI_API_KEY is not present (CI / offline dev).
/// This is deterministic and based on downsampled pixel statistics —
/// it is NOT a substitute for the real Gemini multimodal embedding.
List<double> _offlineEmbedding(List<int> imageBytes) {
  // Attempt to extract meaningful statistics from the raw JPEG bytes.
  // We use 128 evenly-spaced byte samples from the payload as a proxy embedding.
  // This is intentionally naive — it exists only to keep tests runnable offline.
  const dim = 128;
  final result = List<double>.filled(dim, 0.0);

  if (imageBytes.isEmpty) return result;

  final step = max(1, imageBytes.length ~/ dim);
  for (int i = 0; i < dim; i++) {
    final idx = (i * step).clamp(0, imageBytes.length - 1);
    result[i] = imageBytes[idx] / 255.0;
  }

  // Normalise to unit vector.
  final norm = sqrt(result.fold<double>(0, (s, v) => s + v * v));
  if (norm > 0) {
    for (int i = 0; i < dim; i++) {
      result[i] /= norm;
    }
  }
  return result;
}

/// Computes cosine similarity between two equal-length vectors.
double cosineSimilarity(List<double> a, List<double> b) {
  assert(a.length == b.length, 'Embedding dimension mismatch: ${a.length} vs ${b.length}');
  double dot = 0, normA = 0, normB = 0;
  for (int i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }
  final denom = sqrt(normA) * sqrt(normB);
  return denom == 0 ? 0.0 : dot / denom;
}

/// The main Gemini embedding client.
///
/// Usage:
///   final client = GeminiEmbeddingClient(apiKey: Platform.environment['GEMINI_API_KEY']);
///   final embedding = await client.embedImageBytes(bytes);
class GeminiEmbeddingClient {
  /// Model identifier used for the live API.
  static const String modelId = 'gemini-embedding-2';

  /// REST endpoint — multimodal embedContent (images + text in unified space).
  static const String _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/$modelId:embedContent';

  /// Similarity threshold above which an image is predicted as a TRUE MATCH.
  static const double defaultThreshold = 0.65;

  final String? apiKey;
  final http.Client _httpClient;

  GeminiEmbeddingClient({this.apiKey, http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  /// Whether this client can make live Gemini API requests.
  bool get isLive => apiKey != null && apiKey!.isNotEmpty;

  /// Generates an embedding vector for the given image bytes.
  ///
  /// If [apiKey] is provided → calls the Gemini REST API.
  /// Otherwise → falls back to the offline perceptual sampler (CI-safe).
  Future<List<double>> embedImageBytes(List<int> imageBytes) async {
    if (!isLive) {
      return _offlineEmbedding(imageBytes);
    }
    return _liveGeminiEmbedding(imageBytes);
  }

  /// Calls generativelanguage.googleapis.com to obtain a multimodal embedding.
  Future<List<double>> _liveGeminiEmbedding(List<int> imageBytes) async {
    final base64Image = base64Encode(imageBytes);

    final body = jsonEncode({
      'model': 'models/$modelId',
      'content': {
        'parts': [
          {
            'inline_data': {
              'mime_type': 'image/jpeg',
              'data': base64Image,
            }
          }
        ]
      }
    });

    final response = await _httpClient.post(
      Uri.parse(_baseUrl),
      headers: {
        'Content-Type': 'application/json',
        'x-goog-api-key': apiKey!,
      },
      body: body,
    );

    if (response.statusCode != 200) {
      throw GeminiEmbeddingException(
        'Gemini API request failed: HTTP ${response.statusCode}\n${response.body}',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final values = (decoded['embedding']['values'] as List).cast<double>();
    return values;
  }

  void dispose() {
    _httpClient.close();
  }
}

/// Runs the full AI recognition benchmark.
///
/// Loads reference ad from [referenceImagePath], then evaluates every entry
/// in [benchmarkManifest] against it.
class AiRecognitionBenchmark {
  final GeminiEmbeddingClient client;
  final double threshold;

  AiRecognitionBenchmark({
    required this.client,
    this.threshold = GeminiEmbeddingClient.defaultThreshold,
  });

  /// Runs benchmark.
  ///
  /// [referenceImagePath] — path to reference advertisement on disk.
  /// [benchmarkManifest]  — list of test case maps:
  ///   { 'filename': String, 'expected': 'TRUE MATCH'|'FALSE MATCH', 'variation': String }
  /// [benchmarkDir]       — directory containing the benchmark test images.
  Future<BenchmarkReport> run({
    required String referenceImagePath,
    required List<Map<String, dynamic>> benchmarkManifest,
    required String benchmarkDir,
  }) async {
    final referenceBytes = File(referenceImagePath).readAsBytesSync();
    final referenceEmbedding = await client.embedImageBytes(referenceBytes);

    final results = <BenchmarkResult>[];

    for (final testCase in benchmarkManifest) {
      final filename = testCase['filename'] as String;
      final expectedLabel = testCase['expected'] as String;
      final imagePath = '$benchmarkDir/$filename';

      if (!File(imagePath).existsSync()) {
        results.add(BenchmarkResult(
          imageName: filename,
          similarityScore: 0.0,
          expectedLabel: expectedLabel,
          predictedLabel: 'ERROR — FILE NOT FOUND',
          pass: false,
        ));
        continue;
      }

      final testBytes = File(imagePath).readAsBytesSync();
      final testEmbedding = await client.embedImageBytes(testBytes);
      final score = cosineSimilarity(referenceEmbedding, testEmbedding);

      final predictedLabel = score >= threshold ? 'TRUE MATCH' : 'FALSE MATCH';
      final pass = predictedLabel == expectedLabel;

      results.add(BenchmarkResult(
        imageName: filename,
        similarityScore: score,
        expectedLabel: expectedLabel,
        predictedLabel: predictedLabel,
        pass: pass,
      ));
    }

    return BenchmarkReport(
      results: results,
      threshold: threshold,
      modelUsed: GeminiEmbeddingClient.modelId,
      liveApiUsed: client.isLive,
    );
  }

  /// Formats a [BenchmarkReport] as a human-readable console/markdown table.
  static String formatReport(BenchmarkReport report) {
    final sb = StringBuffer();
    sb.writeln('');
    sb.writeln('═══════════════════════════════════════════════════════════════════');
    sb.writeln('  BILLY THE VIEWER — PHASE 10 AI RECOGNITION BENCHMARK REPORT');
    sb.writeln('═══════════════════════════════════════════════════════════════════');
    sb.writeln('  Model   : ${report.modelUsed}');
    sb.writeln('  Mode    : ${report.liveApiUsed ? 'LIVE — Gemini API (real embeddings)' : 'OFFLINE — perceptual fallback (no API key)'}');
    sb.writeln('  Threshold: ${report.threshold.toStringAsFixed(2)}');
    sb.writeln('───────────────────────────────────────────────────────────────────');
    sb.writeln(
      '${'IMAGE'.padRight(35)} ${'SCORE'.padLeft(6)}  ${'EXPECTED'.padRight(13)} ${'PREDICTED'.padRight(13)} RESULT',
    );
    sb.writeln('───────────────────────────────────────────────────────────────────');

    for (final r in report.results) {
      final name = r.imageName.length > 34
          ? '${r.imageName.substring(0, 31)}...'
          : r.imageName;
      final score = r.similarityScore.toStringAsFixed(4);
      final status = r.pass ? '✅ PASS' : '❌ FAIL';
      sb.writeln(
        '${name.padRight(35)} ${score.padLeft(6)}  ${r.expectedLabel.padRight(13)} ${r.predictedLabel.padRight(13)} $status',
      );
    }

    sb.writeln('───────────────────────────────────────────────────────────────────');
    sb.writeln('  Total: ${report.totalTests}  ✅ PASS: ${report.passCount}  ❌ FAIL: ${report.failCount}');
    sb.writeln('  Accuracy : ${(report.accuracy * 100).toStringAsFixed(1)}%');
    sb.writeln('  TP: ${report.truePositives}  FN: ${report.falseNegatives}  TN: ${report.trueNegatives}  FP: ${report.falsePositives}');
    sb.writeln('═══════════════════════════════════════════════════════════════════');
    return sb.toString();
  }
}

/// Thrown when the Gemini REST API returns an error response.
class GeminiEmbeddingException implements Exception {
  final String message;
  const GeminiEmbeddingException(this.message);
  @override
  String toString() => 'GeminiEmbeddingException: $message';
}
