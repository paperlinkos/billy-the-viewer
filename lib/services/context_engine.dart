import 'package:billy_the_viewer/models/ad_target.dart';

/// ContextEngine infers the display medium (Billboard, Screen/TV, Flyer/Print)
/// using device posture, ambient light, and GPS geofencing.
///
/// It narrows down the search space and prioritizes likely candidate advertisements
/// so matching is instantaneous (< 300ms) and resistant to real-world movement.
class ContextEngine {
  const ContextEngine();

  /// Classifies the environmental context given the live sensor parameters and candidate ads.
  ContextClassification classify({
    required SensorContext context,
    required List<AdTarget> registeredTargets,
  }) {
    // 1. Geofence Check: Are we within range of any registered physical billboards?
    final List<String> nearbyBillboardIds = [];
    if (context.hasGps) {
      for (final target in registeredTargets) {
        if (target.mediumType == AdMediumType.billboard && target.location != null) {
          if (target.location!.isWithinRange(context.userLatitude!, context.userLongitude!)) {
            nearbyBillboardIds.add(target.id);
          }
        }
      }
    }

    // If viewer is physically within a registered billboard's geofence, strong billboard signal
    if (nearbyBillboardIds.isNotEmpty) {
      return ContextClassification(
        predictedMedium: AdMediumType.billboard,
        confidence: 0.95,
        rationale: 'Viewer within ${nearbyBillboardIds.length} registered billboard geofence(s).',
        matchedGeofencedCampaignIds: nearbyBillboardIds,
      );
    }

    // 2. Posture & Optical Heuristics:
    // Pitch angles:
    //  +15° to +90° = pointing up towards an elevated highway billboard or building poster
    //  -15° to +10° = eye-level pointing at TV, computer monitor, or digital display
    //  -25° to -85° = angled down towards a flyer, book, magazine, or table
    final pitch = context.devicePitchDegrees;
    final isPointingUp = pitch > 15.0;
    final isPointingDown = pitch < -25.0;
    final isEyeLevel = pitch >= -15.0 && pitch <= 15.0;

    // Ambient light: high luminance (> 0.70) suggests outdoor daylight
    final isOutdoorSunlight = context.ambientLuminance > 0.70;

    // Backlit screen signal: high contrast between glowing content and room
    final isBacklitScreen = context.contrastRatio > 0.45 && context.ambientLuminance < 0.65;

    if (isPointingUp || (isOutdoorSunlight && pitch > 0.0)) {
      final conf = isPointingUp && isOutdoorSunlight ? 0.90 : 0.75;
      return ContextClassification(
        predictedMedium: AdMediumType.billboard,
        confidence: conf,
        rationale: 'Device tilted upward (${pitch.toStringAsFixed(1)}°) in outdoor/elevated posture.',
      );
    }

    if (isPointingDown) {
      return ContextClassification(
        predictedMedium: AdMediumType.flyer,
        confidence: 0.85,
        rationale: 'Device tilted downward (${pitch.toStringAsFixed(1)}°) in reading posture.',
      );
    }

    if (isEyeLevel && isBacklitScreen) {
      return ContextClassification(
        predictedMedium: AdMediumType.screen,
        confidence: 0.88,
        rationale: 'Eye-level posture (${pitch.toStringAsFixed(1)}°) with backlit digital display contrast.',
      );
    }

    if (isEyeLevel) {
      return ContextClassification(
        predictedMedium: AdMediumType.screen,
        confidence: 0.65,
        rationale: 'Eye-level viewing posture.',
      );
    }

    return const ContextClassification(
      predictedMedium: AdMediumType.universal,
      confidence: 0.50,
      rationale: 'Neutral context, scanning universal candidate set.',
    );
  }

  /// Ranks and filters active candidate ad targets based on the current context.
  /// If geofenced billboards are present nearby, they are immediately prioritized.
  List<AdTarget> filterAndRankCandidates({
    required List<AdTarget> allTargets,
    required SensorContext context,
  }) {
    if (allTargets.isEmpty) return const [];

    final classification = classify(
      context: context,
      registeredTargets: allTargets,
    );

    // If geofenced billboards are detected, prioritize them first
    if (classification.matchedGeofencedCampaignIds.isNotEmpty) {
      final geofenced = <AdTarget>[];
      final others = <AdTarget>[];

      for (final t in allTargets) {
        if (classification.matchedGeofencedCampaignIds.contains(t.id)) {
          geofenced.add(t);
        } else {
          others.add(t);
        }
      }

      // Return geofenced first, followed by others as fallback
      return [...geofenced, ...others];
    }

    // Otherwise rank by medium affinity
    final predicted = classification.predictedMedium;
    if (predicted == AdMediumType.universal) {
      return allTargets;
    }

    final prioritized = <AdTarget>[];
    final universals = <AdTarget>[];
    final others = <AdTarget>[];

    for (final t in allTargets) {
      if (t.mediumType == predicted) {
        prioritized.add(t);
      } else if (t.mediumType == AdMediumType.universal) {
        universals.add(t);
      } else {
        others.add(t);
      }
    }

    return [...prioritized, ...universals, ...others];
  }
}
