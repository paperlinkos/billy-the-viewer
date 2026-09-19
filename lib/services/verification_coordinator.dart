import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:billy_the_viewer/models/ad_target.dart';
import 'package:billy_the_viewer/services/gemini_embedding_service.dart';
import 'package:billy_the_viewer/services/matching_engine.dart';

/// VerificationCoordinator orchestrates asynchronous second-tier verification using
/// Gemini multimodal embeddings.
///
/// Features:
/// - Single-flight: Drops redundant triggers while a request is already in flight.
/// - In-session Cache: Confirmed campaign IDs are cached for [cacheTtl] (~10s) to avoid repeated network hits.
/// - Creative Embedding Cache: Caches reference embeddings for registered ad creatives.
/// - Non-blocking: Designed to be invoked asynchronously from the UI frame loop without freezing the camera stream.
class VerificationCoordinator {
  final GeminiEmbeddingClient geminiClient;
  final Duration cacheTtl;
  final double verificationThreshold;

  // Single-flight lock
  bool _isInFlight = false;

  // Cache: campaignId -> timestamp of confirmed verification
  final Map<String, DateTime> _confirmedCache = {};

  // Cache: campaignId -> pre-computed reference Gemini embedding
  final Map<String, List<double>> _referenceEmbeddingCache = {};

  VerificationCoordinator({
    GeminiEmbeddingClient? geminiClient,
    this.cacheTtl = const Duration(seconds: 10),
    this.verificationThreshold = 0.65,
  }) : geminiClient = geminiClient ??
            GeminiEmbeddingClient(
              apiKey: Platform.environment['GEMINI_API_KEY'],
            );

  bool get isInFlight => _isInFlight;

  /// Checks if a campaign was already confirmed by Gemini within the active cache window.
  bool isRecentlyConfirmed(String campaignId) {
    final confirmedAt = _confirmedCache[campaignId];
    if (confirmedAt == null) return false;
    final age = DateTime.now().difference(confirmedAt);
    if (age <= cacheTtl) {
      return true;
    }
    _confirmedCache.remove(campaignId);
    return false;
  }

  /// Manually records a confirmed campaign into the cache.
  void recordConfirmed(String campaignId) {
    _confirmedCache[campaignId] = DateTime.now();
  }

  /// Asynchronously verifies a candidate [AdTarget] against the live [frameJpegBytes].
  ///
  /// Returns a [MatchResult] if verified, or `null` if rejected, in-flight, or failed.
  Future<MatchResult?> verifyCandidate({
    required AdTarget candidate,
    required List<int> frameJpegBytes,
    List<AdTarget>? candidatePool,
  }) async {
    // 1. Fast Cache Path: If this campaign was already verified recently, return immediate confirmation
    if (isRecentlyConfirmed(candidate.id)) {
      debugPrint('VerificationCoordinator: Campaign "${candidate.name}" hit cache (verified within last ${cacheTtl.inSeconds}s).');
      return MatchResult(target: candidate, similarity: 0.95);
    }

    // 2. Single-Flight Guard: Drop trigger if a verification request is already in flight
    if (_isInFlight) {
      debugPrint('VerificationCoordinator: Dropping verification request for "${candidate.name}" (another request in flight).');
      return null;
    }

    // 3. Optional candidate pool validation: Ensure candidate is in the pre-filtered set
    if (candidatePool != null && candidatePool.isNotEmpty) {
      final inPool = candidatePool.any((t) => t.id == candidate.id);
      if (!inPool) {
        debugPrint('VerificationCoordinator: Candidate "${candidate.name}" not in pre-filtered candidate pool. Skipping.');
        return null;
      }
    }

    _isInFlight = true;

    try {
      // 4. Obtain reference embedding for the candidate ad creative
      final refEmbedding = await _getOrComputeReferenceEmbedding(candidate);
      if (refEmbedding.isEmpty) {
        debugPrint('VerificationCoordinator: Could not compute reference embedding for "${candidate.name}".');
        return null;
      }

      // 5. Compute live frame embedding
      final frameEmbedding = await geminiClient.embedImageBytes(frameJpegBytes);
      if (frameEmbedding.isEmpty) {
        debugPrint('VerificationCoordinator: Live frame embedding from geminiClient is empty.');
        return null;
      }

      // 6. Compute cosine similarity in Gemini embedding space
      final score = cosineSimilarity(refEmbedding, frameEmbedding);
      debugPrint('VerificationCoordinator: Gemini similarity for "${candidate.name}" = ${score.toStringAsFixed(4)} (threshold: $verificationThreshold)');

      if (score >= verificationThreshold) {
        recordConfirmed(candidate.id);
        return MatchResult(target: candidate, similarity: score);
      }

      debugPrint('VerificationCoordinator: candidate "${candidate.name}" rejected because score (${score.toStringAsFixed(4)}) < threshold ($verificationThreshold).');
      return null;
    } catch (e) {
      debugPrint('VerificationCoordinator error verifying candidate: $e');
      return null;
    } finally {
      _isInFlight = false;
    }
  }

  /// Retrieves or computes the Gemini embedding for the campaign's reference creative.
  Future<List<double>> _getOrComputeReferenceEmbedding(AdTarget target) async {
    if (_referenceEmbeddingCache.containsKey(target.id)) {
      return _referenceEmbeddingCache[target.id]!;
    }

    List<int> bytes = [];

    // 1. Direct in-memory creative bytes from campaign creation (newly uploaded ads)
    if (target.creativeBytes != null && target.creativeBytes!.isNotEmpty) {
      bytes = target.creativeBytes!;
    }

    // 2. Attempt to load from asset path or file system
    if (bytes.isEmpty && target.imageAsset.isNotEmpty) {
      try {
        final data = await rootBundle.load(target.imageAsset);
        bytes = data.buffer.asUint8List();
      } catch (_) {
        // Try direct file reading if asset load fails
        try {
          final file = File(target.imageAsset);
          if (file.existsSync()) {
            bytes = file.readAsBytesSync();
          }
        } catch (_) {}
      }
    }

    if (bytes.isEmpty) {
      return const [];
    }

    final embedding = await geminiClient.embedImageBytes(bytes);
    if (embedding.isNotEmpty) {
      _referenceEmbeddingCache[target.id] = embedding;
    }
    return embedding;
  }

  /// Clears in-flight status and confirmation cache.
  void reset() {
    _isInFlight = false;
    _confirmedCache.clear();
    _referenceEmbeddingCache.clear();
  }

  void dispose() {
    geminiClient.dispose();
  }
}
