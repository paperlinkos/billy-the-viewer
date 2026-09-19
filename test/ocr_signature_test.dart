import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:billy_the_viewer/models/ad_target.dart';
import 'package:billy_the_viewer/models/campaign.dart';
import 'package:billy_the_viewer/models/recognition_signature.dart';
import 'package:billy_the_viewer/screens/create_campaign_screen.dart';
import 'package:billy_the_viewer/services/campaign_repository.dart';
import 'package:billy_the_viewer/services/matching_engine.dart';
import 'package:billy_the_viewer/services/ocr_service.dart';
import 'package:billy_the_viewer/services/signature_service.dart';
import 'package:billy_the_viewer/services/vision_service.dart';

/// Test mock OCR engine providing controllable text extraction results.
class MockOcrEngine implements IOcrEngine {
  final OcrResult resultToReturn;
  final bool shouldThrow;

  MockOcrEngine({
    this.resultToReturn = OcrResult.empty,
    this.shouldThrow = false,
  });

  @override
  Future<OcrResult> extractText(Uint8List imageBytes) async {
    if (shouldThrow) {
      throw Exception('Simulated OCR hardware error');
    }
    return resultToReturn;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late VisionService visionService;
  late Uint8List creativeABytes;
  late Uint8List creativeBBytes;

  setUpAll(() async {
    visionService = VisionService();
    await visionService.initialize();

    final fileA = File('assets/campaigns/demo_ad.jpg');
    final fileB = File('assets/campaigns/demo_ad_2.jpg');
    expect(fileA.existsSync(), isTrue);
    expect(fileB.existsSync(), isTrue);

    creativeABytes = fileA.readAsBytesSync();
    creativeBBytes = fileB.readAsBytesSync();
  });

  setUp(() {
    CampaignRepository().reset();
  });

  group('OCR Signature Integration & Normalization Tests', () {
    test('1. Advertisement containing readable text produces non-empty OCR data', () async {
      const rawText = 'STUDIO NOIR\nARCHITECTURE & DESIGN';
      final normalized = OcrService.normalizeText(rawText);
      final words = OcrService.extractWords(normalized);

      final mockOcr = MockOcrEngine(
        resultToReturn: OcrResult(
          rawText: rawText,
          normalizedText: normalized,
          words: words,
          metadata: {
            'engine': 'mock_ocr',
            'blocksCount': 2,
            'confidence': 0.98,
          },
        ),
      );

      final signatureService = SignatureService(
        visionService: visionService,
        ocrEngine: mockOcr,
      );

      final signature = await signatureService.generateSignature(creativeABytes);

      expect(signature.hasOcrText, isTrue);
      expect(signature.ocrText, rawText);
      expect(signature.normalizedOcrText, 'studio noir architecture design');
      expect(signature.ocrMetadata, isNotNull);
      expect(signature.ocrMetadata!['confidence'], 0.98);
      expect(signature.metadata['hasOcrText'], isTrue);
      expect(signature.metadata['ocrWordsCount'], 4);
    });

    test('2. OCR normalization behaves consistently for case/whitespace/punctuation differences', () {
      // Different formatting of the same advertisement copy
      const sample1 = 'STUDIO NOIR\nArchitecture & Design!';
      const sample2 = 'Studio Noir:   Architecture and Design.';
      const sample3 = '  studio   noir   architecture   design  ';
      const sample4 = 'STUDIO-NOIR: ARCHITECTURE / DESIGN???';

      final norm1 = OcrService.normalizeText(sample1);
      final norm2 = OcrService.normalizeText(sample2);
      final norm3 = OcrService.normalizeText(sample3);
      final norm4 = OcrService.normalizeText(sample4);

      // Verify lowercase, punctuation removal, and single space collapsing
      expect(norm1, 'studio noir architecture design');
      expect(norm2, 'studio noir architecture and design');
      expect(norm3, 'studio noir architecture design');
      expect(norm4, 'studio noir architecture design');

      // 1, 3, and 4 should produce identical normalized strings
      expect(norm1, equals(norm3));
      expect(norm1, equals(norm4));

      // Token extraction
      final words = OcrService.extractWords(norm1);
      expect(words, ['studio', 'noir', 'architecture', 'design']);
    });

    test('3. Image with no detectable text does not crash and produces an empty OCR result', () async {
      // Empty OCR result simulates an ad creative with only abstract artwork or no detectable text
      final mockOcr = MockOcrEngine(resultToReturn: OcrResult.empty);
      final signatureService = SignatureService(
        visionService: visionService,
        ocrEngine: mockOcr,
      );

      final signature = await signatureService.generateSignature(creativeABytes);

      expect(signature.hasOcrText, isFalse);
      expect(signature.ocrText, isEmpty);
      expect(signature.normalizedOcrText, isEmpty);
      expect(signature.ocrMetadata, isNull);
      expect(signature.metadata['hasOcrText'], isFalse);
      expect(signature.metadata['ocrWordsCount'], 0);
      expect(signature.isValid, isTrue); // Visual descriptor remains valid!
    });

    test('3b. Faulty OCR engine failure handles gracefully without crashing signature generation', () async {
      final faultyOcr = MockOcrEngine(shouldThrow: true);
      final signatureService = SignatureService(
        visionService: visionService,
        ocrEngine: faultyOcr,
      );

      final signature = await signatureService.generateSignature(creativeABytes);

      expect(signature.hasOcrText, isFalse);
      expect(signature.isValid, isTrue);
      expect(signature.perceptualFeatures.length, 192);
    });

    test('4. Existing visual signatures remain intact and unaffected by OCR addition', () async {
      final mockOcr = MockOcrEngine(
        resultToReturn: const OcrResult(
          rawText: 'SUMMER SALE 50%',
          normalizedText: 'summer sale 50',
          words: ['summer', 'sale', '50'],
        ),
      );

      final signatureService = SignatureService(
        visionService: visionService,
        ocrEngine: mockOcr,
      );

      final signature = await signatureService.generateSignature(creativeABytes);

      // Verify visual features specification
      expect(signature.version, '1.0');
      expect(signature.signatureVersion, '1.0');
      expect(signature.perceptualFeatures.length, 192);
      expect(signature.primaryFeatures.length, 192);
      expect(signature.metadata['algorithm'], 'relative_spatial_gradient_192');
      expect(signature.metadata['dimension'], 192);

      // Verify self-similarity visual match remains 1.0 (perfect match)
      final rawTarget = AdTarget(
        id: 'ad_target_1',
        name: 'TEST AD',
        brand: 'Test Brand',
        destinationUrl: 'https://example.com',
        imageAsset: '',
        embedding: signature.primaryFeatures,
      );
      final selfSim = MatchingEngine.cosineSimilarity(
        signature.primaryFeatures,
        rawTarget.embedding,
      );
      expect(selfSim, closeTo(1.0, 0.001));

      // Serialization and deserialization preserves both visual features and OCR fields
      final json = signature.toJson();
      final restored = RecognitionSignature.fromJson(json);
      expect(restored.version, signature.version);
      expect(restored.perceptualFeatures, signature.perceptualFeatures);
      expect(restored.ocrText, signature.ocrText);
      expect(restored.normalizedOcrText, signature.normalizedOcrText);
      expect(restored.hasOcrText, isTrue);
    });

    test('5. Campaign creation stores the OCR-enhanced RecognitionSignature', () async {
      final repo = CampaignRepository();
      repo.reset();

      final mockOcr = MockOcrEngine(
        resultToReturn: const OcrResult(
          rawText: 'AURORA ELECTRIC VEHICLES',
          normalizedText: 'aurora electric vehicles',
          words: ['aurora', 'electric', 'vehicles'],
          metadata: {'engine': 'mock_mlkit'},
        ),
      );

      final signatureService = SignatureService(
        visionService: visionService,
        ocrEngine: mockOcr,
      );

      final signature = await signatureService.generateSignature(creativeBBytes);

      final campaign = Campaign(
        id: 'camp-aurora-ocr-001',
        ownerAccountId: 'advertiser-01',
        adName: 'AURORA EV',
        brandName: 'Aurora Motors',
        destinationUrl: 'https://aurora.example.com',
        creativeBytes: creativeBBytes,
        status: CampaignStatus.active,
        createdAt: DateTime.now(),
        recognitionSignature: signature,
        signatureVersion: signature.version,
      );

      repo.addCampaign(campaign);

      // Retrieve from repository and verify OCR signature persistence
      final storedCampaign = repo.getCampaign('camp-aurora-ocr-001');
      expect(storedCampaign, isNotNull);
      expect(storedCampaign!.recognitionSignature, isNotNull);
      expect(storedCampaign.recognitionSignature!.hasOcrText, isTrue);
      expect(storedCampaign.recognitionSignature!.normalizedOcrText, 'aurora electric vehicles');
      expect(storedCampaign.recognitionSignature!.ocrText, 'AURORA ELECTRIC VEHICLES');
      expect(storedCampaign.recognitionSignature!.perceptualFeatures.length, 192);

      // Convert to AdTarget for live matching
      final adTarget = storedCampaign.toAdTarget();
      expect(adTarget.embedding.length, 192);
      expect(adTarget.name, 'AURORA EV');
    });

    testWidgets('5b. CreateCampaignScreen UI stores OCR-enhanced signature on creative upload', (tester) async {
      final repo = CampaignRepository();
      repo.reset();

      final mockOcr = MockOcrEngine(
        resultToReturn: const OcrResult(
          rawText: 'STUDIO NOIR DESIGN',
          normalizedText: 'studio noir design',
          words: ['studio', 'noir', 'design'],
        ),
      );

      final signatureService = SignatureService(
        visionService: visionService,
        ocrEngine: mockOcr,
      );

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

      await tester.enterText(find.widgetWithText(TextFormField, 'ENTER AD NAME'), 'STUDIO NOIR OCR');
      await tester.enterText(find.widgetWithText(TextFormField, 'ENTER BRAND OR CREATOR'), 'Studio Noir');
      await tester.enterText(find.widgetWithText(TextFormField, 'ENTER DESTINATION URL'), 'https://studionoir.example.com');
      await tester.pump();

      // Confirm creative
      await tester.tap(find.text('USE THIS AD'));
      await tester.pumpAndSettle();

      // Submit
      await tester.tap(find.text('CREATE AD'));
      await tester.pump();

      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(find.text('AD READY'), findsOneWidget);
      expect(repo.campaigns.length, 1);

      final created = repo.campaigns.first;
      expect(created.adName, 'STUDIO NOIR OCR');
      expect(created.recognitionSignature, isNotNull);
      expect(created.recognitionSignature!.hasOcrText, isTrue);
      expect(created.recognitionSignature!.normalizedOcrText, 'studio noir design');
      expect(created.recognitionSignature!.perceptualFeatures.length, 192);
    });

    test('6. Existing STUDIO NOIR baseline campaign in CampaignRepository retains valid signature and recognition', () async {
      final repo = CampaignRepository();
      await repo.initialize();

      final studioNoir = repo.getCampaign(CampaignRepository.systemDemoCampaignId);
      expect(studioNoir, isNotNull);
      expect(studioNoir!.recognitionSignature, isNotNull);
      expect(studioNoir.recognitionSignature!.isValid, isTrue);
      expect(studioNoir.recognitionSignature!.perceptualFeatures.length, 192);

      // Verify conversion to active AdTarget
      final activeTargets = repo.getActiveAdTargets();
      expect(activeTargets.any((t) => t.id == CampaignRepository.systemDemoCampaignId), isTrue);
    });

    test('7. Multi-campaign recognition invariance: Two distinct campaigns retain independent signatures', () async {
      final mockOcrNoir = MockOcrEngine(
        resultToReturn: const OcrResult(
          rawText: 'STUDIO NOIR',
          normalizedText: 'studio noir',
          words: ['studio', 'noir'],
        ),
      );

      final mockOcrAurora = MockOcrEngine(
        resultToReturn: const OcrResult(
          rawText: 'AURORA VISION',
          normalizedText: 'aurora vision',
          words: ['aurora', 'vision'],
        ),
      );

      final serviceNoir = SignatureService(
        visionService: visionService,
        ocrEngine: mockOcrNoir,
      );
      final serviceAurora = SignatureService(
        visionService: visionService,
        ocrEngine: mockOcrAurora,
      );

      final sigA = await serviceNoir.generateSignature(creativeABytes);
      final sigB = await serviceAurora.generateSignature(creativeBBytes);

      // Both have distinct OCR and visual signatures
      expect(sigA.normalizedOcrText, 'studio noir');
      expect(sigB.normalizedOcrText, 'aurora vision');

      final targetA = AdTarget(
        id: 'camp_a',
        name: 'STUDIO NOIR',
        brand: 'Studio Noir',
        destinationUrl: 'https://example.com/a',
        imageAsset: '',
        embedding: sigA.primaryFeatures,
      );
      final targetB = AdTarget(
        id: 'camp_b',
        name: 'AURORA VISION',
        brand: 'Aurora',
        destinationUrl: 'https://example.com/b',
        imageAsset: '',
        embedding: sigB.primaryFeatures,
      );

      final engine = const MatchingEngine(threshold: 0.70);

      // Matching target A against query A
      final matchA = engine.findBestMatch(sigA.primaryFeatures, [targetA, targetB]);
      expect(matchA?.target.id, 'camp_a');
      expect(matchA?.similarity, greaterThan(0.95));

      // Matching target B against query B
      final matchB = engine.findBestMatch(sigB.primaryFeatures, [targetA, targetB]);
      expect(matchB?.target.id, 'camp_b');
      expect(matchB?.similarity, greaterThan(0.95));

      // Cross similarity is distinct and significantly lower
      final crossSim = MatchingEngine.cosineSimilarity(sigA.primaryFeatures, sigB.primaryFeatures);
      expect(crossSim, lessThan(0.70));
    });
  });
}
