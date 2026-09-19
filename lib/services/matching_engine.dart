import 'dart:math' as math;
import 'package:billy_the_viewer/models/ad_target.dart';
import 'package:billy_the_viewer/services/ocr_service.dart';

/// The result of an advertisement embedding match comparison.
class MatchResult {
  final AdTarget target;
  final double similarity; // Primary / combined similarity score in [0.0, 1.0]
  final double visualSimilarity;
  final double textSimilarity;
  final bool isAmbiguous;
  final double separationMargin;
  final int distinctiveMatches;
  final String? matchedPhrase;

  const MatchResult({
    required this.target,
    required this.similarity,
    this.visualSimilarity = 0.0,
    this.textSimilarity = 0.0,
    this.isAmbiguous = false,
    this.separationMargin = 1.0,
    this.distinctiveMatches = 0,
    this.matchedPhrase,
  });

  @override
  String toString() =>
      'MatchResult(target: ${target.name}, sim: ${similarity.toStringAsFixed(4)}, '
      'vis: ${visualSimilarity.toStringAsFixed(3)}, txt: ${textSimilarity.toStringAsFixed(3)}, '
      'distinctive: $distinctiveMatches, ambiguous: $isAmbiguous, margin: ${separationMargin.toStringAsFixed(3)})';
}

/// MatchingEngine compares live feature embeddings and OCR text against registered AdTargets.
/// Completely decoupled from UI and Machine Learning inference.
class MatchingEngine {
  /// Default threshold is 0.70 based on empirical separation benchmarking:
  /// - Real ad images score >= 0.95.
  /// - Unrelated scenes score <= 0.18 or are rejected by frame quality gates.
  final double threshold;

  /// Multi-signal weights: visual is primary (0.65), text is additive (0.35).
  final double visualWeight;
  final double textWeight;

  /// Candidate separation margin threshold: if (bestScore - secondScore) < separationMargin,
  /// the match is flagged as ambiguous and requires Gemini verification or further frames.
  final double separationMargin;

  /// Minimum visual similarity required for a candidate to be considered plausible.
  final double plausibleThreshold;

  /// Combined score required for instant crisp confirmation on-device.
  final double crispCombinedThreshold;

  static const double defaultThreshold = 0.70;
  static const double defaultVisualWeight = 0.65;
  static const double defaultTextWeight = 0.35;
  static const double defaultSeparationMargin = 0.08;
  static const double defaultPlausibleThreshold = 0.52;
  static const double defaultCrispCombinedThreshold = 0.82;

  const MatchingEngine({
    this.threshold = defaultThreshold,
    this.visualWeight = defaultVisualWeight,
    this.textWeight = defaultTextWeight,
    this.separationMargin = defaultSeparationMargin,
    this.plausibleThreshold = defaultPlausibleThreshold,
    this.crispCombinedThreshold = defaultCrispCombinedThreshold,
  });

  /// Computes the cosine similarity between two feature vectors:
  /// cosine_similarity = dot(A, B) / (norm(A) * norm(B))
  static double cosineSimilarity(List<double> a, List<double> b) {
    if (a.isEmpty || b.isEmpty || a.length != b.length) {
      return 0.0;
    }

    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;

    for (int i = 0; i < a.length; i++) {
      final valA = a[i];
      final valB = b[i];
      dotProduct += valA * valB;
      normA += valA * valA;
      normB += valB * valB;
    }

    if (normA <= 0.0 || normB <= 0.0) {
      return 0.0;
    }

    final similarity = dotProduct / (math.sqrt(normA) * math.sqrt(normB));
    return similarity.clamp(-1.0, 1.0);
  }

  /// Rotates an 8x8 relative spatial descriptor (192-dim) by 0, 90, 180, or 270 degrees.
  static List<double> rotateVector(List<double> vec, int rotationSteps) {
    if (vec.length != 192 || rotationSteps % 4 == 0) return vec;
    const gridSize = 8;
    final lum = vec.sublist(0, 64);
    final dx = vec.sublist(64, 128);
    final dy = vec.sublist(128, 192);

    final rotLum = List<double>.filled(64, 0.0);
    final rotDx = List<double>.filled(64, 0.0);
    final rotDy = List<double>.filled(64, 0.0);

    for (int y = 0; y < gridSize; y++) {
      for (int x = 0; x < gridSize; x++) {
        int rx = x;
        int ry = y;
        if (rotationSteps % 4 == 1) {
          rx = gridSize - 1 - y;
          ry = x;
        } else if (rotationSteps % 4 == 2) {
          rx = gridSize - 1 - x;
          ry = gridSize - 1 - y;
        } else if (rotationSteps % 4 == 3) {
          rx = y;
          ry = gridSize - 1 - x;
        }
        final srcIdx = y * gridSize + x;
        final dstIdx = ry * gridSize + rx;
        rotLum[dstIdx] = lum[srcIdx];
        if (rotationSteps % 2 == 1) {
          rotDx[dstIdx] = dy[srcIdx];
          rotDy[dstIdx] = dx[srcIdx];
        } else {
          rotDx[dstIdx] = dx[srcIdx];
          rotDy[dstIdx] = dy[srcIdx];
        }
      }
    }

    final combined = [...rotLum, ...rotDx, ...rotDy];
    double normSq = 0.0;
    for (final v in combined) {
      normSq += v * v;
    }
    final norm = math.sqrt(normSq);
    return combined.map((v) => v / (norm > 0 ? norm : 1.0)).toList();
  }

  /// Evaluates similarity across standard 4 rotations (0, 90, 180, 270 degrees)
  /// to support device portrait/landscape viewfinder orientations.
  static double maxSimilarityAcrossRotations(List<double> target, List<double> live) {
    if (target.length != 192 || live.length != 192) {
      return cosineSimilarity(target, live);
    }
    double maxSim = -1.0;
    for (int r = 0; r < 4; r++) {
      final rotLive = rotateVector(live, r);
      final sim = cosineSimilarity(target, rotLive);
      if (sim > maxSim) maxSim = sim;
    }
    return maxSim;
  }

  /// Evaluates and ranks all candidate targets combining visual spatial features and OCR text signals.
  /// Enforces candidate separation margin calculation and flags ambiguous / close results.
  List<MatchResult> rankCandidatesMultiSignal({
    required List<double> liveEmbedding,
    required String liveNormalizedText,
    required List<AdTarget> candidates,
  }) {
    if (liveEmbedding.isEmpty || candidates.isEmpty) {
      return const [];
    }

    final List<MatchResult> scored = [];

    for (final candidate in candidates) {
      if (candidate.embedding.isEmpty) continue;

      // 1. Visual similarity across 4 standard device rotations
      final vSim = maxSimilarityAcrossRotations(candidate.embedding, liveEmbedding);

      // 2. Text similarity & rich multi-word evidence
      double tSim = 0.0;
      double effectiveVWeight = visualWeight;
      double effectiveTWeight = textWeight;
      OcrTextMatchEvidence evidence = OcrTextMatchEvidence.empty;

      if (candidate.hasOcrText && liveNormalizedText.trim().isNotEmpty) {
        evidence = OcrService.evaluateMatchEvidence(
          liveNormalizedText,
          candidate.normalizedOcrText ?? '',
        );
        tSim = evidence.score;
      } else if (candidate.hasOcrText) {
        tSim = OcrService.computeTextSimilarity(
          liveNormalizedText,
          candidate.normalizedOcrText ?? '',
        );
      } else {
        // If candidate ad has NO text (pure graphic/photo), do not penalize it.
        // Dynamically assign full weight to visual descriptor.
        effectiveVWeight = 1.0;
        effectiveTWeight = 0.0;
      }

      // 3. Dynamic multi-signal weighting:
      // When strong distinctive multi-word text evidence is present AND visual signal is plausible (vSim >= 0.10),
      // allow that creative evidence to substantially increase that campaign's score.
      // Text alone cannot confirm without visual plausibility (vSim must be >= 0.10).
      if (evidence.hasDistinctiveEvidence && vSim >= 0.10) {
        effectiveVWeight = 0.25;
        effectiveTWeight = 0.75;
      }

      // 4. Multi-signal additive combined score
      final combined = (effectiveVWeight * vSim) + (effectiveTWeight * tSim);

      scored.add(MatchResult(
        target: candidate,
        similarity: combined,
        visualSimilarity: vSim,
        textSimilarity: tSim,
        distinctiveMatches: evidence.matchedDistinctiveTokens.length,
        matchedPhrase: evidence.matchedPhrase,
      ));
    }

    if (scored.isEmpty) return const [];

    // Sort descending by combined similarity.
    // Ensure STUDIO NOIR / demo campaign cannot override a matching advertiser campaign.
    scored.sort((a, b) {
      final simComp = b.similarity.compareTo(a.similarity);
      if (simComp != 0) return simComp;
      final aIsDemo = a.target.id == 'demo_001';
      final bIsDemo = b.target.id == 'demo_001';
      if (aIsDemo && !bIsDemo) return 1;
      if (!aIsDemo && bIsDemo) return -1;
      return 0;
    });

    // 5. Wrong-ad protection: Calculate candidate separation margin
    double margin = 1.0;
    bool isAmbiguous = false;

    if (scored.length > 1) {
      margin = scored[0].similarity - scored[1].similarity;
      // If top candidate is plausible/near threshold, but separation margin is too tight:
      if (margin < separationMargin && scored[0].similarity >= plausibleThreshold) {
        isAmbiguous = true;
      }
    }

    final top = scored[0];
    scored[0] = MatchResult(
      target: top.target,
      similarity: top.similarity,
      visualSimilarity: top.visualSimilarity,
      textSimilarity: top.textSimilarity,
      isAmbiguous: isAmbiguous,
      separationMargin: margin,
      distinctiveMatches: top.distinctiveMatches,
      matchedPhrase: top.matchedPhrase,
    );

    return scored;
  }

  /// Finds the best matching AdTarget from a registry of candidates.
  /// Returns null if liveEmbedding is empty (failed quality check) or best similarity < threshold.
  /// Supports both fast visual-only path and multi-signal path when [liveNormalizedText] is provided.
  MatchResult? findBestMatch(
    List<double> liveEmbedding,
    List<AdTarget> candidates, {
    String liveNormalizedText = '',
  }) {
    if (liveEmbedding.isEmpty || candidates.isEmpty) {
      return null;
    }

    if (liveNormalizedText.trim().isNotEmpty) {
      final ranked = rankCandidatesMultiSignal(
        liveEmbedding: liveEmbedding,
        liveNormalizedText: liveNormalizedText,
        candidates: candidates,
      );
      if (ranked.isNotEmpty && ranked.first.similarity >= threshold) {
        return ranked.first;
      }
      return null;
    }

    AdTarget? bestTarget;
    double bestSimilarity = -1.0;

    for (final candidate in candidates) {
      if (candidate.embedding.isEmpty) continue;
      final similarity = maxSimilarityAcrossRotations(candidate.embedding, liveEmbedding);
      if (similarity > bestSimilarity) {
        bestSimilarity = similarity;
        bestTarget = candidate;
      }
    }

    if (bestTarget != null && bestSimilarity >= threshold) {
      return MatchResult(
        target: bestTarget,
        similarity: bestSimilarity,
        visualSimilarity: bestSimilarity,
      );
    }

    return null;
  }
}
