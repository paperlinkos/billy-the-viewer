import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/advertiser_profile.dart';
import '../../models/campaign.dart';
import '../../models/recognition_signature.dart';
import 'supabase_config.dart';

/// Contract for fetching remote campaigns from Supabase.
abstract class ISupabaseCampaignService {
  Future<List<Campaign>> fetchActiveRecognitionCampaigns();
}

/// Contract for advertiser onboarding, storage upload, and campaign publishing.
abstract class ISupabaseAdvertiserService {
  Future<AdvertiserProfile?> getAdvertiserProfile([String? userId]);
  Future<AdvertiserProfile> ensureAdvertiserProfile({
    required String displayName,
    required AdvertiserAccountType accountType,
    String? legalName,
    required String contactEmail,
    String? contactPhone,
    String? websiteUrl,
    String? taxOrBusinessId,
  });
  Future<String> uploadCreative({
    required String advertiserId,
    required String campaignId,
    required String creativeId,
    required Uint8List bytes,
    required String fileExtension,
  });
  Future<Campaign> publishCampaign({
    required Campaign campaign,
    required String advertiserId,
    required Uint8List creativeBytes,
    required RecognitionSignature signature,
    String fileExtension = 'jpg',
  });
}

/// Service managing client-safe communication with the remote Supabase project.
///
/// Query boundary:
/// - Reads only from the hardened [public.active_recognition_candidates] view.
/// - Never accesses private advertiser fields (tax IDs, contact emails, billing).
/// - Completely decoupled from the camera scanning / matching loop.
class SupabaseService implements ISupabaseCampaignService, ISupabaseAdvertiserService {
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;
  SupabaseService._internal();

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  SupabaseClient? _customClient;

  /// Allows injecting a mock/custom [SupabaseClient] for testing.
  @visibleForTesting
  void setClientForTesting(SupabaseClient? client) {
    _customClient = client;
    _isInitialized = client != null;
  }

  /// Initializes the Supabase client SDK if not already initialized.
  Future<void> initialize({
    String url = SupabaseConfig.projectUrl,
    String anonKey = SupabaseConfig.anonKey,
  }) async {
    if (_isInitialized) return;

    try {
      // ignore: deprecated_member_use
      await Supabase.initialize(
        url: url,
        // ignore: deprecated_member_use
        anonKey: anonKey,
        debug: kDebugMode,
      );
      _isInitialized = true;
      debugPrint('SupabaseService: Successfully initialized Supabase client.');
    } catch (e) {
      debugPrint('SupabaseService: Initialization notice: $e');
      try {
        if (Supabase.instance.isInitialized) {
          _isInitialized = true;
        }
      } catch (_) {}
    }
  }

  SupabaseClient get client {
    if (_customClient != null) return _customClient!;
    return Supabase.instance.client;
  }

  /// Fetches active, unexpired campaigns from the [active_recognition_candidates] view.
  ///
  /// Safe parsing:
  /// - Malformed rows are skipped without failing the entire batch.
  /// - Supports both PostgreSQL vector syntax ("[0.12, 0.45, ...]") and JSON arrays.
  /// - Maps rows directly to the existing domain [Campaign] model.
  @override
  Future<List<Campaign>> fetchActiveRecognitionCampaigns() async {
    final List<Campaign> candidates = [];

    try {
      final response = await client
          .from('active_recognition_candidates')
          .select('*');

      final List<dynamic> rows = response as List<dynamic>;

      for (final rawRow in rows) {
        try {
          if (rawRow is! Map<String, dynamic>) continue;
          final campaign = mapRowToCampaign(rawRow);
          if (campaign != null) {
            candidates.add(campaign);
          }
        } catch (rowError) {
          debugPrint('SupabaseService: Skipping malformed row: $rowError');
        }
      }

      debugPrint('SupabaseService: Synchronized ${candidates.length} active campaign(s) from remote.');
    } catch (e) {
      debugPrint('SupabaseService: Remote sync failed (offline or network error): $e');
      rethrow;
    }

    return candidates;
  }

  /// Maps a row from [active_recognition_candidates] into the existing [Campaign] model.
  static Campaign? mapRowToCampaign(Map<String, dynamic> row) {
    final campaignId = row['campaign_id']?.toString();
    final adName = row['ad_name']?.toString();
    final brandName = row['brand_name']?.toString();

    if (campaignId == null || adName == null || brandName == null) {
      return null;
    }

    // 1. Visual vector parsing (pgvector returns "[0.12, -0.45, ...]")
    final List<double> vector = parseVector(row['visual_vector']);
    if (vector.length != 192) {
      debugPrint('SupabaseService: Candidate "$adName" [$campaignId] has invalid vector dimension (${vector.length} != 192). Skipping.');
      return null;
    }

    // 2. Normalized OCR text
    final normalizedOcr = row['normalized_ocr_text']?.toString();
    final signatureVersion = row['signature_version']?.toString() ?? '1.0';

    // 3. Medium type mapping
    final mediumTypeStr = row['medium_type']?.toString();
    final mediumType = AdMediumType.values.firstWhere(
      (m) => m.name == mediumTypeStr,
      orElse: () => AdMediumType.universal,
    );

    // 4. Creative URL
    final creativeUrl = row['creative_url']?.toString();

    final signature = RecognitionSignature(
      version: signatureVersion,
      perceptualFeatures: vector,
      normalizedOcrText: normalizedOcr,
      ocrText: normalizedOcr,
      metadata: {
        'algorithm': 'relative_spatial_gradient_192',
        'remoteSignatureId': row['signature_id']?.toString(),
      },
    );

    return Campaign(
      id: campaignId,
      ownerAccountId: row['advertiser_id']?.toString() ?? 'remote-advertiser',
      adName: adName,
      brandName: brandName,
      destinationUrl: row['destination_url']?.toString() ?? '',
      creativeAsset: creativeUrl,
      creativePath: null,
      creativeBytes: null,
      status: CampaignStatus.active,
      createdAt: DateTime.now(),
      recognitionSignature: signature,
      signatureVersion: signatureVersion,
      mediumType: mediumType,
    );
  }

  /// Helper to robustly parse pgvector string format or JSON float list.
  static List<double> parseVector(dynamic rawVector) {
    if (rawVector == null) return const [];

    if (rawVector is List) {
      return rawVector.map((e) => (e as num).toDouble()).toList();
    }

    if (rawVector is String) {
      final trimmed = rawVector.trim();
      if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
        try {
          final parsed = jsonDecode(trimmed);
          if (parsed is List) {
            return parsed.map((e) => (e as num).toDouble()).toList();
          }
        } catch (_) {
          // Fallback manual split for comma-delimited string
          final inner = trimmed.substring(1, trimmed.length - 1).trim();
          if (inner.isEmpty) return const [];
          return inner
              .split(',')
              .map((s) => double.tryParse(s.trim()) ?? 0.0)
              .toList();
        }
      }
    }

    return const [];
  }

  // ===========================================================================
  // PHASE 2 — ADVERTISER ONBOARDING, STORAGE UPLOAD & CAMPAIGN PUBLISHING
  // ===========================================================================

  /// Returns the current authenticated user's ID or null if unauthenticated.
  String? get currentUserId => client.auth.currentUser?.id;

  /// Returns true if there is an authenticated Supabase user.
  bool get isAuthenticated => client.auth.currentUser != null;

  /// Retrieves the [AdvertiserProfile] associated with the given user or current authenticated user.
  /// If no profile exists, returns null.
  @override
  Future<AdvertiserProfile?> getAdvertiserProfile([String? userId]) async {
    final uid = userId ?? currentUserId;
    if (uid == null) {
      debugPrint('SupabaseService.getAdvertiserProfile: No authenticated user.');
      return null;
    }

    try {
      final response = await client
          .from('advertiser_profiles')
          .select('*')
          .eq('created_by', uid)
          .maybeSingle();

      if (response == null) {
        return null;
      }

      return AdvertiserProfile.fromJson(response);
    } catch (e) {
      debugPrint('SupabaseService.getAdvertiserProfile error: $e');
      rethrow;
    }
  }

  /// Ensures an advertiser profile exists for the authenticated user.
  /// If one already exists, reuses and returns it without creating a duplicate.
  /// If none exists, validates and creates a new row in [advertiser_profiles].
  @override
  Future<AdvertiserProfile> ensureAdvertiserProfile({
    required String displayName,
    required AdvertiserAccountType accountType,
    String? legalName,
    required String contactEmail,
    String? contactPhone,
    String? websiteUrl,
    String? taxOrBusinessId,
  }) async {
    final uid = currentUserId;
    if (uid == null) {
      throw StateError('Cannot create or ensure advertiser profile without an authenticated Supabase session.');
    }

    // 1. Check if profile already exists for this user to avoid duplicates
    final existing = await getAdvertiserProfile(uid);
    if (existing != null) {
      debugPrint('SupabaseService: Reusing existing advertiser profile [${existing.id}].');
      return existing;
    }

    // 2. Validate parameters against DB constraints
    if (accountType == AdvertiserAccountType.organization) {
      final validationError = AdvertiserProfile.validateOrganization(
        legalName: legalName,
        displayName: displayName,
        contactEmail: contactEmail,
      );
      if (validationError != null) {
        throw ArgumentError(validationError);
      }
    } else {
      final validationError = AdvertiserProfile.validateIndividual(
        displayName: displayName,
        contactEmail: contactEmail,
      );
      if (validationError != null) {
        throw ArgumentError(validationError);
      }
    }

    // 3. Insert new advertiser profile
    final payload = {
      'created_by': uid,
      'account_type': accountType.value,
      'display_name': displayName.trim(),
      'legal_name': legalName?.trim(),
      'contact_email': contactEmail.trim().toLowerCase(),
      'contact_phone': contactPhone?.trim(),
      'website_url': websiteUrl?.trim(),
      'tax_or_business_id': taxOrBusinessId?.trim(),
      'verification_status': 'unverified',
    };

    try {
      final insertedRow = await client
          .from('advertiser_profiles')
          .insert(payload)
          .select()
          .single();

      final profile = AdvertiserProfile.fromJson(insertedRow);
      debugPrint('SupabaseService: Created new advertiser profile [${profile.id}] for user [$uid].');
      return profile;
    } catch (e) {
      debugPrint('SupabaseService.ensureAdvertiserProfile insert failed: $e');
      rethrow;
    }
  }

  /// Uploads ad creative bytes to the public `ad-creatives` bucket under the authorized namespace:
  /// `ad-creatives/{advertiser_id}/{campaign_id}/{creative_id}.[extension]`
  /// Returns the public CDN URL of the uploaded asset.
  @override
  Future<String> uploadCreative({
    required String advertiserId,
    required String campaignId,
    required String creativeId,
    required Uint8List bytes,
    required String fileExtension,
  }) async {
    final cleanExt = fileExtension.replaceAll('.', '').toLowerCase();
    final mimeType = switch (cleanExt) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'jpg' || 'jpeg' || _ => 'image/jpeg',
    };

    final storagePath = '$advertiserId/$campaignId/$creativeId.$cleanExt';
    debugPrint('SupabaseService.uploadCreative: Uploading to $storagePath (${bytes.length} bytes)...');

    try {
      await client.storage.from('ad-creatives').uploadBinary(
        storagePath,
        bytes,
        fileOptions: FileOptions(
          contentType: mimeType,
          upsert: true,
        ),
      );

      final publicUrl = client.storage.from('ad-creatives').getPublicUrl(storagePath);
      debugPrint('SupabaseService.uploadCreative: Public URL: $publicUrl');
      return publicUrl;
    } catch (e) {
      debugPrint('SupabaseService.uploadCreative error: $e');
      rethrow;
    }
  }

  /// Publishes a campaign atomically across Supabase Storage and database tables:
  /// 1. Uploads creative to storage: ad-creatives/{advertiser_id}/{campaign_id}/{creative_id}.[ext]
  /// 2. Inserts campaign row: campaigns (id, advertiser_id, ad_name, brand_name, destination_url, status)
  /// 3. Inserts creative row: creatives (id, campaign_id, storage_path, public_url, file_name, file_size_bytes, mime_type)
  /// 4. Inserts signature row: recognition_signatures (id, creative_id, campaign_id, visual_vector, normalized_ocr_text)
  ///
  /// Failure handling: If a later database insertion fails, cleans up the uploaded storage object
  /// where safely possible and rethrows with diagnostic context.
  @override
  Future<Campaign> publishCampaign({
    required Campaign campaign,
    required String advertiserId,
    required Uint8List creativeBytes,
    required RecognitionSignature signature,
    String fileExtension = 'jpg',
  }) async {
    final cleanExt = fileExtension.replaceAll('.', '').toLowerCase();
    final mimeType = switch (cleanExt) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'jpg' || 'jpeg' || _ => 'image/jpeg',
    };

    final campaignId = campaign.id;
    final creativeId = 'cr-${DateTime.now().millisecondsSinceEpoch}';
    final signatureId = 'sig-${DateTime.now().millisecondsSinceEpoch}';
    final storagePath = '$advertiserId/$campaignId/$creativeId.$cleanExt';

    // 1. Upload creative
    String publicUrl;
    try {
      publicUrl = await uploadCreative(
        advertiserId: advertiserId,
        campaignId: campaignId,
        creativeId: creativeId,
        bytes: creativeBytes,
        fileExtension: cleanExt,
      );
    } catch (uploadError) {
      debugPrint('SupabaseService.publishCampaign: Storage upload failed: $uploadError');
      rethrow;
    }

    // 2. Insert into campaigns, creatives, recognition_signatures
    try {
      // Step A: campaigns
      await client.from('campaigns').insert({
        'id': campaignId,
        'advertiser_id': advertiserId,
        'ad_name': campaign.adName,
        'brand_name': campaign.brandName,
        'destination_url': campaign.destinationUrl,
        'status': campaign.status.name,
        'medium_type': campaign.mediumType.name,
        'start_at': campaign.startAt?.toIso8601String(),
        'end_at': campaign.endAt?.toIso8601String(),
        'is_demo': false,
      });

      // Step B: creatives
      await client.from('creatives').insert({
        'id': creativeId,
        'campaign_id': campaignId,
        'storage_path': storagePath,
        'public_url': publicUrl,
        'file_name': '$creativeId.$cleanExt',
        'file_size_bytes': creativeBytes.length,
        'mime_type': mimeType,
      });

      // Step C: recognition_signatures
      final vector = signature.primaryFeatures;
      final vectorFormatted = '[${vector.map((v) => v.toStringAsFixed(6)).join(',')}]';

      await client.from('recognition_signatures').insert({
        'id': signatureId,
        'creative_id': creativeId,
        'campaign_id': campaignId,
        'version': signature.version,
        'visual_vector': vectorFormatted,
        'raw_ocr_text': signature.ocrText,
        'normalized_ocr_text': signature.normalizedOcrText,
        'algorithm': 'relative_spatial_gradient_192',
      });

      debugPrint('SupabaseService.publishCampaign: Campaign [$campaignId] successfully published remotely.');

      // Return copy of campaign populated with remote CDN creativeAsset and metadata
      return campaign.copyWith(
        creativeAsset: publicUrl,
        creativeBytes: creativeBytes,
        recognitionSignature: RecognitionSignature(
          version: signature.version,
          perceptualFeatures: signature.perceptualFeatures,
          embedding: signature.embedding,
          ocrText: signature.ocrText,
          normalizedOcrText: signature.normalizedOcrText,
          metadata: {
            ...signature.metadata,
            'remoteSignatureId': signatureId,
            'remoteCreativeId': creativeId,
            'remoteStoragePath': storagePath,
          },
        ),
      );
    } catch (dbError) {
      debugPrint('SupabaseService.publishCampaign: Database insertion failed: $dbError. Attempting storage cleanup...');
      try {
        await client.storage.from('ad-creatives').remove([storagePath]);
        debugPrint('SupabaseService.publishCampaign: Cleaned up storage object $storagePath after DB failure.');
      } catch (cleanupError) {
        debugPrint('SupabaseService.publishCampaign: Storage cleanup warning: $cleanupError');
      }
      rethrow;
    }
  }
}
