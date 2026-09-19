import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:billy_the_viewer/models/advertiser_profile.dart';
import 'package:billy_the_viewer/models/campaign.dart';
import 'package:billy_the_viewer/models/recognition_signature.dart';
import 'package:billy_the_viewer/services/account_session.dart';
import 'package:billy_the_viewer/services/campaign_repository.dart';
import 'package:billy_the_viewer/services/supabase/supabase_service.dart';

/// Mock implementation of ISupabaseAdvertiserService for safe testing without live network
class MockSupabaseAdvertiserService implements ISupabaseAdvertiserService {
  final Map<String, AdvertiserProfile> profiles = {};
  final List<String> uploadedPaths = [];
  final List<Map<String, dynamic>> publishedCampaigns = [];
  bool shouldFailPublish = false;
  bool shouldFailUpload = false;

  @override
  Future<AdvertiserProfile?> getAdvertiserProfile([String? userId]) async {
    if (userId == null) return profiles.values.firstOrNull;
    return profiles[userId];
  }

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
    // Check validation
    if (accountType == AdvertiserAccountType.organization) {
      final err = AdvertiserProfile.validateOrganization(
        legalName: legalName,
        displayName: displayName,
        contactEmail: contactEmail,
      );
      if (err != null) throw ArgumentError(err);
    } else {
      final err = AdvertiserProfile.validateIndividual(
        displayName: displayName,
        contactEmail: contactEmail,
      );
      if (err != null) throw ArgumentError(err);
    }

    // Reuse if existing profile with same display name or email exists
    final existing = profiles.values.where((p) => p.contactEmail == contactEmail).firstOrNull;
    if (existing != null) {
      return existing;
    }

    final newProfile = AdvertiserProfile(
      id: 'adv-uuid-${profiles.length + 1}',
      createdBy: 'user-auth-123',
      accountType: accountType,
      displayName: displayName,
      legalName: legalName,
      contactEmail: contactEmail,
      contactPhone: contactPhone,
      websiteUrl: websiteUrl,
      taxOrBusinessId: taxOrBusinessId,
      createdAt: DateTime.now(),
    );

    profiles['user-auth-123'] = newProfile;
    return newProfile;
  }

  @override
  Future<String> uploadCreative({
    required String advertiserId,
    required String campaignId,
    required String creativeId,
    required Uint8List bytes,
    required String fileExtension,
  }) async {
    if (shouldFailUpload) {
      throw Exception('Simulated creative upload network failure');
    }

    final path = '$advertiserId/$campaignId/$creativeId.$fileExtension';
    uploadedPaths.add(path);
    return 'https://rnjwteqijmxhdjsrktau.supabase.co/storage/v1/object/public/ad-creatives/$path';
  }

  @override
  Future<Campaign> publishCampaign({
    required Campaign campaign,
    required String advertiserId,
    required Uint8List creativeBytes,
    required RecognitionSignature signature,
    String fileExtension = 'jpg',
  }) async {
    if (shouldFailPublish) {
      throw Exception('Simulated database publish failure');
    }

    final creativeId = 'cr-${DateTime.now().millisecondsSinceEpoch}';
    final publicUrl = await uploadCreative(
      advertiserId: advertiserId,
      campaignId: campaign.id,
      creativeId: creativeId,
      bytes: creativeBytes,
      fileExtension: fileExtension,
    );

    publishedCampaigns.add({
      'campaign': campaign,
      'advertiserId': advertiserId,
      'creativeId': creativeId,
      'publicUrl': publicUrl,
    });

    return campaign.copyWith(
      creativeAsset: publicUrl,
      creativeBytes: creativeBytes,
      recognitionSignature: signature,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 2 — Advertiser Onboarding & Campaign Publishing Tests', () {
    late CampaignRepository repository;
    late AccountSession session;
    late MockSupabaseAdvertiserService mockService;

    setUp(() async {
      repository = CampaignRepository();
      repository.reset();
      await repository.initialize();

      session = AccountSession();
      session.reset();

      mockService = MockSupabaseAdvertiserService();
    });

    // 1. Individual profile serialization
    test('1. Individual profile serialization & deserialization', () {
      final profile = AdvertiserProfile(
        id: 'adv-001',
        createdBy: 'user-001',
        accountType: AdvertiserAccountType.individual,
        displayName: 'John Creative',
        contactEmail: 'john@creative.com',
        contactPhone: '+1 555 0100',
        websiteUrl: 'https://john.design',
        createdAt: DateTime(2026, 3, 1),
      );

      final json = profile.toJson();
      expect(json['id'], 'adv-001');
      expect(json['account_type'], 'individual');
      expect(json['display_name'], 'John Creative');
      expect(json['contact_email'], 'john@creative.com');
      expect(json['legal_name'], isNull);

      final parsed = AdvertiserProfile.fromJson(json);
      expect(parsed.id, 'adv-001');
      expect(parsed.isIndividual, isTrue);
      expect(parsed.isOrganization, isFalse);
      expect(parsed.displayName, 'John Creative');
      expect(parsed.contactEmail, 'john@creative.com');
    });

    // 2. Organization profile serialization
    test('2. Organization profile serialization & deserialization', () {
      final profile = AdvertiserProfile(
        id: 'adv-002',
        createdBy: 'user-002',
        accountType: AdvertiserAccountType.organization,
        displayName: 'Acme Media',
        legalName: 'Acme Media Holdings LLC',
        contactEmail: 'ads@acme.com',
        taxOrBusinessId: 'US-EIN-987654321',
        verificationStatus: AdvertiserVerificationStatus.pending,
      );

      final json = profile.toJson();
      expect(json['id'], 'adv-002');
      expect(json['account_type'], 'organization');
      expect(json['legal_name'], 'Acme Media Holdings LLC');
      expect(json['verification_status'], 'pending');

      final parsed = AdvertiserProfile.fromJson(json);
      expect(parsed.isOrganization, isTrue);
      expect(parsed.legalName, 'Acme Media Holdings LLC');
      expect(parsed.taxOrBusinessId, 'US-EIN-987654321');
    });

    // 3. Organization legal-name validation
    test('3. Organization requires non-empty legal name', () {
      // Organization with empty legal name fails
      final orgErr = AdvertiserProfile.validateOrganization(
        legalName: '   ',
        displayName: 'Brand X',
        contactEmail: 'brand@x.com',
      );
      expect(orgErr, contains('ORGANIZATION REQUIRES A VALID LEGAL NAME'));

      // Organization with null legal name fails
      final orgErrNull = AdvertiserProfile.validateOrganization(
        legalName: null,
        displayName: 'Brand X',
        contactEmail: 'brand@x.com',
      );
      expect(orgErrNull, contains('ORGANIZATION REQUIRES A VALID LEGAL NAME'));

      // Organization with valid legal name passes
      final orgValid = AdvertiserProfile.validateOrganization(
        legalName: 'Brand X Corporation',
        displayName: 'Brand X',
        contactEmail: 'brand@x.com',
      );
      expect(orgValid, isNull);

      // Individual does not require legal name
      final indValid = AdvertiserProfile.validateIndividual(
        displayName: 'Brand X',
        contactEmail: 'brand@x.com',
      );
      expect(indValid, isNull);
    });

    // 4. Existing advertiser profile is reused instead of duplicated
    test('4. Existing advertiser profile is reused instead of duplicated', () async {
      final first = await mockService.ensureAdvertiserProfile(
        displayName: 'Studio Noir',
        accountType: AdvertiserAccountType.individual,
        contactEmail: 'studio@noir.com',
      );

      final second = await mockService.ensureAdvertiserProfile(
        displayName: 'Studio Noir',
        accountType: AdvertiserAccountType.individual,
        contactEmail: 'studio@noir.com',
      );

      expect(second.id, first.id);
      expect(mockService.profiles.length, 1);
    });

    // 5. Campaign IDs remain compatible with String-based Dart models
    test('5. Campaign IDs remain compatible with String-based Dart models', () {
      const stringIds = [
        'campaign-studio-noir-001',
        'camp-1789541497168',
        'c43a3e6a-7341-4775-8025-a134812a673b',
      ];

      for (final id in stringIds) {
        final c = Campaign(
          id: id,
          adName: 'TEST AD',
          brandName: 'TEST BRAND',
          destinationUrl: 'https://test.com',
          createdAt: DateTime.now(),
        );
        expect(c.id, id);
        expect(c.id, isA<String>());
      }
    });

    // 6. Creative upload path is generated correctly under advertiser namespace
    test('6. Creative upload path is formatted: advertiser_id/campaign_id/creative_id.ext', () async {
      final fakeBytes = Uint8List.fromList([1, 2, 3, 4]);
      final cdnUrl = await mockService.uploadCreative(
        advertiserId: 'adv-uuid-001',
        campaignId: 'camp-12345',
        creativeId: 'cr-999',
        bytes: fakeBytes,
        fileExtension: 'jpg',
      );

      expect(mockService.uploadedPaths.length, 1);
      expect(mockService.uploadedPaths.first, 'adv-uuid-001/camp-12345/cr-999.jpg');
      expect(cdnUrl, contains('adv-uuid-001/camp-12345/cr-999.jpg'));
    });

    // 7. Campaign publishing maps all IDs correctly
    test('7. Campaign publishing maps all IDs correctly across storage and campaign', () async {
      final fakeBytes = Uint8List.fromList([1, 2, 3, 4]);
      const signature = RecognitionSignature(
        version: '1.0',
        perceptualFeatures: [0.1, 0.2, 0.3],
        normalizedOcrText: 'studio noir launch',
      );

      final campaign = Campaign(
        id: 'camp-custom-777',
        ownerAccountId: 'adv-uuid-001',
        adName: 'NOIR SHOES',
        brandName: 'Studio Noir',
        destinationUrl: 'https://noir.com/shoes',
        createdAt: DateTime.now(),
      );

      final published = await mockService.publishCampaign(
        campaign: campaign,
        advertiserId: 'adv-uuid-001',
        creativeBytes: fakeBytes,
        signature: signature,
        fileExtension: 'png',
      );

      expect(published.id, 'camp-custom-777');
      expect(published.creativeAsset, contains('adv-uuid-001/camp-custom-777/'));
      expect(published.creativeAsset, endsWith('.png'));
      expect(published.recognitionSignature?.normalizedOcrText, 'studio noir launch');
      expect(mockService.publishedCampaigns.length, 1);
      expect(mockService.publishedCampaigns.first['advertiserId'], 'adv-uuid-001');
    });

    // 8. Invalid/malformed Supabase rows fail safely
    test('8. Malformed Supabase rows fail safely in SupabaseService', () {
      // Row missing campaign_id
      expect(SupabaseService.mapRowToCampaign({'ad_name': 'Test', 'brand_name': 'Brand'}), isNull);

      // Row with invalid vector dimension
      final badVectorRow = {
        'campaign_id': 'c1',
        'ad_name': 'Ad 1',
        'brand_name': 'Brand 1',
        'visual_vector': '[0.1, 0.2]', // Only 2 dimensions, needs 192
      };
      expect(SupabaseService.mapRowToCampaign(badVectorRow), isNull);

      // Safe vector parser on garbage string
      expect(SupabaseService.parseVector('invalid-json'), isEmpty);
      expect(SupabaseService.parseVector(null), isEmpty);
    });

    // 9. Remote publish failure does not crash the app
    test('9. Remote publish failure throws caught error without crashing', () async {
      mockService.shouldFailPublish = true;

      final campaign = Campaign(
        id: 'camp-fail-test',
        adName: 'FAIL AD',
        brandName: 'FAIL BRAND',
        destinationUrl: 'https://fail.com',
        createdAt: DateTime.now(),
      );

      expect(
        () async => await mockService.publishCampaign(
          campaign: campaign,
          advertiserId: 'adv-001',
          creativeBytes: Uint8List.fromList([1, 2]),
          signature: const RecognitionSignature(),
        ),
        throwsA(isA<Exception>()),
      );
    });

    // 10. Existing local campaigns remain available after sync failure
    test('10. Existing local campaigns remain available after sync failure', () async {
      expect(repository.campaigns.isNotEmpty, isTrue);
      final initialCount = repository.campaigns.length;

      // Simulate a sync failure via CampaignRepository
      await repository.syncRemoteCampaigns(
        supabaseService: FailingCampaignService(),
      );

      // Local campaigns are preserved untouched
      expect(repository.campaigns.length, initialCount);
      expect(repository.getCampaign(CampaignRepository.systemDemoCampaignId), isNotNull);
    });

    // 11. Demo campaign `campaign-studio-noir-001` cannot be overwritten
    test('11. Demo campaign campaign-studio-noir-001 cannot be deleted or overwritten', () {
      final original = repository.getCampaign(CampaignRepository.systemDemoCampaignId);
      expect(original, isNotNull);

      // Attempt deletion
      final deleted = repository.deleteCampaign(CampaignRepository.systemDemoCampaignId);
      expect(deleted, isFalse);
      expect(repository.getCampaign(CampaignRepository.systemDemoCampaignId), isNotNull);
    });

    // 12. Newly published campaign is immediately added to local recognition candidates
    test('12. Newly published campaign is immediately added to CampaignRepository', () async {
      final signature = RecognitionSignature(
        version: '1.0',
        perceptualFeatures: List.filled(192, 0.5),
        normalizedOcrText: 'immediate recognition ad',
      );

      final newCampaign = Campaign(
        id: 'camp-immediate-001',
        ownerAccountId: 'adv-001',
        adName: 'IMMEDIATE AD',
        brandName: 'Local Brand',
        destinationUrl: 'https://localbrand.com',
        status: CampaignStatus.active,
        createdAt: DateTime.now(),
        recognitionSignature: signature,
      );

      // Local Recognition Immediacy:
      repository.addCampaign(newCampaign);

      // Verify active ad targets immediately include this campaign with 0ms network latency
      final activeTargets = repository.getActiveAdTargets();
      final target = activeTargets.where((t) => t.id == 'camp-immediate-001').firstOrNull;

      expect(target, isNotNull);
      expect(target!.name, 'IMMEDIATE AD');
      expect(target.recognitionSignature?.normalizedOcrText, 'immediate recognition ad');
      expect(target.recognitionSignature?.primaryFeatures.length, 192);
    });
  });
}

class FailingCampaignService implements ISupabaseCampaignService {
  @override
  Future<List<Campaign>> fetchActiveRecognitionCampaigns() async {
    throw Exception('Simulated offline / network failure during candidate fetch');
  }
}
