import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:url_launcher/url_launcher.dart';
import 'package:billy_the_viewer/app/theme.dart';
import 'package:billy_the_viewer/models/ad_target.dart';
import 'package:billy_the_viewer/screens/account_screen.dart';
import 'package:billy_the_viewer/screens/create_campaign_screen.dart';
import 'package:billy_the_viewer/screens/inline_camera_view.dart';
import 'package:billy_the_viewer/screens/rewards_screen.dart';
import 'package:billy_the_viewer/services/account_session.dart';
import 'package:billy_the_viewer/services/camera_service.dart';
import 'package:billy_the_viewer/services/campaign_repository.dart';
import 'package:billy_the_viewer/services/context_engine.dart';
import 'package:billy_the_viewer/services/matching_engine.dart';
import 'package:billy_the_viewer/services/ocr_service.dart';
import 'package:billy_the_viewer/services/verification_coordinator.dart';
import 'package:billy_the_viewer/services/multi_scale_photo_analyzer.dart';
import 'package:billy_the_viewer/services/vision_service.dart';
import 'package:billy_the_viewer/widgets/billy_button.dart';

/// Phase 4/11 HomeScreen:
/// Connects CameraService → VisionService → ContextEngine → MatchingEngine → VerificationCoordinator → Discovery Result UI.
class HomeScreen extends StatefulWidget {
  final CameraService? cameraService;
  final VisionService? visionService;
  final MatchingEngine? matchingEngine;
  final ContextEngine? contextEngine;
  final VerificationCoordinator? verificationCoordinator;
  final OcrService? ocrService;
  final SensorContext? initialSensorContext;
  final List<AdTarget>? initialCampaigns;
  final AccountSession? accountSession;
  final ScanMode? initialScanMode;

  const HomeScreen({
    super.key,
    this.cameraService,
    this.visionService,
    this.matchingEngine,
    this.contextEngine,
    this.verificationCoordinator,
    this.ocrService,
    this.initialSensorContext,
    this.initialCampaigns,
    this.accountSession,
    this.initialScanMode,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late final CameraService _cameraService;
  late final VisionService _visionService;
  late final MatchingEngine _matchingEngine;
  late final AccountSession _accountSession;
  late final ContextEngine _contextEngine;
  late final VerificationCoordinator _verificationCoordinator;
  late final OcrService _ocrService;

  SensorContext _sensorContext = const SensorContext();
  ContextClassification? _currentClassification;

  bool _isCameraActive = false;
  ScanMode _scanMode = ScanMode.photo;
  RecognitionState _recognitionState = RecognitionState.looking;
  MatchResult? _confirmedMatch;

  List<AdTarget> _campaigns = [];
  bool _campaignsReady = false;
  bool _isProcessingFrame = false;
  DateTime _lastProcessedTime = DateTime.fromMillisecondsSinceEpoch(0);

  // Live similarity score seen during scanning
  double _liveSimilarity = 0.0;

  // Throttled on-device OCR state (~450ms single-flight)
  String _latestLiveOcrText = '';
  DateTime _lastOcrProcessedTime = DateTime.fromMillisecondsSinceEpoch(0);
  bool _isOcrInFlight = false;
  static const Duration _ocrThrottleDuration = Duration(milliseconds: 450);

  // Rolling confidence window for movement-resilient match confirmation
  static const int _rollingWindowSize = 8;
  final List<MatchResult?> _recentFrameMatches = [];

  // Distance diagnostic session counter
  int _distanceTestCounter = 0;

  // Threshold optimized for handheld movement separation:
  // True ads score 0.88-0.96; unrelated scenes score <= 0.18.
  static const double _perceptualThreshold = 0.60;
  // High-rate frame inspection: 120ms (~8 FPS) catches sharp moments between hand shakes
  static const Duration _frameThrottleDuration = Duration(milliseconds: 120);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cameraService = widget.cameraService ?? CameraService();
    _visionService = widget.visionService ?? VisionService();
    _matchingEngine = widget.matchingEngine ?? const MatchingEngine(threshold: _perceptualThreshold);
    _accountSession = widget.accountSession ?? AccountSession();
    _contextEngine = widget.contextEngine ?? const ContextEngine();
    _verificationCoordinator = widget.verificationCoordinator ?? VerificationCoordinator();
    _ocrService = widget.ocrService ?? OcrService();
    _sensorContext = widget.initialSensorContext ?? const SensorContext();
    _scanMode = widget.initialScanMode ?? ScanMode.photo;

    _initServices();
  }

  Future<void> _initServices() async {
    try {
      if (!_visionService.isInitialized) {
        await _visionService.initialize();
      }
    } catch (e) {
      debugPrint('HomeScreen: Error initializing vision service: $e');
    }

    // Single source of truth for campaign lifecycle:
    // Only currently active campaigns are provided to the matching engine.
    List<AdTarget> embeddedCampaigns = [];

    if (widget.initialCampaigns != null) {
      embeddedCampaigns = widget.initialCampaigns!;
    } else {
      final repository = CampaignRepository();
      if (!repository.isInitialized) {
        await repository.initialize();
      }
      embeddedCampaigns = repository.getActiveAdTargets();
    }

    if (mounted) {
      setState(() {
        _campaigns = embeddedCampaigns;
        _campaignsReady = true;
        _currentClassification = _contextEngine.classify(
          context: _sensorContext,
          registeredTargets: _campaigns,
        );
      });
    }

    debugPrint('Billy: ${_campaigns.length} active campaign(s) ready for matching.');
  }

  Future<void> _navigateToRewards() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RewardsScreen(
          accountSession: _accountSession,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _navigateToCreateAd() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CreateCampaignScreen(
          accountSession: _accountSession,
          ownerAccountId: _accountSession.currentAccount?.id,
        ),
      ),
    );
    _syncCampaigns();
    if (mounted) setState(() {});
  }

  Future<void> _navigateToAccount() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AccountScreen(
          accountSession: _accountSession,
        ),
      ),
    );
    _syncCampaigns();
    if (mounted) setState(() {});
  }

  void _syncCampaigns() {
    if (widget.initialCampaigns != null) return;
    final activeTargets = CampaignRepository().getActiveAdTargets();
    if (mounted) {
      setState(() {
        _campaigns = activeTargets;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraService.dispose();
    _visionService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isCameraActive) return;

    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _cameraService.stopImageStream();
      _cameraService.dispose().then((_) {
        if (mounted) setState(() {});
      });
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    final status = await _cameraService.initialize();
    if (mounted) {
      setState(() {});
    }

    if (status == CameraStateStatus.ready) {
      if (_scanMode == ScanMode.live) {
        _startFrameProcessing();
      }
    }
  }

  void _startFrameProcessing() {
    if (_cameraService.controller == null || !_cameraService.isReady) return;

    _cameraService.startImageStream((CameraImage image) {
      _onCameraFrame(image);
    });
  }

  void _onCameraFrame(CameraImage image) async {
    // Guards
    if (_isProcessingFrame ||
        _recognitionState == RecognitionState.recognized ||
        !_isCameraActive ||
        !_campaignsReady ||
        _campaigns.isEmpty) {
      return;
    }

    // Throttle: 120ms (~8 FPS) allows capturing sharp frames during handheld movement
    final now = DateTime.now();
    if (now.difference(_lastProcessedTime) < _frameThrottleDuration) {
      return;
    }

    _isProcessingFrame = true;
    _lastProcessedTime = now;

    try {
      final embedding = await _visionService.generateEmbeddingFromCameraImage(image);

      // Fast optical ambient & contrast estimation from camera luminance plane
      if (image.planes.isNotEmpty) {
        final bytes = image.planes[0].bytes;
        if (bytes.isNotEmpty) {
          double lumSum = 0.0;
          final step = math.max(1, bytes.length ~/ 128);
          int count = 0;
          for (int i = 0; i < bytes.length; i += step) {
            lumSum += bytes[i];
            count++;
          }
          final avgLum = count > 0 ? (lumSum / count) / 255.0 : 0.5;

          _sensorContext = SensorContext(
            devicePitchDegrees: _sensorContext.devicePitchDegrees,
            ambientLuminance: avgLum,
            contrastRatio: _sensorContext.contrastRatio,
            userLatitude: _sensorContext.userLatitude,
            userLongitude: _sensorContext.userLongitude,
          );
        }
      }

      // Context-aware candidate filtering and ranking
      final candidateTargets = _contextEngine.filterAndRankCandidates(
        allTargets: _campaigns,
        context: _sensorContext,
      );
      _currentClassification = _contextEngine.classify(
        context: _sensorContext,
        registeredTargets: _campaigns,
      );

      if (embedding.isNotEmpty) {
        double bestSim = 0.0;
        for (final c in candidateTargets) {
          if (c.embedding.isNotEmpty) {
            final sim = MatchingEngine.maxSimilarityAcrossRotations(c.embedding, embedding);
            if (sim > bestSim) bestSim = sim;
          }
        }

        // Throttled live OCR trigger:
        // Only run OCR when:
        // - At least one candidate has plausible visual similarity (>= plausibleThreshold)
        // - OCR is not already in flight (single-flight guard)
        // - Sufficient time elapsed since last OCR run (_ocrThrottleDuration)
        final now = DateTime.now();
        if (bestSim >= _matchingEngine.plausibleThreshold &&
            !_isOcrInFlight &&
            now.difference(_lastOcrProcessedTime) >= _ocrThrottleDuration) {
          _triggerThrottledLiveOcr(image);
        }

        // Multi-signal candidate ranking combining visual spatial features + live OCR text
        final ranked = _matchingEngine.rankCandidatesMultiSignal(
          liveEmbedding: embedding,
          liveNormalizedText: _latestLiveOcrText,
          candidates: candidateTargets,
        );

        final match = ranked.isNotEmpty ? ranked.first : null;
        final displaySim = match?.similarity ?? bestSim;

        if (mounted) {
          setState(() {
            _liveSimilarity = displaySim;
          });
        }

        _recordFrameMatch(match);
        _evaluateConfidenceWindow(image, candidateTargets);
      } else {
        // Frame failed quality checks (too dark, overexposed, or uniform scene/wall)
        _recordFrameMatch(null);
        if (mounted) {
          setState(() {
            _liveSimilarity = 0.0;
          });
        }
        _evaluateConfidenceWindow(image, candidateTargets);
      }
    } catch (e) {
      debugPrint('HomeScreen: Error processing camera frame: $e');
    } finally {
      _isProcessingFrame = false;
    }
  }

  /// Asynchronously runs live OCR on the current camera frame without blocking the frame loop.
  void _triggerThrottledLiveOcr(CameraImage image) async {
    if (_isOcrInFlight) return;
    _isOcrInFlight = true;
    _lastOcrProcessedTime = DateTime.now();

    try {
      final frameJpeg = VisionService.convertCameraImageToJpeg(image);
      final result = await _ocrService.extractText(frameJpeg);
      if (result.hasText) {
        _latestLiveOcrText = result.normalizedText;
      }
    } catch (e) {
      debugPrint('HomeScreen: Throttled live OCR warning: $e');
    } finally {
      _isOcrInFlight = false;
    }
  }

  void _recordFrameMatch(MatchResult? match) {
    _recentFrameMatches.add(match);
    if (_recentFrameMatches.length > _rollingWindowSize) {
      _recentFrameMatches.removeAt(0);
    }
  }

  void _evaluateConfidenceWindow(CameraImage image, List<AdTarget> candidatePool) {
    MatchResult? confirmed;
    String? bestCandidateTargetId;
    int maxHits = 0;

    // Evaluate candidate target hit frequency across recent frames in the window
    final candidates = _recentFrameMatches.whereType<MatchResult>().toList();
    for (final m in candidates) {
      final targetId = m.target.id;
      final hits = candidates
          .where((item) => item.target.id == targetId)
          .toList();

      if (hits.length > maxHits) {
        maxHits = hits.length;
        bestCandidateTargetId = targetId;
      }

      hits.sort((a, b) => b.similarity.compareTo(a.similarity));
      final highestSim = hits.first.similarity;

      // Dynamic Two-Tier Movement & Wrong-Ad Resilient Confirmation:
      // Multi-Signal Crisp Hit: combined similarity >= crispCombinedThreshold (0.82)
      //                         AND unambiguous (candidate margin >= 0.08) confirms immediately!
      final isCrispHit = highestSim >= _matchingEngine.crispCombinedThreshold && !hits.first.isAmbiguous;

      // Tier 2 Dual / Motion Hit / Ambiguous candidate resolution:
      // - Dual Hit: >= 2 hits with similarity >= 0.65 within rolling window.
      // - Sustained Motion Hit: >= 3 hits with similarity >= 0.58 within rolling window.
      // - Ambiguous High Hit: high similarity but close competing candidate -> route to Gemini to break tie!
      final isDualHit = hits.length >= 2 && highestSim >= 0.65;
      final isSustainedMotionHit = hits.length >= 3 && hits.every((h) => h.similarity >= 0.58);
      final isAmbiguousHighHit = highestSim >= _matchingEngine.crispCombinedThreshold && hits.first.isAmbiguous;

      if (isCrispHit) {
        confirmed = hits.first;
        break;
      } else if (isDualHit || isSustainedMotionHit || isAmbiguousHighHit) {
        final candidateTarget = hits.first.target;

        // In-session cache check (10s TTL):
        if (_verificationCoordinator.isRecentlyConfirmed(candidateTarget.id)) {
          confirmed = hits.first;
          break;
        }

        // Show optimistic "possible match" / verifying state without freezing the camera stream
        if (mounted && _recognitionState != RecognitionState.confirming) {
          setState(() {
            _recognitionState = RecognitionState.confirming;
          });
        }

        // Trigger ONE async Gemini verification call (single-flight enforced inside coordinator)
        if (!_verificationCoordinator.isInFlight) {
          final frameJpeg = VisionService.convertCameraImageToJpeg(image);
          _triggerAsyncGeminiVerification(
            candidate: candidateTarget,
            frameJpeg: frameJpeg,
            candidatePool: candidatePool,
          );
        }
      }
    }

    if (confirmed != null) {
      debugPrint(
        'Billy Recognition: CONFIRMED MATCH ($maxHits/$_rollingWindowSize frames in window) → '
        '${confirmed.target.name} (similarity: ${confirmed.similarity.toStringAsFixed(3)})',
      );
      if (mounted) {
        setState(() {
          _recognitionState = RecognitionState.recognized;
          _confirmedMatch = confirmed;
        });
        _cameraService.stopImageStream();
      }
    } else if (maxHits > 0) {
      debugPrint(
        'Billy Recognition: ACCUMULATING CONFIDENCE ($maxHits/$_rollingWindowSize frames in window) → '
        'Target ID $bestCandidateTargetId',
      );
      if (mounted && _recognitionState != RecognitionState.confirming) {
        setState(() {
          _recognitionState = RecognitionState.confirming;
        });
      }
    } else {
      if (mounted && _recognitionState == RecognitionState.confirming && !_verificationCoordinator.isInFlight) {
        setState(() {
          _recognitionState = RecognitionState.looking;
        });
      }
    }
  }

  void _triggerAsyncGeminiVerification({
    required AdTarget candidate,
    required Uint8List frameJpeg,
    required List<AdTarget> candidatePool,
  }) async {
    final result = await _verificationCoordinator.verifyCandidate(
      candidate: candidate,
      frameJpegBytes: frameJpeg,
      candidatePool: candidatePool,
    );

    if (!mounted || !_isCameraActive || _recognitionState == RecognitionState.recognized) {
      return;
    }

    if (result != null) {
      debugPrint('Billy Recognition: GEMINI ASYNC VERIFIED → ${result.target.name}');
      setState(() {
        _recognitionState = RecognitionState.recognized;
        _confirmedMatch = result;
      });
      _cameraService.stopImageStream();
    } else {
      debugPrint('Billy Recognition: Gemini verification returned negative or failed.');
      if (_recognitionState == RecognitionState.confirming) {
        setState(() {
          _recognitionState = RecognitionState.looking;
        });
      }
    }
  }

  void _openCamera() {
    _syncCampaigns();
    _currentClassification = _contextEngine.classify(
      context: _sensorContext,
      registeredTargets: _campaigns,
    );
    setState(() {
      _isCameraActive = true;
      _recognitionState = RecognitionState.looking;
      _confirmedMatch = null;
      _liveSimilarity = 0.0;
      _recentFrameMatches.clear();
      if (widget.initialScanMode != null) {
        _scanMode = widget.initialScanMode!;
      }
    });
    _initializeCamera();
  }

  void _closeCamera() {
    setState(() {
      _isCameraActive = false;
      _recognitionState = RecognitionState.looking;
      _confirmedMatch = null;
      _liveSimilarity = 0.0;
      _recentFrameMatches.clear();
    });
    _cameraService.dispose();
  }

  void _onRetake() {
    setState(() {
      _recognitionState = RecognitionState.looking;
      _confirmedMatch = null;
      _liveSimilarity = 0.0;
      _recentFrameMatches.clear();
    });
    if (_scanMode == ScanMode.live) {
      _startFrameProcessing();
    }
  }

  void _scanAgain() {
    _onRetake();
  }

  /// Deliberate, high-accuracy single still image recognition flow.
  /// Captures ONE photo, pauses the frame loop, and deep analyzes the still image.
  Future<void> _takePhotoAndAnalyze([Uint8List? directBytes]) async {
    if (_recognitionState == RecognitionState.analyzingPhoto) return;

    _distanceTestCounter++;
    final String testTag = 'DISTANCE_TEST_$_distanceTestCounter';
    debugPrint('==================================================');
    debugPrint('[$testTag] PHOTO SCAN DISTANCE DIAGNOSTIC START');

    // 1. Temporarily pause live stream if running (does not dispose camera)
    _cameraService.stopImageStream();

    setState(() {
      _recognitionState = RecognitionState.analyzingPhoto;
      _confirmedMatch = null;
      _liveSimilarity = 0.0;
    });

    try {
      // 2. Capture highest-quality still image available (or use directBytes in test)
      final Uint8List? imageBytes;
      if (directBytes != null) {
        imageBytes = directBytes;
      } else {
        imageBytes = await _cameraService.takePicture();
      }

      if (imageBytes == null || imageBytes.isEmpty) {
        debugPrint('[$testTag] Captured image bytes are null or empty.');
        debugPrint('$testTag | image=null | adCoverage=0.0% | topCandidate=none | visual=0.0000 | text=0.0000 | combined=0.0000 | margin=0.0000 | decision=NO_MATCH (empty_image)');
        debugPrint('==================================================');
        if (mounted) {
          setState(() {
            _recognitionState = RecognitionState.noMatch;
          });
        }
        return;
      }

      // DIAG 1: Captured image dimensions & ad coverage estimation
      img.Image? decoded;
      String imageDimsCompact = '${imageBytes.length}B';
      String adCoverage = 'unknown';
      try {
        decoded = img.decodeImage(imageBytes);
        if (decoded != null) {
          imageDimsCompact = '${decoded.width}x${decoded.height}';
          final w = decoded.width;
          final h = decoded.height;
          int minX = w, maxX = 0, minY = h, maxY = 0;
          for (int y = 0; y < h; y += 4) {
            for (int x = 0; x < w; x += 4) {
              final p = decoded.getPixel(x, y);
              final lum = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
              if (lum > 25) {
                if (x < minX) minX = x;
                if (x > maxX) maxX = x;
                if (y < minY) minY = y;
                if (y > maxY) maxY = y;
              }
            }
          }
          if (maxX >= minX && maxY >= minY) {
            final adW = maxX - minX;
            final adH = maxY - minY;
            final pct = (adW * adH) / (w * h) * 100.0;
            adCoverage = '${pct.toStringAsFixed(1)}% (${adW}x$adH)';
          }

          final minDim = math.min(w, h);
          final startX = (w - minDim) ~/ 2;
          final startY = (h - minDim) ~/ 2;
          debugPrint('[$testTag] Center-square crop: ${minDim}x$minDim at ($startX, $startY) to (${startX + minDim}, ${startY + minDim})');
        }
      } catch (_) {}

      debugPrint('[$testTag] Captured Image: $imageDimsCompact (${imageBytes.length} bytes)');
      debugPrint('[$testTag] Approximate Ad Coverage: $adCoverage');

      // 3. Process captured image through visual embedding & OCR evidence
      final liveEmbedding = await _visionService.generateEmbeddingFromBytes(imageBytes);
      debugPrint('[$testTag] Generated embedding dimensions: ${liveEmbedding.length}-dim (empty: ${liveEmbedding.isEmpty})');

      final ocrResult = await _ocrService.extractText(imageBytes);
      final liveNormalizedText = ocrResult.normalizedText;
      debugPrint('[$testTag] OCR text extracted: raw="${ocrResult.rawText}", normalized="$liveNormalizedText"');

      // 4. Use active campaign pool from CampaignRepository (exclude paused, expired, draft, processing)
      _syncCampaigns();
      List<AdTarget> activeCandidates = _campaigns.where((c) => c.embedding.isNotEmpty).toList();
      if (activeCandidates.isEmpty) {
        activeCandidates = CampaignRepository().getActiveAdTargets().where((c) => c.embedding.isNotEmpty).toList();
      }

      debugPrint('[$testTag] Candidate pool: ${activeCandidates.length} active candidate(s)');

      if (activeCandidates.isEmpty || liveEmbedding.isEmpty) {
        final String reason = activeCandidates.isEmpty
            ? 'No active candidates with valid embeddings found in CampaignRepository.'
            : 'Generated live embedding is empty (image failed luminance/contrast/quality checks in VisionService).';
        debugPrint('[$testTag] Rejection reason: $reason');
        debugPrint('$testTag | image=$imageDimsCompact | adCoverage=$adCoverage | topCandidate=none | visual=0.0000 | text=0.0000 | combined=0.0000 | margin=0.0000 | decision=NO_MATCH ($reason)');
        debugPrint('==================================================');
        if (mounted) {
          setState(() {
            _recognitionState = RecognitionState.noMatch;
          });
        }
        return;
      }

      // 5. Rank all eligible candidates using multi-signal matching
      final ranked = _matchingEngine.rankCandidatesMultiSignal(
        liveEmbedding: liveEmbedding,
        liveNormalizedText: liveNormalizedText,
        candidates: activeCandidates,
      );

      if (ranked.isEmpty) {
        debugPrint('[$testTag] MatchingEngine returned 0 scored candidates.');
        debugPrint('$testTag | image=$imageDimsCompact | adCoverage=$adCoverage | topCandidate=none | visual=0.0000 | text=0.0000 | combined=0.0000 | margin=0.0000 | decision=NO_MATCH (zero_candidates_scored)');
        debugPrint('==================================================');
        if (mounted) {
          setState(() {
            _recognitionState = RecognitionState.noMatch;
          });
        }
        return;
      }

      // Top 3 candidate ranking log
      final top3 = ranked.take(3).toList();
      debugPrint('[$testTag] Top candidates ranking (${ranked.length} total scored):');
      for (int i = 0; i < top3.length; i++) {
        final r = top3[i];
        final m = (i + 1 < ranked.length) ? (r.similarity - ranked[i + 1].similarity) : 1.0;
        debugPrint('   #${i + 1}: [${r.target.id}] "${r.target.name}" '
            '| visual: ${r.visualSimilarity.toStringAsFixed(4)} '
            '| text: ${r.textSimilarity.toStringAsFixed(4)} '
            '| combined: ${r.similarity.toStringAsFixed(4)} '
            '| margin: ${m.toStringAsFixed(4)}');
      }

      final top = ranked.first;

      // Top-vs-second margin
      final double margin = ranked.length > 1 ? (ranked[0].similarity - ranked[1].similarity) : 1.0;
      final bool isAmbiguous = top.isAmbiguous || (ranked.length > 1 && margin < _matchingEngine.separationMargin);
      debugPrint('[$testTag] Top-vs-second margin: ${margin.toStringAsFixed(4)} '
          '(separationMargin threshold: ${_matchingEngine.separationMargin}, isAmbiguous: $isAmbiguous)');

      MatchResult bestCandidate = top;
      String bestCropName = 'primary';
      double bestMargin = margin;
      bool bestIsAmbiguous = isAmbiguous;

      // MULTI-SCALE PHOTO RECOGNITION PASS:
      // If primary pass is not decisive (similarity below threshold OR ambiguous):
      // Run MultiScalePhotoAnalyzer across 8 scale/crop regions.
      // Evidence is aggregated per candidate — the same campaign repeatedly scoring
      // highest across multiple regions earns a corroboration bonus.
      // All wrong-ad protections, visual plausibility guards, and thresholds remain unchanged.
      final isPrimaryDecisive = top.similarity >= _matchingEngine.threshold && !isAmbiguous;
      if (!isPrimaryDecisive) {
        if (decoded == null) {
          try {
            decoded = img.decodeImage(imageBytes);
          } catch (_) {}
        }

        if (decoded != null && decoded.width >= 64 && decoded.height >= 64) {
          debugPrint('[$testTag] Primary pass not decisive '
              '(sim: ${top.similarity.toStringAsFixed(4)} < ${_matchingEngine.threshold} '
              'or ambiguous: $isAmbiguous). '
              'Launching MULTI-SCALE PASS (full_center + center_75 + center_1_5x + '
              'center_2x + top + bottom + left + right)...');

          final analyzer = MultiScalePhotoAnalyzer(
            visionService: _visionService,
            ocrService: _ocrService,
            matchingEngine: _matchingEngine,
          );

          final aggregated = await analyzer.analyze(
            image: decoded,
            candidates: activeCandidates,
            testTag: testTag,
          );

          // Print MULTISCALE SUMMARY
          debugPrint('[$testTag] ${aggregated.formatSummary(threshold: _matchingEngine.threshold)}');

          // If aggregated result has a confident match with better evidence than primary,
          // promote it to bestCandidate for the downstream decision
          if (aggregated.bestCandidate != null) {
            final agg = aggregated.bestCandidate!;
            final aggMarginVal = aggregated.aggregatedMargin;
            // Build a synthetic MatchResult from aggregated evidence to feed
            // into the existing threshold/Gemini decision machinery below
            if (agg.aggregatedScore > bestCandidate.similarity) {
              final promotedResult = MatchResult(
                target: agg.candidate,
                similarity: agg.aggregatedScore,
                visualSimilarity: agg.bestVisualScore,
                textSimilarity: agg.bestTextScore,
                isAmbiguous: aggregated.rankedCandidates.length > 1 &&
                    aggMarginVal < _matchingEngine.separationMargin &&
                    agg.aggregatedScore >= _matchingEngine.plausibleThreshold,
                separationMargin: aggMarginVal,
                distinctiveMatches: agg.distinctiveHits,
                matchedPhrase: agg.bestMatchedPhrase,
              );
              bestCandidate = promotedResult;
              bestCropName = 'multiscale[${agg.votingRegions.join("+")}]';
              bestMargin = aggMarginVal;
              bestIsAmbiguous = promotedResult.isAmbiguous;

              debugPrint('[$testTag] Multi-scale promoted candidate: '
                  '"${agg.candidate.name}" '
                  '(aggregated: ${agg.aggregatedScore.toStringAsFixed(4)}, '
                  'regions: ${agg.votingRegions.join(", ")}, '
                  'margin: ${aggMarginVal.toStringAsFixed(4)})');
            } else {
              debugPrint('[$testTag] Multi-scale best (${agg.aggregatedScore.toStringAsFixed(4)}) '
                  'did not exceed primary best (${bestCandidate.similarity.toStringAsFixed(4)}). '
                  'Keeping primary result.');
            }
          }
        }
      }

      // Compact summary helper
      void printCompactSummary(String decision) {
        debugPrint('--------------------------------------------------');
        debugPrint('[$testTag] Final Decision: $decision');
        debugPrint('$testTag | image=$imageDimsCompact | adCoverage=$adCoverage | topCandidate=${bestCandidate.target.name} | visual=${bestCandidate.visualSimilarity.toStringAsFixed(4)} | text=${bestCandidate.textSimilarity.toStringAsFixed(4)} | combined=${bestCandidate.similarity.toStringAsFixed(4)} | margin=${bestMargin.toStringAsFixed(4)} | decision=$decision');
        debugPrint('==================================================');
      }

      // Check minimum threshold against the strongest candidate across all passes
      if (bestCandidate.similarity < _matchingEngine.threshold) {
        final rejectReason = 'below_threshold (${bestCandidate.similarity.toStringAsFixed(4)} < ${_matchingEngine.threshold})';
        debugPrint('[$testTag] Decision: Similarity below threshold (${bestCandidate.similarity.toStringAsFixed(4)} < ${_matchingEngine.threshold}). '
            'Rejected best candidate "${bestCandidate.target.name}" from crop [$bestCropName] as insufficient confidence.');
        printCompactSummary('NO_MATCH ($rejectReason)');
        if (mounted) {
          setState(() {
            _recognitionState = RecognitionState.noMatch;
          });
        }
        return;
      }

      MatchResult? confirmed;

      // WRONG-AD PROTECTION:
      // A candidate is sent to VerificationCoordinator only when genuinely ambiguous (margin < 0.08).
      // A clear candidate with a good margin (>= 0.08) is accepted based on local visual + OCR signals.
      final needsVerification = bestIsAmbiguous;
      debugPrint('[$testTag] Decision flags: crop=$bestCropName, candidate="${bestCandidate.target.name}", '
          'similarity=${bestCandidate.similarity.toStringAsFixed(4)}, margin=${bestMargin.toStringAsFixed(4)}, '
          'separationMargin=${_matchingEngine.separationMargin}, isAmbiguous=$bestIsAmbiguous, needsVerification=$needsVerification');

      if (needsVerification) {
        debugPrint(
          'HomeScreen: Photo Scan ambiguous (margin: ${bestMargin.toStringAsFixed(3)} < ${_matchingEngine.separationMargin}). '
          'Triggering Gemini verification.',
        );
        debugPrint('[$testTag] Escalating to VerificationCoordinator (candidate: "${bestCandidate.target.name}" [${bestCandidate.target.id}], '
            'isLiveClient: ${_verificationCoordinator.geminiClient.isLive})...');
        confirmed = await _verificationCoordinator.verifyCandidate(
          candidate: bestCandidate.target,
          frameJpegBytes: imageBytes,
          candidatePool: activeCandidates,
        );
        if (confirmed == null) {
          debugPrint('[$testTag] VerificationCoordinator returned null / candidate was rejected by Gemini (similarity < ${_verificationCoordinator.verificationThreshold} or API key unavailable).');
          printCompactSummary('NO_MATCH (Gemini rejected / unavailable)');
        } else {
          debugPrint('[$testTag] VerificationCoordinator confirmed candidate "${confirmed.target.name}" with score ${confirmed.similarity.toStringAsFixed(4)}.');
          printCompactSummary('MATCH_CONFIRMED (${confirmed.target.name})');
        }
      } else {
        debugPrint('[$testTag] Clear unambiguous candidate confirmed via visual+OCR signals on crop [$bestCropName] without Gemini '
            '(${bestCandidate.similarity.toStringAsFixed(4)} >= ${_matchingEngine.threshold}, margin: ${bestMargin.toStringAsFixed(4)} >= ${_matchingEngine.separationMargin}).');
        confirmed = bestCandidate;
        printCompactSummary('MATCH_CONFIRMED (${confirmed.target.name})');
      }

      if (mounted) {
        if (confirmed != null) {
          setState(() {
            _recognitionState = RecognitionState.recognized;
            _confirmedMatch = confirmed;
          });
        } else {
          setState(() {
            _recognitionState = RecognitionState.noMatch;
          });
        }
      }
    } catch (e) {
      debugPrint('HomeScreen: Error in photo scan analysis: $e');
      debugPrint('[$testTag] Exception thrown during photo analysis: $e');
      debugPrint('$testTag | image=unknown | adCoverage=unknown | topCandidate=error | visual=0.0000 | text=0.0000 | combined=0.0000 | margin=0.0000 | decision=NO_MATCH (error: $e)');
      debugPrint('==================================================');
      if (mounted) {
        setState(() {
          _recognitionState = RecognitionState.noMatch;
        });
      }
    }
  }

  Future<void> _viewDestination(String urlString) async {
    try {
      final uri = Uri.parse(urlString);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        _showToast('COULD NOT OPEN: $urlString');
      }
    } catch (e) {
      _showToast('ERROR OPENING DESTINATION');
    }
  }

  void _showToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: BillyTheme.black,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(BillyTheme.space16),
        duration: const Duration(milliseconds: 2000),
        shape: const RoundedRectangleBorder(
          side: BorderSide(color: BillyTheme.white, width: BillyTheme.borderWidthThin),
        ),
        content: Text(
          message,
          style: const TextStyle(
            color: BillyTheme.white,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 2.0,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BillyTheme.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: BillyTheme.space24,
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: child,
              );
            },
            child: _isCameraActive
                ? InlineCameraView(
                    key: const ValueKey('inline_camera'),
                    cameraService: _cameraService,
                    recognitionState: _recognitionState,
                    confirmedMatch: _confirmedMatch,
                    liveSimilarity: _liveSimilarity,
                    threshold: _matchingEngine.threshold,
                    scanMode: _scanMode,
                    onScanModeChanged: (mode) {
                      setState(() {
                        _scanMode = mode;
                      });
                      if (mode == ScanMode.photo) {
                        _cameraService.stopImageStream();
                      } else {
                        if (_recognitionState == RecognitionState.looking) {
                          _startFrameProcessing();
                        }
                      }
                    },
                    onTakePhoto: () => _takePhotoAndAnalyze(),
                    onRetake: _onRetake,
                    contextBadge: (_currentClassification != null &&
                            _currentClassification!.predictedMedium !=
                                AdMediumType.universal)
                        ? _currentClassification!.predictedMedium.iconLabel
                        : null,
                    onClose: _closeCamera,
                    onRetry: _initializeCamera,
                    onScanAgain: _scanAgain,
                    onViewDestination: _viewDestination,
                  )
                : _buildHomeView(context),
          ),
        ),
      ),
    );
  }

  Widget _buildHomeView(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final isCompactScreen = mediaQuery.size.height < 700;

    return LayoutBuilder(
      key: const ValueKey('home_content'),
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight,
            ),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: BillyTheme.space24),

                  // --- Top Header ---
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Image.asset(
                            'assets/branding/logo_transparent_white.png',
                            width: 22,
                            height: 22,
                            fit: BoxFit.contain,
                          ),
                          const SizedBox(width: BillyTheme.space8),
                          const Text(
                            'BILLY',
                            style: BillyTheme.brandHeader,
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: BillyTheme.space8,
                          vertical: BillyTheme.space4,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: BillyTheme.border,
                            width: BillyTheme.borderWidthThin,
                          ),
                        ),
                        child: Text(
                          _campaignsReady
                              ? 'v0.4 · ${_campaigns.length} AD${_campaigns.length != 1 ? "S" : ""}'
                              : 'v0.4 · LOADING...',
                          style: const TextStyle(
                            fontSize: 10.0,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.5,
                            color: BillyTheme.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: BillyTheme.space16),
                  const Divider(
                    color: BillyTheme.black,
                    thickness: BillyTheme.borderWidthThin,
                    height: BillyTheme.borderWidthThin,
                  ),

                  // --- Main Visual / Editorial Area ---
                  const Spacer(flex: 2),

                  Text(
                    'SEE\nSOMETHING?',
                    style: isCompactScreen
                        ? BillyTheme.heroHeadlineCompact
                        : BillyTheme.heroHeadline,
                  ),

                  const SizedBox(height: BillyTheme.space24),

                  const Text(
                    'POINT BILLY AT IT.',
                    style: BillyTheme.bodySubhead,
                  ),

                  const Spacer(flex: 3),

                  // --- Primary Action ---
                  BillyButton(
                    text: 'SCAN',
                    onPressed: _campaignsReady ? _openCamera : null,
                  ),

                  const SizedBox(height: BillyTheme.space12),

                  // --- Role-Based Secondary Navigation ---
                  _buildSecondaryNavigation(),

                  const SizedBox(height: BillyTheme.space16),

                  // --- Bottom Subtle Rule & Footer ---
                  const Divider(
                    color: BillyTheme.borderSubtle,
                    thickness: BillyTheme.borderWidthThin,
                    height: BillyTheme.borderWidthThin,
                  ),

                  const SizedBox(height: BillyTheme.space16),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: const [
                      Text(
                        'VISUAL DISCOVERY',
                        style: BillyTheme.footerText,
                      ),
                      Text(
                        'PHASE 09',
                        style: BillyTheme.footerText,
                      ),
                    ],
                  ),

                  const SizedBox(height: BillyTheme.space16),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSecondaryNavigation() {
    final isConsumer = _accountSession.isConsumer;
    final isAdvertiser = _accountSession.isAdvertiser;

    Widget navItem(String label, VoidCallback onTap) {
      return GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: BillyTheme.space8,
            horizontal: BillyTheme.space8,
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11.0,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.0,
              color: BillyTheme.textSecondary,
              decoration: TextDecoration.underline,
              decorationColor: BillyTheme.borderSubtle,
            ),
          ),
        ),
      );
    }

    const dot = Text(
      '·',
      style: TextStyle(
        fontSize: 12.0,
        fontWeight: FontWeight.w700,
        color: BillyTheme.textSecondary,
      ),
    );

    final List<Widget> items = [];

    if (isConsumer) {
      // Viewer sees only REWARDS and ACCOUNT
      items.add(navItem('REWARDS', _navigateToRewards));
      items.add(dot);
      items.add(navItem('ACCOUNT', _navigateToAccount));
    } else if (isAdvertiser) {
      // Advertiser sees CREATE AD and ACCOUNT
      items.add(navItem('CREATE AD', _navigateToCreateAd));
      items.add(dot);
      items.add(navItem('ACCOUNT', _navigateToAccount));
    } else {
      // Guest sees REWARDS, CREATE AD, ACCOUNT
      items.add(navItem('REWARDS', _navigateToRewards));
      items.add(dot);
      items.add(navItem('CREATE AD', _navigateToCreateAd));
      items.add(dot);
      items.add(navItem('ACCOUNT', _navigateToAccount));
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: items,
    );
  }
}
