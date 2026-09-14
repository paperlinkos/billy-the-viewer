import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:billy_the_viewer/app/theme.dart';
import 'package:billy_the_viewer/models/ad_target.dart';
import 'package:billy_the_viewer/services/camera_service.dart';
import 'package:billy_the_viewer/services/matching_engine.dart';
import 'package:billy_the_viewer/widgets/billy_button.dart';
import 'package:billy_the_viewer/widgets/minimal_looking_indicator.dart';

/// Phase 4 Recognition States for the inline viewer.
enum RecognitionState {
  looking,
  confirming,
  recognized,
  error,
}

/// Inline Camera View that occupies Billy's content area during scanning.
///
/// Implements the Phase 4 Discovery Result Experience:
/// - Inline camera remains visible above the discovery result.
/// - Clear editorial hierarchy:
///   I SEE IT. → STUDIO NOIR → Brand → [Ad Preview] → VIEW → SCAN AGAIN
/// - Fast to understand, confident discovery, no modal popups.
class InlineCameraView extends StatelessWidget {
  final CameraService cameraService;
  final RecognitionState recognitionState;
  final MatchResult? confirmedMatch;
  final double liveSimilarity;
  final double threshold;
  final VoidCallback onClose;
  final VoidCallback onRetry;
  final VoidCallback onScanAgain;
  final Function(String url) onViewDestination;

  const InlineCameraView({
    super.key,
    required this.cameraService,
    required this.recognitionState,
    this.confirmedMatch,
    this.liveSimilarity = 0.0,
    this.threshold = 0.70,
    required this.onClose,
    required this.onRetry,
    required this.onScanAgain,
    required this.onViewDestination,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: BillyTheme.space24),

        // --- Top Inline Bar: BILLY identity + minimal × close button ---
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text(
              'BILLY',
              style: BillyTheme.brandHeader,
            ),
            Semantics(
              button: true,
              label: 'Close camera and return to home',
              child: GestureDetector(
                onTap: onClose,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: BillyTheme.space12,
                    vertical: BillyTheme.space8,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: BillyTheme.border,
                      width: BillyTheme.borderWidthThin,
                    ),
                  ),
                  child: const Text(
                    '✕',
                    style: TextStyle(
                      fontSize: 14.0,
                      fontWeight: FontWeight.w700,
                      color: BillyTheme.black,
                      height: 1.0,
                    ),
                  ),
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

        const SizedBox(height: BillyTheme.space16),

        // --- Camera Preview Content Area (Remains visible throughout) ---
        Expanded(
          child: _buildCameraContent(context),
        ),

        const SizedBox(height: BillyTheme.space16),

        // --- Bottom Instruction / Discovery Result Section ---
        _buildBottomSection(context),

        const SizedBox(height: BillyTheme.space16),
      ],
    );
  }

  Widget _buildCameraContent(BuildContext context) {
    if (cameraService.isReady && cameraService.controller != null) {
      final controller = cameraService.controller!;

      return Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: BillyTheme.black,
          border: Border.all(
            color: BillyTheme.border,
            width: BillyTheme.borderWidthThin,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Camera feed preview
            Center(
              child: CameraPreview(controller),
            ),

            // Minimal framing outline
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: recognitionState == RecognitionState.recognized
                          ? BillyTheme.white.withValues(alpha: 0.5)
                          : BillyTheme.white.withValues(alpha: 0.15),
                      width: BillyTheme.borderWidthThin,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Checking permission or initializing
    if (cameraService.status == CameraStateStatus.initializing ||
        cameraService.status == CameraStateStatus.checkingPermission ||
        cameraService.status == CameraStateStatus.initial) {
      return Container(
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border.all(
            color: BillyTheme.borderSubtle,
            width: BillyTheme.borderWidthThin,
          ),
          color: BillyTheme.grayExtraLight,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Text(
              'OPENING...',
              style: TextStyle(
                fontSize: 12.0,
                fontWeight: FontWeight.w800,
                letterSpacing: 3.0,
                color: BillyTheme.black,
              ),
            ),
          ],
        ),
      );
    }

    // Error or Permission Denied State
    final isPermanentlyDenied =
        cameraService.status == CameraStateStatus.permissionPermanentlyDenied;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(BillyTheme.space24),
      decoration: BoxDecoration(
        border: Border.all(
          color: BillyTheme.border,
          width: BillyTheme.borderWidthThin,
        ),
        color: BillyTheme.white,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'CAMERA\nUNAVAILABLE',
            style: TextStyle(
              fontSize: 28.0,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
              height: 1.05,
              color: BillyTheme.black,
            ),
          ),
          const SizedBox(height: BillyTheme.space16),
          const Text(
            'BILLY NEEDS CAMERA ACCESS TO SEE.',
            style: BillyTheme.bodySubhead,
          ),
          if (cameraService.errorMessage != null) ...[
            const SizedBox(height: BillyTheme.space12),
            Text(
              cameraService.errorMessage!,
              style: BillyTheme.footerText.copyWith(
                color: BillyTheme.grayMedium,
              ),
            ),
          ],
          const SizedBox(height: BillyTheme.space32),
          BillyButton(
            text: isPermanentlyDenied ? 'OPEN SETTINGS' : 'TRY AGAIN',
            onPressed: isPermanentlyDenied
                ? () => cameraService.openSettings()
                : onRetry,
          ),
        ],
      ),
    );
  }

  Widget _buildBottomSection(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.0, 0.04),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: recognitionState == RecognitionState.recognized && confirmedMatch != null
          ? _DiscoveryResultCard(
              key: const ValueKey('discovery_result_card'),
              matchResult: confirmedMatch!,
              onScanAgain: onScanAgain,
              onViewDestination: onViewDestination,
            )
          : _buildLookingState(context),
    );
  }

  /// Default Scanning State (LOOKING / CONFIRMING)
  Widget _buildLookingState(BuildContext context) {
    return Container(
      key: const ValueKey('looking_state'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (cameraService.isReady) ...[
            const MinimalLookingIndicator(),
            const SizedBox(height: BillyTheme.space16),
          ],

          const Text(
            'SHOW BILLY SOMETHING',
            style: TextStyle(
              fontSize: 16.0,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
              color: BillyTheme.black,
            ),
          ),
          const SizedBox(height: BillyTheme.space4),
          const Text(
            'POINT AT AN AD',
            style: BillyTheme.bodySubhead,
          ),

          const SizedBox(height: BillyTheme.space16),

          // Live similarity indicator
          if (cameraService.isReady && liveSimilarity > 0) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'MATCH ${(liveSimilarity * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                    fontSize: 9.0,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2.0,
                    color: BillyTheme.black,
                  ),
                ),
                Text(
                  'NEED ${(threshold * 100).toStringAsFixed(0)}%',
                  style: BillyTheme.footerText,
                ),
              ],
            ),
            const SizedBox(height: BillyTheme.space4),
            LayoutBuilder(
              builder: (context, constraints) {
                final barFill = (liveSimilarity / threshold).clamp(0.0, 1.0);
                return Stack(
                  children: [
                    Container(
                      height: 2.0,
                      width: constraints.maxWidth,
                      color: BillyTheme.borderSubtle,
                    ),
                    Container(
                      height: 2.0,
                      width: constraints.maxWidth * barFill,
                      color: BillyTheme.black,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: BillyTheme.space12),
          ] else ...[
            const Divider(
              color: BillyTheme.borderSubtle,
              thickness: BillyTheme.borderWidthThin,
              height: BillyTheme.borderWidthThin,
            ),
            const SizedBox(height: BillyTheme.space12),
          ],

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text(
                'VISUAL DISCOVERY',
                style: BillyTheme.footerText,
              ),
              Text(
                'PHASE 04',
                style: BillyTheme.footerText,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Phase 4 Discovery Result Card:
/// Implements the exact editorial hierarchy:
/// 1. I SEE IT.
/// 2. STUDIO NOIR (Campaign / Target Name)
/// 3. Brand
/// 4. [Advertisement preview]
/// 5. VIEW (Primary action)
/// 6. SCAN AGAIN (Secondary action)
///
/// Features staged, restrained micro-animations:
/// Status → Name & Brand → Preview → Actions (total 320ms).
class _DiscoveryResultCard extends StatefulWidget {
  final MatchResult matchResult;
  final VoidCallback onScanAgain;
  final Function(String url) onViewDestination;

  const _DiscoveryResultCard({
    super.key,
    required this.matchResult,
    required this.onScanAgain,
    required this.onViewDestination,
  });

  @override
  State<_DiscoveryResultCard> createState() => _DiscoveryResultCardState();
}

class _DiscoveryResultCardState extends State<_DiscoveryResultCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _statusFade;
  late final Animation<double> _infoFade;
  late final Animation<double> _previewFade;
  late final Animation<double> _actionsFade;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );

    // Staged sequence: Status → Name/Brand → Preview → Actions
    _statusFade = CurvedAnimation(
      parent: _animController,
      curve: const Interval(0.0, 0.45, curve: Curves.easeOut),
    );
    _infoFade = CurvedAnimation(
      parent: _animController,
      curve: const Interval(0.15, 0.65, curve: Curves.easeOut),
    );
    _previewFade = CurvedAnimation(
      parent: _animController,
      curve: const Interval(0.35, 0.85, curve: Curves.easeOut),
    );
    _actionsFade = CurvedAnimation(
      parent: _animController,
      curve: const Interval(0.55, 1.0, curve: Curves.easeOut),
    );

    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = widget.matchResult.target;
    final primaryAction = ad.effectiveActions.isNotEmpty
        ? ad.effectiveActions.first
        : AdAction(type: 'view', label: 'VIEW', destination: ad.destinationUrl);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(BillyTheme.space16),
      decoration: BoxDecoration(
        color: BillyTheme.white,
        border: Border.all(
          color: BillyTheme.border,
          width: BillyTheme.borderWidthThin,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. I SEE IT. (Status Bar)
          FadeTransition(
            opacity: _statusFade,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text(
                  'I SEE IT.',
                  style: TextStyle(
                    fontSize: 12.0,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.5,
                    color: BillyTheme.black,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: BillyTheme.space8,
                    vertical: BillyTheme.space4,
                  ),
                  decoration: BoxDecoration(
                    color: BillyTheme.black,
                    border: Border.all(
                      color: BillyTheme.border,
                      width: BillyTheme.borderWidthThin,
                    ),
                  ),
                  child: const Text(
                    'AD RECOGNIZED',
                    style: TextStyle(
                      fontSize: 9.0,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                      color: BillyTheme.white,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: BillyTheme.space12),
          const Divider(
            color: BillyTheme.borderSubtle,
            thickness: BillyTheme.borderWidthThin,
            height: BillyTheme.borderWidthThin,
          ),
          const SizedBox(height: BillyTheme.space12),

          // 2. STUDIO NOIR (Campaign Name) & 3. Brand
          FadeTransition(
            opacity: _infoFade,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 4. [Advertisement Preview] Clean rectangular container
                FadeTransition(
                  opacity: _previewFade,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: BillyTheme.black,
                        width: BillyTheme.borderWidthThin,
                      ),
                    ),
                    child: Image.asset(
                      ad.imageAsset,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: BillyTheme.grayExtraLight,
                        child: const Center(
                          child: Text(
                            'AD',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: BillyTheme.black,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: BillyTheme.space16),

                // Name & Brand Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ad.name.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 16.0,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.3,
                          height: 1.2,
                          color: BillyTheme.black,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: BillyTheme.space4),
                      Text(
                        ad.brand,
                        style: BillyTheme.bodySubhead.copyWith(
                          fontSize: 12.0,
                          letterSpacing: 1.2,
                          color: BillyTheme.grayMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: BillyTheme.space16),

          // 5. VIEW (Primary Action) & 6. SCAN AGAIN (Secondary Action)
          FadeTransition(
            opacity: _actionsFade,
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: BillyButton(
                    text: primaryAction.label.toUpperCase(),
                    height: 48.0,
                    onPressed: () => widget.onViewDestination(primaryAction.destination),
                  ),
                ),
                const SizedBox(width: BillyTheme.space12),
                Expanded(
                  flex: 2,
                  child: BillyButton(
                    text: 'SCAN AGAIN',
                    isOutlined: true,
                    height: 48.0,
                    onPressed: widget.onScanAgain,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
