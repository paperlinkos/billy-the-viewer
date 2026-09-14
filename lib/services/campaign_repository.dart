import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/ad_target.dart';
import '../models/campaign.dart';
import '../models/recognition_signature.dart';
import 'signature_service.dart';

/// In-memory repository managing campaigns for the current session.
/// The single source of truth for campaign lifecycle state.
/// Ensures that Billy's matching engine ONLY receives currently active campaigns.
class CampaignRepository {
  static final CampaignRepository _instance = CampaignRepository._internal();
  factory CampaignRepository() => _instance;
  CampaignRepository._internal();

  final List<Campaign> _campaigns = [];
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  /// Returns all campaigns in the repository.
  List<Campaign> get campaigns => List.unmodifiable(_campaigns);

  /// Returns campaigns owned by a specific advertiser account.
  List<Campaign> getCampaignsForOwner(String ownerAccountId) {
    return _campaigns.where((c) => c.ownerAccountId == ownerAccountId).toList();
  }

  /// Returns only campaigns that are currently active and not expired.
  List<Campaign> getActiveCampaigns() {
    return _campaigns.where((c) => c.isCurrentlyActive).toList();
  }

  /// Single source of truth for recognition candidates across all advertisers.
  /// Consumer recognition searches all eligible active campaigns regardless of owner.
  List<Campaign> getActiveCampaignsForRecognition() {
    return getActiveCampaigns();
  }

  /// Returns [AdTarget] representations strictly for currently active campaigns.
  /// Paused, expired, draft, and processing campaigns are completely excluded.
  List<AdTarget> getActiveAdTargets() {
    return getActiveCampaignsForRecognition().map((c) => c.toAdTarget()).toList();
  }

  /// Alias getter for active ad targets.
  List<AdTarget> get activeAdTargets => getActiveAdTargets();

  /// Initializes the repository with the baseline STUDIO NOIR demo campaign.
  Future<void> initialize({SignatureService? signatureService}) async {
    if (_isInitialized) return;

    final service = signatureService ?? SignatureService();

    // Baseline STUDIO NOIR demo campaign
    try {
      final ByteData data = await rootBundle.load('assets/campaigns/demo_ad.jpg');
      final Uint8List bytes = data.buffer.asUint8List();
      final signature = await service.generateSignature(bytes);

      final studioNoir = Campaign(
        id: 'campaign-studio-noir-001',
        ownerAccountId: 'system-demo-owner',
        adName: 'STUDIO NOIR',
        brandName: 'Studio Noir',
        destinationUrl: 'https://studionoir.example.com',
        creativeAsset: 'assets/campaigns/demo_ad.jpg',
        creativeBytes: bytes,
        status: CampaignStatus.active,
        createdAt: DateTime(2026, 1, 1),
        recognitionSignature: signature,
        signatureVersion: signature.version,
      );

      _campaigns.clear();
      _campaigns.add(studioNoir);
      _isInitialized = true;
      debugPrint('CampaignRepository: Initialized with STUDIO NOIR demo campaign.');
    } catch (e) {
      debugPrint('CampaignRepository: Could not load demo campaign creative: $e');
      _isInitialized = true;
    }
  }

  /// Finds a campaign by ID.
  Campaign? getCampaign(String id) {
    try {
      return _campaigns.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Adds a new campaign to the repository.
  void addCampaign(Campaign campaign) {
    _campaigns.removeWhere((c) => c.id == campaign.id);
    _campaigns.add(campaign);
    debugPrint('CampaignRepository: Added campaign "${campaign.adName}" (${campaign.status.name}).');
  }

  /// Updates an existing campaign's metadata.
  bool updateCampaign(Campaign updated) {
    final index = _campaigns.indexWhere((c) => c.id == updated.id);
    if (index != -1) {
      _campaigns[index] = updated;
      debugPrint('CampaignRepository: Updated campaign "${updated.adName}".');
      return true;
    }
    return false;
  }

  /// Pauses an active campaign so Billy stops recognizing it.
  bool pauseCampaign(String id) {
    final index = _campaigns.indexWhere((c) => c.id == id);
    if (index != -1) {
      _campaigns[index] = _campaigns[index].copyWith(status: CampaignStatus.paused);
      debugPrint('CampaignRepository: Paused campaign "$id".');
      return true;
    }
    return false;
  }

  /// Activates a paused or draft campaign so Billy can recognize it.
  bool activateCampaign(String id) {
    final index = _campaigns.indexWhere((c) => c.id == id);
    if (index != -1) {
      _campaigns[index] = _campaigns[index].copyWith(status: CampaignStatus.active);
      debugPrint('CampaignRepository: Activated campaign "$id".');
      return true;
    }
    return false;
  }

  /// Marks a campaign as expired.
  bool expireCampaign(String id) {
    final index = _campaigns.indexWhere((c) => c.id == id);
    if (index != -1) {
      _campaigns[index] = _campaigns[index].copyWith(status: CampaignStatus.expired);
      debugPrint('CampaignRepository: Expired campaign "$id".');
      return true;
    }
    return false;
  }

  static const String systemDemoCampaignId = 'campaign-studio-noir-001';

  /// Permanently removes a campaign from the repository.
  /// The baseline STUDIO NOIR demo campaign is protected and cannot be deleted
  /// by normal operations unless [isSystemAction] is true.
  bool deleteCampaign(String id, {bool isSystemAction = false}) {
    final campaign = getCampaign(id);
    if (campaign == null) return false;

    if (campaign.id == systemDemoCampaignId && !isSystemAction) {
      debugPrint('CampaignRepository: Protected system demo campaign "$id" cannot be deleted.');
      return false;
    }

    final initialLength = _campaigns.length;
    _campaigns.removeWhere((c) => c.id == id);
    final removed = _campaigns.length < initialLength;
    if (removed) {
      debugPrint('CampaignRepository: Deleted campaign "$id".');
    }
    return removed;
  }

  /// Duplicates an existing campaign.
  /// Creates a new campaign with a distinct ID, copies metadata and creative,
  /// assigns ownership, generates its own signature, and registers it.
  Future<Campaign> duplicateCampaign(
    String originalId, {
    String? newOwnerAccountId,
    SignatureService? signatureService,
  }) async {
    final original = getCampaign(originalId);
    if (original == null) {
      throw StateError('Original campaign "$originalId" not found.');
    }

    final newId = 'camp-copy-${DateTime.now().millisecondsSinceEpoch}';
    final ownerId = newOwnerAccountId ?? original.ownerAccountId;
    final service = signatureService ?? SignatureService();

    RecognitionSignature? signature;
    if (original.creativeBytes != null && original.creativeBytes!.isNotEmpty) {
      signature = await service.generateSignature(original.creativeBytes!);
    } else {
      signature = original.recognitionSignature;
    }

    final duplicate = Campaign(
      id: newId,
      ownerAccountId: ownerId,
      adName: '${original.adName} (COPY)',
      brandName: original.brandName,
      destinationUrl: original.destinationUrl,
      creativePath: original.creativePath,
      creativeAsset: original.creativeAsset,
      creativeBytes: original.creativeBytes,
      status: CampaignStatus.active,
      createdAt: DateTime.now(),
      startAt: original.startAt,
      endAt: original.endAt,
      recognitionSignature: signature,
      signatureVersion: signature?.version ?? original.signatureVersion,
    );

    addCampaign(duplicate);
    debugPrint('CampaignRepository: Duplicated campaign "$originalId" to "$newId".');
    return duplicate;
  }

  /// Replaces the creative asset of an existing campaign and regenerates its visual signature.
  /// Transitions: active/paused -> processing -> generates signature -> active.
  /// The old signature is discarded completely so old creative cannot match.
  /// If processing fails, reverts to draft/error state rather than leaving an inconsistent state.
  Future<Campaign> updateCreative(
    String id,
    Uint8List newCreativeBytes, {
    String? newCreativePath,
    SignatureService? signatureService,
  }) async {
    final existing = getCampaign(id);
    if (existing == null) {
      throw StateError('Campaign with id "$id" not found.');
    }

    final service = signatureService ?? SignatureService();

    // 1. Transition to processing and clear old signature immediately
    final processing = existing.copyWith(
      status: CampaignStatus.processing,
      creativeBytes: newCreativeBytes,
      creativePath: newCreativePath,
      creativeAsset: null,
      recognitionSignature: const RecognitionSignature(perceptualFeatures: []),
    );
    updateCampaign(processing);

    try {
      // 2. Generate new signature from new creative
      final newSignature = await service.generateSignature(newCreativeBytes);

      // 3. Attach new signature and set status to active
      final updated = existing.copyWith(
        status: CampaignStatus.active,
        creativeBytes: newCreativeBytes,
        creativePath: newCreativePath,
        creativeAsset: null,
        recognitionSignature: newSignature,
        signatureVersion: newSignature.version,
      );
      updateCampaign(updated);

      debugPrint('CampaignRepository: Creative updated and new signature generated for "${updated.adName}".');
      return updated;
    } catch (e) {
      // On failure, revert to draft with empty/invalid signature to prevent mismatch
      final failed = existing.copyWith(
        status: CampaignStatus.draft,
        recognitionSignature: const RecognitionSignature(perceptualFeatures: []),
      );
      updateCampaign(failed);
      rethrow;
    }
  }

  /// Clears user-created campaigns and resets to baseline for test isolation.
  void reset() {
    _campaigns.clear();
    _isInitialized = false;
  }
}
