import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:billy_the_viewer/models/campaign.dart';
import 'package:billy_the_viewer/screens/campaign_detail_screen.dart';
import 'package:billy_the_viewer/screens/home_screen.dart';
import 'package:billy_the_viewer/services/campaign_repository.dart';
import 'package:billy_the_viewer/services/matching_engine.dart';
import 'package:billy_the_viewer/services/signature_service.dart';
import 'package:billy_the_viewer/services/vision_service.dart';

/// Helper to generate test creative A: top half white, bottom half dark with an asymmetric mark.
Uint8List _generateCreativeABytes() {
  final image = img.Image(width: 128, height: 128);
  for (int y = 0; y < 128; y++) {
    for (int x = 0; x < 128; x++) {
      // Asymmetric pattern: top-left quadrant bright, rest dark
      final val = (x < 64 && y < 64) ? 240 : 20;
      image.setPixelRgb(x, y, val, val, val);
    }
  }
  return Uint8List.fromList(img.encodeJpg(image));
}

/// Helper to generate test creative B: center circle bright, rest dark with cross-hatch.
Uint8List _generateCreativeBBytes() {
  final image = img.Image(width: 128, height: 128);
  for (int y = 0; y < 128; y++) {
    for (int x = 0; x < 128; x++) {
      // Center circle pattern
      final dx = x - 64;
      final dy = y - 64;
      final isCircle = (dx * dx + dy * dy) < (28 * 28);
      final val = isCircle ? 240 : 20;
      image.setPixelRgb(x, y, val, val, val);
    }
  }
  return Uint8List.fromList(img.encodeJpg(image));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late VisionService visionService;
  late SignatureService signatureService;
  late Uint8List creativeABytes;
  late Uint8List creativeBBytes;

  setUpAll(() async {
    visionService = VisionService();
    await visionService.initialize();
    signatureService = SignatureService(
      generator: LightweightSignatureGenerator(visionService: visionService),
    );
    creativeABytes = _generateCreativeABytes();
    creativeBBytes = _generateCreativeBBytes();
  });

  setUp(() {
    CampaignRepository().reset();
  });

  group('Phase 6: Campaign Lifecycle States & Recognition Filtering', () {
    test('ACTIVE: Active campaign appears in recognition candidates', () async {
      final repo = CampaignRepository();
      final sig = await signatureService.generateSignature(creativeABytes);
      final campaign = Campaign(
        id: 'camp-active',
        adName: 'ACTIVE AD',
        brandName: 'Active Brand',
        destinationUrl: 'https://active.example.com',
        creativeBytes: creativeABytes,
        status: CampaignStatus.active,
        createdAt: DateTime.now(),
        recognitionSignature: sig,
      );
      repo.addCampaign(campaign);

      final activeCampaigns = repo.getActiveCampaigns();
      final activeTargets = repo.getActiveAdTargets();

      expect(activeCampaigns.any((c) => c.id == 'camp-active'), isTrue);
      expect(activeTargets.any((t) => t.id == 'camp-active'), isTrue);
    });

    test('PAUSED: Paused campaign does not appear in recognition candidates', () async {
      final repo = CampaignRepository();
      final sig = await signatureService.generateSignature(creativeABytes);
      final campaign = Campaign(
        id: 'camp-paused',
        adName: 'PAUSED AD',
        brandName: 'Paused Brand',
        destinationUrl: 'https://paused.example.com',
        creativeBytes: creativeABytes,
        status: CampaignStatus.paused,
        createdAt: DateTime.now(),
        recognitionSignature: sig,
      );
      repo.addCampaign(campaign);

      expect(repo.getActiveCampaigns().any((c) => c.id == 'camp-paused'), isFalse);
      expect(repo.getActiveAdTargets().any((t) => t.id == 'camp-paused'), isFalse);
    });

    test('EXPIRED: Expired campaign does not appear (via status or past endAt)', () async {
      final repo = CampaignRepository();
      final sig = await signatureService.generateSignature(creativeABytes);

      // Status == expired
      final explicitExpired = Campaign(
        id: 'camp-expired-explicit',
        adName: 'EXPIRED AD 1',
        brandName: 'Expired Brand',
        destinationUrl: 'https://expired.example.com',
        creativeBytes: creativeABytes,
        status: CampaignStatus.expired,
        createdAt: DateTime.now().subtract(const Duration(days: 30)),
        recognitionSignature: sig,
      );

      // Status == active, but endAt in the past
      final scheduledExpired = Campaign(
        id: 'camp-expired-scheduled',
        adName: 'EXPIRED AD 2',
        brandName: 'Expired Brand',
        destinationUrl: 'https://expired.example.com',
        creativeBytes: creativeABytes,
        status: CampaignStatus.active,
        createdAt: DateTime.now().subtract(const Duration(days: 10)),
        endAt: DateTime.now().subtract(const Duration(hours: 1)),
        recognitionSignature: sig,
      );

      repo.addCampaign(explicitExpired);
      repo.addCampaign(scheduledExpired);

      expect(scheduledExpired.isExpired, isTrue);
      expect(scheduledExpired.effectiveStatus, CampaignStatus.expired);
      expect(scheduledExpired.isCurrentlyActive, isFalse);

      expect(repo.getActiveCampaigns().any((c) => c.id == 'camp-expired-explicit'), isFalse);
      expect(repo.getActiveCampaigns().any((c) => c.id == 'camp-expired-scheduled'), isFalse);
      expect(repo.getActiveAdTargets().any((t) => t.id == 'camp-expired-scheduled'), isFalse);
    });

    test('DRAFT: Draft campaign does not appear in recognition candidates', () async {
      final repo = CampaignRepository();
      final campaign = Campaign(
        id: 'camp-draft',
        adName: 'DRAFT AD',
        brandName: 'Draft Brand',
        destinationUrl: 'https://draft.example.com',
        status: CampaignStatus.draft,
        createdAt: DateTime.now(),
      );
      repo.addCampaign(campaign);

      expect(repo.getActiveCampaigns().any((c) => c.id == 'camp-draft'), isFalse);
      expect(repo.getActiveAdTargets().any((t) => t.id == 'camp-draft'), isFalse);
    });

    test('PROCESSING: Processing campaign does not appear in recognition candidates', () async {
      final repo = CampaignRepository();
      final campaign = Campaign(
        id: 'camp-proc',
        adName: 'PROCESSING AD',
        brandName: 'Processing Brand',
        destinationUrl: 'https://proc.example.com',
        status: CampaignStatus.processing,
        createdAt: DateTime.now(),
      );
      repo.addCampaign(campaign);

      expect(repo.getActiveCampaigns().any((c) => c.id == 'camp-proc'), isFalse);
      expect(repo.getActiveAdTargets().any((t) => t.id == 'camp-proc'), isFalse);
    });
  });

  group('Phase 6: Lifecycle State Transitions', () {
    test('PAUSING: Active -> Paused removes campaign from recognition immediately', () async {
      final repo = CampaignRepository();
      final sig = await signatureService.generateSignature(creativeABytes);
      final campaign = Campaign(
        id: 'camp-toggle',
        adName: 'STUDIO NOIR',
        brandName: 'Studio Noir',
        destinationUrl: 'https://studionoir.example.com',
        creativeBytes: creativeABytes,
        status: CampaignStatus.active,
        createdAt: DateTime.now(),
        recognitionSignature: sig,
      );
      repo.addCampaign(campaign);

      expect(repo.getActiveAdTargets().length, 1);

      // Pause campaign
      final paused = repo.pauseCampaign('camp-toggle');
      expect(paused, isTrue);
      expect(repo.getCampaign('camp-toggle')!.status, CampaignStatus.paused);
      expect(repo.getActiveAdTargets().isEmpty, isTrue);
    });

    test('ACTIVATION: Paused -> Active restores campaign to recognition immediately', () async {
      final repo = CampaignRepository();
      final sig = await signatureService.generateSignature(creativeABytes);
      final campaign = Campaign(
        id: 'camp-toggle-2',
        adName: 'STUDIO NOIR',
        brandName: 'Studio Noir',
        destinationUrl: 'https://studionoir.example.com',
        creativeBytes: creativeABytes,
        status: CampaignStatus.paused,
        createdAt: DateTime.now(),
        recognitionSignature: sig,
      );
      repo.addCampaign(campaign);

      expect(repo.getActiveAdTargets().isEmpty, isTrue);

      // Activate campaign
      final activated = repo.activateCampaign('camp-toggle-2');
      expect(activated, isTrue);
      expect(repo.getCampaign('camp-toggle-2')!.status, CampaignStatus.active);
      expect(repo.getActiveAdTargets().length, 1);
    });

    test('DELETE: Deleted campaign disappears permanently from repository and recognition', () async {
      final repo = CampaignRepository();
      final sig = await signatureService.generateSignature(creativeABytes);
      final campaign = Campaign(
        id: 'camp-to-delete',
        adName: 'DELETE ME',
        brandName: 'Ephemeral Brand',
        destinationUrl: 'https://del.example.com',
        creativeBytes: creativeABytes,
        status: CampaignStatus.active,
        createdAt: DateTime.now(),
        recognitionSignature: sig,
      );
      repo.addCampaign(campaign);

      expect(repo.getActiveAdTargets().length, 1);

      // Delete campaign
      final deleted = repo.deleteCampaign('camp-to-delete');
      expect(deleted, isTrue);
      expect(repo.getCampaign('camp-to-delete'), isNull);
      expect(repo.campaigns.isEmpty, isTrue);
      expect(repo.getActiveAdTargets().isEmpty, isTrue);
    });
  });

  group('Phase 6: Creative Replacement & Signature Regeneration', () {
    test('Changing creative generates new signature and completely discards old signature', () async {
      final repo = CampaignRepository();
      final originalSig = await signatureService.generateSignature(creativeABytes);

      final campaign = Campaign(
        id: 'camp-creative-test',
        adName: 'IMAGE SWAP TEST',
        brandName: 'Swap Brand',
        destinationUrl: 'https://swap.example.com',
        creativeBytes: creativeABytes,
        status: CampaignStatus.active,
        createdAt: DateTime.now(),
        recognitionSignature: originalSig,
      );
      repo.addCampaign(campaign);

      expect(repo.getCampaign('camp-creative-test')!.recognitionSignature!.primaryFeatures, originalSig.primaryFeatures);

      // Replace creative with creativeBBytes
      final updated = await repo.updateCreative(
        'camp-creative-test',
        creativeBBytes,
        signatureService: signatureService,
      );

      expect(updated.status, CampaignStatus.active);
      expect(updated.creativeBytes, creativeBBytes);
      expect(updated.recognitionSignature, isNotNull);

      // Verify the new signature does not equal old signature
      expect(updated.recognitionSignature!.primaryFeatures, isNot(equals(originalSig.primaryFeatures)));

      // Verify MatchingEngine recognizes new creative B and rejects old creative A
      const engine = MatchingEngine(threshold: 0.85);
      final target = updated.toAdTarget();

      final matchNew = engine.findBestMatch(updated.recognitionSignature!.primaryFeatures, [target]);
      expect(matchNew, isNotNull);
      expect(matchNew!.similarity, greaterThanOrEqualTo(0.99));

      // Matching with old creative signature yields low similarity or no match
      final matchOld = engine.findBestMatch(originalSig.primaryFeatures, [target]);
      final oldSim = matchOld?.similarity ?? 0.0;
      expect(oldSim, lessThan(0.85));
    });
  });

  group('Phase 6: Destination URL Validation', () {
    test('Rejects invalid destination URLs and accepts valid HTTP/HTTPS URLs', () {
      // Invalid
      expect(Campaign.isValidDestinationUrl(null), isFalse);
      expect(Campaign.isValidDestinationUrl(''), isFalse);
      expect(Campaign.isValidDestinationUrl('   '), isFalse);
      expect(Campaign.isValidDestinationUrl('not_a_url'), isFalse);
      expect(Campaign.isValidDestinationUrl('ftp://example.com'), isFalse);
      expect(Campaign.isValidDestinationUrl('javascript:alert(1)'), isFalse);
      expect(Campaign.isValidDestinationUrl('http://'), isFalse);
      expect(Campaign.isValidDestinationUrl('https://'), isFalse);

      // Valid
      expect(Campaign.isValidDestinationUrl('https://example.com'), isTrue);
      expect(Campaign.isValidDestinationUrl('http://studionoir.com'), isTrue);
      expect(Campaign.isValidDestinationUrl('https://sub.domain.org/path?q=1#hash'), isTrue);
    });
  });

  group('Phase 6: Multiple Campaigns & Selective Recognition', () {
    test('Matching engine only considers active campaigns when A=active, B=paused, C=expired', () async {
      final repo = CampaignRepository();
      final sigA = await signatureService.generateSignature(creativeABytes);
      final sigB = await signatureService.generateSignature(creativeBBytes);
      final sigC = await signatureService.generateSignature(creativeABytes);

      final campaignA = Campaign(
        id: 'camp-A',
        adName: 'CAMPAIGN A',
        brandName: 'Brand A',
        destinationUrl: 'https://a.com',
        creativeBytes: creativeABytes,
        status: CampaignStatus.active,
        createdAt: DateTime.now(),
        recognitionSignature: sigA,
      );

      final campaignB = Campaign(
        id: 'camp-B',
        adName: 'CAMPAIGN B',
        brandName: 'Brand B',
        destinationUrl: 'https://b.com',
        creativeBytes: creativeBBytes,
        status: CampaignStatus.paused,
        createdAt: DateTime.now(),
        recognitionSignature: sigB,
      );

      final campaignC = Campaign(
        id: 'camp-C',
        adName: 'CAMPAIGN C',
        brandName: 'Brand C',
        destinationUrl: 'https://c.com',
        creativeBytes: creativeABytes,
        status: CampaignStatus.expired,
        createdAt: DateTime.now().subtract(const Duration(days: 30)),
        recognitionSignature: sigC,
      );

      repo.addCampaign(campaignA);
      repo.addCampaign(campaignB);
      repo.addCampaign(campaignC);

      // Request active targets from repository
      final eligibleTargets = repo.getActiveAdTargets();

      expect(eligibleTargets.length, 1);
      expect(eligibleTargets.first.id, 'camp-A');

      const engine = MatchingEngine(threshold: 0.85);

      // Frame with creative A -> matched against campaign A
      final matchA = engine.findBestMatch(sigA.primaryFeatures, eligibleTargets);
      expect(matchA, isNotNull);
      expect(matchA!.target.id, 'camp-A');

      // Frame with creative B -> campaign B is paused so no match is found!
      final matchB = engine.findBestMatch(sigB.primaryFeatures, eligibleTargets);
      expect(matchB, isNull);
    });
  });

  group('Phase 6: CampaignDetailScreen UI Controls', () {
    testWidgets('Displays details, toggles PAUSE/ACTIVATE, and supports DELETE confirmation', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = CampaignRepository();
      final sig = await signatureService.generateSignature(creativeABytes);
      final campaign = Campaign(
        id: 'detail-test-1',
        adName: 'STUDIO NOIR',
        brandName: 'Studio Noir',
        destinationUrl: 'https://studionoir.example.com',
        creativeBytes: creativeABytes,
        status: CampaignStatus.active,
        createdAt: DateTime(2026, 3, 1),
        recognitionSignature: sig,
      );
      repo.addCampaign(campaign);

      await tester.pumpWidget(
        MaterialApp(
          home: CampaignDetailScreen(
            campaignId: 'detail-test-1',
            campaignRepository: repo,
            signatureService: signatureService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('STUDIO NOIR'), findsOneWidget);
      expect(find.text('Studio Noir'), findsOneWidget);
      expect(find.text('ACTIVE'), findsOneWidget);
      expect(find.text('PAUSE AD'), findsOneWidget);

      // Tap PAUSE AD
      await tester.tap(find.text('PAUSE AD'));
      await tester.pumpAndSettle();

      expect(find.text('PAUSED'), findsOneWidget);
      expect(find.text('ACTIVATE AD'), findsOneWidget);
      expect(repo.getCampaign('detail-test-1')!.status, CampaignStatus.paused);

      // Tap ACTIVATE AD
      await tester.tap(find.text('ACTIVATE AD'));
      await tester.pumpAndSettle();

      expect(find.text('ACTIVE'), findsOneWidget);
      expect(find.text('PAUSE AD'), findsOneWidget);
      expect(repo.getCampaign('detail-test-1')!.status, CampaignStatus.active);

      // Test DELETE AD flow
      await tester.tap(find.text('DELETE AD'));
      await tester.pumpAndSettle();

      expect(find.text('CONFIRM DELETE'), findsOneWidget);
      expect(find.text('CANCEL'), findsOneWidget);

      // Tap CANCEL first
      await tester.tap(find.text('CANCEL'));
      await tester.pumpAndSettle();

      expect(repo.getCampaign('detail-test-1'), isNotNull);

      // Tap DELETE AD and CONFIRM DELETE
      await tester.tap(find.text('DELETE AD'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('CONFIRM DELETE'));
      await tester.pumpAndSettle();

      // Confirmed deleted from repo
      expect(repo.getCampaign('detail-test-1'), isNull);
    });
  });

  group('Phase 6: HomeScreen Integration & Pause Proof', () {
    testWidgets('Pausing STUDIO NOIR causes HomeScreen to exclude it from recognition', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = CampaignRepository();
      final sig = await signatureService.generateSignature(creativeABytes);
      final campaign = Campaign(
        id: 'campaign-studio-noir-001',
        adName: 'STUDIO NOIR',
        brandName: 'Studio Noir',
        destinationUrl: 'https://studionoir.example.com',
        creativeBytes: creativeABytes,
        status: CampaignStatus.active,
        createdAt: DateTime(2026, 1, 1),
        recognitionSignature: sig,
      );
      repo.addCampaign(campaign);

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(visionService: visionService),
        ),
      );
      await tester.pumpAndSettle();

      // Initial active state has 1 ad
      expect(find.text('v0.4 · 1 AD'), findsOneWidget);

      // Now pause STUDIO NOIR in repository
      repo.pauseCampaign('campaign-studio-noir-001');

      // Tap CREATE AD and return to trigger sync
      await tester.tap(find.text('CREATE AD'));
      await tester.pumpAndSettle();

      // Tap BACK
      await tester.tap(find.text('BACK'));
      await tester.pumpAndSettle();

      // Now 0 ads are active
      expect(find.text('v0.4 · 0 ADS'), findsOneWidget);

      // Re-activate STUDIO NOIR
      repo.activateCampaign('campaign-studio-noir-001');

      // Tap CREATE AD and return
      await tester.tap(find.text('CREATE AD'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('BACK'));
      await tester.pumpAndSettle();

      // Back to 1 active ad
      expect(find.text('v0.4 · 1 AD'), findsOneWidget);
    });
  });
}
