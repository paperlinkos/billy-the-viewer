import 'dart:typed_data';
import 'ad_target.dart';
import 'recognition_signature.dart';

export 'ad_medium_context.dart';

/// Campaign status lifecycle states.
enum CampaignStatus {
  draft,
  processing,
  active,
  paused,
  expired,
}

extension CampaignStatusExtension on CampaignStatus {
  String get displayName {
    switch (this) {
      case CampaignStatus.draft:
        return 'DRAFT';
      case CampaignStatus.processing:
        return 'PROCESSING';
      case CampaignStatus.active:
        return 'ACTIVE';
      case CampaignStatus.paused:
        return 'PAUSED';
      case CampaignStatus.expired:
        return 'EXPIRED';
    }
  }
}

/// Represents an advertiser campaign created locally or fetched from a registry.
class Campaign {
  final String id;
  final String ownerAccountId;
  final String adName;
  final String brandName;
  final String destinationUrl;
  final String? creativePath;
  final String? creativeAsset;
  final Uint8List? creativeBytes;
  final CampaignStatus status;
  final DateTime createdAt;
  final DateTime? startAt;
  final DateTime? endAt;
  final RecognitionSignature? recognitionSignature;
  final String signatureVersion;

  // Medium and physical location context
  final AdMediumType mediumType;
  final GeoLocation? location;

  const Campaign({
    required this.id,
    this.ownerAccountId = 'system-demo-owner',
    required this.adName,
    required this.brandName,
    required this.destinationUrl,
    this.creativePath,
    this.creativeAsset,
    this.creativeBytes,
    this.status = CampaignStatus.draft,
    required this.createdAt,
    this.startAt,
    this.endAt,
    this.recognitionSignature,
    this.signatureVersion = '1.0',
    this.mediumType = AdMediumType.universal,
    this.location,
  });

  /// Validates whether a destination URL meets format requirements:
  /// - Non-empty
  /// - Valid parseable URI
  /// - HTTP or HTTPS scheme
  /// - Non-empty host
  static bool isValidDestinationUrl(String? url) {
    if (url == null || url.trim().isEmpty) return false;
    final trimmed = url.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return false;
    if (!uri.hasScheme || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return false;
    }
    if (uri.host.isEmpty) return false;
    return true;
  }

  /// Whether this campaign has expired either via status flag or past endAt date.
  bool get isExpired {
    if (status == CampaignStatus.expired) return true;
    if (endAt != null && DateTime.now().isAfter(endAt!)) return true;
    return false;
  }

  /// Dynamic effective status accounting for schedule expiration.
  CampaignStatus get effectiveStatus {
    if (status == CampaignStatus.active && isExpired) {
      return CampaignStatus.expired;
    }
    return status;
  }

  /// Whether Billy's recognition matching engine is allowed to compare frames against this campaign.
  /// Strictly requires:
  /// 1. Status == CampaignStatus.active
  /// 2. If startAt is set, current time must be >= startAt
  /// 3. If endAt is set, current time must be <= endAt (not expired)
  bool get isCurrentlyActive {
    if (status != CampaignStatus.active) return false;
    final now = DateTime.now();
    if (startAt != null && now.isBefore(startAt!)) return false;
    if (endAt != null && now.isAfter(endAt!)) return false;
    return true;
  }

  Campaign copyWith({
    String? id,
    String? ownerAccountId,
    String? adName,
    String? brandName,
    String? destinationUrl,
    String? creativePath,
    String? creativeAsset,
    Uint8List? creativeBytes,
    CampaignStatus? status,
    DateTime? createdAt,
    DateTime? startAt,
    DateTime? endAt,
    RecognitionSignature? recognitionSignature,
    String? signatureVersion,
    AdMediumType? mediumType,
    GeoLocation? location,
  }) {
    return Campaign(
      id: id ?? this.id,
      ownerAccountId: ownerAccountId ?? this.ownerAccountId,
      adName: adName ?? this.adName,
      brandName: brandName ?? this.brandName,
      destinationUrl: destinationUrl ?? this.destinationUrl,
      creativePath: creativePath ?? this.creativePath,
      creativeAsset: creativeAsset ?? this.creativeAsset,
      creativeBytes: creativeBytes ?? this.creativeBytes,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      startAt: startAt ?? this.startAt,
      endAt: endAt ?? this.endAt,
      recognitionSignature: recognitionSignature ?? this.recognitionSignature,
      signatureVersion: signatureVersion ?? this.signatureVersion,
      mediumType: mediumType ?? this.mediumType,
      location: location ?? this.location,
    );
  }

  /// Converts this campaign into an [AdTarget] compatible with Billy's recognition matching engine.
  AdTarget toAdTarget() {
    final actions = [
      if (destinationUrl.isNotEmpty)
        AdAction(
          type: 'view',
          label: 'VIEW',
          destination: destinationUrl,
        ),
    ];

    return AdTarget(
      id: id,
      name: adName,
      brand: brandName,
      destinationUrl: destinationUrl,
      imageAsset: creativeAsset ?? creativePath ?? '',
      actions: actions,
      mediumType: mediumType,
      location: location,
      embedding: recognitionSignature?.primaryFeatures ?? const [],
      ocrText: recognitionSignature?.ocrText,
      normalizedOcrText: recognitionSignature?.normalizedOcrText,
      creativeBytes: creativeBytes,
      recognitionSignature: recognitionSignature,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'ownerAccountId': ownerAccountId,
      'adName': adName,
      'brandName': brandName,
      'destinationUrl': destinationUrl,
      if (creativePath != null) 'creativePath': creativePath,
      if (creativeAsset != null) 'creativeAsset': creativeAsset,
      'status': status.name,
      'createdAt': createdAt.toIso8601String(),
      if (startAt != null) 'startAt': startAt!.toIso8601String(),
      if (endAt != null) 'endAt': endAt!.toIso8601String(),
      if (recognitionSignature != null)
        'recognitionSignature': recognitionSignature!.toJson(),
      'signatureVersion': signatureVersion,
      'mediumType': mediumType.name,
      if (location != null) 'location': location!.toJson(),
    };
  }

  factory Campaign.fromJson(Map<String, dynamic> json, {Uint8List? creativeBytes}) {
    final statusName = json['status'] as String? ?? 'draft';
    final status = CampaignStatus.values.firstWhere(
      (s) => s.name == statusName,
      orElse: () => CampaignStatus.draft,
    );

    AdMediumType parsedMedium = AdMediumType.universal;
    if (json['mediumType'] is String) {
      parsedMedium = AdMediumType.values.firstWhere(
        (m) => m.name == json['mediumType'],
        orElse: () => AdMediumType.universal,
      );
    }

    GeoLocation? parsedLocation;
    if (json['location'] is Map<String, dynamic>) {
      parsedLocation = GeoLocation.fromJson(json['location'] as Map<String, dynamic>);
    }

    return Campaign(
      id: json['id'] as String,
      ownerAccountId: json['ownerAccountId'] as String? ?? 'system-demo-owner',
      adName: json['adName'] as String,
      brandName: json['brandName'] as String,
      destinationUrl: json['destinationUrl'] as String? ?? '',
      creativePath: json['creativePath'] as String?,
      creativeAsset: json['creativeAsset'] as String?,
      creativeBytes: creativeBytes,
      status: status,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      startAt: json['startAt'] != null
          ? DateTime.tryParse(json['startAt'] as String)
          : null,
      endAt: json['endAt'] != null
          ? DateTime.tryParse(json['endAt'] as String)
          : null,
      recognitionSignature: json['recognitionSignature'] != null
          ? RecognitionSignature.fromJson(
              json['recognitionSignature'] as Map<String, dynamic>)
          : null,
      signatureVersion: json['signatureVersion'] as String? ?? '1.0',
      mediumType: parsedMedium,
      location: parsedLocation,
    );
  }
}
