import 'package:flutter/foundation.dart';
import '../models/reward.dart';

/// Service managing rewards for viewers.
/// Decoupled from recognition and camera pipelines.
/// Uses in-memory storage for the current local prototype,
/// designed to be swapped with a real backend in future phases.
class RewardService extends ChangeNotifier {
  static final RewardService _instance = RewardService._internal();
  factory RewardService() => _instance;
  RewardService._internal();

  final List<Reward> _rewards = [];

  /// Retrieves all rewards associated with a specific viewer account ID.
  /// For a new viewer with no prior rewards, returns an empty list.
  List<Reward> getRewardsForViewer(String viewerId) {
    return _rewards.where((r) => r.viewerAccountId == viewerId).toList();
  }

  /// Calculates the aggregated summary for a viewer account.
  RewardSummary getRewardSummary(String viewerId) {
    final viewerRewards = getRewardsForViewer(viewerId);
    return RewardSummary(
      totalCount: viewerRewards.length,
      pendingCount: viewerRewards.where((r) => r.isPending).length,
      earnedCount: viewerRewards.where((r) => r.isEarned).length,
      claimedCount: viewerRewards.where((r) => r.isClaimed).length,
      expiredCount: viewerRewards.where((r) => r.isExpired).length,
    );
  }

  /// Registers a new reward event.
  void addReward(Reward reward) {
    _rewards.add(reward);
    debugPrint('RewardService: Added reward ${reward.id} (${reward.status.displayName}) for viewer ${reward.viewerAccountId}.');
    notifyListeners();
  }

  /// Resets repository state for test isolation.
  void reset() {
    _rewards.clear();
    notifyListeners();
  }
}
