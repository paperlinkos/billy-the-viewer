import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:billy_the_viewer/models/account.dart';
import 'package:billy_the_viewer/models/campaign.dart';
import 'package:billy_the_viewer/models/recognition_signature.dart';
import 'package:billy_the_viewer/screens/campaign_detail_screen.dart';
import 'package:billy_the_viewer/screens/campaign_list_screen.dart';
import 'package:billy_the_viewer/screens/create_campaign_screen.dart';
import 'package:billy_the_viewer/services/account_session.dart';
import 'package:billy_the_viewer/services/campaign_repository.dart';
import 'package:billy_the_viewer/services/matching_engine.dart';
import 'package:billy_the_viewer/services/signature_service.dart';
import 'package:billy_the_viewer/services/vision_service.dart';

/// Helper to generate test creative A (128x128 with bright top-left quadrant).
Uint8List _generateCreativeA() {
  final image = img.Image(width: 128, height: 128);
  for (int y = 0; y < 128; y++) {
    for (int x = 0; x < 128; x++) {
      final val = (x < 64 && y < 64) ? 240 : 20;
      image.setPixelRgb(x, y, val, val, val);
    }
  }
  return Uint8List.fromList(img.encodeJpg(image));
}

/// Helper to generate test creative B (128x128 with bright center circle).
Uint8List _generateCreativeB() {
  final image = img.Image(width: 128, height: 128);
  for (int y = 0; y < 128; y++) {
    for (int x = 0; x < 128; x++) {
      final dx = x - 64;
      final dy = y - 64;
      final isCircle = (dx * dx + dy * dy) < (28 * 28);
      final val = isCircle ? 240 : 20;
      image.setPixelRgb(x, y, val, val, val);
    }
  }
  return Uint8List.fromList(img.encodeJpg(image));
}

/// Generator that simulates an unrecoverable failure during signature processing.
class FailingSignatureGenerator implements ISignatureGenerator {
  String get algorithm => 'failing-test-algo';
  String get version => '0.0';

  @override
  Future<RecognitionSignature> generate(Uint8List imageBytes) async {
    throw Exception('Simulated signature generation engine failure');
  }
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
    creativeABytes = _generateCreativeA();
    creativeBBytes = _generateCreativeB();
  });

  setUp(() {
    CampaignRepository().reset();
    AccountSession().reset();
  });

  // ===========================================================================
  // 1. CREATION
  // ===========================================================================
  group('Phase 8: 1. Creation Requirements', () {
    test('Valid creative creates active campaign with valid signature', () async {
      final repo = CampaignRepository();
      final sig = await signatureService.generateSignature(creativeABytes);

      final campaign = Campaign(
        id: 'create-valid-1',
        ownerAccountId: 'adv-123',
        adName: 'STUDIO NOIR',
        brandName: 'Studio Noir',
        destinationUrl: 'https://studionoir.example.com',
        creativeBytes: creativeABytes,
        status: CampaignStatus.active,
        createdAt: DateTime.now(),
        recognitionSignature: sig,
        signatureVersion: sig.version,
      );

      repo.addCampaign(campaign);
      expect(repo.getCampaign('create-valid-1'), isNotNull);
      expect(repo.getCampaign('create-valid-1')!.isCurrentlyActive, isTrue);
      expect(repo.getActiveCampaignsForRecognition(), contains(campaign));
    });

    test('Invalid destination cannot submit: URL validation rejects invalid URLs', () {
      expect(Campaign.isValidDestinationUrl(''), isFalse);
      expect(Campaign.isValidDestinationUrl('not-a-url'), isFalse);
      expect(Campaign.isValidDestinationUrl('ftp://invalidscheme.com'), isFalse);
      expect(Campaign.isValidDestinationUrl('http://'), isFalse);
      expect(Campaign.isValidDestinationUrl('https://'), isFalse);

      // Valid destinations
      expect(Campaign.isValidDestinationUrl('https://studionoir.com'), isTrue);
      expect(Campaign.isValidDestinationUrl('http://studionoir.com/lookbook'), isTrue);
      expect(Campaign.isValidDestinationUrl('https://brand.co/shop?id=123'), isTrue);
    });

    test('Schedule validation: end date must be after start date if supplied', () {
      final now = DateTime.now();
      final future = now.add(const Duration(days: 7));
      final past = now.subtract(const Duration(days: 7));

      final validCampaign = Campaign(
        id: 'valid-schedule',
        adName: 'VALID',
        brandName: 'Brand',
        destinationUrl: 'https://example.com',
        createdAt: now,
        startAt: now,
        endAt: future,
        status: CampaignStatus.active,
      );
      expect(validCampaign.isCurrentlyActive, isTrue);

      final expiredCampaign = Campaign(
        id: 'expired-schedule',
        adName: 'EXPIRED',
        brandName: 'Brand',
        destinationUrl: 'https://example.com',
        createdAt: past,
        startAt: past,
        endAt: now.subtract(const Duration(days: 1)),
        status: CampaignStatus.active,
      );
      expect(expiredCampaign.isCurrentlyActive, isFalse);
    });
  });

  // ===========================================================================
  // 2. PROCESSING
  // ===========================================================================
  group('Phase 8: 2. Processing & Signature Generation', () {
    test('Signature generation executes and populates diagnostic metadata', () async {
      final sig = await signatureService.generateSignature(creativeABytes);

      expect(sig.primaryFeatures, isNotEmpty);
      expect(sig.algorithm, equals('relative_spatial_gradient_192'));
      expect(sig.signatureVersion, equals('1.0'));
      expect(sig.dimensions, equals('128x128'));
      expect(sig.processingDurationMs, isNotNull);
      expect(sig.processingDurationMs, greaterThanOrEqualTo(0));
      expect(sig.processingTimestamp, isNotNull);
    });

    test('Successful signature generation activates campaign in repository', () async {
      final repo = CampaignRepository();
      final sig = await signatureService.generateSignature(creativeABytes);

      final campaign = Campaign(
        id: 'proc-success-1',
        adName: 'STUDIO NOIR',
        brandName: 'Studio Noir',
        destinationUrl: 'https://studionoir.example.com',
        creativeBytes: creativeABytes,
        status: CampaignStatus.active,
        createdAt: DateTime.now(),
        recognitionSignature: sig,
      );
      repo.addCampaign(campaign);

      final recognitionCandidates = repo.getActiveCampaignsForRecognition();
      expect(recognitionCandidates.map((c) => c.id), contains('proc-success-1'));
    });

    test('Failed signature generation does not create a falsely active campaign', () async {
      final repo = CampaignRepository();
      final failingService = SignatureService(generator: FailingSignatureGenerator());

      // Try updateCreative with failing service
      final initialCampaign = Campaign(
        id: 'fail-test-1',
        adName: 'FAIL TEST',
        brandName: 'Brand',
        destinationUrl: 'https://example.com',
        creativeBytes: creativeABytes,
        status: CampaignStatus.active,
        createdAt: DateTime.now(),
        recognitionSignature: const RecognitionSignature(perceptualFeatures: [0.5, 0.5]),
      );
      repo.addCampaign(initialCampaign);

      expect(
        () async => await repo.updateCreative(
          'fail-test-1',
          creativeBBytes,
          signatureService: failingService,
        ),
        throwsA(isA<Exception>()),
      );

      // Verify campaign is NOT active and NOT eligible for recognition
      final afterFailure = repo.getCampaign('fail-test-1');
      expect(afterFailure, isNotNull);
      expect(afterFailure!.status, isNot(CampaignStatus.active));
      expect(repo.getActiveCampaignsForRecognition(), isEmpty);
    });
  });

  // ===========================================================================
  // 3. OWNERSHIP
  // ===========================================================================
  group('Phase 8: 3. Ownership & Multi-Advertiser Isolation', () {
    test('Campaign belongs to current advertiser account', () {
      final session = AccountSession();
      final advertiser = Account(
        id: 'adv-noir-001',
        email: 'noir@studionoir.com',
        displayName: 'Studio Noir Advertiser',
        role: AccountRole.advertiser,
        createdAt: DateTime.now(),
      );
      session.signIn(advertiser);

      final campaign = Campaign(
        id: 'camp-noir-001',
        ownerAccountId: session.currentAccount!.id,
        adName: 'STUDIO NOIR',
        brandName: 'Studio Noir',
        destinationUrl: 'https://studionoir.com',
        createdAt: DateTime.now(),
      );

      expect(campaign.ownerAccountId, equals('adv-noir-001'));
    });

    test('Advertiser cannot see another advertiser campaigns', () {
      final repo = CampaignRepository();

      final campA = Campaign(
        id: 'c-a',
        ownerAccountId: 'owner-a',
        adName: 'CAMPAIGN A',
        brandName: 'Brand A',
        destinationUrl: 'https://a.example.com',
        createdAt: DateTime.now(),
      );
      final campB = Campaign(
        id: 'c-b',
        ownerAccountId: 'owner-b',
        adName: 'CAMPAIGN B',
        brandName: 'Brand B',
        destinationUrl: 'https://b.example.com',
        createdAt: DateTime.now(),
      );

      repo.addCampaign(campA);
      repo.addCampaign(campB);

      final ownerAAds = repo.getCampaignsForOwner('owner-a');
      expect(ownerAAds.map((c) => c.id), contains('c-a'));
      expect(ownerAAds.map((c) => c.id), isNot(contains('c-b')));

      final ownerBAds = repo.getCampaignsForOwner('owner-b');
      expect(ownerBAds.map((c) => c.id), contains('c-b'));
      expect(ownerBAds.map((c) => c.id), isNot(contains('c-a')));
    });
  });

  // ===========================================================================
  // 4. CREATIVE REPLACEMENT
  // ===========================================================================
  group('Phase 8: 4. Creative Replacement & Signature Regeneration', () {
    test('Replacing creative regenerates signature and discards old signature', () async {
      final repo = CampaignRepository();
      final engine = MatchingEngine();

      // 1. Initial campaign with Creative A
      final sigA = await signatureService.generateSignature(creativeABytes);
      final campaign = Campaign(
        id: 'replace-test-1',
        adName: 'REPLACEABLE AD',
        brandName: 'Brand',
        destinationUrl: 'https://example.com',
        creativeBytes: creativeABytes,
        status: CampaignStatus.active,
        createdAt: DateTime.now(),
        recognitionSignature: sigA,
      );
      repo.addCampaign(campaign);

      // Verify Creative A matches
      final matchBefore = engine.findBestMatch(sigA.primaryFeatures, repo.getActiveAdTargets());
      expect(matchBefore, isNotNull);
      expect(matchBefore!.target.id, equals('replace-test-1'));

      // 2. Update creative to Creative B
      final updated = await repo.updateCreative(
        'replace-test-1',
        creativeBBytes,
        signatureService: signatureService,
      );

      expect(updated.creativeBytes, equals(creativeBBytes));
      expect(updated.recognitionSignature, isNotNull);
      expect(updated.recognitionSignature!.primaryFeatures, isNot(equals(sigA.primaryFeatures)));

      // 3. Verify Campaign is NOT recognized with old creative A
      final matchOldAfter = engine.findBestMatch(sigA.primaryFeatures, repo.getActiveAdTargets());
      // Either null or very low confidence not matching old
      if (matchOldAfter != null) {
        expect(matchOldAfter.similarity, lessThan(0.70));
      }

      // 4. Verify Campaign is recognized with new creative B
      final sigB = await signatureService.generateSignature(creativeBBytes);
      final matchNewAfter = engine.findBestMatch(sigB.primaryFeatures, repo.getActiveAdTargets());
      expect(matchNewAfter, isNotNull);
      expect(matchNewAfter!.target.id, equals('replace-test-1'));
      expect(matchNewAfter.similarity, greaterThanOrEqualTo(0.85));
    });
  });

  // ===========================================================================
  // 5. DUPLICATION
  // ===========================================================================
  group('Phase 8: 5. Campaign Duplication', () {
    test('Duplicate receives new ID, copies metadata, belongs to advertiser, receives signature', () async {
      final repo = CampaignRepository();
      final sig = await signatureService.generateSignature(creativeABytes);

      final original = Campaign(
        id: 'original-001',
        ownerAccountId: 'adv-dupe-test',
        adName: 'ORIGINAL AD',
        brandName: 'Brand Original',
        destinationUrl: 'https://original.example.com',
        creativeBytes: creativeABytes,
        status: CampaignStatus.active,
        createdAt: DateTime(2026, 3, 1),
        recognitionSignature: sig,
      );
      repo.addCampaign(original);

      final duplicate = await repo.duplicateCampaign(
        'original-001',
        signatureService: signatureService,
      );

      // Duplicate receives new ID
      expect(duplicate.id, isNot(equals(original.id)));
      expect(duplicate.id, startsWith('camp-copy-'));

      // Original remains unchanged
      final originalAfter = repo.getCampaign('original-001');
      expect(originalAfter, isNotNull);
      expect(originalAfter!.adName, equals('ORIGINAL AD'));

      // Duplicate belongs to same advertiser
      expect(duplicate.ownerAccountId, equals('adv-dupe-test'));

      // Duplicate copies metadata
      expect(duplicate.brandName, equals(original.brandName));
      expect(duplicate.destinationUrl, equals(original.destinationUrl));
      expect(duplicate.creativeBytes, equals(original.creativeBytes));

      // Duplicate receives its own recognition signature
      expect(duplicate.recognitionSignature, isNotNull);
      expect(duplicate.recognitionSignature!.primaryFeatures, isNotEmpty);
      expect(duplicate.status, equals(CampaignStatus.active));
    });
  });

  // ===========================================================================
  // 6. LIFECYCLE
  // ===========================================================================
  group('Phase 8: 6. Lifecycle State Controls', () {
    test('Pause removes campaign from recognition; activate returns it', () async {
      final repo = CampaignRepository();
      final sig = await signatureService.generateSignature(creativeABytes);

      final campaign = Campaign(
        id: 'life-1',
        adName: 'LIFECYCLE AD',
        brandName: 'Brand',
        destinationUrl: 'https://example.com',
        creativeBytes: creativeABytes,
        status: CampaignStatus.active,
        createdAt: DateTime.now(),
        recognitionSignature: sig,
      );
      repo.addCampaign(campaign);

      expect(repo.getActiveCampaignsForRecognition(), contains(campaign));

      // Pause
      final paused = repo.pauseCampaign('life-1');
      expect(paused, isTrue);
      expect(repo.getActiveCampaignsForRecognition(), isEmpty);

      // Activate
      final activated = repo.activateCampaign('life-1');
      expect(activated, isTrue);
      expect(repo.getActiveCampaignsForRecognition().map((c) => c.id), contains('life-1'));
    });

    test('Expiration removes campaign from recognition', () async {
      final repo = CampaignRepository();
      final sig = await signatureService.generateSignature(creativeABytes);

      final now = DateTime.now();
      final activeUntilTomorrow = Campaign(
        id: 'expires-tomorrow',
        adName: 'TOMORROW',
        brandName: 'Brand',
        destinationUrl: 'https://example.com',
        creativeBytes: creativeABytes,
        status: CampaignStatus.active,
        createdAt: now,
        startAt: now,
        endAt: now.add(const Duration(days: 1)),
        recognitionSignature: sig,
      );
      repo.addCampaign(activeUntilTomorrow);
      expect(repo.getActiveCampaignsForRecognition().map((c) => c.id), contains('expires-tomorrow'));

      final expiredYesterday = Campaign(
        id: 'expired-yesterday',
        adName: 'YESTERDAY',
        brandName: 'Brand',
        destinationUrl: 'https://example.com',
        creativeBytes: creativeABytes,
        status: CampaignStatus.active,
        createdAt: now.subtract(const Duration(days: 2)),
        startAt: now.subtract(const Duration(days: 2)),
        endAt: now.subtract(const Duration(days: 1)),
        recognitionSignature: sig,
      );
      repo.addCampaign(expiredYesterday);
      expect(repo.getActiveCampaignsForRecognition().map((c) => c.id), isNot(contains('expired-yesterday')));
    });

    test('Delete removes campaign from recognition and advertiser view', () async {
      final repo = CampaignRepository();
      final sig = await signatureService.generateSignature(creativeABytes);

      final campaign = Campaign(
        id: 'del-user-ad',
        ownerAccountId: 'adv-test',
        adName: 'DELETE ME',
        brandName: 'Brand',
        destinationUrl: 'https://example.com',
        creativeBytes: creativeABytes,
        status: CampaignStatus.active,
        createdAt: DateTime.now(),
        recognitionSignature: sig,
      );
      repo.addCampaign(campaign);

      expect(repo.getCampaign('del-user-ad'), isNotNull);
      expect(repo.getActiveCampaignsForRecognition(), isNotEmpty);

      final deleted = repo.deleteCampaign('del-user-ad');
      expect(deleted, isTrue);
      expect(repo.getCampaign('del-user-ad'), isNull);
      expect(repo.getActiveCampaignsForRecognition(), isEmpty);
      expect(repo.getCampaignsForOwner('adv-test'), isEmpty);
    });
  });

  // ===========================================================================
  // 7. DEMO PROTECTION
  // ===========================================================================
  group('Phase 8: 7. STUDIO NOIR Demo Protection', () {
    test('STUDIO NOIR demo campaign is protected from accidental user deletion', () async {
      final repo = CampaignRepository();
      await repo.initialize(signatureService: signatureService);

      final demo = repo.getCampaign(CampaignRepository.systemDemoCampaignId);
      expect(demo, isNotNull);
      expect(demo!.adName, equals('STUDIO NOIR'));

      // Attempting to delete without isSystemAction: true fails
      final deleteResult = repo.deleteCampaign(CampaignRepository.systemDemoCampaignId);
      expect(deleteResult, isFalse);

      // Demo campaign remains intact
      expect(repo.getCampaign(CampaignRepository.systemDemoCampaignId), isNotNull);
      expect(repo.getActiveCampaignsForRecognition().map((c) => c.id), contains(CampaignRepository.systemDemoCampaignId));
    });
  });

  // ===========================================================================
  // 8. WIDGET / UI TESTS
  // ===========================================================================
  group('Phase 8: 8. Advertiser Pipeline UI Workflow Tests', () {
    testWidgets('CreateCampaignScreen completes 5-step pipeline', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = CampaignRepository();
      AccountSession().signIn(Account(
        id: 'adv-flow-1',
        email: 'adv@test.com',
        displayName: 'Test Advertiser',
        role: AccountRole.advertiser,
        createdAt: DateTime.now(),
      ));

      await tester.pumpWidget(
        MaterialApp(
          home: CreateCampaignScreen(
            campaignRepository: repo,
            signatureService: signatureService,
            initialCreativeBytes: creativeABytes,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Step 1: AD CREATIVE
      expect(find.text('STEP 01 / 05'), findsOneWidget);
      expect(find.text('AD CREATIVE'), findsWidgets);
      expect(find.text('USE THIS AD'), findsOneWidget);

      await tester.tap(find.text('USE THIS AD'));
      await tester.pumpAndSettle();

      // Step 2: CAMPAIGN INFORMATION
      expect(find.text('STEP 02 / 05'), findsOneWidget);
      expect(find.text('CAMPAIGN INFORMATION'), findsWidgets);

      // Enter campaign details
      await tester.enterText(find.byType(TextField).at(0), 'STUDIO NOIR');
      await tester.enterText(find.byType(TextField).at(1), 'STUDIO NOIR');
      await tester.enterText(find.byType(TextField).at(2), 'https://studionoir.example.com');
      await tester.pumpAndSettle();

      // Tap REVIEW AD to enter Step 3
      expect(find.text('REVIEW AD'), findsOneWidget);
      await tester.ensureVisible(find.text('REVIEW AD'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('REVIEW AD'));
      await tester.pumpAndSettle();

      // Step 3: REVIEW
      expect(find.text('STEP 03 / 05'), findsOneWidget);
      expect(find.text('REVIEW YOUR AD'), findsWidgets);
      expect(find.text('THIS IS THE ADVERTISEMENT BILLY WILL LEARN TO RECOGNISE.'), findsOneWidget);
      expect(find.text('STUDIO NOIR'), findsWidgets);
      expect(find.text('https://studionoir.example.com'), findsOneWidget);
      expect(find.text('CREATE AD'), findsOneWidget);
      expect(find.text('EDIT'), findsOneWidget);

      // Tap CREATE AD to trigger Step 4 Processing
      await tester.ensureVisible(find.text('CREATE AD'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CREATE AD'));
      await tester.pump(); // Start async processing

      // Step 4: PROCESSING screen displays
      expect(find.text('BILLY IS LEARNING THIS AD'), findsWidgets);

      // Wait for real signature generation to complete and advance to Step 5
      await tester.pumpAndSettle();

      // Step 5: AD ACTIVE screen
      expect(find.text('STEP 05 / 05'), findsOneWidget);
      expect(find.text('AD READY'), findsOneWidget);
      expect(find.text('ACTIVE'), findsWidgets);
      expect(find.text('DONE'), findsOneWidget);

      // Verify campaign was saved in repository and is active
      final created = repo.campaigns.firstWhere((c) => c.adName == 'STUDIO NOIR');
      expect(created.isCurrentlyActive, isTrue);
      expect(created.recognitionSignature, isNotNull);
      expect(created.recognitionSignature!.primaryFeatures, isNotEmpty);
      expect(created.ownerAccountId, equals('adv-flow-1'));
    });

    testWidgets('CampaignDetailScreen displays details, READY FOR RECOGNITION, and DUPLICATE AD', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = CampaignRepository();
      final sig = await signatureService.generateSignature(creativeABytes);
      final campaign = Campaign(
        id: 'detail-phase8-1',
        ownerAccountId: 'adv-detail-test',
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
            campaignId: 'detail-phase8-1',
            campaignRepository: repo,
            signatureService: signatureService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify display elements
      expect(find.text('STUDIO NOIR'), findsWidgets);
      expect(find.text('Studio Noir'), findsOneWidget);
      expect(find.text('ACTIVE'), findsOneWidget);
      expect(find.text('https://studionoir.example.com'), findsOneWidget);
      expect(find.text('READY FOR RECOGNITION'), findsOneWidget);
      expect(find.text('DUPLICATE AD'), findsOneWidget);

      // Tap DUPLICATE AD
      await tester.tap(find.text('DUPLICATE AD'));
      await tester.pumpAndSettle();

      // Verify duplicate was created in repository
      expect(repo.campaigns.length, equals(2));
      final duplicate = repo.campaigns.firstWhere((c) => c.id != 'detail-phase8-1');
      expect(duplicate.adName, equals('STUDIO NOIR (COPY)'));
      expect(duplicate.recognitionSignature, isNotNull);
    });

    testWidgets('CampaignListScreen displays advertiser dashboard metrics and empty state', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = CampaignRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: CampaignListScreen(
            campaignRepository: repo,
            ownerAccountId: 'empty-adv',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Top bar dashboard metrics
      expect(find.textContaining('ACTIVE'), findsWidgets);
      expect(find.textContaining('PAUSED'), findsOneWidget);
      expect(find.textContaining('EXPIRED'), findsOneWidget);
      expect(find.textContaining('PROCESSING'), findsOneWidget);

      // Empty state
      expect(find.text('YOUR ADS'), findsWidgets);
      expect(find.text('NO ADS YET.'), findsOneWidget);
      expect(find.text('CREATE YOUR FIRST AD'), findsOneWidget);
    });
  });
}
