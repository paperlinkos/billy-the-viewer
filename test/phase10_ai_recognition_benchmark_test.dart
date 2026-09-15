// test/phase10_ai_recognition_benchmark_test.dart
//
// Phase 10 — AI Recognition Benchmark: Unit Tests
// ─────────────────────────────────────────────────────────────────────────────
// These tests validate the benchmark infrastructure WITHOUT requiring network
// access or a GEMINI_API_KEY. All tests use the offline perceptual fallback.
//
// Existing production tests (phases 1-9) are completely unaffected.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
import 'package:billy_the_viewer/experimental/gemini_embedding_service.dart';

// ── Helpers ──────────────────────────────────────────────────────────────────

/// Creates a unit-length vector of [dim] elements all equal.
List<double> _uniformVector(int dim, [double value = 1.0]) {
  final v = List<double>.filled(dim, value);
  final norm = sqrt(v.fold<double>(0, (s, x) => s + x * x));
  return norm == 0 ? v : v.map((e) => e / norm).toList();
}

/// Creates a zero vector.
List<double> _zeroVector(int dim) => List<double>.filled(dim, 0.0);

// ── Mock HTTP Client that returns a canned embedding response ─────────────────

class _MockHttpClient extends http.BaseClient {
  final int statusCode;
  final Map<String, dynamic> body;

  _MockHttpClient({required this.statusCode, required this.body});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(body))),
      statusCode,
      headers: {'content-type': 'application/json'},
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

void main() {
  group('Phase 10: 1. Cosine Similarity Maths', () {
    test('Identical vectors → similarity = 1.0', () {
      final v = _uniformVector(128);
      expect(cosineSimilarity(v, v), closeTo(1.0, 1e-9));
    });

    test('Orthogonal vectors → similarity = 0.0', () {
      final a = [1.0, 0.0, 0.0];
      final b = [0.0, 1.0, 0.0];
      expect(cosineSimilarity(a, b), closeTo(0.0, 1e-9));
    });

    test('Opposite vectors → similarity = -1.0', () {
      final a = _uniformVector(16);
      final b = a.map((e) => -e).toList();
      expect(cosineSimilarity(a, b), closeTo(-1.0, 1e-9));
    });

    test('Zero vector → returns 0 without exception', () {
      final a = _uniformVector(16);
      final b = _zeroVector(16);
      expect(cosineSimilarity(a, b), 0.0);
    });

    test('Similar-but-not-identical vectors → score between 0 and 1', () {
      final random = Random(42);
      final a = List<double>.generate(64, (_) => random.nextDouble());
      // Slight perturbation
      final b = a.map((v) => (v + random.nextDouble() * 0.1).clamp(0.0, 1.0)).toList();
      final score = cosineSimilarity(a, b);
      expect(score, greaterThan(0.8));
      expect(score, lessThan(1.0));
    });
  });

  group('Phase 10: 2. GeminiEmbeddingClient — Offline Mode', () {
    test('isLive is false when no API key is provided', () {
      final client = GeminiEmbeddingClient(apiKey: null);
      expect(client.isLive, isFalse);
      client.dispose();
    });

    test('isLive is false for empty string API key', () {
      final client = GeminiEmbeddingClient(apiKey: '');
      expect(client.isLive, isFalse);
      client.dispose();
    });

    test('isLive is true when API key is provided', () {
      final client = GeminiEmbeddingClient(apiKey: 'test-key-123');
      expect(client.isLive, isTrue);
      client.dispose();
    });

    test('embedImageBytes returns 128-dim unit vector in offline mode', () async {
      final client = GeminiEmbeddingClient(apiKey: null);
      // Generate fake JPEG-like bytes with recognisable pattern
      final fakeBytes = List<int>.generate(3000, (i) => (i * 3 + 42) % 256);
      final embedding = await client.embedImageBytes(fakeBytes);

      expect(embedding.length, 128);
      // Must be unit-normalised
      final norm = sqrt(embedding.fold<double>(0, (s, v) => s + v * v));
      expect(norm, closeTo(1.0, 1e-6));
      client.dispose();
    });

    test('Offline embedding of same bytes produces identical result (deterministic)', () async {
      final client = GeminiEmbeddingClient(apiKey: null);
      final bytes = List<int>.generate(5000, (i) => i % 256);
      final e1 = await client.embedImageBytes(bytes);
      final e2 = await client.embedImageBytes(bytes);
      expect(e1, equals(e2));
      client.dispose();
    });

    test('Offline embeddings of different images produce different vectors', () async {
      final client = GeminiEmbeddingClient(apiKey: null);
      final bytes1 = List<int>.generate(3000, (i) => i % 256);
      final bytes2 = List<int>.generate(3000, (i) => (i * 7 + 128) % 256);
      final e1 = await client.embedImageBytes(bytes1);
      final e2 = await client.embedImageBytes(bytes2);
      final score = cosineSimilarity(e1, e2);
      // They should differ — cosine similarity < 1.0
      expect(score, lessThan(0.999));
      client.dispose();
    });
  });

  group('Phase 10: 3. GeminiEmbeddingClient — Live API (mocked)', () {
    test('Uses x-goog-api-key header and returns embedding from JSON', () async {
      const mockEmbedding = [0.1, 0.2, 0.3, 0.4, 0.5];
      final mockClient = _MockHttpClient(
        statusCode: 200,
        body: {
          'embedding': {'values': mockEmbedding}
        },
      );
      final client = GeminiEmbeddingClient(
          apiKey: 'test-api-key-abc', httpClient: mockClient);
      final embedding = await client.embedImageBytes([255, 128, 64]);
      expect(embedding, equals([0.1, 0.2, 0.3, 0.4, 0.5]));
      client.dispose();
    });

    test('Throws GeminiEmbeddingException on non-200 response', () async {
      final mockClient = _MockHttpClient(
        statusCode: 503,
        body: {'error': 'Service unavailable'},
      );
      final client = GeminiEmbeddingClient(
          apiKey: 'test-api-key-abc', httpClient: mockClient);
      expect(
        () async => client.embedImageBytes([1, 2, 3]),
        throwsA(isA<GeminiEmbeddingException>()),
      );
      client.dispose();
    });

    test('GeminiEmbeddingException has descriptive message', () {
      const e = GeminiEmbeddingException('HTTP 503: No capacity');
      expect(e.toString(), contains('GeminiEmbeddingException'));
      expect(e.toString(), contains('503'));
    });
  });

  group('Phase 10: 4. AiRecognitionBenchmark — With Manifest', () {
    late Directory tmpDir;
    late String referenceImagePath;
    late String benchmarkDir;

    setUpAll(() {
      tmpDir = Directory.systemTemp.createTempSync('billy_benchmark_test_');
      referenceImagePath = '${tmpDir.path}/reference.jpg';
      benchmarkDir = '${tmpDir.path}/benchmark';
      Directory(benchmarkDir).createSync();

      // Write synthetic JPEG-like byte patterns
      final refBytes = List<int>.generate(4096, (i) => (i + 10) % 256);
      File(referenceImagePath).writeAsBytesSync(refBytes);

      // match_a.jpg — same as reference (expect: TRUE MATCH)
      File('$benchmarkDir/match_a.jpg').writeAsBytesSync(refBytes);

      // match_b.jpg — slightly perturbed (expect: TRUE MATCH — relies on fallback)
      final perturbedBytes =
          List<int>.generate(4096, (i) => ((i + 10) % 256 + 1) % 256);
      File('$benchmarkDir/match_b.jpg').writeAsBytesSync(perturbedBytes);

      // nomatch_x.jpg — completely different (expect: FALSE MATCH)
      final differentBytes =
          List<int>.generate(4096, (i) => (i * 7 + 200) % 256);
      File('$benchmarkDir/nomatch_x.jpg').writeAsBytesSync(differentBytes);
    });

    tearDownAll(() {
      tmpDir.deleteSync(recursive: true);
    });

    List<Map<String, dynamic>> testManifest() => [
          {'filename': 'match_a.jpg', 'expected': 'TRUE MATCH', 'variation': 'Exact copy'},
          {'filename': 'match_b.jpg', 'expected': 'TRUE MATCH', 'variation': 'Slight perturbation'},
          {'filename': 'nomatch_x.jpg', 'expected': 'FALSE MATCH', 'variation': 'Unrelated scene'},
        ];

    test('Benchmark produces one result per test case', () async {
      final client = GeminiEmbeddingClient(apiKey: null);
      final benchmark = AiRecognitionBenchmark(client: client, threshold: 0.65);
      final report = await benchmark.run(
        referenceImagePath: referenceImagePath,
        benchmarkManifest: testManifest(),
        benchmarkDir: benchmarkDir,
      );
      expect(report.results.length, 3);
      client.dispose();
    });

    test('Exact copy of reference scores very highly (≥ 0.99)', () async {
      final client = GeminiEmbeddingClient(apiKey: null);
      final benchmark = AiRecognitionBenchmark(client: client, threshold: 0.65);
      final report = await benchmark.run(
        referenceImagePath: referenceImagePath,
        benchmarkManifest: [
          {'filename': 'match_a.jpg', 'expected': 'TRUE MATCH', 'variation': 'Exact copy'},
        ],
        benchmarkDir: benchmarkDir,
      );
      expect(report.results.first.similarityScore, greaterThanOrEqualTo(0.99));
      expect(report.results.first.pass, isTrue);
      client.dispose();
    });

    test('Missing image results in a FAIL result with zero score', () async {
      final client = GeminiEmbeddingClient(apiKey: null);
      final benchmark = AiRecognitionBenchmark(client: client, threshold: 0.65);
      final report = await benchmark.run(
        referenceImagePath: referenceImagePath,
        benchmarkManifest: [
          {'filename': 'DOES_NOT_EXIST.jpg', 'expected': 'TRUE MATCH', 'variation': 'Missing file'},
        ],
        benchmarkDir: benchmarkDir,
      );
      expect(report.results.first.pass, isFalse);
      expect(report.results.first.similarityScore, 0.0);
      client.dispose();
    });

    test('BenchmarkReport accuracy, TP, FP, TN, FN computed correctly', () async {
      final client = GeminiEmbeddingClient(apiKey: null);
      final benchmark = AiRecognitionBenchmark(client: client, threshold: 0.99);
      // With threshold 0.99: exact copy passes, others may fail
      final report = await benchmark.run(
        referenceImagePath: referenceImagePath,
        benchmarkManifest: testManifest(),
        benchmarkDir: benchmarkDir,
      );
      expect(report.totalTests, 3);
      expect(report.passCount + report.failCount, 3);
      expect(report.accuracy, greaterThanOrEqualTo(0.0));
      expect(report.accuracy, lessThanOrEqualTo(1.0));
      expect(report.truePositives + report.falseNegatives,
          report.results.where((r) => r.expectedLabel == 'TRUE MATCH').length);
      expect(report.trueNegatives + report.falsePositives,
          report.results.where((r) => r.expectedLabel == 'FALSE MATCH').length);
      client.dispose();
    });

    test('formatReport produces well-formed table string', () async {
      final client = GeminiEmbeddingClient(apiKey: null);
      final benchmark = AiRecognitionBenchmark(client: client, threshold: 0.65);
      final report = await benchmark.run(
        referenceImagePath: referenceImagePath,
        benchmarkManifest: testManifest(),
        benchmarkDir: benchmarkDir,
      );
      final formatted = AiRecognitionBenchmark.formatReport(report);
      expect(formatted, contains('BILLY THE VIEWER'));
      expect(formatted, contains('Accuracy'));
      expect(formatted, contains('PASS'));
      expect(formatted, contains('SCORE'));
      client.dispose();
    });
  });

  group('Phase 10: 5. Benchmark Manifest File (real assets)', () {
    const manifestPath = 'assets/recognition_benchmark/benchmark_manifest.json';
    const benchmarkDir = 'assets/recognition_benchmark';

    test('Manifest file exists and contains expected fields', () {
      final file = File(manifestPath);
      expect(file.existsSync(), isTrue,
          reason:
              'Run dart run tool/generate_benchmark_assets.dart to create benchmark assets');
      final manifest = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      expect(manifest['tests'], isA<List>());
      expect((manifest['tests'] as List).length, greaterThanOrEqualTo(8));
      expect(manifest['threshold'], isA<num>());
    });

    test('All manifest image files exist on disk', () {
      final file = File(manifestPath);
      if (!file.existsSync()) return; // Skip if not generated
      final manifest = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final tests = (manifest['tests'] as List).cast<Map<String, dynamic>>();
      for (final t in tests) {
        final path = '$benchmarkDir/${t['filename']}';
        expect(File(path).existsSync(), isTrue,
            reason: 'Benchmark image not found: $path');
      }
    });

    test('Manifest has both TRUE MATCH and FALSE MATCH entries', () {
      final file = File(manifestPath);
      if (!file.existsSync()) return;
      final manifest = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final tests = (manifest['tests'] as List).cast<Map<String, dynamic>>();
      final expectedLabels = tests.map((t) => t['expected'] as String).toSet();
      expect(expectedLabels, containsAll(['TRUE MATCH', 'FALSE MATCH']));
    });
  });

  group('Phase 10: 6. Regression — Service Architecture', () {
    test('GeminiEmbeddingService is in lib/services/ with forwarding export in lib/experimental/', () {
      // Verify the forwarding export exists in the experimental/ namespace
      const servicePath = 'lib/experimental/gemini_embedding_service.dart';
      expect(File(servicePath).existsSync(), isTrue);

      // Verify it is in the services directory
      const productionPath = 'lib/services/gemini_embedding_service.dart';
      expect(File(productionPath).existsSync(), isTrue,
          reason: 'Gemini embedding service is promoted to services directory');
    });

    test('HomeScreen source does not import gemini_embedding_service', () {
      const homeScreenPath = 'lib/screens/home_screen.dart';
      final source = File(homeScreenPath).readAsStringSync();
      expect(source.contains('gemini_embedding_service'), isFalse,
          reason: 'HomeScreen must not reference the experimental embedding service');
    });

    test('MatchingEngine source does not import gemini_embedding_service', () {
      // Find the matching engine file
      final files = Directory('lib/services').listSync();
      for (final f in files) {
        if (f.path.contains('matching_engine') || f.path.contains('vision')) {
          final source = File(f.path).readAsStringSync();
          expect(source.contains('gemini_embedding_service'), isFalse,
              reason: 'Production recognition must not reference the experimental service');
        }
      }
    });
  });
}
