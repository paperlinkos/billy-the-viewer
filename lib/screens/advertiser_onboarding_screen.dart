import 'package:flutter/material.dart';
import '../app/theme.dart';
import '../models/account.dart';
import '../models/advertiser_profile.dart';
import '../services/account_session.dart';
import '../services/supabase/supabase_service.dart';
import '../widgets/billy_button.dart';

/// Screen for onboarding new advertisers:
/// Supports INDIVIDUAL and ORGANIZATION profiles matching `public.advertiser_profiles`.
class AdvertiserOnboardingScreen extends StatefulWidget {
  final SupabaseService? supabaseService;
  final AccountSession? accountSession;
  final VoidCallback? onOnboardingComplete;

  const AdvertiserOnboardingScreen({
    super.key,
    this.supabaseService,
    this.accountSession,
    this.onOnboardingComplete,
  });

  @override
  State<AdvertiserOnboardingScreen> createState() => _AdvertiserOnboardingScreenState();
}

class _AdvertiserOnboardingScreenState extends State<AdvertiserOnboardingScreen> {
  final _formKey = GlobalKey<FormState>();

  AdvertiserAccountType _accountType = AdvertiserAccountType.individual;

  final _displayNameController = TextEditingController();
  final _legalNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _websiteController = TextEditingController();
  final _taxIdController = TextEditingController();

  late final SupabaseService _supabaseService;
  late final AccountSession _accountSession;

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _supabaseService = widget.supabaseService ?? SupabaseService();
    _accountSession = widget.accountSession ?? AccountSession();

    // Pre-populate email if user is already signed in with Supabase Auth
    final userEmail = _supabaseService.client.auth.currentUser?.email ??
        _accountSession.currentAccount?.email;
    if (userEmail != null && userEmail.isNotEmpty && !userEmail.contains('billy.local')) {
      _emailController.text = userEmail;
    }
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _legalNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _websiteController.dispose();
    _taxIdController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_formKey.currentState != null && !_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final profile = await _supabaseService.ensureAdvertiserProfile(
        displayName: _displayNameController.text.trim(),
        accountType: _accountType,
        legalName: _accountType == AdvertiserAccountType.organization
            ? _legalNameController.text.trim()
            : null,
        contactEmail: _emailController.text.trim().toLowerCase(),
        contactPhone: _phoneController.text.trim().isNotEmpty
            ? _phoneController.text.trim()
            : null,
        websiteUrl: _websiteController.text.trim().isNotEmpty
            ? _websiteController.text.trim()
            : null,
        taxOrBusinessId: _taxIdController.text.trim().isNotEmpty
            ? _taxIdController.text.trim()
            : null,
      );

      // Cache profile in active advertiser session
      if (_accountSession.currentAccount != null) {
        _accountSession.attachAdvertiserProfile(profile);
      } else {
        final account = Account(
          id: _supabaseService.currentUserId ?? profile.createdBy,
          email: profile.contactEmail,
          displayName: profile.displayName,
          role: AccountRole.advertiser,
          createdAt: DateTime.now(),
          advertiserProfile: profile,
        );
        _accountSession.signIn(account);
      }

      if (!mounted) return;

      if (widget.onOnboardingComplete != null) {
        widget.onOnboardingComplete!();
      } else {
        Navigator.of(context).pop(profile);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'COULD NOT SAVE PROFILE: $e';
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOrg = _accountType == AdvertiserAccountType.organization;

    return Scaffold(
      backgroundColor: BillyTheme.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: BillyTheme.space24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: BillyTheme.space16),

                // Back Button & Header
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
                              'CANCEL',
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
                    const Text(
                      'ONBOARDING',
                      style: TextStyle(
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
                  'ADVERTISER SETUP',
                  style: TextStyle(
                    fontSize: 32.0,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1.0,
                    color: BillyTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: BillyTheme.space8),
                const Text(
                  'SELECT YOUR ACCOUNT TYPE AND IDENTITY.',
                  style: TextStyle(
                    fontSize: 11.0,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2.0,
                    color: BillyTheme.textSecondary,
                  ),
                ),

                const SizedBox(height: BillyTheme.space24),

                // Account Type Selector: [ INDIVIDUAL ] [ ORGANIZATION ]
                Row(
                  children: [
                    Expanded(
                      child: _buildTypeSegment(
                        label: 'INDIVIDUAL',
                        isSelected: !isOrg,
                        onTap: () => setState(() => _accountType = AdvertiserAccountType.individual),
                      ),
                    ),
                    const SizedBox(width: BillyTheme.space12),
                    Expanded(
                      child: _buildTypeSegment(
                        label: 'ORGANIZATION',
                        isSelected: isOrg,
                        onTap: () => setState(() => _accountType = AdvertiserAccountType.organization),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: BillyTheme.space24),

                // ORGANIZATION-ONLY: Company / Legal Name
                if (isOrg) ...[
                  _buildFieldLabel('COMPANY / LEGAL NAME *'),
                  const SizedBox(height: BillyTheme.space8),
                  TextFormField(
                    controller: _legalNameController,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                    decoration: _inputDecoration('e.g. Acme Media Corp Ltd'),
                    validator: (val) {
                      if (isOrg && (val == null || val.trim().isEmpty)) {
                        return 'ORGANIZATION REQUIRES A VALID LEGAL NAME';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: BillyTheme.space16),
                ],

                // Display Name / Brand Name
                _buildFieldLabel('DISPLAY NAME / BRAND NAME *'),
                const SizedBox(height: BillyTheme.space8),
                TextFormField(
                  controller: _displayNameController,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                  decoration: _inputDecoration('e.g. Studio Noir'),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'DISPLAY NAME / BRAND NAME IS REQUIRED';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: BillyTheme.space16),

                // Contact Email
                _buildFieldLabel('CONTACT EMAIL *'),
                const SizedBox(height: BillyTheme.space8),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                  decoration: _inputDecoration('advertiser@brand.com'),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty || !val.contains('@')) {
                      return 'A VALID CONTACT EMAIL IS REQUIRED';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: BillyTheme.space16),

                // Contact Phone
                _buildFieldLabel('CONTACT PHONE (OPTIONAL)'),
                const SizedBox(height: BillyTheme.space8),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                  decoration: _inputDecoration('+1 555 0199'),
                ),

                const SizedBox(height: BillyTheme.space16),

                // Website
                _buildFieldLabel('WEBSITE (OPTIONAL)'),
                const SizedBox(height: BillyTheme.space8),
                TextFormField(
                  controller: _websiteController,
                  keyboardType: TextInputType.url,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                  decoration: _inputDecoration('https://brand.com'),
                ),

                if (isOrg) ...[
                  const SizedBox(height: BillyTheme.space16),
                  _buildFieldLabel('TAX / BUSINESS ID (OPTIONAL)'),
                  const SizedBox(height: BillyTheme.space8),
                  TextFormField(
                    controller: _taxIdController,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                    decoration: _inputDecoration('VAT / EIN / Business Reg'),
                  ),
                ],

                if (_errorMessage != null) ...[
                  const SizedBox(height: BillyTheme.space16),
                  Container(
                    padding: const EdgeInsets.all(BillyTheme.space12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      border: Border.all(color: Colors.red.shade700, width: BillyTheme.borderWidthThin),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(
                        fontSize: 11.0,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                        color: Colors.red.shade900,
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: BillyTheme.space32),

                BillyButton(
                  text: _isSubmitting ? 'SAVING PROFILE...' : 'CONFIRM & CONTINUE',
                  height: 54.0,
                  onPressed: _isSubmitting ? null : _submit,
                ),

                const SizedBox(height: BillyTheme.space48),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTypeSegment({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: BillyTheme.space12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? BillyTheme.black : BillyTheme.background,
          border: Border.all(
            color: BillyTheme.black,
            width: BillyTheme.borderWidthThin,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.0,
            fontWeight: FontWeight.w800,
            letterSpacing: 2.0,
            color: isSelected ? BillyTheme.white : BillyTheme.black,
          ),
        ),
      ),
    );
  }

  Widget _buildFieldLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 10.0,
        fontWeight: FontWeight.w800,
        letterSpacing: 2.0,
        color: BillyTheme.textSecondary,
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
        color: BillyTheme.textSecondary,
        fontWeight: FontWeight.w500,
        fontSize: 13.0,
      ),
      filled: true,
      fillColor: BillyTheme.surface,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: BillyTheme.space12,
        vertical: BillyTheme.space12,
      ),
      border: const OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: BillyTheme.black, width: BillyTheme.borderWidthThin),
      ),
      enabledBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: BillyTheme.black, width: BillyTheme.borderWidthThin),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: BillyTheme.black, width: BillyTheme.borderWidthBold),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: Colors.red.shade700, width: BillyTheme.borderWidthThin),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: Colors.red.shade700, width: BillyTheme.borderWidthBold),
      ),
    );
  }
}
