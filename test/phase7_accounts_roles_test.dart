import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:billy_the_viewer/models/account.dart';
import 'package:billy_the_viewer/models/campaign.dart';
import 'package:billy_the_viewer/screens/account_screen.dart';
import 'package:billy_the_viewer/screens/campaign_list_screen.dart';
import 'package:billy_the_viewer/screens/home_screen.dart';
import 'package:billy_the_viewer/services/account_session.dart';
import 'package:billy_the_viewer/services/campaign_repository.dart';
import 'package:billy_the_viewer/services/matching_engine.dart';
import 'package:billy_the_viewer/services/signature_service.dart';
import 'package:billy_the_viewer/services/vision_service.dart';

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

/// Helper to generate test creative B: center circle bright, rest dark.
Uint8List _generateCreativeBBytes() {
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
    AccountSession().reset();
  });

  tearDown(() {
    CampaignRepository().reset();
    AccountSession().reset();
  });

  group('Phase 7: Account Model & Roles', () {
    test('Consumer account model creates valid consumer structure', () {
      final now = DateTime.now();
      final account = Account(
        id: 'viewer-123',
        email: 'viewer@example.com',
        displayName: 'Test Viewer',
        role: AccountRole.consumer,
        createdAt: now,
      );

      expect(account.id, 'viewer-123');
      expect(account.email, 'viewer@example.com');
      expect(account.displayName, 'Test Viewer');
      expect(account.role, AccountRole.consumer);
      expect(account.isConsumer, isTrue);
      expect(account.isAdvertiser, isFalse);
      expect(account.role.displayName, 'VIEWER');
    });

    test('Advertiser account model creates valid advertiser structure', () {
      final now = DateTime.now();
      final account = Account(
        id: 'advertiser-456',
        email: 'brand@example.com',
        displayName: 'Acme Brand',
        role: AccountRole.advertiser,
        createdAt: now,
      );

      expect(account.id, 'advertiser-456');
      expect(account.email, 'brand@example.com');
      expect(account.displayName, 'Acme Brand');
      expect(account.role, AccountRole.advertiser);
      expect(account.isAdvertiser, isTrue);
      expect(account.isConsumer, isFalse);
      expect(account.role.displayName, 'ADVERTISER');
    });

    test('Account serialization toJson and fromJson preserves data', () {
      final original = Account(
        id: 'acc-789',
        email: 'user@test.org',
        displayName: 'Jane Doe',
        role: AccountRole.advertiser,
        createdAt: DateTime(2026, 3, 15, 10, 30),
      );

      final json = original.toJson();
      final restored = Account.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.email, original.email);
      expect(restored.displayName, original.displayName);
      expect(restored.role, AccountRole.advertiser);
      expect(restored.isAdvertiser, isTrue);
    });

    test('Account copyWith modifies fields cleanly', () {
      final original = Account(
        id: 'user-1',
        email: 'first@test.org',
        displayName: 'First Name',
        role: AccountRole.consumer,
        createdAt: DateTime.now(),
      );

      final updated = original.copyWith(
        displayName: 'Updated Name',
        role: AccountRole.advertiser,
      );

      expect(updated.id, 'user-1');
      expect(updated.displayName, 'Updated Name');
      expect(updated.role, AccountRole.advertiser);
      expect(updated.isAdvertiser, isTrue);
    });
  });

  group('Phase 7: Account Session Management', () {
    test('Session is initially signed out', () {
      final session = AccountSession();
      expect(session.isSignedIn, isFalse);
      expect(session.currentAccount, isNull);
      expect(session.isConsumer, isFalse);
      expect(session.isAdvertiser, isFalse);
    });

    test('signInAsConsumer creates active consumer session', () {
      final session = AccountSession();
      final account = session.signInAsConsumer(displayName: 'Fast Viewer');

      expect(session.isSignedIn, isTrue);
      expect(session.isConsumer, isTrue);
      expect(session.isAdvertiser, isFalse);
      expect(session.currentAccount?.id, account.id);
      expect(session.currentAccount?.displayName, 'Fast Viewer');
      expect(session.currentAccount?.role, AccountRole.consumer);
    });

    test('signInAsAdvertiser creates active advertiser session', () {
      final session = AccountSession();
      final account = session.signInAsAdvertiser(displayName: 'Fast Advertiser');

      expect(session.isSignedIn, isTrue);
      expect(session.isAdvertiser, isTrue);
      expect(session.isConsumer, isFalse);
      expect(session.currentAccount?.id, account.id);
      expect(session.currentAccount?.displayName, 'Fast Advertiser');
      expect(session.currentAccount?.role, AccountRole.advertiser);
    });

    test('signOut clears current account session', () {
      final session = AccountSession();
      session.signInAsConsumer();
      expect(session.isSignedIn, isTrue);

      session.signOut();
      expect(session.isSignedIn, isFalse);
      expect(session.currentAccount, isNull);
    });

    test('Session restoration within current process across callers', () {
      final session1 = AccountSession();
      session1.signInAsAdvertiser(id: 'adv-shared-99', displayName: 'Shared Adv');

      final session2 = AccountSession();
      expect(session2.isSignedIn, isTrue);
      expect(session2.currentAccount?.id, 'adv-shared-99');
      expect(session2.currentAccount?.displayName, 'Shared Adv');
      expect(session2.isAdvertiser, isTrue);
    });
  });

  group('Phase 7: Ownership Isolation', () {
    test('Advertiser A and Advertiser B only see their owned campaigns', () async {
      final repo = CampaignRepository();
      final sigA = await signatureService.generateSignature(creativeABytes);
      final sigB = await signatureService.generateSignature(creativeBBytes);

      final campaignA = Campaign(
        id: 'camp-A',
        ownerAccountId: 'advertiser-A',
        adName: 'CAMPAIGN ALPHA',
        brandName: 'Alpha Corp',
        destinationUrl: 'https://alpha.example.com',
        creativeBytes: creativeABytes,
        status: CampaignStatus.active,
        createdAt: DateTime.now(),
        recognitionSignature: sigA,
      );

      final campaignB = Campaign(
        id: 'camp-B',
        ownerAccountId: 'advertiser-B',
        adName: 'CAMPAIGN BETA',
        brandName: 'Beta LLC',
        destinationUrl: 'https://beta.example.com',
        creativeBytes: creativeBBytes,
        status: CampaignStatus.active,
        createdAt: DateTime.now(),
        recognitionSignature: sigB,
      );

      repo.addCampaign(campaignA);
      repo.addCampaign(campaignB);

      // Verify Advertiser A isolation
      final advertiserACampaigns = repo.getCampaignsForOwner('advertiser-A');
      expect(advertiserACampaigns.length, 1);
      expect(advertiserACampaigns.first.id, 'camp-A');
      expect(advertiserACampaigns.first.adName, 'CAMPAIGN ALPHA');

      // Verify Advertiser B isolation
      final advertiserBCampaigns = repo.getCampaignsForOwner('advertiser-B');
      expect(advertiserBCampaigns.length, 1);
      expect(advertiserBCampaigns.first.id, 'camp-B');
      expect(advertiserBCampaigns.first.adName, 'CAMPAIGN BETA');
    });
  });

  group('Phase 7: Consumer Recognition Independence', () {
    test('Consumer recognition can match both Campaign A and Campaign B', () async {
      final repo = CampaignRepository();
      final sigA = await signatureService.generateSignature(creativeABytes);
      final sigB = await signatureService.generateSignature(creativeBBytes);

      final campaignA = Campaign(
        id: 'camp-A',
        ownerAccountId: 'advertiser-A',
        adName: 'CAMPAIGN ALPHA',
        brandName: 'Alpha Corp',
        destinationUrl: 'https://alpha.example.com',
        creativeBytes: creativeABytes,
        status: CampaignStatus.active,
        createdAt: DateTime.now(),
        recognitionSignature: sigA,
      );

      final campaignB = Campaign(
        id: 'camp-B',
        ownerAccountId: 'advertiser-B',
        adName: 'CAMPAIGN BETA',
        brandName: 'Beta LLC',
        destinationUrl: 'https://beta.example.com',
        creativeBytes: creativeBBytes,
        status: CampaignStatus.active,
        createdAt: DateTime.now(),
        recognitionSignature: sigB,
      );

      repo.addCampaign(campaignA);
      repo.addCampaign(campaignB);

      // Recognition searches all active campaigns regardless of owner
      final recognitionCandidates = repo.getActiveCampaignsForRecognition();
      expect(recognitionCandidates.map((c) => c.id), containsAll(['camp-A', 'camp-B']));

      final activeTargets = repo.getActiveAdTargets();
      expect(activeTargets.map((t) => t.id), containsAll(['camp-A', 'camp-B']));

      // Consumer matching engine tests
      const matchingEngine = MatchingEngine(threshold: 0.70);

      // Match frame from creative A
      final matchA = matchingEngine.findBestMatch(sigA.primaryFeatures, activeTargets);
      expect(matchA, isNotNull);
      expect(matchA!.target.id, 'camp-A');
      expect(matchA.target.name, 'CAMPAIGN ALPHA');
      expect(matchA.similarity, greaterThan(0.90));

      // Match frame from creative B
      final matchB = matchingEngine.findBestMatch(sigB.primaryFeatures, activeTargets);
      expect(matchB, isNotNull);
      expect(matchB!.target.id, 'camp-B');
      expect(matchB.target.name, 'CAMPAIGN BETA');
      expect(matchB.similarity, greaterThan(0.90));
    });
  });

  group('Phase 7: Pause & Delete Lifecycle with Ownership', () {
    test('Pausing Campaign A removes it from recognition while preserving ownership', () async {
      final repo = CampaignRepository();
      final sigA = await signatureService.generateSignature(creativeABytes);
      final sigB = await signatureService.generateSignature(creativeBBytes);

      repo.addCampaign(Campaign(
        id: 'camp-A',
        ownerAccountId: 'advertiser-A',
        adName: 'CAMPAIGN ALPHA',
        brandName: 'Alpha Corp',
        destinationUrl: 'https://alpha.example.com',
        creativeBytes: creativeABytes,
        status: CampaignStatus.active,
        createdAt: DateTime.now(),
        recognitionSignature: sigA,
      ));

      repo.addCampaign(Campaign(
        id: 'camp-B',
        ownerAccountId: 'advertiser-B',
        adName: 'CAMPAIGN BETA',
        brandName: 'Beta LLC',
        destinationUrl: 'https://beta.example.com',
        creativeBytes: creativeBBytes,
        status: CampaignStatus.active,
        createdAt: DateTime.now(),
        recognitionSignature: sigB,
      ));

      // Pause Campaign A
      final paused = repo.pauseCampaign('camp-A');
      expect(paused, isTrue);

      // Advertiser A still sees it in their owned campaigns list (with PAUSED status)
      final advertiserACampaigns = repo.getCampaignsForOwner('advertiser-A');
      expect(advertiserACampaigns.length, 1);
      expect(advertiserACampaigns.first.status, CampaignStatus.paused);

      // But recognition candidates NO LONGER contain Campaign A
      final recognitionCandidates = repo.getActiveCampaignsForRecognition();
      expect(recognitionCandidates.map((c) => c.id), isNot(contains('camp-A')));
      expect(recognitionCandidates.map((c) => c.id), contains('camp-B'));

      // Consumer matching engine can no longer match Campaign A
      const matchingEngine = MatchingEngine(threshold: 0.70);
      final matchA = matchingEngine.findBestMatch(
        sigA.primaryFeatures,
        repo.getActiveAdTargets(),
      );
      expect(matchA, isNull);
    });

    test('Deleting Campaign A removes it from advertiser list and recognition', () async {
      final repo = CampaignRepository();
      final sigA = await signatureService.generateSignature(creativeABytes);

      repo.addCampaign(Campaign(
        id: 'camp-A',
        ownerAccountId: 'advertiser-A',
        adName: 'CAMPAIGN ALPHA',
        brandName: 'Alpha Corp',
        destinationUrl: 'https://alpha.example.com',
        creativeBytes: creativeABytes,
        status: CampaignStatus.active,
        createdAt: DateTime.now(),
        recognitionSignature: sigA,
      ));

      expect(repo.getCampaignsForOwner('advertiser-A').length, 1);
      expect(repo.getActiveCampaignsForRecognition().length, 1);

      // Delete Campaign A
      final deleted = repo.deleteCampaign('camp-A');
      expect(deleted, isTrue);

      // Removed from advertiser's list
      expect(repo.getCampaignsForOwner('advertiser-A').isEmpty, isTrue);

      // Removed from recognition
      expect(repo.getActiveCampaignsForRecognition().isEmpty, isTrue);
      expect(repo.getActiveAdTargets().isEmpty, isTrue);
    });

    test('STUDIO NOIR continues to work with system-demo-owner', () {
      final repo = CampaignRepository();
      final studioNoir = Campaign(
        id: 'campaign-studio-noir-001',
        ownerAccountId: 'system-demo-owner',
        adName: 'STUDIO NOIR',
        brandName: 'Studio Noir',
        destinationUrl: 'https://studionoir.example.com',
        status: CampaignStatus.active,
        createdAt: DateTime(2026, 1, 1),
      );
      repo.addCampaign(studioNoir);

      // Available to system-demo-owner
      final demoCampaigns = repo.getCampaignsForOwner('system-demo-owner');
      expect(demoCampaigns.length, 1);
      expect(demoCampaigns.first.adName, 'STUDIO NOIR');

      // Hidden from regular Advertiser X
      final advXCampaigns = repo.getCampaignsForOwner('advertiser-X');
      expect(advXCampaigns.isEmpty, isTrue);

      // Active for consumer recognition
      final activeForRecognition = repo.getActiveCampaignsForRecognition();
      expect(activeForRecognition.map((c) => c.id), contains('campaign-studio-noir-001'));
    });
  });

  group('Phase 7: UI & Navigation Flow Tests', () {
    testWidgets('AccountScreen signed out renders WELCOME, CONTINUE AS VIEWER, and I RUN ADS',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: AccountScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('WELCOME TO BILLY'), findsOneWidget);
      expect(find.text('SELECT AN ACCOUNT ROLE TO CONTINUE.'), findsOneWidget);
      expect(find.text('CONTINUE AS VIEWER'), findsOneWidget);
      expect(find.text('I RUN ADS'), findsOneWidget);
    });

    testWidgets('AccountScreen: Continue as Viewer transitions to Viewer screen with Sign Out',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: AccountScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Tap CONTINUE AS VIEWER
      await tester.tap(find.text('CONTINUE AS VIEWER'));
      await tester.pumpAndSettle();

      expect(find.text('VIEWER'), findsAtLeastNWidgets(1));
      expect(find.text('SIGNED IN'), findsOneWidget);
      expect(find.text('SCAN NOW'), findsOneWidget);
      expect(find.text('SIGN OUT'), findsOneWidget);
      expect(AccountSession().isConsumer, isTrue);

      // Tap SIGN OUT
      await tester.tap(find.text('SIGN OUT'));
      await tester.pumpAndSettle();

      expect(find.text('WELCOME TO BILLY'), findsOneWidget);
      expect(AccountSession().isSignedIn, isFalse);
    });

    testWidgets('AccountScreen: I Run Ads transitions to Advertiser screen with controls',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: AccountScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Tap I RUN ADS
      await tester.tap(find.text('I RUN ADS'));
      await tester.pumpAndSettle();

      expect(find.text('ADVERTISER'), findsAtLeastNWidgets(1));
      expect(find.text('SIGNED IN'), findsOneWidget);
      expect(find.text('YOUR ADS'), findsOneWidget);
      expect(find.text('CREATE AD'), findsOneWidget);
      expect(find.text('SIGN OUT'), findsOneWidget);
      expect(AccountSession().isAdvertiser, isTrue);
    });

    testWidgets('CampaignListScreen with owner filter shows only owned campaigns',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final repo = CampaignRepository();
      repo.addCampaign(Campaign(
        id: 'camp-A',
        ownerAccountId: 'owner-A',
        adName: 'ONLY FOR OWNER A',
        brandName: 'Brand A',
        destinationUrl: 'https://a.com',
        status: CampaignStatus.active,
        createdAt: DateTime.now(),
      ));
      repo.addCampaign(Campaign(
        id: 'camp-B',
        ownerAccountId: 'owner-B',
        adName: 'ONLY FOR OWNER B',
        brandName: 'Brand B',
        destinationUrl: 'https://b.com',
        status: CampaignStatus.active,
        createdAt: DateTime.now(),
      ));

      await tester.pumpWidget(
        MaterialApp(
          home: CampaignListScreen(
            campaignRepository: repo,
            ownerAccountId: 'owner-A',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('ONLY FOR OWNER A'), findsOneWidget);
      expect(find.text('ONLY FOR OWNER B'), findsNothing);
    });

    testWidgets('HomeScreen displays ACCOUNT entry point alongside CREATE AD',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: HomeScreen(initialCampaigns: []),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('BILLY'), findsOneWidget);
      expect(find.text('SCAN'), findsOneWidget);
      expect(find.text('CREATE AD'), findsOneWidget);
      expect(find.text('ACCOUNT'), findsOneWidget);

      // Tap ACCOUNT navigates to AccountScreen
      await tester.tap(find.text('ACCOUNT'));
      await tester.pumpAndSettle();

      expect(find.text('WELCOME TO BILLY'), findsOneWidget);
    });
  });
}
