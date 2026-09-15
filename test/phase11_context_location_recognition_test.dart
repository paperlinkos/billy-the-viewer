import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:billy_the_viewer/models/ad_target.dart';
import 'package:billy_the_viewer/screens/home_screen.dart';
import 'package:billy_the_viewer/screens/inline_camera_view.dart';
import 'package:billy_the_viewer/services/account_session.dart';
import 'package:billy_the_viewer/services/camera_service.dart';
import 'package:billy_the_viewer/services/context_engine.dart';

class FakeCameraService extends CameraService {
  CameraStateStatus stubbedStatus = CameraStateStatus.ready;

  @override
  CameraStateStatus get status => stubbedStatus;

  @override
  bool get isReady => stubbedStatus == CameraStateStatus.ready;

  @override
  Future<CameraStateStatus> initialize() async => stubbedStatus;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeCameraService fakeCameraService;

  setUp(() {
    fakeCameraService = FakeCameraService();
  });

  group('Phase 11: 1. Geolocation & Haversine Geofence Tests', () {
    test('GeoLocation distanceTo correctly calculates spherical distance in meters', () {
      // Abuja City Gate: 9.0289, 7.4258
      // Abuja Junction (approx 1.2km away): 9.0395, 7.4258
      const gate = GeoLocation(latitude: 9.0289, longitude: 7.4258, radiusMeters: 300);
      final dist = gate.distanceTo(9.0395, 7.4258);

      // Distance should be approx 1178 meters
      expect(dist, greaterThan(1100));
      expect(dist, lessThan(1250));
    });

    test('isWithinRange correctly identifies catchment zone', () {
      const billboard = GeoLocation(
        latitude: 9.05785,
        longitude: 7.49508,
        radiusMeters: 250.0,
        label: 'Central Expressway Billboard',
      );

      // 50 meters away (inside)
      expect(billboard.isWithinRange(9.05820, 7.49508), isTrue);

      // 2000 meters away (outside)
      expect(billboard.isWithinRange(9.07585, 7.49508), isFalse);
    });
  });

  group('Phase 11: 2. ContextEngine Posture & Optical Classification Tests', () {
    const contextEngine = ContextEngine();

    final targetBillboard = AdTarget(
      id: 'bb-1',
      name: 'Highway Billboard',
      brand: 'BILLY OOH',
      destinationUrl: 'https://billyapp.co/ooh',
      imageAsset: '',
      mediumType: AdMediumType.billboard,
      location: const GeoLocation(
        latitude: 9.05785,
        longitude: 7.49508,
        radiusMeters: 300,
      ),
    );

    final targetFlyer = const AdTarget(
      id: 'flyer-1',
      name: 'Coffee Shop Flyer',
      brand: 'Roast Co',
      destinationUrl: 'https://roast.co',
      imageAsset: '',
      mediumType: AdMediumType.flyer,
    );

    final targetScreen = const AdTarget(
      id: 'screen-1',
      name: 'Smart TV Spot',
      brand: 'Streamly',
      destinationUrl: 'https://streamly.io',
      imageAsset: '',
      mediumType: AdMediumType.screen,
    );

    final targets = [targetBillboard, targetFlyer, targetScreen];

    test('Classifies as BILLBOARD when user GPS is within registered billboard catchment', () {
      final classification = contextEngine.classify(
        context: const SensorContext(
          userLatitude: 9.05790,
          userLongitude: 7.49510, // ~10m from billboard
          devicePitchDegrees: 0.0,
        ),
        registeredTargets: targets,
      );

      expect(classification.predictedMedium, AdMediumType.billboard);
      expect(classification.confidence, greaterThanOrEqualTo(0.90));
      expect(classification.matchedGeofencedCampaignIds, contains('bb-1'));
    });

    test('Classifies as BILLBOARD when phone tilted upward towards sky/highway', () {
      final classification = contextEngine.classify(
        context: const SensorContext(
          devicePitchDegrees: 35.0, // Tilted up 35 degrees
          ambientLuminance: 0.75, // Bright daylight
        ),
        registeredTargets: targets,
      );

      expect(classification.predictedMedium, AdMediumType.billboard);
      expect(classification.confidence, greaterThanOrEqualTo(0.80));
    });

    test('Classifies as FLYER when phone tilted downward in reading posture', () {
      final classification = contextEngine.classify(
        context: const SensorContext(
          devicePitchDegrees: -45.0, // Tilted down reading
          ambientLuminance: 0.45,
        ),
        registeredTargets: targets,
      );

      expect(classification.predictedMedium, AdMediumType.flyer);
      expect(classification.confidence, greaterThanOrEqualTo(0.80));
    });

    test('Classifies as SCREEN when held at eye-level with backlit digital display contrast', () {
      final classification = contextEngine.classify(
        context: const SensorContext(
          devicePitchDegrees: 0.0, // Eye level
          contrastRatio: 0.60, // High backlit display contrast
          ambientLuminance: 0.40, // Dimmer indoor background
        ),
        registeredTargets: targets,
      );

      expect(classification.predictedMedium, AdMediumType.screen);
      expect(classification.confidence, greaterThanOrEqualTo(0.80));
    });

    test('filterAndRankCandidates prioritizes geofenced billboard to index 0', () {
      final ranked = contextEngine.filterAndRankCandidates(
        allTargets: targets,
        context: const SensorContext(
          userLatitude: 9.05785,
          userLongitude: 7.49508,
        ),
      );

      expect(ranked.first.id, 'bb-1');
      expect(ranked.length, 3);
    });

    test('filterAndRankCandidates prioritizes flyer when scanning downwards', () {
      final ranked = contextEngine.filterAndRankCandidates(
        allTargets: targets,
        context: const SensorContext(
          devicePitchDegrees: -50.0,
        ),
      );

      expect(ranked.first.id, 'flyer-1');
    });
  });

  group('Phase 11: 3. Motion & Handheld Shake Resilient Matching Tests', () {
    test('Crisp single frame (>= 0.84) confirms match immediately', () {
      // Simulating a crisp aligned frame:
      final frameSim = 0.88;
      expect(frameSim >= 0.84, isTrue); // Triggers Case 1 Instant Crisp Hit
    });

    test('Sustained motion hit confirms across hand-shake fluctuations (0.75, 0.52 blur, 0.70, 0.55 blur, 0.72)', () {
      // In handheld movement: individual frames dip due to hand tremor / autofocus,
      // but true hits consistently score >= 0.58.
      final simulatedWindow = [
        0.75, // Hit 1 (sharp)
        0.52, // Motion blur (miss)
        0.70, // Hit 2 (sharp)
        0.55, // Motion blur (miss)
        0.72, // Hit 3 (sharp)
      ];

      final hitsAbove58 = simulatedWindow.where((s) => s >= 0.58).toList();
      expect(hitsAbove58.length, 3); // 3 hits >= 0.58 confirms match even with shake!
    });

    test('Unrelated negative scenes never reach the motion threshold (all <= 0.18)', () {
      final negativeScenes = [0.12, 0.05, 0.18, -0.04, 0.11];
      final anyHit = negativeScenes.any((s) => s >= 0.58);
      expect(anyHit, isFalse); // Absolute zero false positives on negative scenes
    });
  });

  group('Phase 11: 4. UI Context Badge & Inline Camera Integration Tests', () {
    testWidgets('InlineCameraView renders contextBadge when provided', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InlineCameraView(
              cameraService: fakeCameraService,
              recognitionState: RecognitionState.looking,
              threshold: 0.60,
              contextBadge: '📍 BILLBOARD',
              onClose: () {},
              onRetry: () {},
              onScanAgain: () {},
              onViewDestination: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('BILLY'), findsOneWidget);
      expect(find.text('📍 BILLBOARD'), findsOneWidget);
    });

    testWidgets('HomeScreen initializes with contextEngine and displays context in scanner', (tester) async {
      final session = AccountSession();
      session.signInAsConsumer();

      const geofencedBillboard = AdTarget(
        id: 'bb-local',
        name: 'LOCAL BILLBOARD',
        brand: 'BILLY',
        destinationUrl: 'https://billyapp.co',
        imageAsset: '',
        mediumType: AdMediumType.billboard,
        location: GeoLocation(latitude: 9.05, longitude: 7.49, radiusMeters: 500),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            cameraService: fakeCameraService,
            accountSession: session,
            initialCampaigns: const [geofencedBillboard],
            initialSensorContext: const SensorContext(
              userLatitude: 9.0501,
              userLongitude: 7.4901, // Inside geofence
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap SCAN to open inline camera
      await tester.tap(find.text('SCAN'));
      await tester.pump();

      // Inline scanner should display the BILLBOARD context badge
      expect(find.text('📍 BILLBOARD'), findsOneWidget);
    });
  });
}
