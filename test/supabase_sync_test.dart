import 'package:flutter_test/flutter_test.dart';
import 'package:billy_the_viewer/models/campaign.dart';
import 'package:billy_the_viewer/models/recognition_signature.dart';
import 'package:billy_the_viewer/services/campaign_repository.dart';
import 'package:billy_the_viewer/services/supabase/supabase_service.dart';

class MockSupabaseCampaignService implements ISupabaseCampaignService {
  final List<Campaign> campaignsToReturn;
  final bool shouldThrow;

  MockSupabaseCampaignService({
    this.campaignsToReturn = const [],
    this.shouldThrow = false,
  });

  @override
  Future<List<Campaign>> fetchActiveRecognitionCampaigns() async {
    if (shouldThrow) {
      throw Exception('Simulated network failure / offline');
    }
    return campaignsToReturn;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Supabase Integration & Mapping Tests', () {
    test('1. Supabase campaign row maps correctly to Campaign and AdTarget', () {
      final sampleVector = List<double>.generate(192, (i) => i * 0.005);
      final row = {
        'campaign_id': 'remote_camp_123',
        'advertiser_id': 'adv_profile_999',
        'ad_name': 'REMOTE BRAND CAMPAIGN',
        'brand_name': 'Acme Global',
        'destination_url': 'https://acme.example.com',
        'medium_type': 'billboard',
        'is_demo': false,
        'creative_id': 'creative_abc',
        'creative_url': 'https://example.com/storage/ad-creatives/creative_abc.jpg',
        'signature_id': 'sig_xyz',
        'visual_vector': sampleVector,
        'normalized_ocr_text': 'acme global superior quality',
        'signature_version': '1.0',
      };

      final campaign = SupabaseService.mapRowToCampaign(row);

      expect(campaign, isNotNull);
      expect(campaign!.id, equals('remote_camp_123'));
      expect(campaign.adName, equals('REMOTE BRAND CAMPAIGN'));
      expect(campaign.brandName, equals('Acme Global'));
      expect(campaign.destinationUrl, equals('https://acme.example.com'));
      expect(campaign.creativeAsset, equals('https://example.com/storage/ad-creatives/creative_abc.jpg'));
      expect(campaign.mediumType, equals(AdMediumType.billboard));
      expect(campaign.status, equals(CampaignStatus.active));
      expect(campaign.recognitionSignature, isNotNull);
      expect(campaign.recognitionSignature!.perceptualFeatures.length, equals(192));
      expect(campaign.recognitionSignature!.normalizedOcrText, equals('acme global superior quality'));

      // Test conversion to AdTarget
      final adTarget = campaign.toAdTarget();
      expect(adTarget.id, equals('remote_camp_123'));
      expect(adTarget.name, equals('REMOTE BRAND CAMPAIGN'));
      expect(adTarget.brand, equals('Acme Global'));
      expect(adTarget.embedding.length, equals(192));
      expect(adTarget.normalizedOcrText, equals('acme global superior quality'));
      expect(adTarget.imageAsset, equals('https://example.com/storage/ad-creatives/creative_abc.jpg'));
    });

    test('2. Supabase vector parser parses both List and string representations', () {
      final listVector = [0.1, 0.2, 0.3];
      expect(SupabaseService.parseVector(listVector), equals([0.1, 0.2, 0.3]));

      const stringVector = '[0.123, -0.456, 0.789]';
      final parsed = SupabaseService.parseVector(stringVector);
      expect(parsed.length, equals(3));
      expect(parsed[0], closeTo(0.123, 0.001));
      expect(parsed[1], closeTo(-0.456, 0.001));
      expect(parsed[2], closeTo(0.789, 0.001));

      expect(SupabaseService.parseVector(null), isEmpty);
      expect(SupabaseService.parseVector('invalid'), isEmpty);
    });

    test('3. Row with invalid vector length (< 192) is rejected gracefully', () {
      final invalidRow = {
        'campaign_id': 'bad_camp',
        'ad_name': 'BAD VECTOR AD',
        'brand_name': 'Bad Brand',
        'visual_vector': [0.1, 0.2], // Only 2 dimensions
      };

      final campaign = SupabaseService.mapRowToCampaign(invalidRow);
      expect(campaign, isNull);
    });

    test('4. CampaignRepository.syncRemoteCampaigns populates active candidates', () async {
      final repo = CampaignRepository();
      repo.reset();
      await repo.initialize(); // Seeds STUDIO NOIR

      expect(repo.campaigns.length, equals(1));
      expect(repo.campaigns.first.id, equals(CampaignRepository.systemDemoCampaignId));

      final remoteVector = List<double>.filled(192, 0.5);
      final remoteCampaign = Campaign(
        id: 'remote_sync_001',
        ownerAccountId: 'adv_profile_1',
        adName: 'REMOTE SYNCED AD',
        brandName: 'Cloud Brand',
        destinationUrl: 'https://cloud.example.com',
        creativeAsset: 'https://example.com/ad.jpg',
        status: CampaignStatus.active,
        createdAt: DateTime.now(),
        recognitionSignature: RecognitionSignature(
          perceptualFeatures: remoteVector,
          normalizedOcrText: 'cloud ad',
        ),
      );

      final mockService = MockSupabaseCampaignService(
        campaignsToReturn: [remoteCampaign],
      );

      final syncedCount = await repo.syncRemoteCampaigns(supabaseService: mockService);
      expect(syncedCount, equals(1));
      expect(repo.campaigns.length, equals(2));

      final found = repo.getCampaign('remote_sync_001');
      expect(found, isNotNull);
      expect(found!.adName, equals('REMOTE SYNCED AD'));
      expect(repo.activeAdTargets.any((t) => t.id == 'remote_sync_001'), isTrue);
    });

    test('5. Duplicate synchronization updates campaign without duplicating entries', () async {
      final repo = CampaignRepository();
      repo.reset();
      await repo.initialize();

      final remoteCampaignV1 = Campaign(
        id: 'remote_sync_002',
        adName: 'CLOUD AD V1',
        brandName: 'Cloud Brand',
        destinationUrl: 'https://v1.example.com',
        createdAt: DateTime.now(),
        status: CampaignStatus.active,
        recognitionSignature: RecognitionSignature(perceptualFeatures: List<double>.filled(192, 0.1)),
      );

      final remoteCampaignV2 = Campaign(
        id: 'remote_sync_002',
        adName: 'CLOUD AD V2 (UPDATED)',
        brandName: 'Cloud Brand',
        destinationUrl: 'https://v2.example.com',
        createdAt: DateTime.now(),
        status: CampaignStatus.active,
        recognitionSignature: RecognitionSignature(perceptualFeatures: List<double>.filled(192, 0.2)),
      );

      final mockServiceV1 = MockSupabaseCampaignService(campaignsToReturn: [remoteCampaignV1]);
      final mockServiceV2 = MockSupabaseCampaignService(campaignsToReturn: [remoteCampaignV2]);

      await repo.syncRemoteCampaigns(supabaseService: mockServiceV1);
      expect(repo.campaigns.length, equals(2));
      expect(repo.getCampaign('remote_sync_002')!.adName, equals('CLOUD AD V1'));

      await repo.syncRemoteCampaigns(supabaseService: mockServiceV2);
      expect(repo.campaigns.length, equals(2)); // Still 2, not 3
      expect(repo.getCampaign('remote_sync_002')!.adName, equals('CLOUD AD V2 (UPDATED)'));
    });

    test('6. Offline / network failure in syncRemoteCampaigns retains existing local campaigns without crashing', () async {
      final repo = CampaignRepository();
      repo.reset();
      await repo.initialize();

      final mockFailingService = MockSupabaseCampaignService(shouldThrow: true);

      // Should complete without throwing exception
      final syncedCount = await repo.syncRemoteCampaigns(supabaseService: mockFailingService);
      expect(syncedCount, equals(0));

      // Local demo campaign remains intact and active
      expect(repo.campaigns.length, equals(1));
      expect(repo.campaigns.first.id, equals(CampaignRepository.systemDemoCampaignId));
      expect(repo.activeAdTargets.isNotEmpty, isTrue);
    });

    test('7. Protected baseline STUDIO NOIR demo campaign cannot be overridden by remote payload', () async {
      final repo = CampaignRepository();
      repo.reset();
      await repo.initialize();

      final fakeRemoteStudioNoir = Campaign(
        id: CampaignRepository.systemDemoCampaignId,
        adName: 'FAKE OVERRIDE NOIR',
        brandName: 'Fake Brand',
        destinationUrl: 'https://fake.example.com',
        createdAt: DateTime.now(),
        status: CampaignStatus.active,
      );

      final mockService = MockSupabaseCampaignService(campaignsToReturn: [fakeRemoteStudioNoir]);
      await repo.syncRemoteCampaigns(supabaseService: mockService);

      final studioNoir = repo.getCampaign(CampaignRepository.systemDemoCampaignId);
      expect(studioNoir, isNotNull);
      expect(studioNoir!.adName, equals('STUDIO NOIR')); // Preserved original
      expect(studioNoir.brandName, equals('Studio Noir'));
    });
  });
}
