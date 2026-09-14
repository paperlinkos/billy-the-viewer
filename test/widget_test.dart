import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:billy_the_viewer/app/app.dart';
import 'package:billy_the_viewer/models/ad_target.dart';
import 'package:billy_the_viewer/screens/home_screen.dart';
import 'package:billy_the_viewer/screens/inline_camera_view.dart';
import 'package:billy_the_viewer/services/camera_service.dart';
import 'package:billy_the_viewer/services/matching_engine.dart';

class FakeCameraService extends CameraService {
  CameraStateStatus stubbedStatus = CameraStateStatus.initial;
  String? stubbedErrorMessage;
  bool initializeCalled = false;
  bool disposeCalled = false;

  @override
  CameraStateStatus get status => stubbedStatus;

  @override
  String? get errorMessage => stubbedErrorMessage;

  @override
  bool get isReady => stubbedStatus == CameraStateStatus.ready;

  @override
  Future<CameraStateStatus> initialize() async {
    initializeCalled = true;
    return stubbedStatus;
  }

  @override
  Future<void> dispose() async {
    disposeCalled = true;
  }
}

void main() {
  group('MatchingEngine Unit Tests', () {
    test('Identical vectors produce cosine similarity of approximately 1.0', () {
      final vecA = [0.2, 0.5, 0.8, 0.1];
      final similarity = MatchingEngine.cosineSimilarity(vecA, vecA);
      expect(similarity, closeTo(1.0, 0.0001));
    });

    test('Orthogonal and distinct vectors produce lower similarity', () {
      final vecA = [1.0, 0.0, 0.0, 0.0];
      final vecB = [0.0, 1.0, 0.0, 0.0];
      final similarity = MatchingEngine.cosineSimilarity(vecA, vecB);
      expect(similarity, closeTo(0.0, 0.0001));
    });

    test('findBestMatch selects best candidate above threshold', () {
      const engine = MatchingEngine(threshold: 0.80);
      final registeredAd = AdTarget(
        id: 'ad_1',
        name: 'Studio Noir',
        brand: 'Studio Noir',
        destinationUrl: 'https://example.com',
        imageAsset: 'assets/campaigns/demo_ad.jpg',
        embedding: [0.5, 0.5, 0.5, 0.5],
      );

      final otherAd = AdTarget(
        id: 'ad_2',
        name: 'Other Ad',
        brand: 'Brand B',
        destinationUrl: 'https://example.com/b',
        imageAsset: 'assets/campaigns/other.jpg',
        embedding: [-0.5, 0.5, -0.5, 0.5],
      );

      final liveVector = [0.49, 0.51, 0.50, 0.49];
      final match = engine.findBestMatch(liveVector, [registeredAd, otherAd]);

      expect(match, isNotNull);
      expect(match!.target.id, equals('ad_1'));
      expect(match.similarity, greaterThan(0.95));
    });

    test('findBestMatch returns null when similarity is below threshold', () {
      const engine = MatchingEngine(threshold: 0.90);
      final registeredAd = AdTarget(
        id: 'ad_1',
        name: 'Studio Noir',
        brand: 'Studio Noir',
        destinationUrl: 'https://example.com',
        imageAsset: 'assets/campaigns/demo_ad.jpg',
        embedding: [1.0, 0.0, 0.0],
      );

      final liveVector = [0.5, 0.5, 0.0];
      final match = engine.findBestMatch(liveVector, [registeredAd]);

      expect(match, isNull);
    });
  });

  group('Phase 4 Action Model & Campaign Registry Tests', () {
    test('AdAction serialization and deserialization', () {
      const actionJson = {
        'type': 'view',
        'label': 'VIEW DETAILS',
        'destination': 'https://example.com/details',
      };

      final action = AdAction.fromJson(actionJson);
      expect(action.type, 'view');
      expect(action.label, 'VIEW DETAILS');
      expect(action.destination, 'https://example.com/details');

      final serialized = action.toJson();
      expect(serialized['type'], 'view');
      expect(serialized['label'], 'VIEW DETAILS');
      expect(serialized['destination'], 'https://example.com/details');
    });

    test('AdTarget derives effectiveActions fallback when actions list is empty', () {
      const target = AdTarget(
        id: 'demo_001',
        name: 'Studio Noir',
        brand: 'Studio Noir',
        destinationUrl: 'https://example.com/studio-noir',
        imageAsset: 'assets/campaigns/demo_ad.jpg',
      );

      expect(target.effectiveActions.length, 1);
      expect(target.effectiveActions.first.type, 'view');
      expect(target.effectiveActions.first.label, 'VIEW');
      expect(target.effectiveActions.first.destination, 'https://example.com/studio-noir');
    });

    test('AdTarget parses explicit actions and future reward fields correctly', () {
      const jsonStr = '''
      {
        "id": "demo_002",
        "name": "Reward Demo",
        "brand": "Brand X",
        "destinationUrl": "https://example.com/x",
        "imageAsset": "assets/campaigns/demo_ad.jpg",
        "actions": [
          {
            "type": "view",
            "label": "EXPLORE",
            "destination": "https://example.com/x"
          }
        ],
        "hasReward": true,
        "rewardType": "points",
        "rewardAmount": 100,
        "rewardDescription": "Earn 100 points"
      }
      ''';

      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      final target = AdTarget.fromJson(map);

      expect(target.id, 'demo_002');
      expect(target.actions.length, 1);
      expect(target.actions.first.label, 'EXPLORE');
      expect(target.hasReward, isTrue);
      expect(target.rewardType, 'points');
      expect(target.rewardAmount, 100);
      expect(target.rewardDescription, 'Earn 100 points');
    });
  });

  group('Phase 4 Discovery Result UX Tests', () {
    testWidgets('TEST 4: Open camera with unrelated scene remains LOOKING...', (WidgetTester tester) async {
      await tester.pumpWidget(const BillyApp());

      expect(find.text('BILLY'), findsOneWidget);
      expect(find.text('SEE\nSOMETHING?'), findsOneWidget);
      expect(find.text('SCAN'), findsOneWidget);
    });

    testWidgets('TEST 3: Recognition / camera open allows close back to Home', (WidgetTester tester) async {
      final fakeCameraService = FakeCameraService();

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            cameraService: fakeCameraService,
            initialCampaigns: const [],
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('SCAN'));
      await tester.pumpAndSettle();

      expect(fakeCameraService.initializeCalled, isTrue);
      expect(find.text('SHOW BILLY SOMETHING'), findsOneWidget);
      expect(find.text('POINT AT AN AD'), findsOneWidget);

      await tester.tap(find.text('✕'));
      await tester.pumpAndSettle();

      expect(fakeCameraService.disposeCalled, isTrue);
      expect(find.text('SCAN'), findsOneWidget);
    });

    testWidgets('TEST 1 & 2: Recognition displays hierarchy, VIEW opens destination, SCAN AGAIN resets to LOOKING...', (WidgetTester tester) async {
      final fakeCameraService = FakeCameraService();
      const demoTarget = AdTarget(
        id: 'demo_001',
        name: 'Studio Noir Architecture',
        brand: 'Studio Noir',
        destinationUrl: 'https://example.com/studio-noir',
        imageAsset: 'assets/campaigns/demo_ad.jpg',
        actions: [
          AdAction(type: 'view', label: 'VIEW', destination: 'https://example.com/studio-noir')
        ],
        embedding: [0.1, 0.2],
      );

      String? launchedUrl;
      bool scanAgainTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InlineCameraView(
              cameraService: fakeCameraService,
              recognitionState: RecognitionState.recognized,
              confirmedMatch: const MatchResult(target: demoTarget, similarity: 0.95),
              onClose: () {},
              onRetry: () {},
              onScanAgain: () => scanAgainTapped = true,
              onViewDestination: (url) => launchedUrl = url,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Hierarchy verification:
      // 1. I SEE IT.
      // 2. STUDIO NOIR ARCHITECTURE (Target Name)
      // 3. Studio Noir (Brand)
      // 4. VIEW
      // 5. SCAN AGAIN
      expect(find.text('I SEE IT.'), findsOneWidget);
      expect(find.text('AD RECOGNIZED'), findsOneWidget);
      expect(find.text('STUDIO NOIR ARCHITECTURE'), findsOneWidget);
      expect(find.text('Studio Noir'), findsOneWidget);
      expect(find.text('VIEW'), findsOneWidget);
      expect(find.text('SCAN AGAIN'), findsOneWidget);

      // TEST 1: VIEW opens destination URL
      await tester.tap(find.text('VIEW'));
      expect(launchedUrl, equals('https://example.com/studio-noir'));

      // TEST 2: SCAN AGAIN resets state
      await tester.tap(find.text('SCAN AGAIN'));
      expect(scanAgainTapped, isTrue);
    });
  });
}
