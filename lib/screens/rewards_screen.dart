import 'package:flutter/material.dart';
import '../app/theme.dart';
import '../models/account.dart';
import '../models/reward.dart';
import '../services/account_session.dart';
import '../services/reward_service.dart';
import '../widgets/billy_button.dart';
import 'account_screen.dart';

/// Minimal brutalist screen for the viewer reward experience.
/// Decoupled from financial processing and advertising mechanics.
class RewardsScreen extends StatefulWidget {
  final AccountSession? accountSession;
  final RewardService? rewardService;

  const RewardsScreen({
    super.key,
    this.accountSession,
    this.rewardService,
  });

  @override
  State<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends State<RewardsScreen> {
  late final AccountSession _accountSession;
  late final RewardService _rewardService;

  @override
  void initState() {
    super.initState();
    _accountSession = widget.accountSession ?? AccountSession();
    _rewardService = widget.rewardService ?? RewardService();
  }

  @override
  Widget build(BuildContext context) {
    final account = _accountSession.currentAccount;
    final isSignedIn = _accountSession.isSignedIn;
    final isViewer = _accountSession.isConsumer;

    return Scaffold(
      backgroundColor: BillyTheme.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: BillyTheme.space24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: BillyTheme.space16),

              // --- Top Navigation Header ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      color: Colors.transparent,
                      padding: const EdgeInsets.symmetric(vertical: BillyTheme.space8),
                      child: Row(
                        children: const [
                          Icon(Icons.arrow_back, size: 18, color: BillyTheme.black),
                          SizedBox(width: BillyTheme.space8),
                          Text(
                            'BACK',
                            style: TextStyle(
                              fontSize: 11.0,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 2.0,
                              color: BillyTheme.black,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Text(
                    isSignedIn
                        ? (isViewer ? 'VIEWER' : account!.role.displayName)
                        : 'GUEST',
                    style: const TextStyle(
                      fontSize: 10.0,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2.0,
                      color: BillyTheme.textSecondary,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: BillyTheme.space12),
              const Divider(
                color: BillyTheme.black,
                thickness: BillyTheme.borderWidthThin,
                height: BillyTheme.borderWidthThin,
              ),

              const SizedBox(height: BillyTheme.space24),

              const Text(
                'REWARDS',
                style: TextStyle(
                  fontSize: 32.0,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.0,
                  color: BillyTheme.textPrimary,
                ),
              ),

              const SizedBox(height: BillyTheme.space8),

              // --- Body Content based on Session State ---
              Expanded(
                child: !isSignedIn
                    ? _buildGuestView()
                    : (isViewer
                        ? _buildViewerView(account!)
                        : _buildAdvertiserView()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Guest state: Prompts user to sign in to access rewards.
  Widget _buildGuestView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'SIGN IN TO SEE YOUR REWARDS',
          style: TextStyle(
            fontSize: 14.0,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
            color: BillyTheme.textPrimary,
          ),
        ),
        const SizedBox(height: BillyTheme.space8),
        const Text(
          'AN ACCOUNT IS REQUIRED TO TRACK AND REDEEM REWARDS WHEN YOU DISCOVER ADVERTISEMENTS.',
          style: TextStyle(
            fontSize: 11.0,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.5,
            height: 1.4,
            color: BillyTheme.textSecondary,
          ),
        ),

        const Spacer(),

        BillyButton(
          text: 'CONTINUE AS VIEWER',
          height: 52.0,
          onPressed: () {
            setState(() {
              _accountSession.signInAsConsumer();
            });
          },
        ),

        const SizedBox(height: BillyTheme.space12),

        BillyButton(
          text: 'SIGN IN',
          isOutlined: true,
          height: 52.0,
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => AccountScreen(accountSession: _accountSession),
              ),
            ).then((_) {
              if (mounted) setState(() {});
            });
          },
        ),

        const SizedBox(height: BillyTheme.space32),
      ],
    );
  }

  /// Viewer state: Displays reward summary or clean empty state.
  Widget _buildViewerView(Account account) {
    final rewards = _rewardService.getRewardsForViewer(account.id);
    final summary = _rewardService.getRewardSummary(account.id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'YOUR REWARDS',
              style: TextStyle(
                fontSize: 12.0,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.0,
                color: BillyTheme.textSecondary,
              ),
            ),
            Text(
              '${summary.totalCount} RECORD${summary.totalCount != 1 ? "S" : ""}',
              style: const TextStyle(
                fontSize: 10.0,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
                color: BillyTheme.textSecondary,
              ),
            ),
          ],
        ),

        const SizedBox(height: BillyTheme.space16),

        Expanded(
          child: rewards.isEmpty
              ? _buildEmptyRewardsView()
              : _buildRewardsList(rewards),
        ),
      ],
    );
  }

  /// Empty rewards state: Explains prototype status and encourages discovery.
  Widget _buildEmptyRewardsView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              border: Border.all(
                color: BillyTheme.black,
                width: BillyTheme.borderWidthThin,
              ),
            ),
            child: const Icon(
              Icons.stars_outlined,
              size: 28,
              color: BillyTheme.black,
            ),
          ),
          const SizedBox(height: BillyTheme.space24),
          const Text(
            'NO REWARDS YET',
            style: TextStyle(
              fontSize: 16.0,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.0,
              color: BillyTheme.textPrimary,
            ),
          ),
          const SizedBox(height: BillyTheme.space8),
          const Text(
            'KEEP DISCOVERING',
            style: TextStyle(
              fontSize: 11.0,
              fontWeight: FontWeight.w800,
              letterSpacing: 2.0,
              color: BillyTheme.textSecondary,
            ),
          ),
          const SizedBox(height: BillyTheme.space12),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: BillyTheme.space16),
            child: Text(
              'POINT BILLY AT REGISTERED ADVERTISEMENTS TO SCAN, DISCOVER, AND UNLOCK REWARDS.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11.0,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.5,
                height: 1.4,
                color: BillyTheme.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: BillyTheme.space32),
          BillyButton(
            text: 'SCAN NOW',
            height: 48.0,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  /// List of rewards for viewers who have earned/claimed items.
  Widget _buildRewardsList(List<Reward> rewards) {
    return ListView.separated(
      itemCount: rewards.length,
      separatorBuilder: (context, index) => const SizedBox(height: BillyTheme.space12),
      itemBuilder: (context, index) {
        final reward = rewards[index];
        return Container(
          padding: const EdgeInsets.all(BillyTheme.space16),
          decoration: BoxDecoration(
            border: Border.all(
              color: BillyTheme.black,
              width: BillyTheme.borderWidthThin,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    reward.title ?? reward.rewardType.displayName,
                    style: const TextStyle(
                      fontSize: 13.0,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                      color: BillyTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'CAMPAIGN ID: ${reward.campaignId}',
                    style: const TextStyle(
                      fontSize: 10.0,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.0,
                      color: BillyTheme.textSecondary,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: BillyTheme.space8,
                  vertical: BillyTheme.space4,
                ),
                decoration: const BoxDecoration(
                  color: BillyTheme.black,
                ),
                child: Text(
                  reward.status.displayName,
                  style: const TextStyle(
                    fontSize: 9.0,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                    color: BillyTheme.white,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Advertiser fallback: Explains that rewards are a viewer-facing feature.
  Widget _buildAdvertiserView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Text(
            'ADVERTISER ACCOUNT',
            style: TextStyle(
              fontSize: 14.0,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.0,
              color: BillyTheme.textPrimary,
            ),
          ),
          SizedBox(height: BillyTheme.space12),
          Text(
            'REWARDS ARE A VIEWER EXPERIENCE FEATURE. USE YOUR ADVERTISER DASHBOARD TO MANAGE CAMPAIGNS.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11.0,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.5,
              height: 1.4,
              color: BillyTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
