import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;
import '../app/theme.dart';
import '../models/account.dart';
import '../services/account_session.dart';
import '../services/supabase/supabase_service.dart';
import '../widgets/billy_button.dart';
import 'advertiser_onboarding_screen.dart';
import 'campaign_list_screen.dart';
import 'create_campaign_screen.dart';
import 'rewards_screen.dart';

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
        Image.asset(
          'assets/branding/logo_transparent_black.png',
          width: 48,
          height: 48,
          fit: BoxFit.contain,
        ),
        const SizedBox(height: BillyTheme.space24),
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
          onPressed: _handleAdvertiserFlow,
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
          text: 'REWARDS',
          isOutlined: true,
          height: 52.0,
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => RewardsScreen(
                  accountSession: _accountSession,
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
          text: 'ACCOUNT SETTINGS',
          isOutlined: true,
          height: 52.0,
          onPressed: () => _showAccountSettingsDialog(context, account),
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

  void _showAccountSettingsDialog(BuildContext context, Account account) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: BillyTheme.background,
        shape: const RoundedRectangleBorder(
          side: BorderSide(color: BillyTheme.black, width: 2),
        ),
        title: const Text(
          'ACCOUNT SETTINGS',
          style: TextStyle(
            fontSize: 16.0,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
            color: BillyTheme.textPrimary,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ACCOUNT: ${account.displayName}',
              style: const TextStyle(
                fontSize: 12.0,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
                color: BillyTheme.textPrimary,
              ),
            ),
            const SizedBox(height: BillyTheme.space8),
            Text(
              'EMAIL: ${account.email}',
              style: const TextStyle(
                fontSize: 11.0,
                fontWeight: FontWeight.w500,
                color: BillyTheme.textSecondary,
              ),
            ),
            const SizedBox(height: BillyTheme.space8),
            Text(
              'ROLE: ${account.role.displayName.toUpperCase()}',
              style: const TextStyle(
                fontSize: 11.0,
                fontWeight: FontWeight.w500,
                color: BillyTheme.textSecondary,
              ),
            ),
            const SizedBox(height: BillyTheme.space8),
            Text(
              'ID: ${account.id}',
              style: const TextStyle(
                fontSize: 10.0,
                fontWeight: FontWeight.w400,
                color: BillyTheme.textSecondary,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text(
              'CLOSE',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: BillyTheme.black,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // PHASE 2 — ADVERTISER AUTH & ONBOARDING ROUTING
  // ===========================================================================

  Future<void> _handleAdvertiserFlow() async {
    final supabase = SupabaseService();

    // In widget test environments or when Supabase client is uninitialized,
    // gracefully fall back to local advertiser session immediately.
    bool hasLiveSupabase = false;
    try {
      hasLiveSupabase = supabase.isInitialized;
    } catch (_) {
      hasLiveSupabase = false;
    }

    if (!hasLiveSupabase) {
      setState(() {
        _accountSession.signInAsAdvertiser();
      });
      return;
    }

    // 1. If not authenticated with Supabase, present clean login/sign-up dialog
    if (!supabase.isAuthenticated) {
      final success = await _showAdvertiserAuthDialog(context);
      if (success != true || !mounted) return;
    }

    // 2. Check if advertiser profile already exists for the authenticated user
    try {
      final existingProfile = await supabase.getAdvertiserProfile();

      if (existingProfile != null) {
        // Profile exists: attach to session and open advertiser dashboard
        final user = supabase.client.auth.currentUser;
        final account = Account(
          id: user?.id ?? existingProfile.createdBy,
          email: user?.email ?? existingProfile.contactEmail,
          displayName: existingProfile.displayName,
          role: AccountRole.advertiser,
          createdAt: existingProfile.createdAt ?? DateTime.now(),
          advertiserProfile: existingProfile,
        );

        setState(() {
          _accountSession.signIn(account);
        });
      } else {
        // Profile missing: route to AdvertiserOnboardingScreen
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AdvertiserOnboardingScreen(
              supabaseService: supabase,
              accountSession: _accountSession,
              onOnboardingComplete: () {
                Navigator.of(context).pop();
                setState(() {});
              },
            ),
          ),
        );
      }
    } catch (e) {
      // Offline / network failure fallback: allow session continuation with diagnostic warning
      debugPrint('AccountScreen: Profile check failed (offline/network): $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('ADVERTISER SYNC NOTICE: $e'),
          backgroundColor: BillyTheme.black,
        ),
      );
      setState(() {
        _accountSession.signInAsAdvertiser();
      });
    }
  }

  Future<bool?> _showAdvertiserAuthDialog(BuildContext context) {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    bool isSignUp = false;
    bool isLoading = false;
    String? dialogError;

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: BillyTheme.background,
          shape: const RoundedRectangleBorder(
            side: BorderSide(color: BillyTheme.black, width: BillyTheme.borderWidthBold),
          ),
          title: Text(
            isSignUp ? 'CREATE ADVERTISER ACCOUNT' : 'ADVERTISER SIGN IN',
            style: const TextStyle(
              fontSize: 16.0,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
              color: BillyTheme.textPrimary,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'SIGN IN TO MANAGE CAMPAIGNS & ASSETS.',
                  style: TextStyle(
                    fontSize: 10.0,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                    color: BillyTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: BillyTheme.space16),
                const Text(
                  'EMAIL',
                  style: TextStyle(
                    fontSize: 10.0,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                    color: BillyTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: BillyTheme.space4),
                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                  decoration: const InputDecoration(
                    hintText: 'advertiser@brand.com',
                    filled: true,
                    fillColor: BillyTheme.surface,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.zero),
                  ),
                ),
                const SizedBox(height: BillyTheme.space12),
                const Text(
                  'PASSWORD',
                  style: TextStyle(
                    fontSize: 10.0,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                    color: BillyTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: BillyTheme.space4),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                  decoration: const InputDecoration(
                    hintText: '••••••••',
                    filled: true,
                    fillColor: BillyTheme.surface,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.zero),
                  ),
                ),
                if (dialogError != null) ...[
                  const SizedBox(height: BillyTheme.space12),
                  Text(
                    dialogError!,
                    style: TextStyle(
                      fontSize: 10.0,
                      fontWeight: FontWeight.w700,
                      color: Colors.red.shade800,
                    ),
                  ),
                ],
                const SizedBox(height: BillyTheme.space16),
                GestureDetector(
                  onTap: () {
                    setDialogState(() {
                      isSignUp = !isSignUp;
                      dialogError = null;
                    });
                  },
                  child: Text(
                    isSignUp
                        ? 'ALREADY HAVE AN ACCOUNT? SIGN IN'
                        : 'NEW ADVERTISER? CREATE ACCOUNT',
                    style: const TextStyle(
                      fontSize: 10.0,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                      decoration: TextDecoration.underline,
                      color: BillyTheme.black,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.of(dialogCtx).pop(false),
              child: const Text(
                'CANCEL',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: BillyTheme.textSecondary,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: BillyTheme.black,
                foregroundColor: BillyTheme.white,
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              ),
              onPressed: isLoading
                  ? null
                  : () async {
                      final email = emailController.text.trim();
                      final password = passwordController.text;

                      if (email.isEmpty || !email.contains('@') || password.isEmpty) {
                        setDialogState(() {
                          dialogError = 'ENTER A VALID EMAIL AND PASSWORD.';
                        });
                        return;
                      }

                      setDialogState(() {
                        isLoading = true;
                        dialogError = null;
                      });

                      try {
                        final supabase = SupabaseService();
                        if (isSignUp) {
                          await supabase.client.auth.signUp(
                            email: email,
                            password: password,
                          );
                        } else {
                          await supabase.client.auth.signInWithPassword(
                            email: email,
                            password: password,
                          );
                        }
                        if (dialogCtx.mounted) {
                          Navigator.of(dialogCtx).pop(true);
                        }
                      } on AuthException catch (e) {
                        setDialogState(() {
                          dialogError = e.message.toUpperCase();
                          isLoading = false;
                        });
                      } catch (e) {
                        setDialogState(() {
                          dialogError = 'AUTH FAILED: $e';
                          isLoading = false;
                        });
                      }
                    },
              child: Text(
                isLoading ? 'WAIT...' : (isSignUp ? 'SIGN UP' : 'SIGN IN'),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
