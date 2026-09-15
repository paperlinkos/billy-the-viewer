import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app/theme.dart';
import '../models/campaign.dart';
import '../services/account_session.dart';
import '../services/campaign_repository.dart';
import '../services/signature_service.dart';
import '../widgets/billy_button.dart';
import 'account_screen.dart';
import 'campaign_list_screen.dart';

/// Screen managing Billy's multi-step advertiser campaign pipeline:
/// STEP 1: AD CREATIVE (upload / sample, preview, confirm)
/// STEP 2: CAMPAIGN INFORMATION (name, brand, destination, optional schedule)
/// STEP 3: REVIEW (visual confirmation before learning)
/// STEP 4: PROCESSING (signature extraction via SignatureService)
/// STEP 5: AD ACTIVE (campaign registered and available to Billy's recognition engine)
class CreateCampaignScreen extends StatefulWidget {
  final SignatureService? signatureService;
  final CampaignRepository? campaignRepository;
  final AccountSession? accountSession;
  final Uint8List? initialCreativeBytes;
  final String? ownerAccountId;

  const CreateCampaignScreen({
    super.key,
    this.signatureService,
    this.campaignRepository,
    this.accountSession,
    this.initialCreativeBytes,
    this.ownerAccountId,
  });

  @override
  State<CreateCampaignScreen> createState() => _CreateCampaignScreenState();
}

class _CreateCampaignScreenState extends State<CreateCampaignScreen> {
  final _formKey = GlobalKey<FormState>();
  final _adNameController = TextEditingController();
  final _brandController = TextEditingController();
  final _destinationController = TextEditingController(text: 'https://example.com');

  DateTime? _startAt = DateTime.now();
  DateTime? _endAt;
  String? _scheduleError;

  final ImagePicker _picker = ImagePicker();
  late final SignatureService _signatureService;
  late final CampaignRepository _campaignRepository;
  late final AccountSession _accountSession;

  Uint8List? _creativeBytes;
  String? _creativePath;
  String? _creativeAsset;
  bool _isCreativeConfirmed = false;

  bool _isReviewStep = false;
  CampaignStatus _currentStatus = CampaignStatus.draft;
  String _processingStageText = '';
  Campaign? _activeCampaign;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _accountSession = widget.accountSession ?? AccountSession();
    _signatureService = widget.signatureService ?? SignatureService();
    _campaignRepository = widget.campaignRepository ?? CampaignRepository();
    if (widget.initialCreativeBytes != null) {
      _creativeBytes = widget.initialCreativeBytes;
    }
  }

  @override
  void dispose() {
    _adNameController.dispose();
    _brandController.dispose();
    _destinationController.dispose();
    super.dispose();
  }

  Future<void> _pickImageFromGallery() async {
    try {
      final XFile? file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 90,
      );

      if (file != null) {
        final bytes = await file.readAsBytes();
        setState(() {
          _creativeBytes = bytes;
          _creativePath = file.path;
          _creativeAsset = null;
          _isCreativeConfirmed = false;
          _errorMessage = null;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'COULD NOT LOAD IMAGE: $e';
      });
    }
  }

  Future<void> _useSampleCreative() async {
    try {
      final ByteData data = await rootBundle.load('assets/campaigns/demo_ad.jpg');
      final Uint8List bytes = data.buffer.asUint8List();
      setState(() {
        _creativeBytes = bytes;
        _creativePath = null;
        _creativeAsset = 'assets/campaigns/demo_ad.jpg';
        _isCreativeConfirmed = false;
        _errorMessage = null;
        if (_adNameController.text.isEmpty) {
          _adNameController.text = 'SAMPLE CAMPAIGN';
        }
        if (_brandController.text.isEmpty) {
          _brandController.text = 'Billy Showcase';
        }
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'COULD NOT LOAD SAMPLE CREATIVE: $e';
      });
    }
  }

  Future<void> _processAndActivateCampaign() async {
    if (_accountSession.isConsumer) {
      setState(() {
        _errorMessage = 'CONSUMER ACCOUNTS CANNOT CREATE CAMPAIGNS';
        _currentStatus = CampaignStatus.draft;
        _isReviewStep = false;
      });
      return;
    }

    if (_formKey.currentState != null && !_formKey.currentState!.validate()) {
      setState(() {
        _isReviewStep = false;
      });
      return;
    }

    if (_scheduleError != null) {
      setState(() {
        _isReviewStep = false;
      });
      return;
    }

    if (_creativeBytes == null || !_isCreativeConfirmed) {
      setState(() {
        _errorMessage = 'PLEASE CONFIRM AD CREATIVE FIRST';
        _isReviewStep = false;
      });
      return;
    }

    setState(() {
      _currentStatus = CampaignStatus.processing;
      _processingStageText = 'PREPARING AD...';
      _errorMessage = null;
    });

    try {
      await Future.delayed(const Duration(milliseconds: 300));

      if (!mounted) return;
      setState(() {
        _processingStageText = 'ANALYZING VISUAL CREATIVE...';
      });
      await Future.delayed(const Duration(milliseconds: 400));

      if (!mounted) return;
      setState(() {
        _processingStageText = 'CREATING RECOGNITION SIGNATURE...';
      });

      // Signature generation using real SignatureService
      final signature = await _signatureService.generateSignature(_creativeBytes!);

      // Packaging into active campaign
      final campaignId = 'camp-${DateTime.now().millisecondsSinceEpoch}';
      final resolvedOwnerId = widget.ownerAccountId ??
          _accountSession.currentAccount?.id ??
          'system-demo-owner';

      final campaign = Campaign(
        id: campaignId,
        ownerAccountId: resolvedOwnerId,
        adName: _adNameController.text.trim().toUpperCase(),
        brandName: _brandController.text.trim(),
        destinationUrl: _destinationController.text.trim(),
        creativePath: _creativePath,
        creativeAsset: _creativeAsset,
        creativeBytes: _creativeBytes,
        status: CampaignStatus.active,
        createdAt: DateTime.now(),
        startAt: _startAt,
        endAt: _endAt,
        recognitionSignature: signature,
        signatureVersion: signature.version,
      );

      _campaignRepository.addCampaign(campaign);

      if (!mounted) return;
      setState(() {
        _currentStatus = CampaignStatus.active;
        _processingStageText = 'AD READY';
        _activeCampaign = campaign;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _currentStatus = CampaignStatus.processing; // Keep in processing view to show error
        _errorMessage = 'COULD NOT PROCESS AD: $e';
      });
    }
  }

  Future<void> _viewDestination(String urlString) async {
    try {
      final uri = Uri.parse(urlString);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        _showDestinationDialog(urlString);
      }
    } catch (e) {
      _showDestinationDialog(urlString);
    }
  }

  void _showDestinationDialog(String urlString) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: BillyTheme.white,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          child: Container(
            padding: const EdgeInsets.all(BillyTheme.space24),
            decoration: BoxDecoration(
              border: Border.all(color: BillyTheme.black, width: BillyTheme.borderWidthBold),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'DESTINATION URL',
                  style: TextStyle(
                    fontSize: 12.0,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2.0,
                    color: BillyTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: BillyTheme.space12),
                Text(
                  urlString,
                  style: const TextStyle(
                    fontSize: 14.0,
                    fontWeight: FontWeight.w500,
                    color: BillyTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: BillyTheme.space24),
                BillyButton(
                  text: 'CLOSE',
                  height: 46.0,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _navigateToCampaignList() {
    final resolvedOwnerId = widget.ownerAccountId ??
        (_accountSession.isAdvertiser ? _accountSession.currentAccount?.id : null);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => CampaignListScreen(
          campaignRepository: _campaignRepository,
          ownerAccountId: resolvedOwnerId,
        ),
      ),
    );
  }

  Widget _buildAccessDeniedView(BuildContext context) {
    return Scaffold(
      backgroundColor: BillyTheme.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: BillyTheme.space24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: BillyTheme.space16),
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
              const SizedBox(height: BillyTheme.space12),
              const Divider(
                color: BillyTheme.black,
                thickness: BillyTheme.borderWidthThin,
                height: BillyTheme.borderWidthThin,
              ),
              const SizedBox(height: BillyTheme.space32),
              const Text(
                'ACCESS RESTRICTED',
                style: TextStyle(
                  fontSize: 28.0,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.0,
                  color: BillyTheme.textPrimary,
                ),
              ),
              const SizedBox(height: BillyTheme.space8),
              const Text(
                'ADVERTISER ACCOUNT REQUIRED',
                style: TextStyle(
                  fontSize: 11.0,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2.0,
                  color: BillyTheme.textSecondary,
                ),
              ),
              const SizedBox(height: BillyTheme.space24),
              const Text(
                'CAMPAIGN CREATION AND MANAGEMENT IS RESERVED FOR ADVERTISERS.\n\nTO CREATE AND MANAGE ADS, SWITCH TO AN ADVERTISER ACCOUNT.',
                style: TextStyle(
                  fontSize: 13.0,
                  fontWeight: FontWeight.w500,
                  height: 1.5,
                  letterSpacing: 0.5,
                  color: BillyTheme.textPrimary,
                ),
              ),
              const Spacer(),
              BillyButton(
                text: 'CONTINUE TO ACCOUNT',
                height: 52.0,
                onPressed: () {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (_) => AccountScreen(accountSession: _accountSession),
                    ),
                  );
                },
              ),
              const SizedBox(height: BillyTheme.space12),
              BillyButton(
                text: 'GO BACK',
                isOutlined: true,
                height: 52.0,
                onPressed: () => Navigator.of(context).pop(),
              ),
              const SizedBox(height: BillyTheme.space48),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_accountSession.isConsumer) {
      return _buildAccessDeniedView(context);
    }

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
                    onTap: () {
                      if (_isReviewStep) {
                        setState(() {
                          _isReviewStep = false;
                        });
                      } else {
                        Navigator.of(context).pop();
                      }
                    },
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
                  GestureDetector(
                    onTap: () {
                      final resolvedOwnerId = widget.ownerAccountId ??
                          (_accountSession.isAdvertiser
                              ? _accountSession.currentAccount?.id
                              : null);
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => CampaignListScreen(
                            campaignRepository: _campaignRepository,
                            ownerAccountId: resolvedOwnerId,
                          ),
                        ),
                      );
                    },
                    child: Container(
                      color: Colors.transparent,
                      padding: const EdgeInsets.symmetric(
                        vertical: BillyTheme.space8,
                        horizontal: BillyTheme.space8,
                      ),
                      child: const Text(
                        'YOUR ADS',
                        style: TextStyle(
                          fontSize: 11.0,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2.0,
                          color: BillyTheme.textSecondary,
                          decoration: TextDecoration.underline,
                        ),
                      ),
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

              const SizedBox(height: BillyTheme.space16),

              // --- Main Pipeline Stage Switcher ---
              Expanded(
                child: _buildBodyContent(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBodyContent() {
    if (_currentStatus == CampaignStatus.processing) {
      return _buildProcessingView();
    } else if (_currentStatus == CampaignStatus.active && _activeCampaign != null) {
      return _buildSuccessView();
    } else if (_isReviewStep) {
      return _buildReviewView();
    }
    return _buildFormView();
  }

  Widget _buildFormView() {
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'CREATE AN AD',
              style: TextStyle(
                fontSize: 28.0,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
                color: BillyTheme.textPrimary,
              ),
            ),
            const SizedBox(height: BillyTheme.space8),
            const Text(
              'REGISTER A NEW ADVERTISEMENT FOR RECOGNITION.',
              style: TextStyle(
                fontSize: 10.0,
                fontWeight: FontWeight.w700,
                letterSpacing: 2.0,
                color: BillyTheme.textSecondary,
              ),
            ),

            const SizedBox(height: BillyTheme.space24),

            if (_errorMessage != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(BillyTheme.space12),
                decoration: BoxDecoration(
                  border: Border.all(color: BillyTheme.black, width: BillyTheme.borderWidthThin),
                ),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(
                    fontSize: 11.0,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                    color: BillyTheme.black,
                  ),
                ),
              ),
              const SizedBox(height: BillyTheme.space16),
            ],

            // --- STEP 1: AD CREATIVE ---
            const Text(
              'STEP 01 / 05',
              style: TextStyle(
                fontSize: 10.0,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.5,
                color: BillyTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            _buildFieldLabel('AD CREATIVE', 'SUPPORTED FORMATS: JPG, JPEG, PNG'),
            const SizedBox(height: BillyTheme.space8),
            _buildCreativeSection(),

            const SizedBox(height: BillyTheme.space32),
            const Divider(
              color: BillyTheme.borderSubtle,
              thickness: BillyTheme.borderWidthThin,
            ),
            const SizedBox(height: BillyTheme.space24),

            // --- STEP 2: CAMPAIGN INFORMATION ---
            const Text(
              'STEP 02 / 05',
              style: TextStyle(
                fontSize: 10.0,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.5,
                color: BillyTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'CAMPAIGN INFORMATION',
              style: TextStyle(
                fontSize: 13.0,
                fontWeight: FontWeight.w900,
                letterSpacing: 2.0,
                color: BillyTheme.textPrimary,
              ),
            ),
            const SizedBox(height: BillyTheme.space16),

            // Field: AD NAME
            _buildFieldLabel('AD NAME', 'EXAMPLE: STUDIO NOIR'),
            const SizedBox(height: BillyTheme.space8),
            TextFormField(
              controller: _adNameController,
              textCapitalization: TextCapitalization.characters,
              cursorColor: BillyTheme.black,
              style: const TextStyle(
                fontSize: 14.0,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
              decoration: _inputDecoration('ENTER AD NAME'),
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? 'AD NAME REQUIRED' : null,
            ),

            const SizedBox(height: BillyTheme.space24),

            // Field: BRAND / ORGANISATION
            _buildFieldLabel('BRAND / ORGANISATION', 'EXAMPLE: STUDIO NOIR'),
            const SizedBox(height: BillyTheme.space8),
            TextFormField(
              controller: _brandController,
              cursorColor: BillyTheme.black,
              style: const TextStyle(
                fontSize: 14.0,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.0,
              ),
              decoration: _inputDecoration('ENTER BRAND OR CREATOR'),
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? 'BRAND REQUIRED' : null,
            ),

            const SizedBox(height: BillyTheme.space24),

            // Field: DESTINATION
            _buildFieldLabel('DESTINATION', 'EXAMPLE: HTTPS://EXAMPLE.COM'),
            const SizedBox(height: BillyTheme.space8),
            TextFormField(
              controller: _destinationController,
              keyboardType: TextInputType.url,
              cursorColor: BillyTheme.black,
              style: const TextStyle(
                fontSize: 14.0,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.5,
              ),
              decoration: _inputDecoration('ENTER DESTINATION URL'),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'DESTINATION URL REQUIRED';
                }
                if (!Campaign.isValidDestinationUrl(value)) {
                  return 'MUST BE A VALID HTTP OR HTTPS URL';
                }
                return null;
              },
            ),

            const SizedBox(height: BillyTheme.space24),

            // Field: CAMPAIGN SCHEDULE (START & END)
            _buildFieldLabel('CAMPAIGN SCHEDULE', 'START TIME AND OPTIONAL END DATE'),
            const SizedBox(height: BillyTheme.space8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: BillyTheme.black),
                      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _startAt ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2035),
                      );
                      if (picked != null) {
                        setState(() {
                          _startAt = picked;
                        });
                      }
                    },
                    child: Text(
                      _startAt != null ? 'START: ${_formatDate(_startAt!)}' : 'START: NOW',
                      style: const TextStyle(
                        fontSize: 10.0,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                        color: BillyTheme.black,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: BillyTheme.space8),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: BillyTheme.black),
                      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _endAt ?? DateTime.now().add(const Duration(days: 30)),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2035),
                      );
                      if (picked != null) {
                        final start = _startAt ?? DateTime.now();
                        if (picked.isBefore(start)) {
                          setState(() {
                            _scheduleError = 'END DATE MUST BE AFTER START DATE';
                          });
                        } else {
                          setState(() {
                            _endAt = picked;
                            _scheduleError = null;
                          });
                        }
                      }
                    },
                    child: Text(
                      _endAt != null ? 'END: ${_formatDate(_endAt!)}' : 'NO END DATE',
                      style: const TextStyle(
                        fontSize: 10.0,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                        color: BillyTheme.black,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (_scheduleError != null) ...[
              const SizedBox(height: 4),
              Text(
                _scheduleError!,
                style: const TextStyle(
                  fontSize: 10.0,
                  fontWeight: FontWeight.w700,
                  color: Colors.red,
                ),
              ),
            ],

            const SizedBox(height: BillyTheme.space32),

            // Actions: REVIEW AD & CREATE AD
            BillyButton(
              text: 'REVIEW AD',
              onPressed: () {
                if (!_formKey.currentState!.validate()) return;
                if (_scheduleError != null) return;
                if (_creativeBytes == null || !_isCreativeConfirmed) {
                  setState(() {
                    _errorMessage = 'PLEASE CONFIRM AD CREATIVE FIRST';
                  });
                  return;
                }
                setState(() {
                  _errorMessage = null;
                  _isReviewStep = true;
                });
              },
            ),

            const SizedBox(height: BillyTheme.space12),

            BillyButton(
              text: 'CREATE AD',
              isOutlined: true,
              onPressed: _isCreativeConfirmed ? _processAndActivateCampaign : null,
            ),

            const SizedBox(height: BillyTheme.space32),
          ],
        ),
      ),
    );
  }

  Widget _buildReviewView() {
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'STEP 03 / 05',
            style: TextStyle(
              fontSize: 10.0,
              fontWeight: FontWeight.w800,
              letterSpacing: 2.5,
              color: BillyTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'REVIEW YOUR AD',
            style: TextStyle(
              fontSize: 28.0,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
              color: BillyTheme.textPrimary,
            ),
          ),
          const SizedBox(height: BillyTheme.space8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(BillyTheme.space12),
            decoration: BoxDecoration(
              border: Border.all(color: BillyTheme.black, width: BillyTheme.borderWidthThin),
            ),
            child: const Text(
              'THIS IS THE ADVERTISEMENT BILLY WILL LEARN TO RECOGNISE.',
              style: TextStyle(
                fontSize: 11.0,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
                color: BillyTheme.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: BillyTheme.space24),

          // Large Creative Preview
          const Text(
            'CREATIVE',
            style: TextStyle(
              fontSize: 10.0,
              fontWeight: FontWeight.w800,
              letterSpacing: 2.0,
              color: BillyTheme.textSecondary,
            ),
          ),
          const SizedBox(height: BillyTheme.space8),
          AspectRatio(
            aspectRatio: 1.0,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: BillyTheme.black, width: BillyTheme.borderWidthBold),
              ),
              child: Image.memory(
                _creativeBytes!,
                fit: BoxFit.contain,
              ),
            ),
          ),

          const SizedBox(height: BillyTheme.space24),

          // Metadata Grid
          _buildReviewRow('AD NAME', _adNameController.text.trim().toUpperCase()),
          const SizedBox(height: BillyTheme.space12),
          _buildReviewRow('BRAND', _brandController.text.trim()),
          const SizedBox(height: BillyTheme.space12),
          _buildReviewRow('DESTINATION', _destinationController.text.trim()),
          const SizedBox(height: BillyTheme.space12),
          _buildReviewRow(
            'START',
            _startAt != null ? _formatDate(_startAt!) : 'NOW',
          ),
          const SizedBox(height: BillyTheme.space12),
          _buildReviewRow(
            'END',
            _endAt != null ? _formatDate(_endAt!) : 'NONE (ONGOING)',
          ),

          const SizedBox(height: BillyTheme.space32),

          BillyButton(
            text: 'CREATE AD',
            onPressed: _processAndActivateCampaign,
          ),
          const SizedBox(height: BillyTheme.space12),
          BillyButton(
            text: 'EDIT',
            isOutlined: true,
            onPressed: () {
              setState(() {
                _isReviewStep = false;
              });
            },
          ),
          const SizedBox(height: BillyTheme.space32),
        ],
      ),
    );
  }

  Widget _buildReviewRow(String label, String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        border: Border.all(color: BillyTheme.borderSubtle, width: BillyTheme.borderWidthThin),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 9.0,
              fontWeight: FontWeight.w800,
              letterSpacing: 2.0,
              color: BillyTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13.0,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
              color: BillyTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFieldLabel(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 11.0,
            fontWeight: FontWeight.w800,
            letterSpacing: 2.5,
            color: BillyTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: const TextStyle(
            fontSize: 9.0,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.5,
            color: BillyTheme.textSecondary,
          ),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
        fontSize: 12.0,
        fontWeight: FontWeight.w500,
        letterSpacing: 1.5,
        color: BillyTheme.textSecondary,
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: BillyTheme.space16,
        vertical: BillyTheme.space16,
      ),
      enabledBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(
          color: BillyTheme.border,
          width: BillyTheme.borderWidthThin,
        ),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(
          color: BillyTheme.black,
          width: BillyTheme.borderWidthBold,
        ),
      ),
      errorBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(
          color: BillyTheme.black,
          width: BillyTheme.borderWidthThin,
        ),
      ),
      focusedErrorBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(
          color: BillyTheme.black,
          width: BillyTheme.borderWidthBold,
        ),
      ),
    );
  }

  Widget _buildCreativeSection() {
    if (_creativeBytes == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(BillyTheme.space24),
        decoration: BoxDecoration(
          border: Border.all(
            color: BillyTheme.borderSubtle,
            width: BillyTheme.borderWidthThin,
          ),
        ),
        child: Column(
          children: [
            const Icon(Icons.image_outlined, size: 36, color: BillyTheme.textSecondary),
            const SizedBox(height: BillyTheme.space12),
            const Text(
              'SELECT ADVERTISEMENT IMAGE',
              style: TextStyle(
                fontSize: 11.0,
                fontWeight: FontWeight.w700,
                letterSpacing: 2.0,
                color: BillyTheme.textPrimary,
              ),
            ),
            const SizedBox(height: BillyTheme.space16),
            BillyButton(
              text: 'SELECT IMAGE',
              height: 48.0,
              onPressed: _pickImageFromGallery,
            ),
            const SizedBox(height: BillyTheme.space8),
            BillyButton(
              text: 'USE SAMPLE CREATIVE',
              height: 44.0,
              isOutlined: true,
              onPressed: _useSampleCreative,
            ),
          ],
        ),
      );
    }

    // Creative preview with confirmation
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(BillyTheme.space16),
      decoration: BoxDecoration(
        border: Border.all(
          color: _isCreativeConfirmed ? BillyTheme.black : BillyTheme.borderSubtle,
          width: _isCreativeConfirmed ? BillyTheme.borderWidthBold : BillyTheme.borderWidthThin,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Prominent Image Preview
          ConstrainedBox(
            constraints: const BoxConstraints(
              maxHeight: 220,
              minWidth: double.infinity,
            ),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: BillyTheme.black, width: BillyTheme.borderWidthThin),
              ),
              child: Image.memory(
                _creativeBytes!,
                fit: BoxFit.contain,
              ),
            ),
          ),
          const SizedBox(height: BillyTheme.space16),

          if (!_isCreativeConfirmed) ...[
            BillyButton(
              text: 'USE THIS AD',
              height: 48.0,
              onPressed: () {
                setState(() {
                  _isCreativeConfirmed = true;
                  _errorMessage = null;
                });
              },
            ),
            const SizedBox(height: BillyTheme.space8),
            BillyButton(
              text: 'CHANGE IMAGE',
              height: 44.0,
              isOutlined: true,
              onPressed: _pickImageFromGallery,
            ),
          ] else ...[
            Row(
              children: [
                const Icon(Icons.check, size: 16, color: BillyTheme.black),
                const SizedBox(width: BillyTheme.space8),
                const Expanded(
                  child: Text(
                    'CREATIVE CONFIRMED',
                    style: TextStyle(
                      fontSize: 11.0,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2.0,
                      color: BillyTheme.black,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _isCreativeConfirmed = false;
                    });
                  },
                  child: const Text(
                    'CHANGE',
                    style: TextStyle(
                      fontSize: 10.0,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                      color: BillyTheme.textSecondary,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProcessingView() {
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: BillyTheme.space24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text(
                'PROCESSING ERROR',
                style: TextStyle(
                  fontSize: 11.0,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 3.0,
                  color: BillyTheme.textSecondary,
                ),
              ),
              const SizedBox(height: BillyTheme.space16),
              const Text(
                'COULD NOT PROCESS AD',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22.0,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.0,
                  color: BillyTheme.textPrimary,
                ),
              ),
              const SizedBox(height: BillyTheme.space12),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12.0,
                  fontWeight: FontWeight.w600,
                  color: BillyTheme.textSecondary,
                ),
              ),
              const SizedBox(height: BillyTheme.space32),
              BillyButton(
                text: 'TRY AGAIN',
                height: 48.0,
                onPressed: _processAndActivateCampaign,
              ),
              const SizedBox(height: BillyTheme.space12),
              BillyButton(
                text: 'EDIT',
                isOutlined: true,
                height: 48.0,
                onPressed: () {
                  setState(() {
                    _currentStatus = CampaignStatus.draft;
                    _isReviewStep = false;
                    _errorMessage = null;
                  });
                },
              ),
            ],
          ),
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: BillyTheme.space24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text(
              'STEP 04 / 05',
              style: TextStyle(
                fontSize: 10.0,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.5,
                color: BillyTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'BILLY VISION',
              style: TextStyle(
                fontSize: 11.0,
                fontWeight: FontWeight.w800,
                letterSpacing: 3.0,
                color: BillyTheme.textSecondary,
              ),
            ),
            const SizedBox(height: BillyTheme.space16),
            const Text(
              'BILLY IS LEARNING THIS AD',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20.0,
                fontWeight: FontWeight.w900,
                letterSpacing: 2.0,
                color: BillyTheme.textPrimary,
              ),
            ),
            const SizedBox(height: BillyTheme.space12),
            Text(
              _processingStageText.isNotEmpty
                  ? _processingStageText
                  : 'CREATING RECOGNITION SIGNATURE...',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12.0,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
                color: BillyTheme.textSecondary,
              ),
            ),
            const SizedBox(height: BillyTheme.space32),
            Container(
              width: 48,
              height: 48,
              padding: const EdgeInsets.all(BillyTheme.space12),
              decoration: BoxDecoration(
                border: Border.all(color: BillyTheme.black, width: BillyTheme.borderWidthThin),
              ),
              child: const CircularProgressIndicator(
                strokeWidth: 2.0,
                valueColor: AlwaysStoppedAnimation<Color>(BillyTheme.black),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessView() {
    final campaign = _activeCampaign!;

    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'STEP 05 / 05',
            style: TextStyle(
              fontSize: 10.0,
              fontWeight: FontWeight.w800,
              letterSpacing: 2.5,
              color: BillyTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'AD READY',
            style: TextStyle(
              fontSize: 32.0,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
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
                decoration: const BoxDecoration(
                  color: BillyTheme.black,
                ),
                child: const Text(
                  'ACTIVE',
                  style: TextStyle(
                    fontSize: 10.0,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2.0,
                    color: BillyTheme.white,
                  ),
                ),
              ),
              const SizedBox(width: BillyTheme.space8),
              const Text(
                'READY FOR VISUAL RECOGNITION',
                style: TextStyle(
                  fontSize: 10.0,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: BillyTheme.textSecondary,
                ),
              ),
            ],
          ),

          const SizedBox(height: BillyTheme.space24),

          // Details box
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(BillyTheme.space16),
            decoration: BoxDecoration(
              border: Border.all(color: BillyTheme.black, width: BillyTheme.borderWidthMedium),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  campaign.adName,
                  style: const TextStyle(
                    fontSize: 18.0,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                    color: BillyTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: BillyTheme.space4),
                Text(
                  campaign.brandName,
                  style: const TextStyle(
                    fontSize: 12.0,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2.0,
                    color: BillyTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: BillyTheme.space16),
                if (campaign.creativeBytes != null) ...[
                  AspectRatio(
                    aspectRatio: 1.0,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: BillyTheme.borderSubtle,
                          width: BillyTheme.borderWidthThin,
                        ),
                      ),
                      child: Image.memory(
                        campaign.creativeBytes!,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  const SizedBox(height: BillyTheme.space16),
                ],
                const Text(
                  'DESTINATION',
                  style: TextStyle(
                    fontSize: 9.0,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2.0,
                    color: BillyTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  campaign.destinationUrl,
                  style: const TextStyle(
                    fontSize: 12.0,
                    fontWeight: FontWeight.w500,
                    color: BillyTheme.textPrimary,
                  ),
                ),
                if (campaign.recognitionSignature != null) ...[
                  const SizedBox(height: BillyTheme.space12),
                  Text(
                    'SIGNATURE: ${campaign.recognitionSignature!.algorithm} · v${campaign.signatureVersion}',
                    style: const TextStyle(
                      fontSize: 9.0,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                      color: BillyTheme.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: BillyTheme.space32),

          // Primary: DONE
          BillyButton(
            text: 'DONE',
            onPressed: _navigateToCampaignList,
          ),

          const SizedBox(height: BillyTheme.space12),

          // Secondary: VIEW AD
          BillyButton(
            text: 'VIEW AD',
            isOutlined: true,
            onPressed: () => _viewDestination(campaign.destinationUrl),
          ),

          const SizedBox(height: BillyTheme.space12),

          BillyButton(
            text: 'CREATE ANOTHER AD',
            isOutlined: true,
            onPressed: () {
              setState(() {
                _currentStatus = CampaignStatus.draft;
                _isReviewStep = false;
                _activeCampaign = null;
                _creativeBytes = null;
                _creativePath = null;
                _creativeAsset = null;
                _isCreativeConfirmed = false;
                _adNameController.clear();
                _brandController.clear();
                _destinationController.text = 'https://example.com';
                _startAt = DateTime.now();
                _endAt = null;
                _errorMessage = null;
              });
            },
          ),

          const SizedBox(height: BillyTheme.space32),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, "0")}-${dt.day.toString().padLeft(2, "0")}';
  }
}
