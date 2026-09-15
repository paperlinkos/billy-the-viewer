// test/multi_ad_recognition_test.dart
//
// Multi-Ad Recognition Test Suite:
// Proves that Billy can register multiple campaigns and accurately distinguish
// between them using the exact same production recognition pipeline.
//
// 1. Two active campaigns can coexist.
// 2. Each campaign has its own unique recognition signature.
// 3. AD A's creative produces a strong match against AD A.
// 4. AD B's creative produces a strong match against AD B.
// 5. AD A does not incorrectly match AD B.
// 6. AD B does not incorrectly match AD A.
// 7. Both campaigns remain independently manageable through the advertiser campaign list.
// 8. Pausing/deactivating one campaign removes only that campaign from recognition while leaving the other active.
// 9. Full advertiser CreateCampaignScreen creation flow for AD B.
// 10. HomeScreen dual-campaign recognition evaluation.

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:billy_the_viewer/models/campaign.dart';
import 'package:billy_the_viewer/screens/campaign_list_screen.dart';
import 'package:billy_the_viewer/screens/create_campaign_screen.dart';
import 'package:billy_the_viewer/screens/home_screen.dart';
import 'package:billy_the_viewer/services/account_session.dart';
import 'package:billy_the_viewer/services/campaign_repository.dart';
import 'package:billy_the_viewer/services/matching_engine.dart';
import 'package:billy_the_viewer/services/signature_service.dart';
import 'package:billy_the_viewer/services/vision_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late VisionService visionService;
  late SignatureService signatureService;
  late Uint8List creativeABytes;
  late Uint8List creativeBBytes;
  late CampaignRepository repository;

  setUpAll(() async {
    visionService = VisionService();
    await visionService.initialize();
    signatureService = SignatureService(
      generator: LightweightSignatureGenerator(visionService: visionService),
    );

    // Load actual creatives from assets
    final fileA = File('assets/campaigns/demo_ad.jpg');
    final fileB = File('assets/campaigns/demo_ad_2.jpg');

    expect(fileA.existsSync(), isTrue, reason: 'assets/campaigns/demo_ad.jpg must exist');
    expect(fileB.existsSync(), isTrue, reason: 'assets/campaigns/demo_ad_2.jpg must exist');

    creativeABytes = fileA.readAsBytesSync();
    creativeBBytes = fileB.readAsBytesSync();
  });

  setUp(() {
    repository = CampaignRepository();
    repository.reset();
  });

  tearDown(() {
    repository.reset();
  });

  group('Multi-Ad Recognition Suite: Two Campaigns Coexistence & Signatures', () {
    test('1. Two active campaigns can coexist in CampaignRepository', () async {
      // 1. Initialize repository with baseline STUDIO NOIR (AD A)
      final sigA = await signatureService.generateSignature(creativeABytes);
      final campaignA = Campaign(
        id: 'campaign-studio-noir-001',
        ownerAccountId: 'system-demo-owner',
        adName: 'STUDIO NOIR',
        brandName: 'Studio Noir',
        destinationUrl: 'https://studionoir.example.com',
        creativeAsset: 'assets/campaigns/demo_ad.jpg',
        creativeBytes: creativeABytes,
        status: CampaignStatus.active,
        createdAt: DateTime(2026, 1, 1),
        recognitionSignature: sigA,
        signatureVersion: sigA.version,
      );
      repository.addCampaign(campaignA);

      // 2. Register second campaign AURORA VISION (AD B)
      final sigB = await signatureService.generateSignature(creativeBBytes);
      final campaignB = Campaign(
        id: 'campaign-aurora-vision-002',
        ownerAccountId: 'advertiser_002',
        adName: 'AURORA VISION',
        brandName: 'Aurora Optics',
        destinationUrl: 'https://aurora.example.com',
        creativeAsset: 'assets/campaigns/demo_ad_2.jpg',
        creativeBytes: creativeBBytes,
        status: CampaignStatus.active,
        createdAt: DateTime(2026, 1, 2),
        recognitionSignature: sigB,
        signatureVersion: sigB.version,
      );
      repository.addCampaign(campaignB);

      // Verify coexistence
      final allCampaigns = repository.campaigns;
      expect(allCampaigns.length, 2);

      final activeCampaigns = repository.getActiveCampaigns();
      expect(activeCampaigns.length, 2);

      final activeTargets = repository.getActiveAdTargets();
      expect(activeTargets.length, 2);
      expect(activeTargets.map((t) => t.id), containsAll(['campaign-studio-noir-001', 'campaign-aurora-vision-002']));
    });

    test('2. Each campaign has its own unique 192-dim recognition signature', () async {
      final sigA = await signatureService.generateSignature(creativeABytes);
      final sigB = await signatureService.generateSignature(creativeBBytes);

      // Both signatures have 192 features
      expect(sigA.perceptualFeatures.length, 192);
      expect(sigB.perceptualFeatures.length, 192);

      // Cosine similarity between AD A and AD B signatures is low (< 0.40)
      final crossSim = MatchingEngine.maxSimilarityAcrossRotations(
        sigA.perceptualFeatures,
        sigB.perceptualFeatures,
      );
      expect(crossSim, lessThan(0.40), reason: 'AD A and AD B signatures must be distinct');
    });
  });

  group('Multi-Ad Recognition Suite: True Matches and Mutual Exclusivity', () {
    test('3. AD A creative produces a strong match against AD A (similarity >= 0.85)', () async {
      final sigA = await signatureService.generateSignature(creativeABytes);
      final sigB = await signatureService.generateSignature(creativeBBytes);

      final campaignA = Campaign(
        id: 'campaign-studio-noir-001',
        adName: 'STUDIO NOIR',
        brandName: 'Studio Noir',
        destinationUrl: 'https://studionoir.example.com',
        creativeBytes: creativeABytes,
        status: CampaignStatus.active,
        createdAt: DateTime(2026, 1, 1),
        recognitionSignature: sigA,
      );
      final campaignB = Campaign(
        id: 'campaign-aurora-vision-002',
        adName: 'AURORA VISION',
        brandName: 'Aurora Optics',
        destinationUrl: 'https://aurora.example.com',
        creativeBytes: creativeBBytes,
        status: CampaignStatus.active,
        createdAt: DateTime(2026, 1, 2),
        recognitionSignature: sigB,
      );
      repository.addCampaign(campaignA);
      repository.addCampaign(campaignB);

      final activeTargets = repository.getActiveAdTargets();
      const engine = MatchingEngine(threshold: 0.60);

      // Live scan of AD A creative
      final liveEmbeddingA = await visionService.generateEmbeddingFromBytes(creativeABytes);
      final match = engine.findBestMatch(liveEmbeddingA, activeTargets);

      expect(match, isNotNull);
      expect(match!.target.id, 'campaign-studio-noir-001');
      expect(match.similarity, greaterThanOrEqualTo(0.85));
    });

    test('4. AD B creative produces a strong match against AD B (similarity >= 0.85)', () async {
      final sigA = await signatureService.generateSignature(creativeABytes);
      final sigB = await signatureService.generateSignature(creativeBBytes);

      final campaignA = Campaign(
        id: 'campaign-studio-noir-001',
        adName: 'STUDIO NOIR',
        brandName: 'Studio Noir',
        destinationUrl: 'https://studionoir.example.com',
        creativeBytes: creativeABytes,
        status: CampaignStatus.active,
        createdAt: DateTime(2026, 1, 1),
        recognitionSignature: sigA,
      );
      final campaignB = Campaign(
        id: 'campaign-aurora-vision-002',
        adName: 'AURORA VISION',
        brandName: 'Aurora Optics',
        destinationUrl: 'https://aurora.example.com',
        creativeBytes: creativeBBytes,
        status: CampaignStatus.active,
        createdAt: DateTime(2026, 1, 2),
        recognitionSignature: sigB,
      );
      repository.addCampaign(campaignA);
      repository.addCampaign(campaignB);

      final activeTargets = repository.getActiveAdTargets();
      const engine = MatchingEngine(threshold: 0.60);

      // Live scan of AD B creative
      final liveEmbeddingB = await visionService.generateEmbeddingFromBytes(creativeBBytes);
      final match = engine.findBestMatch(liveEmbeddingB, activeTargets);

      expect(match, isNotNull);
      expect(match!.target.id, 'campaign-aurora-vision-002');
      expect(match.similarity, greaterThanOrEqualTo(0.85));
    });

    test('5. AD A does NOT incorrectly match AD B', () async {
      final sigB = await signatureService.generateSignature(creativeBBytes);

      final targetB = Campaign(
        id: 'campaign-aurora-vision-002',
        adName: 'AURORA VISION',
        brandName: 'Aurora Optics',
        destinationUrl: 'https://aurora.example.com',
        creativeBytes: creativeBBytes,
        status: CampaignStatus.active,
        createdAt: DateTime(2026, 1, 2),
        recognitionSignature: sigB,
      ).toAdTarget();

      final liveEmbeddingA = await visionService.generateEmbeddingFromBytes(creativeABytes);
      final crossSim = MatchingEngine.maxSimilarityAcrossRotations(targetB.embedding, liveEmbeddingA);

      // Cross similarity is well below recognition threshold (0.60)
      expect(crossSim, lessThan(0.40), reason: 'AD A should not produce a match with AD B target');

      // If only Target B is in the candidate registry, AD A frame yields NO MATCH
      const engine = MatchingEngine(threshold: 0.60);
      final match = engine.findBestMatch(liveEmbeddingA, [targetB]);
      expect(match, isNull);
    });

    test('6. AD B does NOT incorrectly match AD A', () async {
      final sigA = await signatureService.generateSignature(creativeABytes);

      final targetA = Campaign(
        id: 'campaign-studio-noir-001',
        adName: 'STUDIO NOIR',
        brandName: 'Studio Noir',
        destinationUrl: 'https://studionoir.example.com',
        creativeBytes: creativeABytes,
        status: CampaignStatus.active,
        createdAt: DateTime(2026, 1, 1),
        recognitionSignature: sigA,
      ).toAdTarget();

      final liveEmbeddingB = await visionService.generateEmbeddingFromBytes(creativeBBytes);
      final crossSim = MatchingEngine.maxSimilarityAcrossRotations(targetA.embedding, liveEmbeddingB);

      // Cross similarity is well below recognition threshold (0.60)
      expect(crossSim, lessThan(0.40), reason: 'AD B should not produce a match with AD A target');

      // If only Target A is in the candidate registry, AD B frame yields NO MATCH
      const engine = MatchingEngine(threshold: 0.60);
      final match = engine.findBestMatch(liveEmbeddingB, [targetA]);
      expect(match, isNull);
    });
  });

  group('Multi-Ad Recognition Suite: Independent Management & Deactivation', () {
    test('7. Both campaigns remain independently manageable through advertiser campaign list', () async {
      final sigA = await signatureService.generateSignature(creativeABytes);
      final sigB = await signatureService.generateSignature(creativeBBytes);

      final campaignA = Campaign(
        id: 'campaign-studio-noir-001',
        ownerAccountId: 'owner-studio',
        adName: 'STUDIO NOIR',
        brandName: 'Studio Noir',
        destinationUrl: 'https://studionoir.example.com',
        creativeBytes: creativeABytes,
        status: CampaignStatus.active,
        createdAt: DateTime(2026, 1, 1),
        recognitionSignature: sigA,
      );
      final campaignB = Campaign(
        id: 'campaign-aurora-vision-002',
        ownerAccountId: 'owner-aurora',
        adName: 'AURORA VISION',
        brandName: 'Aurora Optics',
        destinationUrl: 'https://aurora.example.com',
        creativeBytes: creativeBBytes,
        status: CampaignStatus.active,
        createdAt: DateTime(2026, 1, 2),
        recognitionSignature: sigB,
      );

      repository.addCampaign(campaignA);
      repository.addCampaign(campaignB);

      // Retrieve owner-specific campaigns
      final studioOwnerAds = repository.getCampaignsForOwner('owner-studio');
      expect(studioOwnerAds.length, 1);
      expect(studioOwnerAds.first.id, 'campaign-studio-noir-001');

      final auroraOwnerAds = repository.getCampaignsForOwner('owner-aurora');
      expect(auroraOwnerAds.length, 1);
      expect(auroraOwnerAds.first.id, 'campaign-aurora-vision-002');

      // Modify metadata on Campaign B without altering Campaign A
      final updatedB = campaignB.copyWith(brandName: 'Aurora Optics International');
      repository.updateCampaign(updatedB);

      expect(repository.getCampaign('campaign-aurora-vision-002')!.brandName, 'Aurora Optics International');
      expect(repository.getCampaign('campaign-studio-noir-001')!.brandName, 'Studio Noir');
    });

    test('8. Pausing/deactivating one campaign removes only that campaign from recognition while leaving the other active', () async {
      final sigA = await signatureService.generateSignature(creativeABytes);
      final sigB = await signatureService.generateSignature(creativeBBytes);

      final campaignA = Campaign(
        id: 'campaign-studio-noir-001',
        adName: 'STUDIO NOIR',
        brandName: 'Studio Noir',
        destinationUrl: 'https://studionoir.example.com',
        creativeBytes: creativeABytes,
        status: CampaignStatus.active,
        createdAt: DateTime(2026, 1, 1),
        recognitionSignature: sigA,
      );
      final campaignB = Campaign(
        id: 'campaign-aurora-vision-002',
        adName: 'AURORA VISION',
        brandName: 'Aurora Optics',
        destinationUrl: 'https://aurora.example.com',
        creativeBytes: creativeBBytes,
        status: CampaignStatus.active,
        createdAt: DateTime(2026, 1, 2),
        recognitionSignature: sigB,
      );

      repository.addCampaign(campaignA);
      repository.addCampaign(campaignB);

      const engine = MatchingEngine(threshold: 0.60);
      final liveEmbeddingA = await visionService.generateEmbeddingFromBytes(creativeABytes);
      final liveEmbeddingB = await visionService.generateEmbeddingFromBytes(creativeBBytes);

      // PART 1: Pause Campaign A
      repository.pauseCampaign(campaignA.id);

      // Verify active target list contains ONLY Campaign B
      var activeTargets = repository.getActiveAdTargets();
      expect(activeTargets.length, 1);
      expect(activeTargets.first.id, campaignB.id);

      // Scanning AD A produces NO MATCH because Campaign A is paused
      expect(engine.findBestMatch(liveEmbeddingA, activeTargets), isNull);

      // Scanning AD B produces TRUE MATCH because Campaign B is still active
      final matchB = engine.findBestMatch(liveEmbeddingB, activeTargets);
      expect(matchB, isNotNull);
      expect(matchB!.target.id, campaignB.id);

      // PART 2: Unpause Campaign A, Pause Campaign B
      repository.activateCampaign(campaignA.id);
      repository.pauseCampaign(campaignB.id);

      activeTargets = repository.getActiveAdTargets();
      expect(activeTargets.length, 1);
      expect(activeTargets.first.id, campaignA.id);

      // Scanning AD B produces NO MATCH because Campaign B is paused
      expect(engine.findBestMatch(liveEmbeddingB, activeTargets), isNull);

      // Scanning AD A produces TRUE MATCH because Campaign A is now active
      final matchA = engine.findBestMatch(liveEmbeddingA, activeTargets);
      expect(matchA, isNotNull);
      expect(matchA!.target.id, campaignA.id);
    });
  });

  group('Multi-Ad Recognition Suite: UI Flow & HomeScreen Integration', () {
    testWidgets('9. CreateCampaignScreen registers second campaign into CampaignRepository through CREATE AD flow', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final session = AccountSession();
      session.signInAsAdvertiser();

      await tester.pumpWidget(
        MaterialApp(
          home: CreateCampaignScreen(
            signatureService: signatureService,
            campaignRepository: repository,
            accountSession: session,
            initialCreativeBytes: creativeBBytes,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Fill in campaign info
      await tester.enterText(find.widgetWithText(TextFormField, 'ENTER AD NAME'), 'AURORA VISION');
      await tester.enterText(find.widgetWithText(TextFormField, 'ENTER BRAND OR CREATOR'), 'Aurora Optics');
      await tester.enterText(find.widgetWithText(TextFormField, 'ENTER DESTINATION URL'), 'https://aurora.example.com');
      await tester.pump();

      // Confirm creative
      expect(find.text('USE THIS AD'), findsOneWidget);
      await tester.tap(find.text('USE THIS AD'));
      await tester.pumpAndSettle();

      expect(find.text('CREATIVE CONFIRMED'), findsOneWidget);

      // Submit
      expect(find.text('CREATE AD'), findsOneWidget);
      await tester.tap(find.text('CREATE AD'));
      await tester.pump();

      // Processing state
      expect(find.text('PREPARING AD...'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();

      // Success state
      expect(find.text('AD READY'), findsOneWidget);
      expect(find.text('ACTIVE'), findsOneWidget);

      // Verify campaign exists in repository with real signature
      final campaigns = repository.campaigns;
      expect(campaigns.length, 1);
      final registered = campaigns.first;
      expect(registered.adName, 'AURORA VISION');
      expect(registered.brandName, 'Aurora Optics');
      expect(registered.recognitionSignature, isNotNull);
      expect(registered.recognitionSignature!.perceptualFeatures.length, 192);
      expect(registered.status, CampaignStatus.active);
    });

    testWidgets('10. HomeScreen recognition pipeline displays and evaluates two active campaigns', (tester) async {
      final sigA = await signatureService.generateSignature(creativeABytes);
      final sigB = await signatureService.generateSignature(creativeBBytes);

      final campaignA = Campaign(
        id: 'campaign-studio-noir-001',
        adName: 'STUDIO NOIR',
        brandName: 'Studio Noir',
        destinationUrl: 'https://studionoir.example.com',
        creativeBytes: creativeABytes,
        status: CampaignStatus.active,
        createdAt: DateTime(2026, 1, 1),
        recognitionSignature: sigA,
      );
      final campaignB = Campaign(
        id: 'campaign-aurora-vision-002',
        adName: 'AURORA VISION',
        brandName: 'Aurora Optics',
        destinationUrl: 'https://aurora.example.com',
        creativeBytes: creativeBBytes,
        status: CampaignStatus.active,
        createdAt: DateTime(2026, 1, 2),
        recognitionSignature: sigB,
      );

      repository.addCampaign(campaignA);
      repository.addCampaign(campaignB);

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            visionService: visionService,
            initialCampaigns: repository.getActiveAdTargets(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Header indicates 2 ads are active in recognition pipeline
      expect(find.text('v0.4 · 2 ADS'), findsOneWidget);
    });

    testWidgets('11. CampaignListScreen shows both campaigns with independent actions', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final sigA = await signatureService.generateSignature(creativeABytes);
      final sigB = await signatureService.generateSignature(creativeBBytes);

      final campaignA = Campaign(
        id: 'campaign-studio-noir-001',
        ownerAccountId: 'test-advertiser',
        adName: 'STUDIO NOIR',
        brandName: 'Studio Noir',
        destinationUrl: 'https://studionoir.example.com',
        creativeBytes: creativeABytes,
        status: CampaignStatus.active,
        createdAt: DateTime(2026, 1, 1),
        recognitionSignature: sigA,
      );
      final campaignB = Campaign(
        id: 'campaign-aurora-vision-002',
        ownerAccountId: 'test-advertiser',
        adName: 'AURORA VISION',
        brandName: 'Aurora Optics',
        destinationUrl: 'https://aurora.example.com',
        creativeBytes: creativeBBytes,
        status: CampaignStatus.active,
        createdAt: DateTime(2026, 1, 2),
        recognitionSignature: sigB,
      );

      repository.addCampaign(campaignA);
      repository.addCampaign(campaignB);

      await tester.pumpWidget(
        MaterialApp(
          home: CampaignListScreen(
            campaignRepository: repository,
            ownerAccountId: 'test-advertiser',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Both ads rendered in list
      expect(find.text('YOUR ADS'), findsOneWidget);
      expect(find.text('STUDIO NOIR'), findsOneWidget);
      expect(find.text('AURORA VISION'), findsOneWidget);
    });
  });
}
