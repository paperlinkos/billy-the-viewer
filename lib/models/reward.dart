/// Status lifecycle for rewards in Billy.
enum RewardStatus {
  pending,
  earned,
  claimed,
  expired,
}

extension RewardStatusExtension on RewardStatus {
  String get displayName {
    switch (this) {
      case RewardStatus.pending:
        return 'PENDING';
      case RewardStatus.earned:
        return 'EARNED';
      case RewardStatus.claimed:
        return 'CLAIMED';
      case RewardStatus.expired:
        return 'EXPIRED';
    }
  }
}

/// Category / type of reward. Extensible for future qualification mechanisms.
enum RewardType {
  discovery,
  engagement,
  promo,
}

extension RewardTypeExtension on RewardType {
  String get displayName {
    switch (this) {
      case RewardType.discovery:
        return 'DISCOVERY';
      case RewardType.engagement:
        return 'ENGAGEMENT';
      case RewardType.promo:
        return 'PROMOTIONAL';
    }
  }
}

/// Domain model representing a viewer reward.
/// Decoupled from recognition and financial processing.
class Reward {
  final String id;
  final String viewerAccountId;
  final String campaignId;
  final RewardType rewardType;
  final RewardStatus status;
  final DateTime createdAt;
  final String? title;
  final Map<String, dynamic>? metadata;

  const Reward({
    required this.id,
    required this.viewerAccountId,
    required this.campaignId,
    required this.rewardType,
    required this.status,
    required this.createdAt,
    this.title,
    this.metadata,
  });

  bool get isPending => status == RewardStatus.pending;
  bool get isEarned => status == RewardStatus.earned;
  bool get isClaimed => status == RewardStatus.claimed;
  bool get isExpired => status == RewardStatus.expired;

  Reward copyWith({
    String? id,
    String? viewerAccountId,
    String? campaignId,
    RewardType? rewardType,
    RewardStatus? status,
    DateTime? createdAt,
    String? title,
    Map<String, dynamic>? metadata,
  }) {
    return Reward(
      id: id ?? this.id,
      viewerAccountId: viewerAccountId ?? this.viewerAccountId,
      campaignId: campaignId ?? this.campaignId,
      rewardType: rewardType ?? this.rewardType,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      title: title ?? this.title,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'viewerAccountId': viewerAccountId,
      'campaignId': campaignId,
      'rewardType': rewardType.name,
      'status': status.name,
      'createdAt': createdAt.toIso8601String(),
      if (title != null) 'title': title,
      if (metadata != null) 'metadata': metadata,
    };
  }

  factory Reward.fromJson(Map<String, dynamic> json) {
    return Reward(
      id: json['id'] as String,
      viewerAccountId: json['viewerAccountId'] as String,
      campaignId: json['campaignId'] as String,
      rewardType: RewardType.values.byName(json['rewardType'] as String),
      status: RewardStatus.values.byName(json['status'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
      title: json['title'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }
}

/// Aggregated reward summary for a viewer.
class RewardSummary {
  final int totalCount;
  final int pendingCount;
  final int earnedCount;
  final int claimedCount;
  final int expiredCount;

  const RewardSummary({
    required this.totalCount,
    required this.pendingCount,
    required this.earnedCount,
    required this.claimedCount,
    required this.expiredCount,
  });

  bool get hasRewards => totalCount > 0;
  bool get isEmpty => totalCount == 0;
}
