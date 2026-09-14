import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:billy_the_viewer/app/theme.dart';
import 'package:billy_the_viewer/models/ad_target.dart';
import 'package:billy_the_viewer/screens/account_screen.dart';
import 'package:billy_the_viewer/screens/create_campaign_screen.dart';
import 'package:billy_the_viewer/screens/inline_camera_view.dart';
import 'package:billy_the_viewer/services/camera_service.dart';
import 'package:billy_the_viewer/services/campaign_repository.dart';
import 'package:billy_the_viewer/services/matching_engine.dart';
import 'package:billy_the_viewer/services/vision_service.dart';
import 'package:billy_the_viewer/widgets/billy_button.dart';

/// Phase 4 HomeScreen:
/// Connects CameraService → VisionService → MatchingEngine → AdTarget → Discovery Result UI.
class HomeScreen extends StatefulWidget {
  final CameraService? cameraService;
  final VisionService? visionService;
  final MatchingEngine? matchingEngine;
  final List<AdTarget>? initialCampaigns;

  const HomeScreen({
    super.key,
    this.cameraService,
    this.visionService,
    this.matchingEngine,
    this.initialCampaigns,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late final CameraService _cameraService;
  late final VisionService _visionService;
  late final MatchingEngine _matchingEngine;

  bool _isCameraActive = false;
  RecognitionState _recognitionState = RecognitionState.looking;
  MatchResult? _confirmedMatch;

  List<AdTarget> _campaigns = [];
  bool _campaignsReady = false;
  bool _isProcessingFrame = false;
  DateTime _lastProcessedTime = DateTime.fromMillisecondsSinceEpoch(0);

  // Live similarity score seen during scanning
  double _liveSimilarity = 0.0;

  // Three-frame recognition confirmation state to ensure stability
  String? _candidateMatchId;
  int _candidateFrameCount = 0;
  static const int _requiredConsecutiveFrames = 3;

  // Threshold based on empirical separation benchmark:
  // Negatives score <= 0.18 or fail quality checks; positive ad scores >= 0.95.
  static const double _perceptualThreshold = 0.70;
  static const Duration _frameThrottleDuration = Duration(milliseconds: 500);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cameraService = widget.cameraService ?? CameraService();
    _visionService = widget.visionService ?? VisionService();
    _matchingEngine = widget.matchingEngine ?? const MatchingEngine(threshold: _perceptualThreshold);

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
      });
    }

    debugPrint('Billy: ${_campaigns.length} active campaign(s) ready for matching.');
  }

  Future<void> _navigateToCreateAd() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const CreateCampaignScreen(),
      ),
    );
    _syncCampaigns();
  }

  Future<void> _navigateToAccount() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const AccountScreen(),
      ),
    );
    _syncCampaigns();
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

    // Throttle
    final now = DateTime.now();
    if (now.difference(_lastProcessedTime) < _frameThrottleDuration) {
      return;
    }

    _isProcessingFrame = true;
    _lastProcessedTime = now;

    try {
      final embedding = await _visionService.generateEmbeddingFromCameraImage(image);

      if (embedding.isNotEmpty) {
        double bestSim = 0.0;
        for (final c in _campaigns) {
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

        final match = _matchingEngine.findBestMatch(embedding, _campaigns);
        if (match != null) {
          if (_candidateMatchId == match.target.id) {
            _candidateFrameCount++;
          } else {
            _candidateMatchId = match.target.id;
            _candidateFrameCount = 1;
          }

          if (_candidateFrameCount >= _requiredConsecutiveFrames) {
            debugPrint(
              'Billy Recognition: CONFIRMED MATCH ($_candidateFrameCount/$_requiredConsecutiveFrames frames) → '
              '${match.target.name} (similarity: ${match.similarity.toStringAsFixed(3)})',
            );
            if (mounted) {
              setState(() {
                _recognitionState = RecognitionState.recognized;
                _confirmedMatch = match;
              });
              _cameraService.stopImageStream();
            }
          } else {
            debugPrint(
              'Billy Recognition: CANDIDATE MATCH ($_candidateFrameCount/$_requiredConsecutiveFrames frames) → '
              '${match.target.name} (similarity: ${match.similarity.toStringAsFixed(3)})',
            );
            if (mounted && _recognitionState != RecognitionState.confirming) {
              setState(() {
                _recognitionState = RecognitionState.confirming;
              });
            }
          }
        } else {
          _candidateMatchId = null;
          _candidateFrameCount = 0;
          if (mounted && _recognitionState == RecognitionState.confirming) {
            setState(() {
              _recognitionState = RecognitionState.looking;
            });
          }
        }
      } else {
        // Frame failed quality checks (too dark, overexposed, or uniform scene/wall)
        _candidateMatchId = null;
        _candidateFrameCount = 0;
        if (mounted) {
          setState(() {
            _liveSimilarity = 0.0;
            if (_recognitionState == RecognitionState.confirming) {
              _recognitionState = RecognitionState.looking;
            }
          });
        }
      }
    } catch (e) {
      debugPrint('HomeScreen: Error processing camera frame: $e');
    } finally {
      _isProcessingFrame = false;
    }
  }

  void _openCamera() {
    _syncCampaigns();
    setState(() {
      _isCameraActive = true;
      _recognitionState = RecognitionState.looking;
      _confirmedMatch = null;
      _liveSimilarity = 0.0;
      _candidateMatchId = null;
      _candidateFrameCount = 0;
    });
    _initializeCamera();
  }

  void _closeCamera() {
    setState(() {
      _isCameraActive = false;
      _recognitionState = RecognitionState.looking;
      _confirmedMatch = null;
      _liveSimilarity = 0.0;
      _candidateMatchId = null;
      _candidateFrameCount = 0;
    });
    _cameraService.dispose();
  }

  void _scanAgain() {
    setState(() {
      _recognitionState = RecognitionState.looking;
      _confirmedMatch = null;
      _liveSimilarity = 0.0;
      _candidateMatchId = null;
      _candidateFrameCount = 0;
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

                  // --- Subtle Secondary Advertiser & Account Entry Points ---
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      GestureDetector(
                        onTap: _navigateToCreateAd,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: BillyTheme.space8,
                            horizontal: BillyTheme.space8,
                          ),
                          child: Text(
                            'CREATE AD',
                            style: TextStyle(
                              fontSize: 11.0,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 2.0,
                              color: BillyTheme.textSecondary,
                              decoration: TextDecoration.underline,
                              decorationColor: BillyTheme.borderSubtle,
                            ),
                          ),
                        ),
                      ),
                      const Text(
                        '·',
                        style: TextStyle(
                          fontSize: 12.0,
                          fontWeight: FontWeight.w700,
                          color: BillyTheme.textSecondary,
                        ),
                      ),
                      GestureDetector(
                        onTap: _navigateToAccount,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: BillyTheme.space8,
                            horizontal: BillyTheme.space8,
                          ),
                          child: Text(
                            'ACCOUNT',
                            style: TextStyle(
                              fontSize: 11.0,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 2.0,
                              color: BillyTheme.textSecondary,
                              decoration: TextDecoration.underline,
                              decorationColor: BillyTheme.borderSubtle,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

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
                        'PHASE 07',
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
}
