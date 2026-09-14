import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:billy_the_viewer/models/campaign.dart';
import 'package:billy_the_viewer/models/recognition_signature.dart';
import 'package:billy_the_viewer/screens/campaign_list_screen.dart';
import 'package:billy_the_viewer/screens/create_campaign_screen.dart';
import 'package:billy_the_viewer/screens/home_screen.dart';
import 'package:billy_the_viewer/services/campaign_repository.dart';
import 'package:billy_the_viewer/services/matching_engine.dart';
import 'package:billy_the_viewer/services/signature_service.dart';
import 'package:billy_the_viewer/services/vision_service.dart';

/// Helper to generate synthetic test image bytes with high visual contrast.
Uint8List _generateTestImageBytes({required int r, required int g, required int b}) {
  final image = img.Image(width: 128, height: 128);
  for (int y = 0; y < 128; y++) {
    for (int x = 0; x < 128; x++) {
      // Checkerboard/stripe pattern to ensure rich edge gradients
      if ((x ~/ 16 + y ~/ 16) % 2 == 0) {
        image.setPixelRgb(x, y, r, g, b);
      } else {
        image.setPixelRgb(x, y, 255 - r, 255 - g, 255 - b);
      }
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
    creativeABytes = _generateTestImageBytes(r: 200, g: 30, b: 30);
    creativeBBytes = _generateTestImageBytes(r: 30, g: 30, b: 200);
  });

  setUp(() {
    CampaignRepository().reset();
  });

  group('Phase 5: RecognitionSignature Architecture', () {
    test('Encapsulates perceptual features, neural embeddings, and metadata', () {
      final features = List.generate(192, (i) => i * 0.005);
      final signature = RecognitionSignature(
        version: '1.0',
        perceptualFeatures: features,
        metadata: {'dimension': 192, 'algorithm': 'test'},
      );

      expect(signature.isValid, isTrue);
      expect(signature.primaryFeatures.length, 192);
      expect(signature.version, '1.0');

      final json = signature.toJson();
      final reconstructed = RecognitionSignature.fromJson(json);

      expect(reconstructed.version, '1.0');
      expect(reconstructed.perceptualFeatures.length, 192);
      expect(reconstructed.metadata['algorithm'], 'test');
    });

    test('Prioritizes neural embedding over perceptualFeatures when present', () {
      final perceptual = List.generate(192, (i) => 0.1);
      final neural = List.generate(256, (i) => 0.9);

      final signature = RecognitionSignature(
        version: '2.0',
        perceptualFeatures: perceptual,
        embedding: neural,
      );

      expect(signature.primaryFeatures.length, 256);
      expect(signature.primaryFeatures.first, 0.9);
    });
  });

  group('Phase 5: Campaign Model & Lifecycle Status', () {
    test('Supports lifecycle states: draft, processing, active, paused, expired', () {
      expect(CampaignStatus.values.length, 5);
      expect(CampaignStatus.draft.displayName, 'DRAFT');
      expect(CampaignStatus.processing.displayName, 'PROCESSING');
      expect(CampaignStatus.active.displayName, 'ACTIVE');
      expect(CampaignStatus.paused.displayName, 'PAUSED');
      expect(CampaignStatus.expired.displayName, 'EXPIRED');
    });

    test('Converts Campaign directly into AdTarget for matching engine', () {
      final signature = RecognitionSignature(
        version: '1.0',
        perceptualFeatures: List.generate(192, (i) => 0.5),
      );

      final campaign = Campaign(
        id: 'camp-test-101',
        adName: 'STUDIO NOIR',
        brandName: 'Studio Noir',
        destinationUrl: 'https://studionoir.example.com',
        creativeAsset: 'assets/campaigns/demo_ad.jpg',
        status: CampaignStatus.active,
        createdAt: DateTime.now(),
        recognitionSignature: signature,
      );

      final adTarget = campaign.toAdTarget();

      expect(adTarget.id, 'camp-test-101');
      expect(adTarget.name, 'STUDIO NOIR');
      expect(adTarget.brand, 'Studio Noir');
      expect(adTarget.destinationUrl, 'https://studionoir.example.com');
      expect(adTarget.effectiveActions.length, 1);
      expect(adTarget.effectiveActions.first.label, 'VIEW');
      expect(adTarget.embedding.length, 192);
    });

    test('Campaign copyWith enables editing without losing metadata or signature', () {
      final campaign = Campaign(
        id: 'camp-1',
        adName: 'ORIGINAL',
        brandName: 'Brand A',
        destinationUrl: 'https://a.com',
        createdAt: DateTime.now(),
      );

      final edited = campaign.copyWith(
        adName: 'MODIFIED',
        brandName: 'Brand B',
        destinationUrl: 'https://b.com',
      );

      expect(edited.id, 'camp-1');
      expect(edited.adName, 'MODIFIED');
      expect(edited.brandName, 'Brand B');
      expect(edited.destinationUrl, 'https://b.com');
    });
  });

  group('Phase 5: SignatureService Implementation', () {
    test('Processes raw creative bytes and returns a valid RecognitionSignature', () async {
      final signature = await signatureService.generateSignature(creativeABytes);

      expect(signature.isValid, isTrue);
      expect(signature.version, '1.0');
      expect(signature.perceptualFeatures.length, 192);
      expect(signature.metadata['dimension'], 192);
      expect(signature.metadata['algorithm'], 'relative_spatial_gradient_192');
    });

    test('Rejects empty creative bytes with ArgumentError', () async {
      expect(
        () => signatureService.generateSignature(Uint8List(0)),
        throwsArgumentError,
      );
    });
  });

  group('Phase 5: CampaignRepository & In-Memory Registry', () {
    test('Stores, updates, and converts campaigns to active AdTargets', () async {
      final repo = CampaignRepository();
      repo.reset();

      final sigA = await signatureService.generateSignature(creativeABytes);
      final campaignA = Campaign(
        id: 'camp-A',
        adName: 'ALPHA BRAND',
        brandName: 'Alpha Inc',
        destinationUrl: 'https://alpha.example.com',
        creativeBytes: creativeABytes,
        status: CampaignStatus.active,
        createdAt: DateTime.now(),
        recognitionSignature: sigA,
      );

      repo.addCampaign(campaignA);
      expect(repo.campaigns.length, 1);
      expect(repo.activeAdTargets.length, 1);
      expect(repo.activeAdTargets.first.name, 'ALPHA BRAND');

      // Edit campaign
      final updated = campaignA.copyWith(adName: 'ALPHA REBRANDED');
      final success = repo.updateCampaign(updated);

      expect(success, isTrue);
      expect(repo.getCampaign('camp-A')!.adName, 'ALPHA REBRANDED');
      expect(repo.activeAdTargets.first.name, 'ALPHA REBRANDED');
    });
  });

  group('Phase 5: Multi-Campaign Recognition Invariance', () {
    test('Recognizes correct campaign when multiple campaigns are registered', () async {
      final sigA = await signatureService.generateSignature(creativeABytes);
      final sigB = await signatureService.generateSignature(creativeBBytes);

      final campaignA = Campaign(
        id: 'camp-A',
        adName: 'AD A',
        brandName: 'Brand A',
        destinationUrl: 'https://a.com',
        status: CampaignStatus.active,
        createdAt: DateTime.now(),
        recognitionSignature: sigA,
      ).toAdTarget();

      final campaignB = Campaign(
        id: 'camp-B',
        adName: 'AD B',
        brandName: 'Brand B',
        destinationUrl: 'https://b.com',
        status: CampaignStatus.active,
        createdAt: DateTime.now(),
        recognitionSignature: sigB,
      ).toAdTarget();

      const engine = MatchingEngine(threshold: 0.85);

      // Match with creative A embedding
      final matchForA = engine.findBestMatch(sigA.primaryFeatures, [campaignA, campaignB]);
      expect(matchForA, isNotNull);
      expect(matchForA!.target.id, 'camp-A');
      expect(matchForA.similarity, greaterThanOrEqualTo(0.99));

      // Match with creative B embedding
      final matchForB = engine.findBestMatch(sigB.primaryFeatures, [campaignA, campaignB]);
      expect(matchForB, isNotNull);
      expect(matchForB!.target.id, 'camp-B');
      expect(matchForB.similarity, greaterThanOrEqualTo(0.99));

      // Unrelated negative vector does not match either
      final unrelatedVector = List.generate(192, (i) => -0.5);
      final matchUnrelated = engine.findBestMatch(unrelatedVector, [campaignA, campaignB]);
      expect(matchUnrelated, isNull);
    });
  });

  group('Phase 5: UI Flow Tests', () {
    testWidgets('HomeScreen displays subtle secondary CREATE AD entry point', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: HomeScreen(initialCampaigns: []),
        ),
      );
      await tester.pumpAndSettle();

      // Verify SCAN is primary
      expect(find.text('SCAN'), findsOneWidget);

      // Verify CREATE AD exists as secondary entry point
      expect(find.text('CREATE AD'), findsOneWidget);
    });

    testWidgets('CreateCampaignScreen performs input, preview confirmation, and processing', (tester) async {
      final repo = CampaignRepository();
      repo.reset();

      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: CreateCampaignScreen(
            signatureService: signatureService,
            campaignRepository: repo,
            initialCreativeBytes: creativeABytes,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('CREATE AN AD'), findsOneWidget);
      expect(find.text('AD NAME'), findsOneWidget);
      expect(find.text('BRAND / ORGANISATION'), findsOneWidget);
      expect(find.text('DESTINATION'), findsOneWidget);

      // Fill in fields
      await tester.enterText(find.widgetWithText(TextFormField, 'ENTER AD NAME'), 'STUDIO NOIR');
      await tester.enterText(find.widgetWithText(TextFormField, 'ENTER BRAND OR CREATOR'), 'Studio Noir');
      await tester.enterText(find.widgetWithText(TextFormField, 'ENTER DESTINATION URL'), 'https://example.com');
      await tester.pump();

      // Verify image preview and confirmation buttons
      expect(find.text('USE THIS AD'), findsOneWidget);
      expect(find.text('CHANGE IMAGE'), findsOneWidget);

      // Confirm creative
      await tester.tap(find.text('USE THIS AD'));
      await tester.pumpAndSettle();

      expect(find.text('CREATIVE CONFIRMED'), findsOneWidget);

      // Submit
      await tester.tap(find.text('CREATE AD'));
      await tester.pump();

      // Verify processing state
      expect(find.text('PREPARING AD...'), findsOneWidget);

      // Advance timers for step 2
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      // Verify success state
      expect(find.text('AD READY'), findsOneWidget);
      expect(find.text('ACTIVE'), findsOneWidget);
      expect(find.text('STUDIO NOIR'), findsWidgets);
      expect(find.text('Studio Noir'), findsWidgets);
      expect(find.text('DONE'), findsOneWidget);
      expect(find.text('VIEW AD'), findsOneWidget);

      // Confirm added to repository
      expect(repo.campaigns.length, 1);
      expect(repo.campaigns.first.adName, 'STUDIO NOIR');
      expect(repo.campaigns.first.status, CampaignStatus.active);
      expect(repo.campaigns.first.recognitionSignature!.isValid, isTrue);

      // Tap DONE to navigate to YOUR ADS
      await tester.tap(find.text('DONE'));
      await tester.pumpAndSettle();

      expect(find.text('YOUR ADS'), findsOneWidget);
      expect(find.text('STUDIO NOIR'), findsOneWidget);
    });

    testWidgets('CampaignListScreen displays ads and allows editing', (tester) async {
      final repo = CampaignRepository();
      repo.reset();

      final sig = await signatureService.generateSignature(creativeABytes);
      final initialCampaign = Campaign(
        id: 'camp-edit-1',
        adName: 'INITIAL AD',
        brandName: 'Initial Brand',
        destinationUrl: 'https://initial.example.com',
        creativeBytes: creativeABytes,
        status: CampaignStatus.active,
        createdAt: DateTime.now(),
        recognitionSignature: sig,
      );
      repo.addCampaign(initialCampaign);

      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: CampaignListScreen(campaignRepository: repo),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('YOUR ADS'), findsOneWidget);
      expect(find.text('INITIAL AD'), findsOneWidget);
      expect(find.text('Initial Brand'), findsOneWidget);
      expect(find.text('ACTIVE'), findsOneWidget);

      // Tap to open CampaignDetailScreen
      await tester.tap(find.text('INITIAL AD'));
      await tester.pumpAndSettle();

      expect(find.text('EDIT AD'), findsOneWidget);

      // Tap EDIT AD to open the edit dialog
      await tester.tap(find.text('EDIT AD'));
      await tester.pumpAndSettle();

      expect(find.text('SAVE CHANGES'), findsOneWidget);

      // Update name
      await tester.enterText(find.widgetWithText(TextFormField, 'INITIAL AD'), 'REVISED AD');
      await tester.enterText(find.widgetWithText(TextFormField, 'Initial Brand'), 'Revised Brand');
      await tester.pump();

      await tester.tap(find.text('SAVE CHANGES'));
      await tester.pumpAndSettle();

      // Return back to YOUR ADS
      await tester.tap(find.text('YOUR ADS'));
      await tester.pumpAndSettle();

      // Check updated row in list
      expect(find.text('REVISED AD'), findsOneWidget);
      expect(find.text('Revised Brand'), findsOneWidget);
      expect(repo.getCampaign('camp-edit-1')!.adName, 'REVISED AD');
    });
  });
}
