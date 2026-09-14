import 'dart:convert';
import 'package:flutter/services.dart';
import 'ad_action.dart';

export 'ad_action.dart';

/// Represents a registered advertisement target within Billy's visual discovery registry.
///
/// Embeddings are generated at runtime by VisionService from [imageAsset].
class AdTarget {
  final String id;
  final String name;
  final String brand;
  final String destinationUrl;
  final String imageAsset;
  final List<AdAction> actions;

  // Future reward compatibility architecture (NOT displayed or processed in Phase 4)
  final bool hasReward;
  final String? rewardType;
  final num? rewardAmount;
  final String? rewardDescription;

  /// Feature embedding generated at runtime by VisionService.
  /// Empty until [HomeScreen] initializes campaigns via VisionService.
  final List<double> embedding;

  const AdTarget({
    required this.id,
    required this.name,
    required this.brand,
    required this.destinationUrl,
    required this.imageAsset,
    this.actions = const [],
    this.hasReward = false,
    this.rewardType,
    this.rewardAmount,
    this.rewardDescription,
    this.embedding = const [],
  });

  /// Returns explicit actions if provided, or defaults to a single 'view' action
  /// derived from [destinationUrl].
  List<AdAction> get effectiveActions {
    if (actions.isNotEmpty) return actions;
    if (destinationUrl.isNotEmpty) {
      return [
        AdAction(
          type: 'view',
          label: 'VIEW',
          destination: destinationUrl,
        ),
      ];
    }
    return const [];
  }

  /// Returns a copy of this AdTarget with the computed embedding attached.
  AdTarget withEmbedding(List<double> embedding) {
    return AdTarget(
      id: id,
      name: name,
      brand: brand,
      destinationUrl: destinationUrl,
      imageAsset: imageAsset,
      actions: actions,
      hasReward: hasReward,
      rewardType: rewardType,
      rewardAmount: rewardAmount,
      rewardDescription: rewardDescription,
      embedding: embedding,
    );
  }

  factory AdTarget.fromJson(Map<String, dynamic> json) {
    List<AdAction> parsedActions = [];
    if (json['actions'] is List) {
      parsedActions = (json['actions'] as List)
          .map((item) => AdAction.fromJson(item as Map<String, dynamic>))
          .toList();
    }

    final destUrl = json['destinationUrl'] as String? ?? '';
    if (parsedActions.isEmpty && destUrl.isNotEmpty) {
      parsedActions = [
        AdAction(
          type: 'view',
          label: 'VIEW',
          destination: destUrl,
        ),
      ];
    }

    return AdTarget(
      id: json['id'] as String,
      name: json['name'] as String,
      brand: json['brand'] as String,
      destinationUrl: destUrl,
      imageAsset: json['imageAsset'] as String,
      actions: parsedActions,
      hasReward: json['hasReward'] as bool? ?? false,
      rewardType: json['rewardType'] as String?,
      rewardAmount: json['rewardAmount'] as num?,
      rewardDescription: json['rewardDescription'] as String?,
      embedding: const [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'brand': brand,
      'destinationUrl': destinationUrl,
      'imageAsset': imageAsset,
      'actions': actions.map((a) => a.toJson()).toList(),
      if (hasReward) 'hasReward': hasReward,
      if (rewardType != null) 'rewardType': rewardType,
      if (rewardAmount != null) 'rewardAmount': rewardAmount,
      if (rewardDescription != null) 'rewardDescription': rewardDescription,
    };
  }

  /// Loads registered campaigns from the local JSON registry asset.
  static Future<List<AdTarget>> loadActiveCampaigns({
    String assetPath = 'assets/campaigns/active_campaigns.json',
  }) async {
    try {
      final jsonString = await rootBundle.loadString(assetPath);
      final dynamic decoded = jsonDecode(jsonString);

      if (decoded is List) {
        return decoded
            .map((item) => AdTarget.fromJson(item as Map<String, dynamic>))
            .toList();
      } else if (decoded is Map && decoded['campaigns'] is List) {
        return (decoded['campaigns'] as List)
            .map((item) => AdTarget.fromJson(item as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      rethrow;
    }
  }
}
