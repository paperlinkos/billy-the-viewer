import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
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
import 'package:billy_the_viewer/services/verification_coordinator.dart';
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
  final SensorContext? initialSensorContext;
  final List<AdTarget>? initialCampaigns;
  final AccountSession? accountSession;

  const HomeScreen({
    super.key,
    this.cameraService,
    this.visionService,
    this.matchingEngine,
    this.contextEngine,
    this.verificationCoordinator,
    this.initialSensorContext,
    this.initialCampaigns,
    this.accountSession,
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

  SensorContext _sensorContext = const SensorContext();
  ContextClassification? _currentClassification;

  bool _isCameraActive = false;
  RecognitionState _recognitionState = RecognitionState.looking;
  MatchResult? _confirmedMatch;

  List<AdTarget> _campaigns = [];
  bool _campaignsReady = false;
  bool _isProcessingFrame = false;
  DateTime _lastProcessedTime = DateTime.fromMillisecondsSinceEpoch(0);

  // Live similarity score seen during scanning
  double _liveSimilarity = 0.0;

  // Rolling confidence window for movement-resilient match confirmation
  static const int _rollingWindowSize = 8;
  final List<MatchResult?> _recentFrameMatches = [];

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
    _sensorContext = widget.initialSensorContext ?? const SensorContext();

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
      _startFrameProcessing();
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

        if (mounted) {
          setState(() {
            _liveSimilarity = bestSim;
          });
        }

        final match = _matchingEngine.findBestMatch(embedding, candidateTargets);
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

      // Dynamic Two-Tier Movement & Shake Resilient Confirmation:
      // Tier 1 Crisp Hit: any single frame with similarity >= 0.84 confirms immediately on-device!
      //                   No cloud/Gemini call needed.
      final isCrispHit = highestSim >= 0.84;

      // Tier 2 Dual / Motion Hit:
      // - Dual Hit: >= 2 hits with similarity >= 0.65 within rolling window.
      // - Sustained Motion Hit: >= 3 hits with similarity >= 0.58 within rolling window.
      final isDualHit = hits.length >= 2 && highestSim >= 0.65;
      final isSustainedMotionHit = hits.length >= 3 && hits.every((h) => h.similarity >= 0.58);

      if (isCrispHit) {
        confirmed = hits.first;
        break;
      } else if (isDualHit || isSustainedMotionHit) {
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

  void _scanAgain() {
    setState(() {
      _recognitionState = RecognitionState.looking;
      _confirmedMatch = null;
      _liveSimilarity = 0.0;
      _recentFrameMatches.clear();
    });
    _startFrameProcessing();
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
                      const Text(
                        'BILLY',
                        style: BillyTheme.brandHeader,
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
