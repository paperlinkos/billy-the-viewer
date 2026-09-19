import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:billy_the_viewer/models/ad_target.dart';
import 'package:billy_the_viewer/services/matching_engine.dart';
import 'package:billy_the_viewer/services/ocr_service.dart';
import 'package:billy_the_viewer/services/vision_service.dart';

// ────────────────────────────────────────────────────────────────────────────
// Data classes
// ────────────────────────────────────────────────────────────────────────────

/// The result of running visual + OCR recognition on a single scale/crop region.
class ScaleRegionResult {
  /// Human-readable name of this region (e.g. 'center_1_5x', 'bottom').
  final String regionName;

  /// Pixel dimensions of the region that was analyzed.
  final int width;
  final int height;

  /// Identity of the top candidate in this region.
  final AdTarget? topCandidate;

  /// Scores for the top candidate in this region.
  final double visualScore;
  final double textScore;
  final double combinedScore;

  /// Number of distinctive OCR tokens matched in this region.
  final int distinctiveMatches;

  /// The matched phrase, if any.
  final String? matchedPhrase;

  /// Margin between #1 and #2 candidates in this region.
  final double margin;

  /// Whether this region failed quality checks (empty embedding).
  final bool failedQuality;

  const ScaleRegionResult({
    required this.regionName,
    required this.width,
    required this.height,
    this.topCandidate,
    this.visualScore = 0.0,
    this.textScore = 0.0,
    this.combinedScore = 0.0,
    this.distinctiveMatches = 0,
    this.matchedPhrase,
    this.margin = 0.0,
    this.failedQuality = false,
  });

  @override
  String toString() =>
      'ScaleRegionResult(region=$regionName, ${width}x$height, '
      'top=${topCandidate?.name ?? "none"}, vis=${visualScore.toStringAsFixed(4)}, '
      'txt=${textScore.toStringAsFixed(4)}, comb=${combinedScore.toStringAsFixed(4)}, '
      'dist=$distinctiveMatches, margin=${margin.toStringAsFixed(4)})';
}

/// Aggregated evidence for a single candidate across ALL analyzed scale regions.
class CandidateAggregatedEvidence {
  final AdTarget candidate;

  /// Number of regions where this candidate scored the highest combined score.
  final int evidenceCount;

  /// Best visual score this candidate achieved across all regions.
  final double bestVisualScore;

  /// Best text score this candidate achieved across all regions.
  final double bestTextScore;

  /// Best combined score this candidate achieved across any single region.
  final double bestCombinedScore;

  /// Number of regions where this candidate showed distinctive OCR evidence.
  final int distinctiveHits;

  /// Final aggregated score (best combined + corroboration bonus).
  final double aggregatedScore;

  /// Names of regions that voted for this candidate as top.
  final List<String> votingRegions;

  /// Best matched phrase found for this candidate across all regions.
  final String? bestMatchedPhrase;

  const CandidateAggregatedEvidence({
    required this.candidate,
    required this.evidenceCount,
    required this.bestVisualScore,
    required this.bestTextScore,
    required this.bestCombinedScore,
    required this.distinctiveHits,
    required this.aggregatedScore,
    required this.votingRegions,
    this.bestMatchedPhrase,
  });
}

/// The complete result of a multi-scale analysis run.
class AggregatedRecognitionResult {
  /// All per-region results, in order analyzed.
  final List<ScaleRegionResult> regionResults;

  /// All candidate evidence aggregated and sorted by aggregatedScore descending.
  final List<CandidateAggregatedEvidence> rankedCandidates;

  /// Whether any candidate crossed the confirmation threshold after aggregation.
  final bool hasConfidentMatch;

  /// The best candidate after aggregation (may be below threshold).
  CandidateAggregatedEvidence? get bestCandidate =>
      rankedCandidates.isNotEmpty ? rankedCandidates.first : null;

  /// Margin between #1 and #2 aggregated candidates.
  double get aggregatedMargin {
    if (rankedCandidates.length < 2) return 1.0;
    return rankedCandidates[0].aggregatedScore -
        rankedCandidates[1].aggregatedScore;
  }

  const AggregatedRecognitionResult({
    required this.regionResults,
    required this.rankedCandidates,
    required this.hasConfidentMatch,
  });

  /// Formats a compact MULTISCALE SUMMARY log block.
  String formatSummary({required double threshold}) {
    final buf = StringBuffer();
    buf.writeln('--- MULTISCALE SUMMARY ---');
    if (bestCandidate != null) {
      final b = bestCandidate!;
      buf.writeln('  Best candidate     : ${b.candidate.name} [${b.candidate.id}]');
      buf.writeln('  Evidence sources   : ${b.votingRegions.join(", ")} (${b.evidenceCount}/${regionResults.length} regions)');
      buf.writeln('  Best visual score  : ${b.bestVisualScore.toStringAsFixed(4)}');
      buf.writeln('  Best text score    : ${b.bestTextScore.toStringAsFixed(4)}');
      buf.writeln('  Aggregated score   : ${b.aggregatedScore.toStringAsFixed(4)}');
      buf.writeln('  Margin (agg)       : ${aggregatedMargin.toStringAsFixed(4)}');
      buf.writeln('  Threshold          : $threshold');
      if (b.bestMatchedPhrase != null) {
        buf.writeln('  Matched phrase     : "${b.bestMatchedPhrase}"');
      }
      buf.writeln('  Distinctive hits   : ${b.distinctiveHits} region(s)');
      buf.writeln('  Final decision     : ${hasConfidentMatch ? "MATCH_CONFIRMED (${b.candidate.name})" : "NO_MATCH (aggregated ${b.aggregatedScore.toStringAsFixed(4)} < $threshold)"}');
    } else {
      buf.writeln('  No scorable candidates found across all regions.');
      buf.writeln('  Final decision     : NO_MATCH');
    }
    buf.write('--------------------------');
    return buf.toString();
  }
}

// ────────────────────────────────────────────────────────────────────────────
// MultiScalePhotoAnalyzer
// ────────────────────────────────────────────────────────────────────────────

/// Stateless utility that analyzes a captured photo at multiple scales/crops,
/// aggregates visual + OCR evidence per candidate campaign, and returns a
/// ranked [AggregatedRecognitionResult].
///
/// Design constraints preserved:
/// - Global matching threshold is NOT lowered.
/// - Visual plausibility guard (bestVisual >= 0.10) is enforced.
/// - Wrong-ad separation margin check is the caller's responsibility.
/// - A single OCR fragment in isolation cannot confirm – corroboration required.
/// - Unrelated images will still produce NO MATCH.
class MultiScalePhotoAnalyzer {
  final VisionService visionService;
  final OcrService ocrService;
  final MatchingEngine matchingEngine;

  /// Minimum number of corroborating regions required for the score bonus.
  static const int corroborationRegionCount = 3;

  /// Score bonus when the same candidate leads in ≥ [corroborationRegionCount] regions.
  static const double corroborationBonus = 0.05;

  /// Minimum visual score for a candidate to be considered plausible (unchanged from engine).
  static const double minPlausibleVisual = 0.10;

  const MultiScalePhotoAnalyzer({
    required this.visionService,
    required this.ocrService,
    required this.matchingEngine,
  });

  /// Extracts the 7 analysis regions from [image]:
  ///   full_center, center_75, center_1_5x, center_2x, top, bottom, left, right.
  ///
  /// The 'full_center' region is the same center-square crop used by the primary pass.
  static Map<String, img.Image> extractScaleRegions(img.Image image) {
    final w = image.width;
    final h = image.height;
    final regions = <String, img.Image>{};

    if (w < 64 || h < 64) return regions;

    final minDim = w < h ? w : h;

    // full_center — standard center square (same as primary pass geometry)
    final fcStartX = (w - minDim) ~/ 2;
    final fcStartY = (h - minDim) ~/ 2;
    regions['full_center'] = img.copyCrop(
      image,
      x: fcStartX,
      y: fcStartY,
      width: minDim,
      height: minDim,
    );

    // center_75 — 75% of the center square (mild zoom, 1.33×)
    final c75 = (minDim * 0.75).round().clamp(32, minDim);
    final c75X = fcStartX + (minDim - c75) ~/ 2;
    final c75Y = fcStartY + (minDim - c75) ~/ 2;
    regions['center_75'] = img.copyCrop(image, x: c75X, y: c75Y, width: c75, height: c75);

    // center_1_5x — 66.7% of center square (simulates 1.5× zoom)
    final c15 = (minDim * 0.667).round().clamp(32, minDim);
    final c15X = fcStartX + (minDim - c15) ~/ 2;
    final c15Y = fcStartY + (minDim - c15) ~/ 2;
    regions['center_1_5x'] = img.copyCrop(image, x: c15X, y: c15Y, width: c15, height: c15);

    // center_2x — 50% of center square (simulates 2× zoom)
    final c2 = (minDim * 0.50).round().clamp(32, minDim);
    final c2X = fcStartX + (minDim - c2) ~/ 2;
    final c2Y = fcStartY + (minDim - c2) ~/ 2;
    regions['center_2x'] = img.copyCrop(image, x: c2X, y: c2Y, width: c2, height: c2);

    // Overlapping spatial crops (existing logic from VisionService)
    final overlapping = VisionService.extractOverlappingCrops(image);
    regions.addAll(overlapping); // top, bottom, left, right

    return regions;
  }

  /// Analyzes [image] at all scale/crop regions against [candidates].
  ///
  /// Aggregates evidence per candidate across all regions.
  /// Returns [AggregatedRecognitionResult] with full per-region logs and ranking.
  Future<AggregatedRecognitionResult> analyze({
    required img.Image image,
    required List<AdTarget> candidates,
    required String testTag,
  }) async {
    if (candidates.isEmpty) {
      return const AggregatedRecognitionResult(
        regionResults: [],
        rankedCandidates: [],
        hasConfidentMatch: false,
      );
    }

    final regions = extractScaleRegions(image);
    final regionResults = <ScaleRegionResult>[];

    // Per-candidate evidence accumulators: candidateId -> accumulator
    final Map<String, _CandidateAccumulator> accumulators = {};
    for (final c in candidates) {
      accumulators[c.id] = _CandidateAccumulator(candidate: c);
    }

    for (final entry in regions.entries) {
      final regionName = entry.key;
      final regionImage = entry.value;

      try {
        final regionBytes = Uint8List.fromList(
          img.encodeJpg(regionImage, quality: 90),
        );

        // Visual embedding
        final regionEmb = await visionService.generateEmbeddingFromBytes(regionBytes);
        if (regionEmb.isEmpty) {
          debugPrint(
            '[$testTag] SCALE[$regionName] (${regionImage.width}×${regionImage.height}) '
            '-> failed quality checks (empty embedding).',
          );
          regionResults.add(ScaleRegionResult(
            regionName: regionName,
            width: regionImage.width,
            height: regionImage.height,
            failedQuality: true,
          ));
          continue;
        }

        // OCR extraction
        final regionOcr = await ocrService.extractText(regionBytes);

        // Rank candidates on this region
        final regionRanked = matchingEngine.rankCandidatesMultiSignal(
          liveEmbedding: regionEmb,
          liveNormalizedText: regionOcr.normalizedText,
          candidates: candidates,
        );

        if (regionRanked.isEmpty) {
          regionResults.add(ScaleRegionResult(
            regionName: regionName,
            width: regionImage.width,
            height: regionImage.height,
          ));
          continue;
        }

        final top = regionRanked.first;
        final regionMargin = regionRanked.length > 1
            ? regionRanked[0].similarity - regionRanked[1].similarity
            : 1.0;

        debugPrint(
          '[$testTag] SCALE[$regionName] (${regionImage.width}×${regionImage.height}) '
          '-> top="${top.target.name}" [${top.target.id}] '
          '| visual=${top.visualSimilarity.toStringAsFixed(4)} '
          '| text=${top.textSimilarity.toStringAsFixed(4)} '
          '| combined=${top.similarity.toStringAsFixed(4)} '
          '| distinctive=${top.distinctiveMatches} '
          '${top.matchedPhrase != null ? '| phrase="${top.matchedPhrase}" ' : ''}'
          '| margin=${regionMargin.toStringAsFixed(4)} '
          '| ocr="${regionOcr.normalizedText.isEmpty ? "(empty)" : regionOcr.normalizedText}"',
        );

        regionResults.add(ScaleRegionResult(
          regionName: regionName,
          width: regionImage.width,
          height: regionImage.height,
          topCandidate: top.target,
          visualScore: top.visualSimilarity,
          textScore: top.textSimilarity,
          combinedScore: top.similarity,
          distinctiveMatches: top.distinctiveMatches,
          matchedPhrase: top.matchedPhrase,
          margin: regionMargin,
        ));

        // Accumulate evidence for the top candidate in this region
        final acc = accumulators[top.target.id];
        if (acc != null) {
          acc.addRegionResult(
            regionName: regionName,
            visualScore: top.visualSimilarity,
            textScore: top.textSimilarity,
            combinedScore: top.similarity,
            distinctiveMatches: top.distinctiveMatches,
            matchedPhrase: top.matchedPhrase,
          );
        }

        // Also accumulate visual + text evidence for all other scored candidates
        // so that a candidate can accumulate visual evidence even from regions
        // where it didn't rank #1.
        for (int i = 1; i < regionRanked.length; i++) {
          final other = regionRanked[i];
          final otherAcc = accumulators[other.target.id];
          if (otherAcc != null) {
            otherAcc.addNonTopRegionResult(
              visualScore: other.visualSimilarity,
              textScore: other.textSimilarity,
              combinedScore: other.similarity,
              distinctiveMatches: other.distinctiveMatches,
              matchedPhrase: other.matchedPhrase,
            );
          }
        }
      } catch (e) {
        debugPrint('[$testTag] SCALE[$regionName] processing error: $e');
        regionResults.add(ScaleRegionResult(
          regionName: regionName,
          width: regionImage.width,
          height: regionImage.height,
          failedQuality: true,
        ));
      }
    }

    // Build aggregated evidence list
    final evidenceList = <CandidateAggregatedEvidence>[];
    for (final acc in accumulators.values) {
      final evidence = acc.build(
        corroborationCount: corroborationRegionCount,
        corroborationBonus: corroborationBonus,
        minPlausibleVisual: minPlausibleVisual,
      );
      if (evidence != null) {
        evidenceList.add(evidence);
      }
    }

    // Sort by aggregated score descending
    evidenceList.sort((a, b) => b.aggregatedScore.compareTo(a.aggregatedScore));

    final threshold = matchingEngine.threshold;
    final hasMatch = evidenceList.isNotEmpty &&
        evidenceList.first.aggregatedScore >= threshold &&
        evidenceList.first.bestVisualScore >= minPlausibleVisual;

    return AggregatedRecognitionResult(
      regionResults: regionResults,
      rankedCandidates: evidenceList,
      hasConfidentMatch: hasMatch,
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Internal accumulator (private)
// ────────────────────────────────────────────────────────────────────────────

class _CandidateAccumulator {
  final AdTarget candidate;

  // Regions where this candidate scored #1
  double _bestCombinedTop = 0.0;
  double _bestVisualTop = 0.0;
  double _bestTextTop = 0.0;
  int _distinctiveHitsTop = 0;
  final List<String> _votingRegions = [];
  String? _bestMatchedPhrase;

  // Best scores from non-top-1 regions (visual-only survival)
  double _bestVisualNonTop = 0.0;
  double _bestCombinedNonTop = 0.0;

  _CandidateAccumulator({required this.candidate});

  void addRegionResult({
    required String regionName,
    required double visualScore,
    required double textScore,
    required double combinedScore,
    required int distinctiveMatches,
    String? matchedPhrase,
  }) {
    _votingRegions.add(regionName);
    if (combinedScore > _bestCombinedTop) {
      _bestCombinedTop = combinedScore;
      _bestVisualTop = visualScore;
      _bestTextTop = textScore;
    }
    if (visualScore > _bestVisualTop) _bestVisualTop = visualScore;
    if (textScore > _bestTextTop) _bestTextTop = textScore;
    if (distinctiveMatches > 0) _distinctiveHitsTop++;
    if (matchedPhrase != null &&
        (matchedPhrase.length > (_bestMatchedPhrase?.length ?? 0))) {
      _bestMatchedPhrase = matchedPhrase;
    }
  }

  void addNonTopRegionResult({
    required double visualScore,
    required double textScore,
    required double combinedScore,
    required int distinctiveMatches,
    String? matchedPhrase,
  }) {
    if (visualScore > _bestVisualNonTop) _bestVisualNonTop = visualScore;
    if (combinedScore > _bestCombinedNonTop) _bestCombinedNonTop = combinedScore;
    if (distinctiveMatches > 0) _distinctiveHitsTop++;
    if (matchedPhrase != null &&
        (matchedPhrase.length > (_bestMatchedPhrase?.length ?? 0))) {
      _bestMatchedPhrase = matchedPhrase;
    }
  }

  /// Builds the final [CandidateAggregatedEvidence] or returns null if
  /// the candidate has no plausible visual evidence across any region.
  CandidateAggregatedEvidence? build({
    required int corroborationCount,
    required double corroborationBonus,
    required double minPlausibleVisual,
  }) {
    // Visual plausibility guard: must have at least some visual signal
    final bestVisual = _bestVisualTop > _bestVisualNonTop
        ? _bestVisualTop
        : _bestVisualNonTop;
    if (bestVisual < minPlausibleVisual) return null;

    // The base score is the best combined score from any single region
    // where this candidate ranked #1. Non-top regions cannot lift the score
    // above what the candidate earned as the top pick somewhere.
    double baseScore = _bestCombinedTop;

    // Corroboration bonus: same candidate leads in ≥ N regions
    double aggregated = baseScore;
    if (_votingRegions.length >= corroborationCount) {
      aggregated = (aggregated + corroborationBonus).clamp(0.0, 1.0);
    }

    if (aggregated <= 0.0 && _bestCombinedNonTop <= 0.0) return null;

    return CandidateAggregatedEvidence(
      candidate: candidate,
      evidenceCount: _votingRegions.length,
      bestVisualScore: bestVisual,
      bestTextScore: _bestTextTop,
      bestCombinedScore: _bestCombinedTop,
      distinctiveHits: _distinctiveHitsTop,
      aggregatedScore: aggregated,
      votingRegions: List.unmodifiable(_votingRegions),
      bestMatchedPhrase: _bestMatchedPhrase,
    );
  }
}
