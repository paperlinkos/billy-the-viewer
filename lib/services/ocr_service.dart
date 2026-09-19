import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Represents detailed textual match evidence between live/captured OCR text
/// and a candidate campaign's registered OCR text.
class OcrTextMatchEvidence {
  final double score; // Overall text evidence score in [0.0, 1.0]
  final bool hasDistinctiveEvidence;
  final List<String> matchedDistinctiveTokens;
  final String? matchedPhrase;
  final int contiguousPhraseLength;
  final double tokenRecall;
  final double tokenPrecision;

  const OcrTextMatchEvidence({
    required this.score,
    required this.hasDistinctiveEvidence,
    this.matchedDistinctiveTokens = const [],
    this.matchedPhrase,
    this.contiguousPhraseLength = 0,
    this.tokenRecall = 0.0,
    this.tokenPrecision = 0.0,
  });

  static const OcrTextMatchEvidence empty = OcrTextMatchEvidence(
    score: 0.0,
    hasDistinctiveEvidence: false,
  );
}

/// Result of OCR text detection and extraction on an advertisement creative.
class OcrResult {
  final String rawText;
  final String normalizedText;
  final List<String> words;
  final Map<String, dynamic> metadata;

  const OcrResult({
    this.rawText = '',
    this.normalizedText = '',
    this.words = const [],
    this.metadata = const {},
  });

  static const OcrResult empty = OcrResult();

  bool get hasText => normalizedText.trim().isNotEmpty;

  Map<String, dynamic> toJson() {
    return {
      'rawText': rawText,
      'normalizedText': normalizedText,
      'words': words,
      'metadata': metadata,
    };
  }

  factory OcrResult.fromJson(Map<String, dynamic> json) {
    return OcrResult(
      rawText: json['rawText'] as String? ?? '',
      normalizedText: json['normalizedText'] as String? ?? '',
      words: (json['words'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
      metadata: (json['metadata'] as Map<String, dynamic>?) ?? const {},
    );
  }

  @override
  String toString() =>
      'OcrResult(hasText: $hasText, wordsCount: ${words.length}, normalized: "$normalizedText")';
}

/// Abstract contract for on-device OCR engines.
/// Allows swapping the underlying OCR implementation (e.g. Google ML Kit,
/// Tesseract, or mock test engines) without altering callers.
abstract class IOcrEngine {
  Future<OcrResult> extractText(Uint8List imageBytes);
}

/// Standalone domain service for on-device OCR and text extraction.
/// Extracts detected text from advertisement creative bytes, normalizes
/// text for case/whitespace/punctuation invariance, and extracts meaningful tokens.
class OcrService implements IOcrEngine {
  final IOcrEngine? _engine;

  OcrService({IOcrEngine? engine}) : _engine = engine;

  /// Generic stop words and low-entropy advertisement filler terms.
  /// These words alone cannot trigger distinctive text matches.
  static const Set<String> genericStopwords = {
    'a', 'an', 'and', 'are', 'as', 'at', 'be', 'by', 'for', 'from',
    'has', 'he', 'in', 'is', 'it', 'its', 'of', 'on', 'or', 'that',
    'the', 'to', 'was', 'were', 'will', 'with', 'this', 'but',
    'they', 'have', 'had', 'what', 'when', 'where', 'who', 'which',
    'why', 'how', 'all', 'any', 'both', 'each', 'few', 'more', 'most',
    'other', 'some', 'such', 'no', 'nor', 'not', 'only', 'own', 'same',
    'so', 'than', 'too', 'very', 'can', 'just', 'should', 'now',
    'ad', 'ads', 'advertisement', 'call', 'contact', 'email', 'com',
    'org', 'net', 'www', 'http', 'https', 'tel', 'phone', 'visit',
    'click', 'here', 'free', 'new', 'get', 'buy', 'shop', 'order',
  };

  /// Normalizes detected OCR text for reliable invariant comparison:
  /// 1. Lowercase all characters.
  /// 2. Converts newlines, tabs, and carriage returns into spaces.
  /// 3. Removes extraneous punctuation while preserving alphanumeric characters and word boundaries.
  /// 4. Collapses multiple contiguous spaces into a single space and trims edges.
  static String normalizeText(String rawText) {
    if (rawText.isEmpty) return '';

    // Convert to lowercase
    String s = rawText.toLowerCase();

    // Replace linebreaks and tabs with spaces
    s = s.replaceAll(RegExp(r'[\r\n\t]+'), ' ');

    // Replace common punctuation with space to isolate words cleanly
    s = s.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');

    // Collapse multiple spaces into one and trim
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();

    return s;
  }

  /// Extracts individual non-empty word tokens from normalized text.
  static List<String> extractWords(String normalizedText) {
    if (normalizedText.isEmpty) return const [];
    return normalizedText
        .split(' ')
        .map((w) => w.trim())
        .where((w) => w.isNotEmpty)
        .toList();
  }

  /// Determines if a word is distinctive (meaningful content word, not a generic stopword).
  static bool isDistinctiveWord(String w) {
    final clean = w.trim().toLowerCase();
    if (clean.length < 3) return false;
    if (genericStopwords.contains(clean)) return false;
    // Disallow pure digits unless it is a meaningful phone or numerical sequence
    if (RegExp(r'^\d+$').hasMatch(clean) && clean.length < 6) return false;
    return true;
  }

  /// Canonicalizes common OCR character misrecognitions:
  /// 0 <-> o, 1/|/! <-> l, 5 <-> s, 8 <-> b, vv <-> w, rn <-> m.
  static String canonicalOcrWord(String w) {
    return w
        .replaceAll('0', 'o')
        .replaceAll('1', 'l')
        .replaceAll('|', 'l')
        .replaceAll('!', 'l')
        .replaceAll('5', 's')
        .replaceAll('8', 'b')
        .replaceAll('vv', 'w')
        .replaceAll('rn', 'm');
  }

  /// Classical Levenshtein distance between two strings.
  static int levenshteinDistance(String s1, String s2) {
    if (s1 == s2) return 0;
    if (s1.isEmpty) return s2.length;
    if (s2.isEmpty) return s1.length;

    List<int> v0 = List<int>.generate(s2.length + 1, (i) => i);
    List<int> v1 = List<int>.filled(s2.length + 1, 0);

    for (int i = 0; i < s1.length; i++) {
      v1[0] = i + 1;
      for (int j = 0; j < s2.length; j++) {
        int cost = (s1[i] == s2[j]) ? 0 : 1;
        v1[j + 1] = math.min(v1[j] + 1, math.min(v0[j + 1] + 1, v0[j] + cost));
      }
      for (int j = 0; j <= s2.length; j++) {
        v0[j] = v1[j];
      }
    }
    return v1[s2.length];
  }

  /// Checks if two word tokens match, taking into account common OCR misrecognitions
  /// and minor character edit distances (e.g. "lving" vs "living", "0" vs "o").
  static bool tokenFuzzyMatch(String a, String b) {
    if (a == b) return true;
    final cA = canonicalOcrWord(a);
    final cB = canonicalOcrWord(b);
    if (cA == cB) return true;

    final maxLen = math.max(a.length, b.length);
    if (maxLen <= 3) return false;

    final dist = levenshteinDistance(cA, cB);
    if (maxLen >= 8) {
      return dist <= 2;
    } else {
      return dist <= 1;
    }
  }

  /// Evaluates multi-signal textual evidence between live/captured OCR text
  /// and candidate campaign registered OCR text.
  ///
  /// Analyzes:
  /// - Contiguous multi-word phrase matching with OCR typo tolerance.
  /// - Distinctive token precision and recall (filtering generic stopwords).
  /// - Classical Dice bigram and substring similarity.
  static OcrTextMatchEvidence evaluateMatchEvidence(
    String liveNormalized,
    String candidateNormalized,
  ) {
    final live = liveNormalized.trim();
    final candidate = candidateNormalized.trim();

    if (live.isEmpty || candidate.isEmpty) {
      return OcrTextMatchEvidence.empty;
    }

    if (live == candidate) {
      final words = extractWords(live);
      final dist = words.where(isDistinctiveWord).toList();
      return OcrTextMatchEvidence(
        score: 1.0,
        hasDistinctiveEvidence: dist.length >= 2,
        matchedDistinctiveTokens: dist,
        matchedPhrase: live,
        contiguousPhraseLength: words.length,
        tokenRecall: 1.0,
        tokenPrecision: 1.0,
      );
    }

    final liveWords = extractWords(live);
    final candidateWords = extractWords(candidate);

    if (liveWords.isEmpty || candidateWords.isEmpty) {
      return OcrTextMatchEvidence.empty;
    }

    // 1. Contiguous Phrase Matching (find longest consecutive matching sequence)
    int maxContiguous = 0;
    int maxContiguousDistinctive = 0;
    String? longestMatchedPhrase;

    for (int i = 0; i < liveWords.length; i++) {
      for (int j = 0; j < candidateWords.length; j++) {
        int k = 0;
        int distCount = 0;
        final matchedTokens = <String>[];

        while ((i + k) < liveWords.length &&
               (j + k) < candidateWords.length &&
               tokenFuzzyMatch(liveWords[i + k], candidateWords[j + k])) {
          final cw = candidateWords[j + k];
          matchedTokens.add(cw);
          if (isDistinctiveWord(cw) || isDistinctiveWord(liveWords[i + k])) {
            distCount++;
          }
          k++;
        }

        if (k > maxContiguous || (k == maxContiguous && distCount > maxContiguousDistinctive)) {
          maxContiguous = k;
          maxContiguousDistinctive = distCount;
          if (matchedTokens.isNotEmpty) {
            longestMatchedPhrase = matchedTokens.join(' ');
          }
        }
      }
    }

    // 2. Distinctive Token Matching (Precision & Recall)
    final matchedCandidateIndices = <int>{};
    final matchedLiveIndices = <int>{};
    final matchedDistinctiveTokens = <String>[];

    for (int i = 0; i < liveWords.length; i++) {
      final lw = liveWords[i];
      for (int j = 0; j < candidateWords.length; j++) {
        if (matchedCandidateIndices.contains(j)) continue;
        final cw = candidateWords[j];
        if (tokenFuzzyMatch(lw, cw)) {
          matchedLiveIndices.add(i);
          matchedCandidateIndices.add(j);
          if (isDistinctiveWord(cw) || isDistinctiveWord(lw)) {
            matchedDistinctiveTokens.add(cw);
          }
          break;
        }
      }
    }

    final liveDistinctiveCount = liveWords.where(isDistinctiveWord).length;
    final tokenPrecision = liveWords.isNotEmpty ? matchedLiveIndices.length / liveWords.length : 0.0;
    final tokenRecall = candidateWords.isNotEmpty ? matchedCandidateIndices.length / candidateWords.length : 0.0;

    // 3. Substring & Bigram Baselines
    double substringScore = 0.0;
    if (live.contains(candidate)) {
      substringScore = 0.95;
    } else if (candidate.contains(live) && live.length >= 4) {
      substringScore = (live.length / candidate.length).clamp(0.60, 0.90);
    }
    final bigramScore = _bigramSimilarity(live, candidate);

    // 4. Synthesize Evidence Score & Distinctive Flag
    double evidenceScore = 0.0;
    bool hasDistinctive = false;

    // A contiguous phrase of 3+ words with at least 2 distinctive words is decisive creative evidence!
    if (maxContiguous >= 3 && maxContiguousDistinctive >= 2) {
      evidenceScore = 0.98;
      hasDistinctive = true;
    } else if (maxContiguous >= 2 && maxContiguousDistinctive >= 2) {
      // 2 consecutive distinctive words (e.g. "singular living", "infinite prestige")
      evidenceScore = 0.92;
      hasDistinctive = true;
    } else if (matchedDistinctiveTokens.length >= 3 && tokenPrecision >= 0.60) {
      // 3+ distinctive tokens matched with strong precision
      evidenceScore = 0.90;
      hasDistinctive = true;
    } else if (matchedDistinctiveTokens.length >= 2 && liveDistinctiveCount <= 3 && tokenPrecision >= 0.50) {
      // 2 distinctive tokens matched when live text only had 2-3 distinctive words
      evidenceScore = 0.85;
      hasDistinctive = true;
    } else {
      // Fallback to token recall, substring, or bigram similarity
      evidenceScore = [
        substringScore,
        tokenRecall,
        bigramScore,
      ].reduce((a, b) => a > b ? a : b);
    }

    return OcrTextMatchEvidence(
      score: evidenceScore.clamp(0.0, 1.0),
      hasDistinctiveEvidence: hasDistinctive,
      matchedDistinctiveTokens: matchedDistinctiveTokens,
      matchedPhrase: longestMatchedPhrase,
      contiguousPhraseLength: maxContiguous,
      tokenRecall: tokenRecall,
      tokenPrecision: tokenPrecision,
    );
  }

  /// Computes a normalized similarity score in [0.0, 1.0] between live OCR text
  /// and registered candidate campaign OCR text.
  static double computeTextSimilarity(String liveNormalized, String candidateNormalized) {
    final evidence = evaluateMatchEvidence(liveNormalized, candidateNormalized);
    return evidence.score;
  }

  /// Helper: Computes character bigram Dice coefficient in [0.0, 1.0].
  static double _bigramSimilarity(String a, String b) {
    if (a.length < 2 || b.length < 2) return 0.0;

    final aBigrams = <String, int>{};
    for (int i = 0; i < a.length - 1; i++) {
      final bg = a.substring(i, i + 2);
      aBigrams[bg] = (aBigrams[bg] ?? 0) + 1;
    }

    int matches = 0;
    for (int i = 0; i < b.length - 1; i++) {
      final bg = b.substring(i, i + 2);
      final count = aBigrams[bg] ?? 0;
      if (count > 0) {
        matches++;
        aBigrams[bg] = count - 1;
      }
    }

    final totalBigrams = (a.length - 1) + (b.length - 1);
    if (totalBigrams == 0) return 0.0;
    return (2.0 * matches) / totalBigrams;
  }

  @override
  Future<OcrResult> extractText(Uint8List imageBytes) async {
    if (imageBytes.isEmpty) {
      return OcrResult.empty;
    }

    if (_engine != null) {
      return _engine.extractText(imageBytes);
    }

    return _processWithMlKit(imageBytes);
  }

  /// Runs Google ML Kit Text Recognition locally on creative bytes.
  Future<OcrResult> _processWithMlKit(Uint8List imageBytes) async {
    // ML Kit on-device text recognition native channels are only available on Android & iOS.
    // In headless host unit tests or unsupported platforms, return empty result gracefully.
    if (!Platform.isAndroid && !Platform.isIOS) {
      return OcrResult.empty;
    }

    final tempDir = Directory.systemTemp;
    final tempFile = File(
      '${tempDir.path}/billy_ocr_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );

    try {
      await tempFile.writeAsBytes(imageBytes, flush: true);

      final inputImage = InputImage.fromFilePath(tempFile.path);
      final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
      await textRecognizer.close();

      final raw = recognizedText.text;
      final normalized = normalizeText(raw);
      final words = extractWords(normalized);

      final blocks = recognizedText.blocks.map((b) => {
        'text': b.text,
        'linesCount': b.lines.length,
      }).toList();

      return OcrResult(
        rawText: raw,
        normalizedText: normalized,
        words: words,
        metadata: {
          'engine': 'google_mlkit_text_recognition',
          'blocksCount': recognizedText.blocks.length,
          'blocks': blocks,
          'extractedAt': DateTime.now().toIso8601String(),
        },
      );
    } catch (e) {
      // Gracefully handle runtime platform limitations (e.g. desktop unit test harness)
      debugPrint('OcrService: ML Kit extraction fallback ($e)');
      return OcrResult.empty;
    } finally {
      try {
        if (tempFile.existsSync()) {
          await tempFile.delete();
        }
      } catch (_) {}
    }
  }
}
