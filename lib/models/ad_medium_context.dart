import 'dart:math' as math;

/// Target display medium for an advertisement.
enum AdMediumType {
  universal,
  billboard,
  screen,
  flyer;

  String get displayName {
    switch (this) {
      case AdMediumType.universal:
        return 'ALL MEDIA';
      case AdMediumType.billboard:
        return 'BILLBOARD';
      case AdMediumType.screen:
        return 'TV / SCREEN';
      case AdMediumType.flyer:
        return 'FLYER / PRINT';
    }
  }

  String get iconLabel {
    switch (this) {
      case AdMediumType.universal:
        return 'SCAN';
      case AdMediumType.billboard:
        return '📍 BILLBOARD';
      case AdMediumType.screen:
        return '📱 SCREEN';
      case AdMediumType.flyer:
        return '📄 PRINT';
    }
  }
}

/// Geolocation configuration for physical out-of-home placements (e.g. billboards).
class GeoLocation {
  final double latitude;
  final double longitude;
  final double radiusMeters;
  final String? label;

  const GeoLocation({
    required this.latitude,
    required this.longitude,
    this.radiusMeters = 300.0,
    this.label,
  });

  /// Computes distance in meters to a point using the Haversine formula.
  double distanceTo(double userLat, double userLng) {
    const earthRadiusMeters = 6371000.0;
    final dLat = _toRadians(userLat - latitude);
    final dLng = _toRadians(userLng - longitude);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(latitude)) *
            math.cos(_toRadians(userLat)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusMeters * c;
  }

  /// Determines whether the given coordinate is within this location's catchment radius.
  bool isWithinRange(double userLat, double userLng) {
    return distanceTo(userLat, userLng) <= radiusMeters;
  }

  static double _toRadians(double degrees) => degrees * (math.pi / 180.0);

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        'radiusMeters': radiusMeters,
        if (label != null) 'label': label,
      };

  factory GeoLocation.fromJson(Map<String, dynamic> json) => GeoLocation(
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        radiusMeters: (json['radiusMeters'] as num?)?.toDouble() ?? 300.0,
        label: json['label'] as String?,
      );
}

/// Captured physical and sensor context from the mobile device during scanning.
class SensorContext {
  /// Device pitch in degrees:
  /// -90° = pointing straight down (reading desk/flyer)
  /// -45° to -20° = relaxed downward reading angle (flyer/magazine/newspaper)
  /// -15° to +10° = horizontal eye-level (laptop, TV, digital display)
  /// +15° to +80° = upward angle (elevated highway billboard, building wrap)
  final double devicePitchDegrees;

  /// Ambient scene luminance (0.0 to 1.0) derived from camera sensor or ambient lux.
  final double ambientLuminance;

  /// Center-to-perimeter dynamic contrast ratio.
  /// Backlit screens show high contrast against ambient room light.
  final double contrastRatio;

  /// Movement or camera instability (0.0 = completely still, 1.0 = heavy shake/motion).
  final double motionIntensity;

  /// Optional GPS coordinate of the viewer.
  final double? userLatitude;
  final double? userLongitude;

  const SensorContext({
    this.devicePitchDegrees = 0.0,
    this.ambientLuminance = 0.5,
    this.contrastRatio = 0.3,
    this.motionIntensity = 0.0,
    this.userLatitude,
    this.userLongitude,
  });

  bool get hasGps => userLatitude != null && userLongitude != null;
}

/// Classification outcome produced by the ContextEngine.
class ContextClassification {
  final AdMediumType predictedMedium;
  final double confidence;
  final String rationale;
  final List<String> matchedGeofencedCampaignIds;

  const ContextClassification({
    required this.predictedMedium,
    required this.confidence,
    required this.rationale,
    this.matchedGeofencedCampaignIds = const [],
  });
}
