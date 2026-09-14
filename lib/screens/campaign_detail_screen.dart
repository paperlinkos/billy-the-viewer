import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app/theme.dart';
import '../models/campaign.dart';
import '../services/campaign_repository.dart';
import '../services/signature_service.dart';
import '../widgets/billy_button.dart';

/// Minimal editorial screen displaying campaign details and controls:
/// - PAUSE AD / ACTIVATE AD
/// - EDIT AD (metadata + creative replacement with signature regeneration)
/// - DELETE AD (with confirmation)
class CampaignDetailScreen extends StatefulWidget {
  final String campaignId;
  final CampaignRepository? campaignRepository;
  final SignatureService? signatureService;

  const CampaignDetailScreen({
    super.key,
    required this.campaignId,
    this.campaignRepository,
    this.signatureService,
  });

  @override
  State<CampaignDetailScreen> createState() => _CampaignDetailScreenState();
}

class _CampaignDetailScreenState extends State<CampaignDetailScreen> {
  late final CampaignRepository _campaignRepository;
  late final SignatureService _signatureService;
  final ImagePicker _picker = ImagePicker();

  Campaign? _campaign;
  bool _isProcessing = false;
  String _processingMessage = '';

  @override
  void initState() {
    super.initState();
    _campaignRepository = widget.campaignRepository ?? CampaignRepository();
    _signatureService = widget.signatureService ?? SignatureService();
    _loadCampaign();
  }

  void _loadCampaign() {
    setState(() {
      _campaign = _campaignRepository.getCampaign(widget.campaignId);
    });
  }

  void _togglePauseActivate() {
    if (_campaign == null) return;

    if (_campaign!.status == CampaignStatus.active) {
      _campaignRepository.pauseCampaign(_campaign!.id);
    } else {
      _campaignRepository.activateCampaign(_campaign!.id);
    }
    _loadCampaign();
  }

  Future<void> _viewDestination(String urlString) async {
    try {
      final uri = Uri.parse(urlString);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        _showDestinationDialog(urlString);
      }
    } catch (_) {
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

  void _confirmDelete() {
    if (_campaign?.id == CampaignRepository.systemDemoCampaignId) {
      showDialog(
        context: context,
        builder: (dialogContext) {
          return Dialog(
            backgroundColor: BillyTheme.white,
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
            insetPadding: const EdgeInsets.symmetric(horizontal: BillyTheme.space24),
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
                    'PROTECTED DEMO AD',
                    style: TextStyle(
                      fontSize: 16.0,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2.0,
                      color: BillyTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: BillyTheme.space12),
                  const Text(
                    'STUDIO NOIR IS THE SYSTEM BASELINE DEMO ADVERTISEMENT AND CANNOT BE DELETED.',
                    style: TextStyle(
                      fontSize: 11.0,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.5,
                      height: 1.4,
                      color: BillyTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: BillyTheme.space24),
                  BillyButton(
                    text: 'OK',
                    height: 44.0,
                    onPressed: () => Navigator.of(dialogContext).pop(),
                  ),
                ],
              ),
            ),
          );
        },
      );
      return;
    }

    showDialog(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: BillyTheme.white,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          insetPadding: const EdgeInsets.symmetric(horizontal: BillyTheme.space24),
          child: Container(
            padding: const EdgeInsets.all(BillyTheme.space24),
            decoration: BoxDecoration(
              border: Border.all(
                color: BillyTheme.black,
                width: BillyTheme.borderWidthBold,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'DELETE AD',
                  style: TextStyle(
                    fontSize: 16.0,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.0,
                    color: BillyTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: BillyTheme.space12),
                const Text(
                  'ARE YOU SURE YOU WANT TO DELETE THIS ADVERTISEMENT? IT WILL BE IMMEDIATELY REMOVED FROM RECOGNITION.',
                  style: TextStyle(
                    fontSize: 11.0,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.5,
                    height: 1.4,
                    color: BillyTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: BillyTheme.space24),
                BillyButton(
                  text: 'CONFIRM DELETE',
                  height: 48.0,
                  onPressed: () {
                    _campaignRepository.deleteCampaign(widget.campaignId);
                    Navigator.of(dialogContext).pop();
                    Navigator.of(context).pop(true); // Return to list with deleted flag
                  },
                ),
                const SizedBox(height: BillyTheme.space8),
                BillyButton(
                  text: 'CANCEL',
                  height: 44.0,
                  isOutlined: true,
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _duplicateCampaign() async {
    if (_campaign == null) return;

    setState(() {
      _isProcessing = true;
      _processingMessage = 'DUPLICATING AD...';
    });

    try {
      final duplicate = await _campaignRepository.duplicateCampaign(
        _campaign!.id,
        signatureService: _signatureService,
      );

      if (!mounted) return;
      setState(() {
        _isProcessing = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: BillyTheme.black,
          content: Text(
            'AD DUPLICATED: ${duplicate.adName}',
            style: const TextStyle(
              color: BillyTheme.white,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
            ),
          ),
        ),
      );

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => CampaignDetailScreen(
            campaignId: duplicate.id,
            campaignRepository: _campaignRepository,
            signatureService: _signatureService,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('DUPLICATION FAILED: $e')),
      );
    }
  }

  void _openEditDialog() {
    if (_campaign == null) return;

    final nameController = TextEditingController(text: _campaign!.adName);
    final brandController = TextEditingController(text: _campaign!.brandName);
    final destController = TextEditingController(text: _campaign!.destinationUrl);
    final formKey = GlobalKey<FormState>();

    Uint8List? newSelectedBytes;
    String? newSelectedPath;
    DateTime? editStartAt = _campaign!.startAt;
    DateTime? editEndAt = _campaign!.endAt;
    String? scheduleError;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: BillyTheme.white,
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              insetPadding: const EdgeInsets.symmetric(horizontal: BillyTheme.space24),
              child: Container(
                padding: const EdgeInsets.all(BillyTheme.space24),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: BillyTheme.black,
                    width: BillyTheme.borderWidthBold,
                  ),
                ),
                child: SingleChildScrollView(
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'EDIT AD',
                              style: TextStyle(
                                fontSize: 16.0,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 2.0,
                                color: BillyTheme.textPrimary,
                              ),
                            ),
                            GestureDetector(
                              onTap: () => Navigator.of(dialogContext).pop(),
                              child: const Icon(Icons.close, size: 20, color: BillyTheme.black),
                            ),
                          ],
                        ),
                        const SizedBox(height: BillyTheme.space12),
                        const Divider(color: BillyTheme.black, thickness: BillyTheme.borderWidthThin),
                        const SizedBox(height: BillyTheme.space16),

                        // Ad Name
                        const Text(
                          'AD NAME',
                          style: TextStyle(fontSize: 10.0, fontWeight: FontWeight.w800, letterSpacing: 2.0),
                        ),
                        const SizedBox(height: BillyTheme.space4),
                        TextFormField(
                          controller: nameController,
                          textCapitalization: TextCapitalization.characters,
                          style: const TextStyle(fontSize: 13.0, fontWeight: FontWeight.w700),
                          decoration: const InputDecoration(
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: BillyTheme.border)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: BillyTheme.black, width: 2.0)),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'REQUIRED' : null,
                        ),

                        const SizedBox(height: BillyTheme.space16),

                        // Brand
                        const Text(
                          'BRAND / ORGANISATION',
                          style: TextStyle(fontSize: 10.0, fontWeight: FontWeight.w800, letterSpacing: 2.0),
                        ),
                        const SizedBox(height: BillyTheme.space4),
                        TextFormField(
                          controller: brandController,
                          style: const TextStyle(fontSize: 13.0, fontWeight: FontWeight.w600),
                          decoration: const InputDecoration(
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: BillyTheme.border)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: BillyTheme.black, width: 2.0)),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'REQUIRED' : null,
                        ),

                        const SizedBox(height: BillyTheme.space16),

                        // Destination URL (strict validation)
                        const Text(
                          'DESTINATION URL',
                          style: TextStyle(fontSize: 10.0, fontWeight: FontWeight.w800, letterSpacing: 2.0),
                        ),
                        const SizedBox(height: BillyTheme.space4),
                        TextFormField(
                          controller: destController,
                          keyboardType: TextInputType.url,
                          style: const TextStyle(fontSize: 13.0, fontWeight: FontWeight.w500),
                          decoration: const InputDecoration(
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: BillyTheme.border)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: BillyTheme.black, width: 2.0)),
                          ),
                          validator: (v) {
                            if (!Campaign.isValidDestinationUrl(v)) {
                              return 'MUST BE A VALID HTTP OR HTTPS URL';
                            }
                            return null;
                          },
                        ),

                        const SizedBox(height: BillyTheme.space16),

                        // Schedule (Start & End)
                        const Text(
                          'CAMPAIGN SCHEDULE',
                          style: TextStyle(fontSize: 10.0, fontWeight: FontWeight.w800, letterSpacing: 2.0),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: BillyTheme.black),
                                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                                ),
                                onPressed: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: editStartAt ?? DateTime.now(),
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2035),
                                  );
                                  if (picked != null) {
                                    setDialogState(() {
                                      editStartAt = picked;
                                    });
                                  }
                                },
                                child: Text(
                                  editStartAt != null
                                      ? 'START: ${_formatDate(editStartAt!)}'
                                      : 'START: NOW',
                                  style: const TextStyle(fontSize: 10.0, fontWeight: FontWeight.w700, color: BillyTheme.black),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: BillyTheme.black),
                                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                                ),
                                onPressed: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: editEndAt ?? DateTime.now().add(const Duration(days: 30)),
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2035),
                                  );
                                  if (picked != null) {
                                    final start = editStartAt ?? DateTime.now();
                                    if (picked.isBefore(start)) {
                                      setDialogState(() {
                                        scheduleError = 'END DATE MUST BE AFTER START DATE';
                                      });
                                    } else {
                                      setDialogState(() {
                                        editEndAt = picked;
                                        scheduleError = null;
                                      });
                                    }
                                  }
                                },
                                child: Text(
                                  editEndAt != null
                                      ? 'END: ${_formatDate(editEndAt!)}'
                                      : 'NO END DATE',
                                  style: const TextStyle(fontSize: 10.0, fontWeight: FontWeight.w700, color: BillyTheme.black),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (scheduleError != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            scheduleError!,
                            style: const TextStyle(fontSize: 10.0, fontWeight: FontWeight.w700, color: Colors.red),
                          ),
                        ],

                        const SizedBox(height: BillyTheme.space24),

                        // Creative Replacement section
                        const Text(
                          'REPLACE CREATIVE IMAGE',
                          style: TextStyle(fontSize: 10.0, fontWeight: FontWeight.w800, letterSpacing: 2.0),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'CHANGING CREATIVE REGENERATES THE RECOGNITION SIGNATURE.',
                          style: TextStyle(fontSize: 9.0, fontWeight: FontWeight.w600, letterSpacing: 1.0, color: BillyTheme.textSecondary),
                        ),
                        const SizedBox(height: BillyTheme.space8),

                        if (newSelectedBytes != null) ...[
                          AspectRatio(
                            aspectRatio: 1.0,
                            child: Container(
                              decoration: BoxDecoration(border: Border.all(color: BillyTheme.black, width: 1.0)),
                              child: Image.memory(newSelectedBytes!, fit: BoxFit.contain),
                            ),
                          ),
                          const SizedBox(height: BillyTheme.space8),
                          const Text(
                            'NEW IMAGE SELECTED · SIGNATURE WILL BE REGENERATED',
                            style: TextStyle(fontSize: 9.0, fontWeight: FontWeight.w700, color: BillyTheme.black),
                          ),
                          const SizedBox(height: BillyTheme.space8),
                        ],

                        Row(
                          children: [
                            Expanded(
                              child: BillyButton(
                                text: 'CHOOSE PHOTO',
                                height: 42.0,
                                isOutlined: true,
                                onPressed: () async {
                                  try {
                                    final XFile? file = await _picker.pickImage(
                                      source: ImageSource.gallery,
                                      maxWidth: 1600,
                                      maxHeight: 1600,
                                      imageQuality: 90,
                                    );
                                    if (file != null) {
                                      final bytes = await file.readAsBytes();
                                      setDialogState(() {
                                        newSelectedBytes = bytes;
                                        newSelectedPath = file.path;
                                      });
                                    }
                                  } catch (_) {}
                                },
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: BillyTheme.space24),

                        BillyButton(
                          text: 'SAVE CHANGES',
                          height: 48.0,
                          onPressed: () async {
                            if (!formKey.currentState!.validate()) return;
                            if (scheduleError != null) return;

                            final messenger = ScaffoldMessenger.of(context);
                            Navigator.of(dialogContext).pop();

                            setState(() {
                              _isProcessing = true;
                              _processingMessage = newSelectedBytes != null
                                  ? 'CREATING RECOGNITION SIGNATURE...'
                                  : 'SAVING CHANGES...';
                            });

                            try {
                              if (newSelectedBytes != null) {
                                // Creative changed: regenerate recognition signature
                                await _campaignRepository.updateCreative(
                                  _campaign!.id,
                                  newSelectedBytes!,
                                  newCreativePath: newSelectedPath,
                                  signatureService: _signatureService,
                                );
                              }

                              // Update other metadata
                              final updated = _campaignRepository.getCampaign(_campaign!.id)!.copyWith(
                                adName: nameController.text.trim().toUpperCase(),
                                brandName: brandController.text.trim(),
                                destinationUrl: destController.text.trim(),
                                startAt: editStartAt,
                                endAt: editEndAt,
                              );
                              _campaignRepository.updateCampaign(updated);

                              if (mounted) {
                                setState(() {
                                  _isProcessing = false;
                                  _campaign = updated;
                                });
                              }
                            } catch (e) {
                              if (mounted) {
                                setState(() {
                                  _isProcessing = false;
                                });
                                messenger.showSnackBar(
                                  SnackBar(content: Text('ERROR SAVING: $e')),
                                );
                              }
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_campaign == null) {
      return Scaffold(
        backgroundColor: BillyTheme.background,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(BillyTheme.space24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: const Text('BACK', style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 2.0)),
                ),
                const Spacer(),
                const Center(child: Text('CAMPAIGN NOT FOUND', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 2.0))),
                const Spacer(),
              ],
            ),
          ),
        ),
      );
    }

    final campaign = _campaign!;

    return Scaffold(
      backgroundColor: BillyTheme.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: BillyTheme.space24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: BillyTheme.space16),

              // Top Nav
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
                            'YOUR ADS',
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
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: BillyTheme.space8, vertical: BillyTheme.space4),
                    decoration: BoxDecoration(
                      color: campaign.effectiveStatus == CampaignStatus.active ? BillyTheme.black : Colors.transparent,
                      border: Border.all(color: BillyTheme.black, width: BillyTheme.borderWidthThin),
                    ),
                    child: Text(
                      campaign.effectiveStatus.displayName,
                      style: TextStyle(
                        fontSize: 10.0,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                        color: campaign.effectiveStatus == CampaignStatus.active ? BillyTheme.white : BillyTheme.black,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: BillyTheme.space12),
              const Divider(color: BillyTheme.black, thickness: BillyTheme.borderWidthThin),
              const SizedBox(height: BillyTheme.space16),

              if (_isProcessing) ...[
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _processingMessage,
                          style: const TextStyle(fontSize: 18.0, fontWeight: FontWeight.w900, letterSpacing: 2.0),
                        ),
                        const SizedBox(height: BillyTheme.space24),
                        const CircularProgressIndicator(
                          strokeWidth: 2.0,
                          valueColor: AlwaysStoppedAnimation<Color>(BillyTheme.black),
                        ),
                      ],
                    ),
                  ),
                ),
              ] else ...[
                Expanded(
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // AD NAME
                        Text(
                          campaign.adName,
                          style: const TextStyle(
                            fontSize: 28.0,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                            color: BillyTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          campaign.brandName,
                          style: const TextStyle(
                            fontSize: 13.0,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 2.0,
                            color: BillyTheme.textSecondary,
                          ),
                        ),

                        const SizedBox(height: BillyTheme.space24),

                        // CREATIVE PREVIEW
                        AspectRatio(
                          aspectRatio: 1.0,
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: BillyTheme.black, width: BillyTheme.borderWidthMedium),
                            ),
                            child: _buildCreativeImage(campaign),
                          ),
                        ),

                        const SizedBox(height: BillyTheme.space24),

                        // DESTINATION
                        const Text(
                          'DESTINATION',
                          style: TextStyle(fontSize: 10.0, fontWeight: FontWeight.w800, letterSpacing: 2.0, color: BillyTheme.textSecondary),
                        ),
                        const SizedBox(height: 4),
                        GestureDetector(
                          onTap: () => _viewDestination(campaign.destinationUrl),
                          child: Text(
                            campaign.destinationUrl,
                            style: const TextStyle(
                              fontSize: 13.0,
                              fontWeight: FontWeight.w600,
                              color: BillyTheme.textPrimary,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),

                        const SizedBox(height: BillyTheme.space16),

                        // SCHEDULE: START, END, CREATED
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'START',
                                  style: TextStyle(
                                    fontSize: 9.0,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 2.0,
                                    color: BillyTheme.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  campaign.startAt != null ? _formatDate(campaign.startAt!) : 'NOW',
                                  style: const TextStyle(fontSize: 11.0, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                const Text(
                                  'END',
                                  style: TextStyle(
                                    fontSize: 9.0,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 2.0,
                                    color: BillyTheme.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  campaign.endAt != null ? _formatDate(campaign.endAt!) : 'NONE (ONGOING)',
                                  style: TextStyle(
                                    fontSize: 11.0,
                                    fontWeight: FontWeight.w600,
                                    color: campaign.isExpired ? Colors.red : BillyTheme.black,
                                  ),
                                ),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                const Text(
                                  'CREATED',
                                  style: TextStyle(
                                    fontSize: 9.0,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 2.0,
                                    color: BillyTheme.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _formatDate(campaign.createdAt),
                                  style: const TextStyle(fontSize: 11.0, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ],
                        ),

                        const SizedBox(height: BillyTheme.space16),

                        // RECOGNITION STATUS (diagnostic status only, no raw vectors)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: BillyTheme.space12,
                            vertical: BillyTheme.space8,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: campaign.isCurrentlyActive ? BillyTheme.black : BillyTheme.borderSubtle,
                              width: BillyTheme.borderWidthThin,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: campaign.isCurrentlyActive ? BillyTheme.black : BillyTheme.borderSubtle,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: BillyTheme.space8),
                              Text(
                                campaign.isCurrentlyActive ? 'READY FOR RECOGNITION' : 'NOT IN RECOGNITION',
                                style: const TextStyle(
                                  fontSize: 10.0,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 2.0,
                                  color: BillyTheme.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: BillyTheme.space24),
                        const Divider(color: BillyTheme.borderSubtle, thickness: BillyTheme.borderWidthThin),
                        const SizedBox(height: BillyTheme.space24),

                        // CONTROLS
                        if (campaign.effectiveStatus == CampaignStatus.active)
                          BillyButton(
                            text: 'PAUSE AD',
                            isOutlined: true,
                            height: 48.0,
                            onPressed: _togglePauseActivate,
                          )
                        else if (campaign.effectiveStatus == CampaignStatus.paused)
                          BillyButton(
                            text: 'ACTIVATE AD',
                            height: 48.0,
                            onPressed: _togglePauseActivate,
                          ),

                        const SizedBox(height: BillyTheme.space12),

                        BillyButton(
                          text: 'EDIT AD',
                          isOutlined: true,
                          height: 48.0,
                          onPressed: _openEditDialog,
                        ),

                        const SizedBox(height: BillyTheme.space12),

                        BillyButton(
                          text: 'DUPLICATE AD',
                          isOutlined: true,
                          height: 48.0,
                          onPressed: _duplicateCampaign,
                        ),

                        const SizedBox(height: BillyTheme.space12),

                        BillyButton(
                          text: 'DELETE AD',
                          isOutlined: true,
                          height: 48.0,
                          onPressed: _confirmDelete,
                        ),

                        const SizedBox(height: BillyTheme.space32),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCreativeImage(Campaign campaign) {
    if (campaign.creativeBytes != null) {
      return Image.memory(campaign.creativeBytes!, fit: BoxFit.contain);
    }
    if (campaign.creativeAsset != null && campaign.creativeAsset!.isNotEmpty) {
      return Image.asset(campaign.creativeAsset!, fit: BoxFit.contain);
    }
    return const Center(
      child: Text('NO PREVIEW AVAILABLE', style: TextStyle(fontSize: 10.0, fontWeight: FontWeight.w700)),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, "0")}-${dt.day.toString().padLeft(2, "0")}';
  }
}
