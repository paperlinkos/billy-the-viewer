import 'package:flutter/material.dart';
import '../app/theme.dart';
import '../models/account.dart';
import '../services/account_session.dart';
import '../widgets/billy_button.dart';
import 'campaign_list_screen.dart';
import 'create_campaign_screen.dart';

/// Minimal account and session management screen.
/// Allows fast-path switching between Consumer (Viewer) and Advertiser roles.
class AccountScreen extends StatefulWidget {
  final AccountSession? accountSession;

  const AccountScreen({
    super.key,
    this.accountSession,
  });

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  late final AccountSession _accountSession;

  @override
  void initState() {
    super.initState();
    _accountSession = widget.accountSession ?? AccountSession();
  }

  @override
  Widget build(BuildContext context) {
    final account = _accountSession.currentAccount;
    final isSignedIn = _accountSession.isSignedIn;

    return Scaffold(
      backgroundColor: BillyTheme.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: BillyTheme.space24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: BillyTheme.space16),

              // --- Top Nav Header ---
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
                    isSignedIn ? account!.role.displayName : 'GUEST',
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

              const SizedBox(height: BillyTheme.space32),

              // --- Main Content View ---
              Expanded(
                child: !isSignedIn
                    ? _buildSignedOutView()
                    : (account!.isConsumer
                        ? _buildViewerView(account)
                        : _buildAdvertiserView(account)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSignedOutView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'WELCOME TO BILLY',
          style: TextStyle(
            fontSize: 32.0,
            fontWeight: FontWeight.w900,
            letterSpacing: -1.0,
            color: BillyTheme.textPrimary,
          ),
        ),
        const SizedBox(height: BillyTheme.space8),
        const Text(
          'SELECT AN ACCOUNT ROLE TO CONTINUE.',
          style: TextStyle(
            fontSize: 11.0,
            fontWeight: FontWeight.w700,
            letterSpacing: 2.0,
            color: BillyTheme.textSecondary,
          ),
        ),

        const Spacer(),

        BillyButton(
          text: 'CONTINUE AS VIEWER',
          height: 54.0,
          onPressed: () {
            setState(() {
              _accountSession.signInAsConsumer();
            });
          },
        ),

        const SizedBox(height: BillyTheme.space12),

        BillyButton(
          text: 'I RUN ADS',
          isOutlined: true,
          height: 54.0,
          onPressed: () {
            setState(() {
              _accountSession.signInAsAdvertiser();
            });
          },
        ),

        const SizedBox(height: BillyTheme.space48),
      ],
    );
  }

  Widget _buildViewerView(Account account) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'VIEWER',
          style: TextStyle(
            fontSize: 36.0,
            fontWeight: FontWeight.w900,
            letterSpacing: -1.0,
            color: BillyTheme.textPrimary,
          ),
        ),
        const SizedBox(height: BillyTheme.space8),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: BillyTheme.space8,
                vertical: BillyTheme.space4,
              ),
              decoration: const BoxDecoration(color: BillyTheme.black),
              child: const Text(
                'SIGNED IN',
                style: TextStyle(
                  fontSize: 10.0,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2.0,
                  color: BillyTheme.white,
                ),
              ),
            ),
            const SizedBox(width: BillyTheme.space8),
            Text(
              account.displayName,
              style: const TextStyle(
                fontSize: 11.0,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.5,
                color: BillyTheme.textSecondary,
              ),
            ),
          ],
        ),

        const SizedBox(height: BillyTheme.space32),
        const Text(
          'POINT BILLY AT ADVERTISEMENTS TO SCAN AND DISCOVER.',
          style: TextStyle(
            fontSize: 12.0,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.5,
            height: 1.4,
            color: BillyTheme.textSecondary,
          ),
        ),

        const Spacer(),

        BillyButton(
          text: 'SCAN NOW',
          height: 52.0,
          onPressed: () => Navigator.of(context).pop(),
        ),

        const SizedBox(height: BillyTheme.space12),

        BillyButton(
          text: 'SIGN OUT',
          isOutlined: true,
          height: 52.0,
          onPressed: () {
            setState(() {
              _accountSession.signOut();
            });
          },
        ),

        const SizedBox(height: BillyTheme.space48),
      ],
    );
  }

  Widget _buildAdvertiserView(Account account) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ADVERTISER',
          style: TextStyle(
            fontSize: 36.0,
            fontWeight: FontWeight.w900,
            letterSpacing: -1.0,
            color: BillyTheme.textPrimary,
          ),
        ),
        const SizedBox(height: BillyTheme.space8),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: BillyTheme.space8,
                vertical: BillyTheme.space4,
              ),
              decoration: const BoxDecoration(color: BillyTheme.black),
              child: const Text(
                'SIGNED IN',
                style: TextStyle(
                  fontSize: 10.0,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2.0,
                  color: BillyTheme.white,
                ),
              ),
            ),
            const SizedBox(width: BillyTheme.space8),
            Text(
              account.displayName,
              style: const TextStyle(
                fontSize: 11.0,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.5,
                color: BillyTheme.textSecondary,
              ),
            ),
          ],
        ),

        const Spacer(),

        BillyButton(
          text: 'YOUR ADS',
          height: 52.0,
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => CampaignListScreen(
                  ownerAccountId: account.id,
                ),
              ),
            );
          },
        ),

        const SizedBox(height: BillyTheme.space12),

        BillyButton(
          text: 'CREATE AD',
          isOutlined: true,
          height: 52.0,
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => CreateCampaignScreen(
                  ownerAccountId: account.id,
                ),
              ),
            );
          },
        ),

        const SizedBox(height: BillyTheme.space12),

        BillyButton(
          text: 'SIGN OUT',
          isOutlined: true,
          height: 52.0,
          onPressed: () {
            setState(() {
              _accountSession.signOut();
            });
          },
        ),

        const SizedBox(height: BillyTheme.space48),
      ],
    );
  }
}
