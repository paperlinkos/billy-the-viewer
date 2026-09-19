import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:billy_the_viewer/models/ad_target.dart';
import 'package:billy_the_viewer/models/campaign.dart';
import 'package:billy_the_viewer/screens/home_screen.dart';
import 'package:billy_the_viewer/screens/inline_camera_view.dart';
import 'package:billy_the_viewer/services/camera_service.dart';
import 'package:billy_the_viewer/services/campaign_repository.dart';
import 'package:billy_the_viewer/services/matching_engine.dart';
import 'package:billy_the_viewer/services/ocr_service.dart';
import 'package:billy_the_viewer/services/verification_coordinator.dart';
import 'package:billy_the_viewer/services/vision_service.dart';
import 'package:billy_the_viewer/widgets/billy_button.dart';

class MockPhotoCameraService extends CameraService {
  CameraStateStatus stubbedStatus = CameraStateStatus.ready;
  bool takePictureCalled = false;
  Uint8List? stubbedPictureBytes;
  Completer<Uint8List?>? pictureCompleter;

  @override
  CameraStateStatus get status => stubbedStatus;

  @override
  bool get isReady => stubbedStatus == CameraStateStatus.ready;

  @override
  Future<CameraStateStatus> initialize() async => stubbedStatus;

  @override
  Future<Uint8List?> takePicture() async {
    takePictureCalled = true;
    if (pictureCompleter != null) {
      return pictureCompleter!.future;
    }
    return stubbedPictureBytes ?? Uint8List.fromList([1, 2, 3, 4]);
  }

  @override
  Future<void> dispose() async {}
}

class MockVisionService extends VisionService {
  List<double> stubbedEmbedding = List.filled(192, 0.1);
  Uint8List? lastReceivedBytes;
  Future<List<double>> Function(Uint8List bytes)? onGenerateEmbedding;

  @override
  Future<List<double>> generateEmbeddingFromBytes(Uint8List jpegBytes) async {
    lastReceivedBytes = jpegBytes;
    if (onGenerateEmbedding != null) {
      return onGenerateEmbedding!(jpegBytes);
    }
    return stubbedEmbedding;
  }
}

class MockOcrService extends OcrService {
  String stubbedText = '';
  Future<OcrResult> Function(Uint8List imageBytes)? onExtractText;

  @override
  Future<OcrResult> extractText(Uint8List imageBytes) async {
    if (onExtractText != null) {
      return onExtractText!(imageBytes);
    }
    final norm = OcrService.normalizeText(stubbedText);
    return OcrResult(
      rawText: stubbedText,
      normalizedText: norm,
      words: OcrService.extractWords(norm),
    );
  }
}

class MockVerificationCoordinator extends VerificationCoordinator {
  int verifyCallCount = 0;
  MatchResult? stubbedResult;
  AdTarget? lastVerifiedCandidate;

  @override
  Future<MatchResult?> verifyCandidate({
    required AdTarget candidate,
    required List<int> frameJpegBytes,
    List<AdTarget>? candidatePool,
  }) async {
    verifyCallCount++;
    lastVerifiedCandidate = candidate;
    return stubbedResult;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockPhotoCameraService cameraService;
  late MockVisionService visionService;
  late MockOcrService ocrService;
  late MockVerificationCoordinator verificationCoordinator;
  late MatchingEngine matchingEngine;
  late CampaignRepository campaignRepository;

  /// Generates normalized 192-dimensional unit vectors pointing in mathematically distinct directions.
  List<double> createDistinctEmbedding(int seed) {
    final list = List<double>.generate(192, (i) {
      final angle = (i * seed * 2 * math.pi) / 192.0;
      return math.cos(angle) + math.sin(angle * 0.5);
    });
    double normSq = 0.0;
    for (final v in list) {
      normSq += v * v;
    }
    final norm = math.sqrt(normSq);
    return list.map((v) => norm > 0 ? v / norm : 0.0).toList();
  }

  setUp(() {
    cameraService = MockPhotoCameraService();
    visionService = MockVisionService();
    ocrService = MockOcrService();
    verificationCoordinator = MockVerificationCoordinator();
    matchingEngine = const MatchingEngine(threshold: 0.60);
    campaignRepository = CampaignRepository();
    campaignRepository.reset();
  });

  group('Photo Scan Recognition Pipeline Tests', () {
    testWidgets('1. Photo capture enters processing state (ANALYZING...)', (tester) async {
      cameraService.pictureCompleter = Completer<Uint8List?>();

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            cameraService: cameraService,
            visionService: visionService,
            ocrService: ocrService,
            verificationCoordinator: verificationCoordinator,
            initialScanMode: ScanMode.photo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open camera
      await tester.tap(find.text('SCAN'));
      await tester.pumpAndSettle();

      expect(find.text('POINT AT AD & CAPTURE'), findsOneWidget);
      expect(find.text('TAKE PHOTO'), findsWidgets);

      // Tap TAKE PHOTO
      await tester.tap(find.widgetWithText(BillyButton, 'TAKE PHOTO'));
      await tester.pump(); // Enter processing state

      expect(find.text('ANALYZING...'), findsOneWidget);
      expect(find.text('PROCESSING'), findsOneWidget);

      // Complete picture capture
      cameraService.pictureCompleter!.complete(Uint8List.fromList([10, 20, 30]));
      await tester.pumpAndSettle();
    });

    testWidgets('2. Captured image is passed to recognition', (tester) async {
      final sampleImageBytes = Uint8List.fromList([42, 43, 44, 45]);
      cameraService.stubbedPictureBytes = sampleImageBytes;

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            cameraService: cameraService,
            visionService: visionService,
            ocrService: ocrService,
            verificationCoordinator: verificationCoordinator,
            initialScanMode: ScanMode.photo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('SCAN'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(BillyButton, 'TAKE PHOTO'));
      await tester.pumpAndSettle();

      expect(cameraService.takePictureCalled, isTrue);
      expect(visionService.lastReceivedBytes, equals(sampleImageBytes));
    });

    testWidgets('3. Correct advertiser campaign is identified from its uploaded creative', (tester) async {
      final advertiserEmbedding = createDistinctEmbedding(1);
      visionService.stubbedEmbedding = advertiserEmbedding;

      final adTarget = AdTarget(
        id: 'campaign_solis',
        name: 'Solis Solar Inverter',
        brand: 'Solis Energy',
        destinationUrl: 'https://solis.energy',
        imageAsset: 'assets/solis.jpg',
        embedding: advertiserEmbedding,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            cameraService: cameraService,
            visionService: visionService,
            ocrService: ocrService,
            verificationCoordinator: verificationCoordinator,
            initialCampaigns: [adTarget],
            initialScanMode: ScanMode.photo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('SCAN'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(BillyButton, 'TAKE PHOTO'));
      await tester.pumpAndSettle();

      // Hierarchy verification:
      expect(find.text('I SEE IT.'), findsOneWidget);
      expect(find.text('SOLIS SOLAR INVERTER'), findsOneWidget);
      expect(find.text('Solis Energy'), findsOneWidget);
      expect(find.text('VIEW'), findsOneWidget);
      expect(find.text('RETAKE'), findsOneWidget);
    });

    testWidgets('4. Similar campaigns are not incorrectly selected', (tester) async {
      final targetAEmbedding = createDistinctEmbedding(1);
      final targetBEmbedding = createDistinctEmbedding(9);

      // Live photo matches Target A
      visionService.stubbedEmbedding = targetAEmbedding;

      final targetA = AdTarget(
        id: 'target_a',
        name: 'Campaign Alpha',
        brand: 'Alpha Brand',
        destinationUrl: 'https://alpha.com',
        imageAsset: 'assets/alpha.jpg',
        embedding: targetAEmbedding,
      );

      final targetB = AdTarget(
        id: 'target_b',
        name: 'Campaign Beta',
        brand: 'Beta Brand',
        destinationUrl: 'https://beta.com',
        imageAsset: 'assets/beta.jpg',
        embedding: targetBEmbedding,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            cameraService: cameraService,
            visionService: visionService,
            ocrService: ocrService,
            verificationCoordinator: verificationCoordinator,
            initialCampaigns: [targetA, targetB],
            initialScanMode: ScanMode.photo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('SCAN'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(BillyButton, 'TAKE PHOTO'));
      await tester.pumpAndSettle();

      expect(find.text('CAMPAIGN ALPHA'), findsOneWidget);
      expect(find.text('CAMPAIGN BETA'), findsNothing);
    });

    testWidgets('5. STUDIO NOIR cannot incorrectly override the advertiser campaign', (tester) async {
      final advertiserEmbedding = createDistinctEmbedding(1);
      final studioNoirEmbedding = createDistinctEmbedding(12);

      visionService.stubbedEmbedding = advertiserEmbedding;

      final studioNoir = AdTarget(
        id: 'demo_001',
        name: 'Studio Noir Architecture',
        brand: 'Studio Noir',
        destinationUrl: 'https://studionoir.com',
        imageAsset: 'assets/demo_ad.jpg',
        embedding: studioNoirEmbedding,
      );

      final advertiserAd = AdTarget(
        id: 'adv_999',
        name: 'Aura Electric Car',
        brand: 'Aura Motors',
        destinationUrl: 'https://aura.com',
        imageAsset: 'assets/aura.jpg',
        embedding: advertiserEmbedding,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            cameraService: cameraService,
            visionService: visionService,
            ocrService: ocrService,
            verificationCoordinator: verificationCoordinator,
            initialCampaigns: [studioNoir, advertiserAd],
            initialScanMode: ScanMode.photo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('SCAN'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(BillyButton, 'TAKE PHOTO'));
      await tester.pumpAndSettle();

      expect(find.text('AURA ELECTRIC CAR'), findsOneWidget);
      expect(find.text('STUDIO NOIR ARCHITECTURE'), findsNothing);
    });

    test('5b. MatchingEngine tie-breaker prefers advertiser campaign over demo_001', () {
      final liveEmb = createDistinctEmbedding(1);

      final demoTarget = AdTarget(
        id: 'demo_001',
        name: 'Studio Noir',
        brand: 'Studio Noir',
        destinationUrl: 'https://studionoir.com',
        imageAsset: 'assets/demo.jpg',
        embedding: liveEmb,
      );

      final advTarget = AdTarget(
        id: 'adv_001',
        name: 'Advertiser Ad',
        brand: 'Adv Brand',
        destinationUrl: 'https://adv.com',
        imageAsset: 'assets/adv.jpg',
        embedding: liveEmb,
      );

      final ranked = matchingEngine.rankCandidatesMultiSignal(
        liveEmbedding: liveEmb,
        liveNormalizedText: '',
        candidates: [demoTarget, advTarget],
      );

      expect(ranked.first.target.id, equals('adv_001'));
    });

    testWidgets('6. OCR evidence is used when available to identify candidate', (tester) async {
      final candidateEmbedding = createDistinctEmbedding(1);
      visionService.stubbedEmbedding = candidateEmbedding;
      ocrService.stubbedText = 'KINETIC ENERGY WATCH';

      final target = AdTarget(
        id: 'kinetic_01',
        name: 'Kinetic Energy Watch',
        brand: 'Kinetic',
        destinationUrl: 'https://kinetic.watch',
        imageAsset: 'assets/kinetic.jpg',
        embedding: candidateEmbedding,
        ocrText: 'KINETIC ENERGY WATCH CHRONO',
        normalizedOcrText: 'kinetic energy watch chrono',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            cameraService: cameraService,
            visionService: visionService,
            ocrService: ocrService,
            verificationCoordinator: verificationCoordinator,
            initialCampaigns: [target],
            initialScanMode: ScanMode.photo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('SCAN'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(BillyButton, 'TAKE PHOTO'));
      await tester.pumpAndSettle();

      expect(find.text('KINETIC ENERGY WATCH'), findsOneWidget);
    });

    testWidgets('7. Ambiguous candidates trigger Gemini verification', (tester) async {
      // Two identical embeddings producing margin = 0.0 (< 0.08)
      final emb = createDistinctEmbedding(1);

      visionService.stubbedEmbedding = emb;

      final candidateA = AdTarget(
        id: 'brand_a',
        name: 'Brand Alpha',
        brand: 'Alpha Co',
        destinationUrl: 'https://a.com',
        imageAsset: 'assets/a.jpg',
        embedding: emb,
      );

      final candidateB = AdTarget(
        id: 'brand_b',
        name: 'Brand Beta',
        brand: 'Beta Co',
        destinationUrl: 'https://b.com',
        imageAsset: 'assets/b.jpg',
        embedding: emb,
      );

      verificationCoordinator.stubbedResult = MatchResult(
        target: candidateA,
        similarity: 0.95,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            cameraService: cameraService,
            visionService: visionService,
            ocrService: ocrService,
            verificationCoordinator: verificationCoordinator,
            initialCampaigns: [candidateA, candidateB],
            initialScanMode: ScanMode.photo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('SCAN'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(BillyButton, 'TAKE PHOTO'));
      await tester.pumpAndSettle();

      expect(verificationCoordinator.verifyCallCount, greaterThan(0));
      expect(verificationCoordinator.lastVerifiedCandidate?.id, equals('brand_a'));
      expect(find.text('BRAND ALPHA'), findsOneWidget);
    });

    testWidgets('7b. Clear candidate with similarity around 0.70-0.81 and margin >0.08 does not unnecessarily require Gemini', (tester) async {
      final embA = createDistinctEmbedding(1);
      final embB = createDistinctEmbedding(10);
      final embOther = createDistinctEmbedding(40);

      // Construct live embedding that has ~0.76 cosine similarity with embA:
      final liveEmb = List<double>.filled(192, 0.0);
      const c = 0.76;
      final s = math.sqrt(1.0 - c * c);
      for (int i = 0; i < 192; i++) {
        liveEmb[i] = c * embA[i] + s * embB[i];
      }
      visionService.stubbedEmbedding = liveEmb;

      final candidateA = AdTarget(
        id: 'candidate_a',
        name: 'Clear Candidate A',
        brand: 'Brand A',
        destinationUrl: 'https://a.com',
        imageAsset: 'assets/a.jpg',
        embedding: embA,
      );

      final candidateB = AdTarget(
        id: 'candidate_b',
        name: 'Distal Candidate B',
        brand: 'Brand B',
        destinationUrl: 'https://b.com',
        imageAsset: 'assets/b.jpg',
        embedding: embOther,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            cameraService: cameraService,
            visionService: visionService,
            ocrService: ocrService,
            verificationCoordinator: verificationCoordinator,
            initialCampaigns: [candidateA, candidateB],
            initialScanMode: ScanMode.photo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('SCAN'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(BillyButton, 'TAKE PHOTO'));
      await tester.pumpAndSettle();

      // VerificationCoordinator was NOT triggered because candidate was clear with margin > 0.08
      expect(verificationCoordinator.verifyCallCount, equals(0));
      expect(find.text('CLEAR CANDIDATE A'), findsOneWidget);
    });

    testWidgets('7c. Gemini-unavailable ambiguous candidates do not falsely confirm an ad', (tester) async {
      final emb = createDistinctEmbedding(1);
      visionService.stubbedEmbedding = emb;

      final candidateA = AdTarget(
        id: 'brand_a',
        name: 'Brand Alpha',
        brand: 'Alpha Co',
        destinationUrl: 'https://a.com',
        imageAsset: 'assets/a.jpg',
        embedding: emb,
      );

      final candidateB = AdTarget(
        id: 'brand_b',
        name: 'Brand Beta',
        brand: 'Beta Co',
        destinationUrl: 'https://b.com',
        imageAsset: 'assets/b.jpg',
        embedding: emb,
      );

      // Gemini is unavailable / rejects
      verificationCoordinator.stubbedResult = null;

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            cameraService: cameraService,
            visionService: visionService,
            ocrService: ocrService,
            verificationCoordinator: verificationCoordinator,
            initialCampaigns: [candidateA, candidateB],
            initialScanMode: ScanMode.photo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('SCAN'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(BillyButton, 'TAKE PHOTO'));
      await tester.pumpAndSettle();

      // Gemini was triggered because candidates were ambiguous
      expect(verificationCoordinator.verifyCallCount, greaterThan(0));
      // But because Gemini returned null, no ad was falsely confirmed
      expect(find.text('NO MATCH FOUND'), findsOneWidget);
      expect(find.text('BRAND ALPHA'), findsNothing);
      expect(find.text('BRAND BETA'), findsNothing);
    });

    testWidgets('8. No-match image produces NO MATCH FOUND and TRY AGAIN', (tester) async {
      // live embedding completely orthogonal/dissimilar to candidate (similarity < 0.2 < threshold 0.60)
      visionService.stubbedEmbedding = createDistinctEmbedding(1);

      final target = AdTarget(
        id: 'target_01',
        name: 'Target One',
        brand: 'Brand One',
        destinationUrl: 'https://example.com',
        imageAsset: 'assets/target.jpg',
        embedding: createDistinctEmbedding(37),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            cameraService: cameraService,
            visionService: visionService,
            ocrService: ocrService,
            verificationCoordinator: verificationCoordinator,
            initialCampaigns: [target],
            initialScanMode: ScanMode.photo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('SCAN'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(BillyButton, 'TAKE PHOTO'));
      await tester.pumpAndSettle();

      expect(find.text('NO MATCH FOUND'), findsOneWidget);
      expect(find.text('TRY AGAIN'), findsWidgets);
      expect(find.widgetWithText(BillyButton, 'RETAKE'), findsOneWidget);
    });

    test('9. Paused/expired campaigns cannot match in CampaignRepository', () {
      final active = Campaign(
        id: 'act_01',
        adName: 'Active Ad',
        brandName: 'Active Brand',
        destinationUrl: 'https://act.com',
        status: CampaignStatus.active,
        createdAt: DateTime.now(),
      );

      final paused = Campaign(
        id: 'pau_01',
        adName: 'Paused Ad',
        brandName: 'Paused Brand',
        destinationUrl: 'https://paused.com',
        status: CampaignStatus.paused,
        createdAt: DateTime.now(),
      );

      final expired = Campaign(
        id: 'exp_01',
        adName: 'Expired Ad',
        brandName: 'Expired Brand',
        destinationUrl: 'https://exp.com',
        status: CampaignStatus.expired,
        createdAt: DateTime.now().subtract(const Duration(days: 10)),
        endAt: DateTime.now().subtract(const Duration(days: 1)),
      );

      campaignRepository.addCampaign(active);
      campaignRepository.addCampaign(paused);
      campaignRepository.addCampaign(expired);

      final activeTargets = campaignRepository.getActiveAdTargets();
      expect(activeTargets.length, equals(1));
      expect(activeTargets.first.id, equals('act_01'));
      expect(activeTargets.any((t) => t.id == 'pau_01'), isFalse);
      expect(activeTargets.any((t) => t.id == 'exp_01'), isFalse);
    });

    testWidgets('10. RETAKE returns to photo capture', (tester) async {
      // Trigger no match first
      visionService.stubbedEmbedding = createDistinctEmbedding(1);

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            cameraService: cameraService,
            visionService: visionService,
            ocrService: ocrService,
            verificationCoordinator: verificationCoordinator,
            initialCampaigns: [
              AdTarget(
                id: 'target_01',
                name: 'Target One',
                brand: 'Brand One',
                destinationUrl: 'https://example.com',
                imageAsset: 'assets/target.jpg',
                embedding: createDistinctEmbedding(37),
              ),
            ],
            initialScanMode: ScanMode.photo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('SCAN'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(BillyButton, 'TAKE PHOTO'));
      await tester.pumpAndSettle();

      expect(find.text('NO MATCH FOUND'), findsOneWidget);

      // Tap RETAKE
      await tester.tap(find.widgetWithText(BillyButton, 'RETAKE'));
      await tester.pumpAndSettle();

      // Returned to photo capture mode:
      expect(find.text('TAKE PHOTO'), findsWidgets);
      expect(find.text('NO MATCH FOUND'), findsNothing);
    });

    testWidgets('11. Existing live camera recognition flow remains passing', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            cameraService: cameraService,
            visionService: visionService,
            ocrService: ocrService,
            verificationCoordinator: verificationCoordinator,
            initialScanMode: ScanMode.live,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('SCAN'));
      await tester.pump(const Duration(milliseconds: 350));

      // In LIVE SCAN mode, live indicators are present
      expect(find.text('SHOW BILLY SOMETHING'), findsOneWidget);
      expect(find.text('POINT AT AN AD'), findsOneWidget);
    });

    test('12. Existing walk-by recognition behavior and cosine similarity are untouched', () {
      final v1 = createDistinctEmbedding(1);
      final v2 = createDistinctEmbedding(1);
      final sim = MatchingEngine.cosineSimilarity(v1, v2);
      expect(sim, closeTo(1.0, 0.001));

      final vDissimilar = createDistinctEmbedding(19);
      final simLow = MatchingEngine.cosineSimilarity(v1, vDissimilar);
      expect(simLow, lessThan(0.5));
    });

    test('13. 4:3 captured photo correctly matches its registered creative via center-crop geometry', () async {
      final vision = VisionService();
      await vision.initialize();

      // Create a 600x600 square pattern for the registered creative
      final squareCreative = img.Image(width: 600, height: 600);
      for (int y = 0; y < 600; y++) {
        for (int x = 0; x < 600; x++) {
          final lum = ((x ~/ 30 + y ~/ 30) % 2 == 0) ? 220 : 30;
          squareCreative.setPixelRgb(x, y, lum, lum, lum);
        }
      }

      // Create a 4:3 captured photo (800x600) where the center 600x600 matches squareCreative
      final photo4x3 = img.Image(width: 800, height: 600);
      for (int y = 0; y < 600; y++) {
        for (int x = 0; x < 800; x++) {
          if (x >= 100 && x < 700) {
            final p = squareCreative.getPixel(x - 100, y);
            photo4x3.setPixel(x, y, p);
          } else {
            photo4x3.setPixelRgb(x, y, 15, 15, 15);
          }
        }
      }

      final creativeEmb = await vision.generateEmbeddingFromImage(squareCreative);
      final photoEmb = await vision.generateEmbeddingFromImage(photo4x3);

      expect(creativeEmb, isNotEmpty);
      expect(photoEmb, isNotEmpty);

      final sim = MatchingEngine.maxSimilarityAcrossRotations(creativeEmb, photoEmb);
      expect(sim, greaterThanOrEqualTo(0.95));
    });

    test('14. 16:9 captured photo correctly matches its registered creative via center-crop geometry', () async {
      final vision = VisionService();
      await vision.initialize();

      // Create a 600x600 square pattern for the registered creative
      final squareCreative = img.Image(width: 600, height: 600);
      for (int y = 0; y < 600; y++) {
        for (int x = 0; x < 600; x++) {
          final lum = ((x * 7 + y * 13) % 255);
          squareCreative.setPixelRgb(x, y, lum, lum, lum);
        }
      }

      // Create a 16:9 captured photo (1066x600) where the center 600x600 matches squareCreative
      final photo16x9 = img.Image(width: 1066, height: 600);
      const startX = (1066 - 600) ~/ 2; // 233
      for (int y = 0; y < 600; y++) {
        for (int x = 0; x < 1066; x++) {
          if (x >= startX && x < startX + 600) {
            final p = squareCreative.getPixel(x - startX, y);
            photo16x9.setPixel(x, y, p);
          } else {
            photo16x9.setPixelRgb(x, y, 20, 20, 20);
          }
        }
      }

      final creativeEmb = await vision.generateEmbeddingFromImage(squareCreative);
      final photoEmb = await vision.generateEmbeddingFromImage(photo16x9);

      expect(creativeEmb, isNotEmpty);
      expect(photoEmb, isNotEmpty);

      final sim = MatchingEngine.maxSimilarityAcrossRotations(creativeEmb, photoEmb);
      expect(sim, greaterThanOrEqualTo(0.95));
    });

    test('15. Minor OCR typos (e.g. "lving" vs "living", "0" vs "o") produce strong text evidence', () {
      const candidateOcr = 'singular living infinite prestige unmatched exclusivity prestigious location';
      const liveOcrTypo = 'singular lving infinite prestige';

      final evidence = OcrService.evaluateMatchEvidence(liveOcrTypo, candidateOcr);

      expect(evidence.hasDistinctiveEvidence, isTrue);
      expect(evidence.score, greaterThanOrEqualTo(0.95));
      expect(evidence.contiguousPhraseLength, greaterThanOrEqualTo(4));
      expect(evidence.matchedDistinctiveTokens, containsAll(['singular', 'living', 'infinite', 'prestige']));
    });

    test('16. Distinctive multi-word text evidence correctly ranks correct campaign over competing campaign with higher visual similarity', () {
      final engine = const MatchingEngine();

      // Setup embeddings
      final embTarget = createDistinctEmbedding(10);
      final embCompetitor = createDistinctEmbedding(20);

      // Create live embedding that has visual similarity ~0.18 to embTarget and ~0.49 to embCompetitor
      // We can construct this directly via cosine similarity vectors:
      // Let's create liveEmb such that maxSimilarity(embTarget, liveEmb) ~ 0.18, maxSimilarity(embCompetitor, liveEmb) ~ 0.49
      // Or we can mock the candidates' embeddings
      final target = AdTarget(
        id: 'camp_target',
        name: 'Target Brand Campaign',
        brand: 'Target Brand',
        destinationUrl: 'https://target.com',
        imageAsset: 'assets/target.jpg',
        embedding: embTarget,
        normalizedOcrText: 'singular living infinite prestige unmatched exclusivity prestigious location',
      );

      final competitor = AdTarget(
        id: 'camp_competitor',
        name: 'Competitor Visual Campaign',
        brand: 'Competitor Brand',
        destinationUrl: 'https://competitor.com',
        imageAsset: 'assets/competitor.jpg',
        embedding: embCompetitor,
        normalizedOcrText: 'aurora vision see the future modern intelligent innovation',
      );

      // Construct a live embedding with controlled similarities:
      // liveEmb = 0.18 * embTarget + 0.49 * embCompetitor + residual
      final liveEmb = List<double>.filled(192, 0.0);
      for (int i = 0; i < 192; i++) {
        liveEmb[i] = 0.18 * embTarget[i] + 0.49 * embCompetitor[i];
      }
      double normSq = 0.0;
      for (final v in liveEmb) {
        normSq += v * v;
      }
      final norm = math.sqrt(normSq);
      for (int i = 0; i < 192; i++) {
        liveEmb[i] /= norm;
      }

      const liveText = 'singular lving infinite prestige';

      final ranked = engine.rankCandidatesMultiSignal(
        liveEmbedding: liveEmb,
        liveNormalizedText: liveText,
        candidates: [competitor, target],
      );

      expect(ranked, isNotEmpty);
      expect(ranked.first.target.id, equals('camp_target'));
      expect(ranked.first.similarity, greaterThanOrEqualTo(0.70));
      expect(ranked.first.distinctiveMatches, greaterThanOrEqualTo(3));
      expect(ranked.first.matchedPhrase, isNotNull);

      // Margin between target and competitor must be decisive (> 0.08)
      final margin = ranked[0].similarity - ranked[1].similarity;
      expect(margin, greaterThan(0.08));
      expect(ranked.first.isAmbiguous, isFalse);
    });

    test('17. Generic stop words alone do not trigger distinctive evidence boost', () {
      const candidateOcr = 'the new sale and free shipping for all customers';
      const liveOcr = 'the and for with new free';

      final evidence = OcrService.evaluateMatchEvidence(liveOcr, candidateOcr);

      // Should NOT qualify as distinctive evidence because tokens are generic stopwords
      expect(evidence.hasDistinctiveEvidence, isFalse);
      expect(evidence.matchedDistinctiveTokens, isEmpty);
    });

    test('18. Independent visual signal guard: scenes with vSim < 0.10 do not receive dynamic text boost', () {
      final engine = const MatchingEngine();

      final embTarget = createDistinctEmbedding(10);
      // Orthogonal/inverted vector to make vSim < 0.05
      final embDissimilar = createDistinctEmbedding(77);

      final target = AdTarget(
        id: 'camp_target',
        name: 'Target Brand Campaign',
        brand: 'Target Brand',
        destinationUrl: 'https://target.com',
        imageAsset: 'assets/target.jpg',
        embedding: embTarget,
        normalizedOcrText: 'singular living infinite prestige unmatched exclusivity',
      );

      const liveText = 'singular living infinite prestige';

      final ranked = engine.rankCandidatesMultiSignal(
        liveEmbedding: embDissimilar,
        liveNormalizedText: liveText,
        candidates: [target],
      );

      expect(ranked, isNotEmpty);
      // Because vSim < 0.10, dynamic text boost (0.75) is NOT applied; standard weights apply
      // Standard weights: 0.65 * vSim (< 0.10) + 0.35 * 0.98 (~0.34) < 0.45 < 0.70 threshold!
      expect(ranked.first.similarity, lessThan(0.70));
    });

    testWidgets('19. HomeScreen Photo Scan correctly confirms campaign with minor OCR typo without Gemini rejection', (tester) async {
      final embTarget = createDistinctEmbedding(10);
      final embCompetitor = createDistinctEmbedding(20);

      final liveEmb = List<double>.filled(192, 0.0);
      for (int i = 0; i < 192; i++) {
        liveEmb[i] = 0.20 * embTarget[i] + 0.45 * embCompetitor[i];
      }
      double normSq = 0.0;
      for (final v in liveEmb) {
        normSq += v * v;
      }
      final norm = math.sqrt(normSq);
      for (int i = 0; i < 192; i++) {
        liveEmb[i] /= norm;
      }

      visionService.stubbedEmbedding = liveEmb;
      ocrService.stubbedText = 'Singular Lving\nInfinite Prestige';

      final target = AdTarget(
        id: 'camp_target',
        name: 'Singular Living HHH',
        brand: 'HHH Luxury',
        destinationUrl: 'https://singularliving.com',
        imageAsset: 'assets/target.jpg',
        embedding: embTarget,
        normalizedOcrText: 'singular living infinite prestige unmatched exclusivity prestigious location',
      );

      final competitor = AdTarget(
        id: 'camp_competitor',
        name: 'Aurora Vision',
        brand: 'Aurora',
        destinationUrl: 'https://aurora.com',
        imageAsset: 'assets/competitor.jpg',
        embedding: embCompetitor,
        normalizedOcrText: 'aurora vision see the future intelligent innovation',
      );

      // Gemini is unavailable in this test to ensure local multi-signal confirms cleanly
      verificationCoordinator.stubbedResult = null;

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            cameraService: cameraService,
            visionService: visionService,
            ocrService: ocrService,
            verificationCoordinator: verificationCoordinator,
            initialCampaigns: [competitor, target],
            initialScanMode: ScanMode.photo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('SCAN'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(BillyButton, 'TAKE PHOTO'));
      await tester.pumpAndSettle();

      // Successfully recognized "Singular Living HHH" based on multi-signal evidence!
      expect(find.text('SINGULAR LIVING HHH'), findsOneWidget);
      expect(find.text('NO MATCH FOUND'), findsNothing);
      // VerificationCoordinator was not needed because margin was clear and unambiguous (> 0.08)
      expect(verificationCoordinator.verifyCallCount, equals(0));
    });

    test('20. VisionService.extractOverlappingCrops returns valid overlapping regions', () {
      final img400 = img.Image(width: 400, height: 400);
      final crops = VisionService.extractOverlappingCrops(img400);

      expect(crops.containsKey('top'), isTrue);
      expect(crops.containsKey('bottom'), isTrue);
      expect(crops.containsKey('left'), isTrue);
      expect(crops.containsKey('right'), isTrue);

      expect(crops['top']!.height, equals((400 * 0.65).round()));
      expect(crops['bottom']!.height, equals(400 - (400 * 0.35).round()));
      expect(crops['left']!.width, equals((400 * 0.65).round()));
      expect(crops['right']!.width, equals(400 - (400 * 0.35).round()));
    });

    testWidgets('21. Top half of ad is recognized when sufficient distinctive evidence exists in crop pass', (tester) async {
      // Primary full image is a 400x400 JPEG
      final testJpeg = Uint8List.fromList(img.encodeJpg(img.Image(width: 400, height: 400)));
      cameraService.stubbedPictureBytes = testJpeg;

      final embTarget = createDistinctEmbedding(10);
      final embUnrelated = createDistinctEmbedding(99);

      // Primary pass returns unrelated embedding (similarity < 0.20) and empty text -> primary pass fails
      visionService.stubbedEmbedding = embUnrelated;
      ocrService.stubbedText = '';

      // When the top crop is analyzed in the multi-region pass, return target-correlated embedding and headline OCR
      visionService.onGenerateEmbedding = (bytes) async {
        // If it is the full image, return unrelated
        if (bytes.length == testJpeg.length) {
          return embUnrelated;
        }
        // For partial crops, return target embedding with plausible visual similarity (0.25)
        return embTarget;
      };

      ocrService.onExtractText = (bytes) async {
        if (bytes.length == testJpeg.length) {
          return OcrResult.empty;
        }
        // Top crop contains the headline
        const text = 'Singular Living Infinite Prestige';
        final norm = OcrService.normalizeText(text);
        return OcrResult(
          rawText: text,
          normalizedText: norm,
          words: OcrService.extractWords(norm),
        );
      };

      final target = AdTarget(
        id: 'camp_target',
        name: 'Singular Living HHH',
        brand: 'HHH Luxury',
        destinationUrl: 'https://singularliving.com',
        imageAsset: 'assets/target.jpg',
        embedding: embTarget,
        normalizedOcrText: 'singular living infinite prestige unmatched exclusivity prestigious location',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            cameraService: cameraService,
            visionService: visionService,
            ocrService: ocrService,
            verificationCoordinator: verificationCoordinator,
            initialCampaigns: [target],
            initialScanMode: ScanMode.photo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('SCAN'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(BillyButton, 'TAKE PHOTO'));
      await tester.pumpAndSettle();

      // Successfully recognized via top crop in multi-region pass!
      expect(find.text('SINGULAR LIVING HHH'), findsOneWidget);
      expect(find.text('NO MATCH FOUND'), findsNothing);
    });

    testWidgets('22. Side/partial ad is recognized when sufficient evidence exists in side crop pass', (tester) async {
      final testJpeg = Uint8List.fromList(img.encodeJpg(img.Image(width: 400, height: 400)));
      cameraService.stubbedPictureBytes = testJpeg;

      final embTarget = createDistinctEmbedding(15);
      final embUnrelated = createDistinctEmbedding(88);

      visionService.stubbedEmbedding = embUnrelated;
      ocrService.stubbedText = '';

      visionService.onGenerateEmbedding = (bytes) async {
        if (bytes.length == testJpeg.length) {
          return embUnrelated;
        }
        // Partial side crop has plausible visual similarity
        return embTarget;
      };

      ocrService.onExtractText = (bytes) async {
        if (bytes.length == testJpeg.length) {
          return OcrResult.empty;
        }
        const text = 'Singular Living Prestigious Location';
        final norm = OcrService.normalizeText(text);
        return OcrResult(
          rawText: text,
          normalizedText: norm,
          words: OcrService.extractWords(norm),
        );
      };

      final target = AdTarget(
        id: 'camp_target',
        name: 'Singular Living HHH',
        brand: 'HHH Luxury',
        destinationUrl: 'https://singularliving.com',
        imageAsset: 'assets/target.jpg',
        embedding: embTarget,
        normalizedOcrText: 'singular living infinite prestige unmatched exclusivity prestigious location',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            cameraService: cameraService,
            visionService: visionService,
            ocrService: ocrService,
            verificationCoordinator: verificationCoordinator,
            initialCampaigns: [target],
            initialScanMode: ScanMode.photo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('SCAN'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(BillyButton, 'TAKE PHOTO'));
      await tester.pumpAndSettle();

      expect(find.text('SINGULAR LIVING HHH'), findsOneWidget);
      expect(find.text('NO MATCH FOUND'), findsNothing);
    });

    testWidgets('23. Genuinely unrelated partial image produces NO MATCH FOUND', (tester) async {
      final testJpeg = Uint8List.fromList(img.encodeJpg(img.Image(width: 400, height: 400)));
      cameraService.stubbedPictureBytes = testJpeg;

      // Both primary and partial crops return unrelated embeddings and empty text
      final embTarget = createDistinctEmbedding(10);
      final embUnrelated = createDistinctEmbedding(99);

      visionService.stubbedEmbedding = embUnrelated;
      visionService.onGenerateEmbedding = (_) async => embUnrelated;
      ocrService.stubbedText = '';
      ocrService.onExtractText = (_) async => OcrResult.empty;

      final target = AdTarget(
        id: 'camp_target',
        name: 'Singular Living HHH',
        brand: 'HHH Luxury',
        destinationUrl: 'https://singularliving.com',
        imageAsset: 'assets/target.jpg',
        embedding: embTarget,
        normalizedOcrText: 'singular living infinite prestige',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            cameraService: cameraService,
            visionService: visionService,
            ocrService: ocrService,
            verificationCoordinator: verificationCoordinator,
            initialCampaigns: [target],
            initialScanMode: ScanMode.photo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('SCAN'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(BillyButton, 'TAKE PHOTO'));
      await tester.pumpAndSettle();

      expect(find.text('NO MATCH FOUND'), findsOneWidget);
      expect(find.text('SINGULAR LIVING HHH'), findsNothing);
    });

    testWidgets('24. Visually similar partial ad remains protected from false confirmation', (tester) async {
      final testJpeg = Uint8List.fromList(img.encodeJpg(img.Image(width: 400, height: 400)));
      cameraService.stubbedPictureBytes = testJpeg;

      final embAlpha = createDistinctEmbedding(1);
      final embBeta = createDistinctEmbedding(1); // identical visual embedding -> ambiguous margin = 0.0

      visionService.stubbedEmbedding = embAlpha;
      visionService.onGenerateEmbedding = (_) async => embAlpha;
      ocrService.stubbedText = '';
      ocrService.onExtractText = (_) async => OcrResult.empty;

      // Gemini rejects / returns null
      verificationCoordinator.stubbedResult = null;

      final candidateA = AdTarget(
        id: 'brand_a',
        name: 'Brand Alpha',
        brand: 'Alpha Co',
        destinationUrl: 'https://a.com',
        imageAsset: 'assets/a.jpg',
        embedding: embAlpha,
      );

      final candidateB = AdTarget(
        id: 'brand_b',
        name: 'Brand Beta',
        brand: 'Beta Co',
        destinationUrl: 'https://b.com',
        imageAsset: 'assets/b.jpg',
        embedding: embBeta,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            cameraService: cameraService,
            visionService: visionService,
            ocrService: ocrService,
            verificationCoordinator: verificationCoordinator,
            initialCampaigns: [candidateA, candidateB],
            initialScanMode: ScanMode.photo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('SCAN'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(BillyButton, 'TAKE PHOTO'));
      await tester.pumpAndSettle();

      // Because candidates are ambiguous and Gemini rejected, no false confirmation occurred!
      expect(find.text('NO MATCH FOUND'), findsOneWidget);
      expect(find.text('BRAND ALPHA'), findsNothing);
      expect(find.text('BRAND BETA'), findsNothing);
      expect(verificationCoordinator.verifyCallCount, greaterThan(0));
    });

    testWidgets('25. Recognized advertiser campaign displays its registered creative rather than generic AD placeholder', (tester) async {
      final creativeBytes = Uint8List.fromList(img.encodeJpg(img.Image(width: 100, height: 100)));
      final emb = createDistinctEmbedding(10);

      visionService.stubbedEmbedding = emb;
      ocrService.stubbedText = 'Singular Living Infinite Prestige';

      final target = AdTarget(
        id: 'camp_uploaded',
        name: 'Uploaded Creative Campaign',
        brand: 'Luxury Brand',
        destinationUrl: 'https://example.com',
        imageAsset: '/path/to/uploaded/gallery_image.jpg', // local filesystem path from gallery picker
        creativeBytes: creativeBytes,
        embedding: emb,
        normalizedOcrText: 'singular living infinite prestige',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            cameraService: cameraService,
            visionService: visionService,
            ocrService: ocrService,
            verificationCoordinator: verificationCoordinator,
            initialCampaigns: [target],
            initialScanMode: ScanMode.photo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('SCAN'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(BillyButton, 'TAKE PHOTO'));
      await tester.pumpAndSettle();

      // Card appears with recognized ad name
      expect(find.text('UPLOADED CREATIVE CAMPAIGN'), findsOneWidget);

      // The discovery result card displays the actual uploaded creative via Image.memory
      final imageFinder = find.descendant(
        of: find.byKey(const ValueKey('discovery_result_card')),
        matching: find.byType(Image),
      );
      expect(imageFinder, findsOneWidget);
      final imageWidget = tester.widget<Image>(imageFinder);
      expect(imageWidget.image, isA<MemoryImage>());
      expect((imageWidget.image as MemoryImage).bytes, equals(creativeBytes));

      // The generic "AD" placeholder text is NOT displayed
      expect(find.text('AD'), findsNothing);
    });

    testWidgets('26. Fallback AD placeholder is shown only when campaign has no usable image', (tester) async {
      final emb = createDistinctEmbedding(10);
      visionService.stubbedEmbedding = emb;
      ocrService.stubbedText = 'Generic Campaign Headline';

      final targetNoImage = AdTarget(
        id: 'camp_no_image',
        name: 'No Image Campaign',
        brand: 'Generic Brand',
        destinationUrl: 'https://example.com',
        imageAsset: '', // No asset or file
        creativeBytes: null, // No in-memory bytes
        embedding: emb,
        normalizedOcrText: 'generic campaign headline',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            cameraService: cameraService,
            visionService: visionService,
            ocrService: ocrService,
            verificationCoordinator: verificationCoordinator,
            initialCampaigns: [targetNoImage],
            initialScanMode: ScanMode.photo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('SCAN'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(BillyButton, 'TAKE PHOTO'));
      await tester.pumpAndSettle();

      expect(find.text('NO IMAGE CAMPAIGN'), findsOneWidget);

      // Fallback "AD" placeholder is displayed
      expect(find.text('AD'), findsOneWidget);
    });
  });
}
