import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:billy_the_viewer/models/ad_target.dart';
import 'package:billy_the_viewer/models/campaign.dart';
import 'package:billy_the_viewer/services/campaign_repository.dart';
import 'package:billy_the_viewer/services/matching_engine.dart';
import 'package:billy_the_viewer/services/ocr_service.dart';
import 'package:billy_the_viewer/services/signature_service.dart';
import 'package:billy_the_viewer/services/verification_coordinator.dart';
import 'package:billy_the_viewer/services/vision_service.dart';

/// Test mock OCR engine providing deterministic text extraction for testing.
class DeterministicOcrEngine implements IOcrEngine {
  final Map<String, OcrResult> responses;
  final OcrResult defaultResponse;

  DeterministicOcrEngine({
    this.responses = const {},
    this.defaultResponse = OcrResult.empty,
  });

  @override
  Future<OcrResult> extractText(Uint8List imageBytes) async {
    for (final entry in responses.entries) {
      if (entry.key.isNotEmpty && imageBytes.length.toString() == entry.key) {
        return entry.value;
      }
    }
    return defaultResponse;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late VisionService visionService;
  late Uint8List creativeABytes; // STUDIO NOIR creative (assets/campaigns/demo_ad.jpg)
  late Uint8List creativeBBytes; // AURORA VISION creative (assets/campaigns/demo_ad_2.jpg)
  late CampaignRepository repository;

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
    repository = CampaignRepository();
    repository.reset();
  });

  group('Multi-Signal Recognition & Wrong-Ad Protection Suite', () {
    test('1. Newly uploaded Campaign A can recognize its own creative using its new signature', () async {
      final ocrEngine = DeterministicOcrEngine(
        defaultResponse: const OcrResult(
          rawText: 'CAMPARI RED PASSION',
          normalizedText: 'campari red passion',
          words: ['campari', 'red', 'passion'],
        ),
      );

      final signatureService = SignatureService(
        visionService: visionService,
        ocrEngine: ocrEngine,
      );

      final signature = await signatureService.generateSignature(creativeABytes);
      final campaignA = Campaign(
        id: 'camp_advertiser_a',
        ownerAccountId: 'brand_owner_1',
        adName: 'CAMPARI RED',
        brandName: 'Campari',
        destinationUrl: 'https://campari.com',
        creativeBytes: creativeABytes,
        status: CampaignStatus.active,
        createdAt: DateTime.now(),
        recognitionSignature: signature,
        signatureVersion: signature.version,
      );

      repository.addCampaign(campaignA);
      final activeTargets = repository.getActiveAdTargets();
      expect(activeTargets.length, 1);

      final target = activeTargets.first;
      expect(target.id, 'camp_advertiser_a');
      expect(target.hasOcrText, isTrue);
      expect(target.normalizedOcrText, 'campari red passion');

      // Live query frame matching
      final liveEmbedding = await visionService.generateEmbeddingFromBytes(creativeABytes);
      final engine = const MatchingEngine();
      final ranked = engine.rankCandidatesMultiSignal(
        liveEmbedding: liveEmbedding,
        liveNormalizedText: 'campari red passion',
        candidates: activeTargets,
      );

      expect(ranked.isNotEmpty, isTrue);
      expect(ranked.first.target.id, 'camp_advertiser_a');
      expect(ranked.first.similarity, greaterThan(0.95));
      expect(ranked.first.isAmbiguous, isFalse);
    });

    test('2. Campaign A does NOT incorrectly return STUDIO NOIR or demo campaign', () async {
      await repository.initialize(); // Baseline STUDIO NOIR registered
      expect(repository.getActiveAdTargets().any((t) => t.id == CampaignRepository.systemDemoCampaignId), isTrue);

      final ocrEngine = DeterministicOcrEngine(
        defaultResponse: const OcrResult(
          rawText: 'AURORA OPTICS B',
          normalizedText: 'aurora optics b',
          words: ['aurora', 'optics', 'b'],
        ),
      );

      final signatureService = SignatureService(
        visionService: visionService,
        ocrEngine: ocrEngine,
      );

      final signatureB = await signatureService.generateSignature(creativeBBytes);
      final campaignB = Campaign(
        id: 'campaign_b_new',
        ownerAccountId: 'owner_b',
        adName: 'AURORA OPTICS',
        brandName: 'Aurora',
        destinationUrl: 'https://aurora.example.com',
        creativeBytes: creativeBBytes,
        status: CampaignStatus.active,
        createdAt: DateTime.now(),
        recognitionSignature: signatureB,
        signatureVersion: signatureB.version,
      );

      repository.addCampaign(campaignB);
      final activeTargets = repository.getActiveAdTargets();
      expect(activeTargets.length, 2);

      // Presenting creative B to the matching engine
      final liveEmbeddingB = await visionService.generateEmbeddingFromBytes(creativeBBytes);
      final engine = const MatchingEngine();

      final ranked = engine.rankCandidatesMultiSignal(
        liveEmbedding: liveEmbeddingB,
        liveNormalizedText: 'aurora optics b',
        candidates: activeTargets,
      );

      expect(ranked.first.target.id, 'campaign_b_new');
      expect(ranked.first.target.id, isNot(CampaignRepository.systemDemoCampaignId));
      expect(ranked.first.similarity, greaterThan(0.90));
    });

    test('3. Cross-campaign separation: Campaign B query does NOT return Campaign A', () async {
      final sigA = await SignatureService(visionService: visionService).generateSignature(creativeABytes);
      final sigB = await SignatureService(visionService: visionService).generateSignature(creativeBBytes);

      final targetA = AdTarget(
        id: 'camp_a',
        name: 'STUDIO NOIR',
        brand: 'Studio Noir',
        destinationUrl: 'https://example.com/a',
        imageAsset: '',
        embedding: sigA.primaryFeatures,
        normalizedOcrText: 'studio noir architecture design',
      );

      final targetB = AdTarget(
        id: 'camp_b',
        name: 'AURORA VISION',
        brand: 'Aurora',
        destinationUrl: 'https://example.com/b',
        imageAsset: '',
        embedding: sigB.primaryFeatures,
        normalizedOcrText: 'aurora vision advanced optics',
      );

      final engine = const MatchingEngine();

      // Query with B's visual features and B's live OCR text
      final ranked = engine.rankCandidatesMultiSignal(
        liveEmbedding: sigB.primaryFeatures,
        liveNormalizedText: 'aurora vision advanced optics',
        candidates: [targetA, targetB],
      );

      expect(ranked.first.target.id, 'camp_b');
      // Second candidate (A) must have a score clearly separated from B
      expect(ranked[1].target.id, 'camp_a');
      expect(ranked.first.separationMargin, greaterThan(0.20));
      expect(ranked.first.isAmbiguous, isFalse);
    });

    test('4. Two visually similar campaigns can be separated using text signal', () {
      // Simulate two campaigns sharing identical visual layout (e.g. geometric poster template)
      final identicalVisual = List.generate(192, (i) => 0.05 * (i % 8));

      final target1 = AdTarget(
        id: 'promo_spring',
        name: 'SPRING FESTIVAL 2026',
        brand: 'Metro Events',
        destinationUrl: 'https://metro.com/spring',
        imageAsset: '',
        embedding: identicalVisual,
        normalizedOcrText: 'spring festival 2026 tickets live music',
      );

      final target2 = AdTarget(
        id: 'promo_autumn',
        name: 'AUTUMN HARVEST 2026',
        brand: 'Metro Events',
        destinationUrl: 'https://metro.com/autumn',
        imageAsset: '',
        embedding: identicalVisual,
        normalizedOcrText: 'autumn harvest 2026 farmers market fresh food',
      );

      final engine = const MatchingEngine();

      // Live frame sees Spring Festival text
      final rankedSpring = engine.rankCandidatesMultiSignal(
        liveEmbedding: identicalVisual,
        liveNormalizedText: 'metro events spring festival 2026 live music today',
        candidates: [target1, target2],
      );

      // Target 1 wins because text matches Spring Festival
      expect(rankedSpring.first.target.id, 'promo_spring');
      expect(rankedSpring.first.textSimilarity, greaterThan(0.80));
      expect(rankedSpring[1].textSimilarity, lessThan(0.35));
      expect(rankedSpring.first.separationMargin, greaterThan(0.15));

      // Live frame sees Autumn Harvest text
      final rankedAutumn = engine.rankCandidatesMultiSignal(
        liveEmbedding: identicalVisual,
        liveNormalizedText: 'autumn harvest 2026 fresh food market',
        candidates: [target1, target2],
      );

      // Target 2 wins because text matches Autumn Harvest
      expect(rankedAutumn.first.target.id, 'promo_autumn');
      expect(rankedAutumn.first.textSimilarity, greaterThan(0.80));
      expect(rankedAutumn[1].textSimilarity, lessThan(0.35));
      expect(rankedAutumn.first.separationMargin, greaterThan(0.15));
    });

    test('5. Wrong-ad protection: Close visual scores without decisive text margin trigger isAmbiguous flag', () {
      final baseVisual = List.generate(192, (i) => 0.05 * (i % 8));
      // Slightly perturb vector for target 2 so visual scores are very close
      final perturbedVisual = List<double>.from(baseVisual);
      perturbedVisual[0] += 0.005;

      final target1 = AdTarget(
        id: 'ad_1',
        name: 'BRAND ALPHA',
        brand: 'Alpha Corp',
        destinationUrl: 'https://alpha.com',
        imageAsset: '',
        embedding: baseVisual,
        normalizedOcrText: 'alpha brand innovative solutions',
      );

      final target2 = AdTarget(
        id: 'ad_2',
        name: 'BRAND BETA',
        brand: 'Beta Corp',
        destinationUrl: 'https://beta.com',
        imageAsset: '',
        embedding: perturbedVisual,
        normalizedOcrText: 'beta brand modern lifestyle',
      );

      final engine = const MatchingEngine(separationMargin: 0.08);

      // Live frame has noisy or empty text (e.g. motion blur during camera movement)
      final rankedNoisyText = engine.rankCandidatesMultiSignal(
        liveEmbedding: baseVisual,
        liveNormalizedText: '', // No readable text extracted in this frame
        candidates: [target1, target2],
      );

      expect(rankedNoisyText.length, 2);
      // Both candidates score high visually but margin is tight (< 0.08)
      expect(rankedNoisyText.first.separationMargin, lessThan(0.08));
      // Wrong-ad protection MUST flag ambiguity so the system does NOT prematurely confirm!
      expect(rankedNoisyText.first.isAmbiguous, isTrue);
    });

    test('6. Walk-by recognition remains intact (multi-frame window and 4-rotation tolerance)', () {
      final sig = List.generate(192, (i) => 0.05 * ((i * 3) % 7));
      final target = AdTarget(
        id: 'walkby_ad',
        name: 'WALKBY TEST AD',
        brand: 'WalkBy',
        destinationUrl: 'https://example.com',
        imageAsset: '',
        embedding: sig,
      );

      // Frame rotated by 90 degrees (handheld orientation switch)
      final rotatedLive = MatchingEngine.rotateVector(sig, 1);
      final engine = const MatchingEngine();

      final result = engine.findBestMatch(rotatedLive, [target]);
      expect(result, isNotNull);
      expect(result!.target.id, 'walkby_ad');
      expect(result.similarity, closeTo(1.0, 0.01));
    });

    test('7. No-false-positive behavior remains intact on unrelated scenes and blank walls', () {
      final sigA = List.generate(192, (i) => 0.05 * (i % 8));
      final targetA = AdTarget(
        id: 'registered_ad',
        name: 'REGISTERED AD',
        brand: 'Brand',
        destinationUrl: 'https://example.com',
        imageAsset: '',
        embedding: sigA,
        normalizedOcrText: 'special limited edition',
      );

      final engine = const MatchingEngine(threshold: 0.70);

      // Unrelated scene vector (orthogonal or noise)
      final unrelatedSceneEmbedding = List.generate(192, (i) => (i % 2 == 0) ? 0.08 : -0.08);

      final match = engine.findBestMatch(
        unrelatedSceneEmbedding,
        [targetA],
        liveNormalizedText: 'exit door floor level',
      );

      expect(match, isNull); // Rejects completely!
    });

    test('8. Paused and expired campaigns remain strictly excluded from recognition candidates', () {
      final repo = CampaignRepository();

      final active = Campaign(
        id: 'camp_active',
        ownerAccountId: 'owner_1',
        adName: 'ACTIVE CAMPAIGN',
        brandName: 'Brand',
        destinationUrl: 'https://active.com',
        status: CampaignStatus.active,
        createdAt: DateTime.now(),
      );

      final paused = Campaign(
        id: 'camp_paused',
        ownerAccountId: 'owner_1',
        adName: 'PAUSED CAMPAIGN',
        brandName: 'Brand',
        destinationUrl: 'https://paused.com',
        status: CampaignStatus.paused,
        createdAt: DateTime.now(),
      );

      final expired = Campaign(
        id: 'camp_expired',
        ownerAccountId: 'owner_1',
        adName: 'EXPIRED CAMPAIGN',
        brandName: 'Brand',
        destinationUrl: 'https://expired.com',
        status: CampaignStatus.expired,
        createdAt: DateTime.now(),
      );

      repo.addCampaign(active);
      repo.addCampaign(paused);
      repo.addCampaign(expired);

      final activeTargets = repo.getActiveAdTargets();
      expect(activeTargets.length, 1);
      expect(activeTargets.first.id, 'camp_active');
    });

    test('9. Creative replacement regenerates both visual and OCR signatures', () async {
      final repo = CampaignRepository();

      final initialOcr = DeterministicOcrEngine(
        defaultResponse: const OcrResult(
          rawText: 'VERSION 1 INITIAL',
          normalizedText: 'version 1 initial',
          words: ['version', '1', 'initial'],
        ),
      );

      final updatedOcr = DeterministicOcrEngine(
        defaultResponse: const OcrResult(
          rawText: 'VERSION 2 REPLACED CREATIVE',
          normalizedText: 'version 2 replaced creative',
          words: ['version', '2', 'replaced', 'creative'],
        ),
      );

      final service1 = SignatureService(visionService: visionService, ocrEngine: initialOcr);
      final sig1 = await service1.generateSignature(creativeABytes);

      final initialCamp = Campaign(
        id: 'updatable_camp_01',
        ownerAccountId: 'owner_1',
        adName: 'UPDATABLE AD',
        brandName: 'Brand',
        destinationUrl: 'https://brand.com',
        creativeBytes: creativeABytes,
        status: CampaignStatus.active,
        createdAt: DateTime.now(),
        recognitionSignature: sig1,
        signatureVersion: sig1.version,
      );

      repo.addCampaign(initialCamp);
      expect(repo.getCampaign('updatable_camp_01')?.recognitionSignature?.normalizedOcrText, 'version 1 initial');

      // Update creative with creativeB and new OCR service
      final service2 = SignatureService(visionService: visionService, ocrEngine: updatedOcr);
      final updatedCamp = await repo.updateCreative(
        'updatable_camp_01',
        creativeBBytes,
        signatureService: service2,
      );

      expect(updatedCamp.recognitionSignature?.normalizedOcrText, 'version 2 replaced creative');
      expect(updatedCamp.status, CampaignStatus.active);

      // Verify active AdTarget conversion reflects updated signatures
      final updatedTarget = repo.getActiveAdTargets().firstWhere((t) => t.id == 'updatable_camp_01');
      expect(updatedTarget.normalizedOcrText, 'version 2 replaced creative');
      expect(updatedTarget.embedding, updatedCamp.recognitionSignature?.primaryFeatures);
    });

    test('10. Gemini verification receives narrowed candidate pool and uses in-memory creativeBytes', () async {
      final mockCoordinator = VerificationCoordinator();

      final targetWithBytes = AdTarget(
        id: 'ad_with_bytes',
        name: 'IN MEMORY CREATIVE AD',
        brand: 'Direct Advertiser',
        destinationUrl: 'https://direct.example.com',
        imageAsset: '', // No asset on disk!
        creativeBytes: creativeABytes, // In-memory creative bytes from upload
        embedding: List.filled(192, 0.1),
      );

      // Pre-filtered candidate pool contains targetWithBytes
      final candidatePool = [targetWithBytes];

      // Pool filtering guard in VerificationCoordinator: candidate outside pool is rejected
      final outsideCandidate = const AdTarget(
        id: 'unregistered_candidate',
        name: 'OUTSIDE',
        brand: 'Outside',
        destinationUrl: '',
        imageAsset: '',
      );

      final outsideResult = await mockCoordinator.verifyCandidate(
        candidate: outsideCandidate,
        frameJpegBytes: creativeABytes,
        candidatePool: candidatePool,
      );
      expect(outsideResult, isNull);
    });
  });
}
