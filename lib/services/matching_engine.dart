import 'dart:math' as math;
import 'package:billy_the_viewer/models/ad_target.dart';

/// The result of an advertisement embedding match comparison.
class MatchResult {
  final AdTarget target;
  final double similarity;

  const MatchResult({
    required this.target,
    required this.similarity,
  });

  @override
  String toString() =>
      'MatchResult(target: ${target.name}, similarity: ${similarity.toStringAsFixed(4)})';
}

/// MatchingEngine compares live feature embeddings against registered AdTargets.
/// Completely decoupled from UI and Machine Learning inference.
class MatchingEngine {
  /// Default threshold is 0.70 based on empirical separation benchmarking:
  /// - Real ad images score >= 0.95.
  /// - Unrelated scenes score <= 0.18 or are rejected by frame quality gates.
  final double threshold;

  const MatchingEngine({this.threshold = 0.70});

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

  /// Finds the best matching AdTarget from a registry of candidates.
  /// Returns null if liveEmbedding is empty (failed quality check) or best similarity < threshold.
  MatchResult? findBestMatch(List<double> liveEmbedding, List<AdTarget> candidates) {
    if (liveEmbedding.isEmpty || candidates.isEmpty) {
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
      return MatchResult(target: bestTarget, similarity: bestSimilarity);
    }

    return null;
  }
}
