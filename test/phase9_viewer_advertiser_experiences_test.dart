import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:billy_the_viewer/models/ad_target.dart';
import 'package:billy_the_viewer/models/campaign.dart';
import 'package:billy_the_viewer/models/recognition_signature.dart';
import 'package:billy_the_viewer/models/reward.dart';
import 'package:billy_the_viewer/screens/account_screen.dart';
import 'package:billy_the_viewer/screens/create_campaign_screen.dart';
import 'package:billy_the_viewer/screens/home_screen.dart';
import 'package:billy_the_viewer/screens/inline_camera_view.dart';
import 'package:billy_the_viewer/screens/rewards_screen.dart';
import 'package:billy_the_viewer/services/account_session.dart';
import 'package:billy_the_viewer/services/camera_service.dart';
import 'package:billy_the_viewer/services/campaign_repository.dart';
import 'package:billy_the_viewer/services/matching_engine.dart';
import 'package:billy_the_viewer/services/reward_service.dart';
import 'package:billy_the_viewer/services/signature_service.dart';
import 'package:billy_the_viewer/services/vision_service.dart';

class FakeCameraService extends CameraService {
  CameraStateStatus stubbedStatus = CameraStateStatus.ready;

  @override
  CameraStateStatus get status => stubbedStatus;

  @override
  bool get isReady => stubbedStatus == CameraStateStatus.ready;

  @override
  Future<CameraStateStatus> initialize() async => stubbedStatus;

  @override
  Future<void> dispose() async {}
}

/// Helper to generate test creative A: top-left quadrant bright, rest dark.
Uint8List _generateCreativeABytes() {
  final image = img.Image(width: 128, height: 128);
  for (int y = 0; y < 128; y++) {
    for (int x = 0; x < 128; x++) {
      final val = (x < 64 && y < 64) ? 240 : 20;
      image.setPixelRgb(x, y, val, val, val);
    }
  }
  return Uint8List.fromList(img.encodeJpg(image));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late VisionService visionService;
  late SignatureService signatureService;
  late Uint8List testCreativeBytes;
  late FakeCameraService fakeCameraService;

  setUpAll(() async {
    visionService = VisionService();
    await visionService.initialize();
    signatureService = SignatureService(
      generator: LightweightSignatureGenerator(visionService: visionService),
    );
    testCreativeBytes = _generateCreativeABytes();
    fakeCameraService = FakeCameraService();
  });

  tearDown(() {
    AccountSession().reset();
    RewardService().reset();
    CampaignRepository().reset();
  });

  group('Phase 9: 1. Viewer Experience Tests', () {
    testWidgets('Viewer on HomeScreen sees SCAN, REWARDS, and ACCOUNT, but NOT CREATE AD', (tester) async {
      final session = AccountSession();
      session.signInAsConsumer();

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            accountSession: session,
            initialCampaigns: const [],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Viewer must see SCAN, REWARDS, and ACCOUNT
      expect(find.text('SCAN'), findsOneWidget);
      expect(find.text('REWARDS'), findsOneWidget);
      expect(find.text('ACCOUNT'), findsOneWidget);

      // Viewer must NOT see advertiser controls
      expect(find.text('CREATE AD'), findsNothing);
      expect(find.text('YOUR ADS'), findsNothing);
    });

    testWidgets('Viewer in AccountScreen sees VIEWER, SIGNED IN, SCAN NOW, REWARDS, SIGN OUT, but no advertiser controls', (tester) async {
      final session = AccountSession();
      session.signInAsConsumer();

      await tester.pumpWidget(
        MaterialApp(
          home: AccountScreen(
            accountSession: session,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Viewer sees specific items
      expect(find.text('VIEWER'), findsWidgets);
      expect(find.text('SIGNED IN'), findsOneWidget);
      expect(find.text('SCAN NOW'), findsOneWidget);
      expect(find.text('REWARDS'), findsOneWidget);
      expect(find.text('SIGN OUT'), findsOneWidget);

      // Viewer does NOT see advertiser controls
      expect(find.text('YOUR ADS'), findsNothing);
      expect(find.text('CREATE AD'), findsNothing);
      expect(find.text('ACCOUNT SETTINGS'), findsNothing);
      expect(find.text('CAMPAIGN MANAGEMENT'), findsNothing);
      expect(find.text('ANALYTICS'), findsNothing);
      expect(find.text('BILLING'), findsNothing);
    });

    testWidgets('Tapping REWARDS in AccountScreen navigates to RewardsScreen', (tester) async {
      final session = AccountSession();
      session.signInAsConsumer();

      await tester.pumpWidget(
        MaterialApp(
          home: AccountScreen(
            accountSession: session,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('REWARDS'));
      await tester.pumpAndSettle();

      // Should be on RewardsScreen
      expect(find.text('REWARDS'), findsWidgets);
      expect(find.text('YOUR REWARDS'), findsOneWidget);
      expect(find.text('NO REWARDS YET'), findsOneWidget);
    });
  });

  group('Phase 9: 2. Advertiser Experience Tests', () {
    testWidgets('Advertiser on HomeScreen sees SCAN, CREATE AD, and ACCOUNT, but NOT REWARDS', (tester) async {
      final session = AccountSession();
      session.signInAsAdvertiser();

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            accountSession: session,
            initialCampaigns: const [],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('SCAN'), findsOneWidget);
      expect(find.text('CREATE AD'), findsOneWidget);
      expect(find.text('ACCOUNT'), findsOneWidget);

      // Advertiser must NOT see viewer reward controls on Home
      expect(find.text('REWARDS'), findsNothing);
    });

    testWidgets('Advertiser in AccountScreen sees ADVERTISER, SIGNED IN, YOUR ADS, CREATE AD, ACCOUNT SETTINGS, SIGN OUT', (tester) async {
      final session = AccountSession();
      session.signInAsAdvertiser();

      await tester.pumpWidget(
        MaterialApp(
          home: AccountScreen(
            accountSession: session,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('ADVERTISER'), findsWidgets);
      expect(find.text('SIGNED IN'), findsOneWidget);
      expect(find.text('YOUR ADS'), findsOneWidget);
      expect(find.text('CREATE AD'), findsOneWidget);
      expect(find.text('ACCOUNT SETTINGS'), findsOneWidget);
      expect(find.text('SIGN OUT'), findsOneWidget);

      // Advertiser does NOT see viewer rewards
      expect(find.text('REWARDS'), findsNothing);
    });

    testWidgets('Advertiser can tap ACCOUNT SETTINGS to see account dialog', (tester) async {
      final session = AccountSession();
      session.signInAsAdvertiser();

      await tester.pumpWidget(
        MaterialApp(
          home: AccountScreen(
            accountSession: session,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('ACCOUNT SETTINGS'));
      await tester.pumpAndSettle();

      expect(find.text('ACCOUNT: Billy Advertiser'), findsOneWidget);
      expect(find.text('EMAIL: advertiser@billy.local'), findsOneWidget);
      expect(find.text('ROLE: ADVERTISER'), findsOneWidget);

      await tester.tap(find.text('CLOSE'));
      await tester.pumpAndSettle();

      expect(find.text('ACCOUNT: Billy Advertiser'), findsNothing);
    });
  });

  group('Phase 9: 3. Role Protection Boundaries Tests', () {
    testWidgets('Consumer attempting to access CreateCampaignScreen is shown ACCESS RESTRICTED', (tester) async {
      final session = AccountSession();
      session.signInAsConsumer();

      await tester.pumpWidget(
        MaterialApp(
          home: CreateCampaignScreen(
            accountSession: session,
            signatureService: signatureService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('ACCESS RESTRICTED'), findsOneWidget);
      expect(find.text('ADVERTISER ACCOUNT REQUIRED'), findsOneWidget);
      expect(find.text('CONTINUE TO ACCOUNT'), findsOneWidget);
      expect(find.text('GO BACK'), findsOneWidget);

      // Form should not be accessible
      expect(find.text('STEP 01 / 05'), findsNothing);
    });

    testWidgets('Advertiser can access CreateCampaignScreen without restriction', (tester) async {
      final session = AccountSession();
      session.signInAsAdvertiser();

      await tester.pumpWidget(
        MaterialApp(
          home: CreateCampaignScreen(
            accountSession: session,
            signatureService: signatureService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('ACCESS RESTRICTED'), findsNothing);
      expect(find.text('CREATE AN AD'), findsOneWidget);
      expect(find.text('STEP 01 / 05'), findsOneWidget);
    });

    testWidgets('Guest can access CreateCampaignScreen for prototype testing', (tester) async {
      final session = AccountSession();
      session.reset(); // Guest / signed out

      await tester.pumpWidget(
        MaterialApp(
          home: CreateCampaignScreen(
            accountSession: session,
            signatureService: signatureService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('ACCESS RESTRICTED'), findsNothing);
      expect(find.text('CREATE AN AD'), findsOneWidget);
    });
  });

  group('Phase 9: 4. Discovery to Destination Flow Tests', () {
    testWidgets('Recognized campaign triggers onViewDestination with actual campaign destination URL without hardcoding', (tester) async {
      const customUrl = 'https://exclusive-brand.co/product-launch';
      String? openedUrl;

      const target = AdTarget(
        id: 'test-ad-1',
        name: 'PRODUCT LAUNCH',
        brand: 'EXCLUSIVE BRAND',
        destinationUrl: customUrl,
        imageAsset: 'assets/images/studio_noir_ad.jpg',
        embedding: [0.1, 0.2],
      );

      const matchResult = MatchResult(
        target: target,
        similarity: 0.96,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InlineCameraView(
              cameraService: fakeCameraService,
              recognitionState: RecognitionState.recognized,
              confirmedMatch: matchResult,
              liveSimilarity: 0.96,
              threshold: 0.70,
              onClose: () {},
              onRetry: () {},
              onScanAgain: () {},
              onViewDestination: (url) => openedUrl = url,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('PRODUCT LAUNCH'), findsOneWidget);
      expect(find.text('EXCLUSIVE BRAND'), findsOneWidget);
      expect(find.text('VIEW'), findsOneWidget);

      await tester.tap(find.text('VIEW'));
      await tester.pumpAndSettle();

      // Destination must match the campaign's exact URL, not a hardcoded one
      expect(openedUrl, equals(customUrl));
    });

    testWidgets('Another campaign destination URL is cleanly forwarded', (tester) async {
      const secondUrl = 'https://paris-fashion-week.com/rsvp';
      String? openedUrl;

      const target = AdTarget(
        id: 'test-ad-2',
        name: 'SPRING RUNWAY',
        brand: 'PFW NOIR',
        destinationUrl: secondUrl,
        imageAsset: 'assets/images/studio_noir_ad.jpg',
        embedding: [0.1, 0.2],
      );

      const matchResult = MatchResult(
        target: target,
        similarity: 0.94,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InlineCameraView(
              cameraService: fakeCameraService,
              recognitionState: RecognitionState.recognized,
              confirmedMatch: matchResult,
              liveSimilarity: 0.94,
              threshold: 0.70,
              onClose: () {},
              onRetry: () {},
              onScanAgain: () {},
              onViewDestination: (url) => openedUrl = url,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('VIEW'));
      await tester.pumpAndSettle();

      expect(openedUrl, equals(secondUrl));
    });
  });

  group('Phase 9: 5. Rewards Foundation & Service Tests', () {
    test('New viewer has empty reward list and zero counts in summary', () {
      final rewardService = RewardService();
      rewardService.reset();

      const viewerId = 'viewer-12345';
      final rewards = rewardService.getRewardsForViewer(viewerId);
      final summary = rewardService.getRewardSummary(viewerId);

      expect(rewards, isEmpty);
      expect(summary.totalCount, equals(0));
      expect(summary.earnedCount, equals(0));
      expect(summary.pendingCount, equals(0));
      expect(summary.claimedCount, equals(0));
      expect(summary.expiredCount, equals(0));
    });

    test('RewardService correctly registers and summarizes rewards without fake monetary values', () {
      final rewardService = RewardService();
      rewardService.reset();

      const viewerId = 'viewer-alpha';
      final reward1 = Reward(
        id: 'rew-1',
        viewerAccountId: viewerId,
        campaignId: 'camp-1',
        title: 'DISCOVERY VERIFIED',
        status: RewardStatus.earned,
        rewardType: RewardType.discovery,
        metadata: const {'description': 'Recognized Studio Noir campaign'},
        createdAt: DateTime.now(),
      );

      final reward2 = Reward(
        id: 'rew-2',
        viewerAccountId: viewerId,
        campaignId: 'camp-2',
        title: 'PROMO ACCESS',
        status: RewardStatus.pending,
        rewardType: RewardType.promo,
        createdAt: DateTime.now(),
      );

      rewardService.addReward(reward1);
      rewardService.addReward(reward2);

      final rewards = rewardService.getRewardsForViewer(viewerId);
      final summary = rewardService.getRewardSummary(viewerId);

      expect(rewards.length, equals(2));
      expect(summary.totalCount, equals(2));
      expect(summary.earnedCount, equals(1));
      expect(summary.pendingCount, equals(1));
      expect(summary.claimedCount, equals(0));

      // Check serialization round-trip
      final json = reward1.toJson();
      final fromJson = Reward.fromJson(json);
      expect(fromJson.id, equals(reward1.id));
      expect(fromJson.status, equals(RewardStatus.earned));
      expect(fromJson.rewardType, equals(RewardType.discovery));
    });

    testWidgets('RewardsScreen displays empty state correctly for new viewer', (tester) async {
      final session = AccountSession();
      session.signInAsConsumer();
      RewardService().reset();

      await tester.pumpWidget(
        MaterialApp(
          home: RewardsScreen(
            accountSession: session,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('REWARDS'), findsWidgets);
      expect(find.text('YOUR REWARDS'), findsOneWidget);
      expect(find.text('NO REWARDS YET'), findsOneWidget);
      expect(find.text('KEEP DISCOVERING'), findsOneWidget);
      expect(find.text('SCAN NOW'), findsOneWidget);

      // Verify no fake balances or currency symbols
      expect(find.textContaining(RegExp(r'[\$€£0-9]+\.[0-9]{2}')), findsNothing);
    });

    testWidgets('RewardsScreen displays reward cards when viewer has rewards', (tester) async {
      final session = AccountSession();
      session.signInAsConsumer();
      final viewerId = session.currentAccount!.id;

      final rewardService = RewardService();
      rewardService.reset();
      rewardService.addReward(
        Reward(
          id: 'rew-abc',
          viewerAccountId: viewerId,
          campaignId: 'camp-xyz',
          title: 'STUDIO NOIR ACCESS PASS',
          status: RewardStatus.earned,
          rewardType: RewardType.discovery,
          metadata: const {'description': 'Special viewer discovery unlocked.'},
          createdAt: DateTime.now(),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RewardsScreen(
            accountSession: session,
            rewardService: rewardService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('YOUR REWARDS'), findsOneWidget);
      expect(find.text('1 RECORD'), findsOneWidget);
      expect(find.text('STUDIO NOIR ACCESS PASS'), findsOneWidget);
      expect(find.text('EARNED'), findsOneWidget);
    });
  });

  group('Phase 9: 6. Guest Behaviour Tests', () {
    testWidgets('Guest on HomeScreen sees SCAN, REWARDS, CREATE AD, ACCOUNT and can scan', (tester) async {
      final session = AccountSession();
      session.reset(); // Guest

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            accountSession: session,
            initialCampaigns: const [],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('SCAN'), findsOneWidget);
      expect(find.text('REWARDS'), findsOneWidget);
      expect(find.text('CREATE AD'), findsOneWidget);
      expect(find.text('ACCOUNT'), findsOneWidget);
    });

    testWidgets('Guest attempting to access Rewards receives sign-in requirement', (tester) async {
      final session = AccountSession();
      session.reset(); // Guest

      await tester.pumpWidget(
        MaterialApp(
          home: RewardsScreen(
            accountSession: session,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('SIGN IN TO SEE YOUR REWARDS'), findsOneWidget);
      expect(find.text('CONTINUE AS VIEWER'), findsOneWidget);
      expect(find.text('SIGN IN'), findsOneWidget);

      // Tapping CONTINUE AS VIEWER signs in as consumer
      await tester.tap(find.text('CONTINUE AS VIEWER'));
      await tester.pumpAndSettle();

      expect(session.isSignedIn, isTrue);
      expect(session.isConsumer, isTrue);
      expect(find.text('YOUR REWARDS'), findsOneWidget);
      expect(find.text('NO REWARDS YET'), findsOneWidget);
    });
  });

  group('Phase 9: 7. Regression & Pipeline Lifecycle Tests', () {
    testWidgets('Existing campaign creation still works for advertiser', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = CampaignRepository();
      repo.reset();

      final session = AccountSession();
      session.signInAsAdvertiser();

      await tester.pumpWidget(
        MaterialApp(
          home: CreateCampaignScreen(
            accountSession: session,
            signatureService: signatureService,
            campaignRepository: repo,
            initialCreativeBytes: testCreativeBytes,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Step 1: Confirm creative
      expect(find.text('STEP 01 / 05'), findsOneWidget);
      expect(find.text('USE THIS AD'), findsOneWidget);
      await tester.tap(find.text('USE THIS AD'));
      await tester.pumpAndSettle();

      // Step 2: Enter info
      expect(find.text('STEP 02 / 05'), findsOneWidget);
      await tester.enterText(find.byType(TextField).at(0), 'PHASE 9 TEST AD');
      await tester.enterText(find.byType(TextField).at(1), 'TEST BRAND');
      await tester.enterText(find.byType(TextField).at(2), 'https://testbrand.com');
      await tester.pumpAndSettle();

      // Step 3: Review
      await tester.ensureVisible(find.text('REVIEW AD'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('REVIEW AD'));
      await tester.pumpAndSettle();

      // Step 4 & 5: Activate
      expect(find.text('STEP 03 / 05'), findsOneWidget);
      await tester.ensureVisible(find.text('CREATE AD'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CREATE AD'));
      await tester.pumpAndSettle();

      expect(find.text('STEP 05 / 05'), findsOneWidget);
      expect(find.text('AD READY'), findsOneWidget);
      expect(repo.campaigns.length, equals(1));
      expect(repo.campaigns.first.adName, equals('PHASE 9 TEST AD'));
      expect(repo.campaigns.first.ownerAccountId, equals(session.currentAccount!.id));
    });

    testWidgets('Existing campaign lifecycle (pause, activate, delete) continues to work', (tester) async {
      final repo = CampaignRepository();
      repo.reset();

      final camp = Campaign(
        id: 'lifecycle-p9-1',
        ownerAccountId: 'owner-p9',
        adName: 'LIFECYCLE AD',
        brandName: 'LIFECYCLE BRAND',
        destinationUrl: 'https://example.com',
        recognitionSignature: const RecognitionSignature(
          perceptualFeatures: [1.0, 2.0, 3.0],
        ),
        status: CampaignStatus.active,
        createdAt: DateTime.now(),
      );
      repo.addCampaign(camp);

      expect(repo.getActiveAdTargets().length, equals(1));

      // Pause
      repo.pauseCampaign(camp.id);
      expect(repo.getActiveAdTargets().length, equals(0));

      // Resume
      repo.activateCampaign(camp.id);
      expect(repo.getActiveAdTargets().length, equals(1));

      // Delete
      repo.deleteCampaign(camp.id);
      expect(repo.campaigns.length, equals(0));
    });

    test('STUDIO NOIR demo campaign still recognizes registered ad and distinguishes negative scene', () async {
      final repository = CampaignRepository();
      repository.reset();
      await repository.initialize();

      final activeTargets = repository.getActiveAdTargets();
      expect(activeTargets.length, equals(1));
      expect(activeTargets.first.name, equals('STUDIO NOIR'));

      const engine = MatchingEngine(threshold: 0.70);

      // Studio Noir target against itself
      final matchResult = engine.findBestMatch(activeTargets.first.embedding, activeTargets);
      expect(matchResult, isNotNull);
      expect(matchResult!.target.name, equals('STUDIO NOIR'));
      expect(matchResult.similarity, greaterThanOrEqualTo(0.99));

      // Studio Noir target against unrelated scene (zeros)
      final negativeEmbedding = List.filled(activeTargets.first.embedding.length, 0.0);
      final negativeResult = engine.findBestMatch(negativeEmbedding, activeTargets);
      expect(negativeResult, isNull);
    });
  });

  group('Phase 9: 8. Rolling Confidence Window Movement Resilience Tests', () {
    test('Rolling window of 6 frames accumulates hits across non-consecutive frames (movement resilience)', () {
      const target = AdTarget(
        id: 'target-movement-1',
        name: 'MOVING TARGET',
        brand: 'MOVING BRAND',
        destinationUrl: 'https://example.com/moving',
        imageAsset: 'assets/images/studio_noir_ad.jpg',
      );

      final matchA = const MatchResult(target: target, similarity: 0.74);
      final matchB = const MatchResult(target: target, similarity: 0.72);

      final rollingWindow = <MatchResult?>[];
      const windowSize = 6;
      const requiredHits = 2;

      void addFrame(MatchResult? m) {
        rollingWindow.add(m);
        if (rollingWindow.length > windowSize) {
          rollingWindow.removeAt(0);
        }
      }

      bool isConfirmed() {
        for (final m in rollingWindow.whereType<MatchResult>()) {
          final hits = rollingWindow.where((item) => item != null && item.target.id == m.target.id).toList();
          if (hits.length >= requiredHits) return true;
        }
        return false;
      }

      // Frame 1: First hit
      addFrame(matchA);
      expect(isConfirmed(), isFalse, reason: 'Single frame should not trigger recognition');

      // Frame 2: Motion blur
      addFrame(null);
      expect(isConfirmed(), isFalse);

      // Frame 3: Motion blur
      addFrame(null);
      expect(isConfirmed(), isFalse);

      // Frame 4: Second hit (non-consecutive)
      addFrame(matchB);
      expect(isConfirmed(), isTrue, reason: 'Non-consecutive hits within window should confirm');
    });

    test('Single random high-similarity frame cannot trigger recognition and rolls out', () {
      const target = AdTarget(
        id: 'target-noise-1',
        name: 'NOISE TARGET',
        brand: 'NOISE BRAND',
        destinationUrl: 'https://example.com/noise',
        imageAsset: 'assets/images/studio_noir_ad.jpg',
      );

      final spikeMatch = const MatchResult(target: target, similarity: 0.85);

      final rollingWindow = <MatchResult?>[];
      const windowSize = 6;
      const requiredHits = 2;

      void addFrame(MatchResult? m) {
        rollingWindow.add(m);
        if (rollingWindow.length > windowSize) {
          rollingWindow.removeAt(0);
        }
      }

      bool isConfirmed() {
        for (final m in rollingWindow.whereType<MatchResult>()) {
          final hits = rollingWindow.where((item) => item != null && item.target.id == m.target.id).toList();
          if (hits.length >= requiredHits) return true;
        }
        return false;
      }

      // Frame 1: Random high similarity spike
      addFrame(spikeMatch);
      expect(isConfirmed(), isFalse, reason: 'Single high-similarity frame cannot trigger recognition');

      // Subsequent 6 frames of unrelated scenes
      for (int i = 0; i < 6; i++) {
        addFrame(null);
        expect(isConfirmed(), isFalse);
      }

      // After 6 misses, the single spike has completely rolled out
      expect(rollingWindow.whereType<MatchResult>(), isEmpty);
      expect(isConfirmed(), isFalse);
    });
  });
}
