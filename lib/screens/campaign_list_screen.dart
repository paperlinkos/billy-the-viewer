import 'package:flutter/material.dart';
import '../app/theme.dart';
import '../models/campaign.dart';
import '../services/account_session.dart';
import '../services/campaign_repository.dart';
import '../widgets/billy_button.dart';
import 'campaign_detail_screen.dart';
import 'create_campaign_screen.dart';

/// Screen displaying a minimal, brutalist list of registered campaigns.
/// Allows viewing details, status controls, and editing for each campaign.
class CampaignListScreen extends StatefulWidget {
  final CampaignRepository? campaignRepository;
  final String? ownerAccountId;

  const CampaignListScreen({
    super.key,
    this.campaignRepository,
    this.ownerAccountId,
  });

  @override
  State<CampaignListScreen> createState() => _CampaignListScreenState();
}

class _CampaignListScreenState extends State<CampaignListScreen> {
  late final CampaignRepository _campaignRepository;

  @override
  void initState() {
    super.initState();
    _campaignRepository = widget.campaignRepository ?? CampaignRepository();
  }

  String? get _effectiveOwnerId =>
      widget.ownerAccountId ??
      (AccountSession().isAdvertiser ? AccountSession().currentAccount?.id : null);

  void _openCreateScreen() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CreateCampaignScreen(
          campaignRepository: _campaignRepository,
          ownerAccountId: _effectiveOwnerId,
        ),
      ),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  void _openDetailScreen(Campaign campaign) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CampaignDetailScreen(
          campaignId: campaign.id,
          campaignRepository: _campaignRepository,
        ),
      ),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final ownerId = _effectiveOwnerId;
    final campaigns = ownerId != null
        ? _campaignRepository.getCampaignsForOwner(ownerId)
        : _campaignRepository.campaigns;

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
                  GestureDetector(
                    onTap: _openCreateScreen,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: BillyTheme.space12,
                        vertical: BillyTheme.space8,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: BillyTheme.black,
                          width: BillyTheme.borderWidthThin,
                        ),
                      ),
                      child: const Text(
                        '+ CREATE AD',
                        style: TextStyle(
                          fontSize: 10.0,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.5,
                          color: BillyTheme.black,
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

              const SizedBox(height: BillyTheme.space24),

              const Text(
                'YOUR ADS',
                style: TextStyle(
                  fontSize: 28.0,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                  color: BillyTheme.textPrimary,
                ),
              ),
              const SizedBox(height: BillyTheme.space4),
              Text(
                '${campaigns.length} REGISTERED CAMPAIGN${campaigns.length != 1 ? "S" : ""}',
                style: const TextStyle(
                  fontSize: 10.0,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2.0,
                  color: BillyTheme.textSecondary,
                ),
              ),

              const SizedBox(height: BillyTheme.space16),

              // --- Advertiser Dashboard Status Summary ---
              Wrap(
                spacing: BillyTheme.space8,
                runSpacing: BillyTheme.space4,
                children: [
                  _buildStatusPill(
                    'ACTIVE',
                    campaigns.where((c) => c.effectiveStatus == CampaignStatus.active).length,
                  ),
                  _buildStatusPill(
                    'PAUSED',
                    campaigns.where((c) => c.effectiveStatus == CampaignStatus.paused).length,
                  ),
                  _buildStatusPill(
                    'EXPIRED',
                    campaigns.where((c) => c.effectiveStatus == CampaignStatus.expired).length,
                  ),
                  _buildStatusPill(
                    'PROCESSING',
                    campaigns.where((c) => c.effectiveStatus == CampaignStatus.processing).length,
                  ),
                ],
              ),

              const SizedBox(height: BillyTheme.space24),

              // --- List of Campaigns ---
              Expanded(
                child: campaigns.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              'NO ADS YET.',
                              style: TextStyle(
                                fontSize: 13.0,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 2.0,
                                color: BillyTheme.textSecondary,
                              ),
                            ),
                            const SizedBox(height: BillyTheme.space16),
                            BillyButton(
                              text: 'CREATE YOUR FIRST AD',
                              width: 240,
                              height: 48.0,
                              onPressed: _openCreateScreen,
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        physics: const ClampingScrollPhysics(),
                        itemCount: campaigns.length,
                        separatorBuilder: (context, index) => const Divider(
                          color: BillyTheme.borderSubtle,
                          thickness: BillyTheme.borderWidthThin,
                          height: BillyTheme.borderWidthThin,
                        ),
                        itemBuilder: (context, index) {
                          final campaign = campaigns[index];
                          return _buildCampaignRow(campaign);
                        },
                      ),
              ),

              const SizedBox(height: BillyTheme.space16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusPill(String label, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: BillyTheme.space8,
        vertical: BillyTheme.space4,
      ),
      decoration: BoxDecoration(
        border: Border.all(
          color: BillyTheme.black,
          width: BillyTheme.borderWidthThin,
        ),
      ),
      child: Text(
        '$label ($count)',
        style: const TextStyle(
          fontSize: 9.0,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.5,
          color: BillyTheme.textPrimary,
        ),
      ),
    );
  }

  Widget _buildCampaignRow(Campaign campaign) {
    final status = campaign.effectiveStatus;
    final isActive = status == CampaignStatus.active;

    return InkWell(
      onTap: () => _openDetailScreen(campaign),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: BillyTheme.space16,
          horizontal: BillyTheme.space4,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Left: Ad Name & Brand & optional Schedule
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    campaign.adName,
                    style: const TextStyle(
                      fontSize: 15.0,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                      color: BillyTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    campaign.brandName,
                    style: const TextStyle(
                      fontSize: 12.0,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 1.0,
                      color: BillyTheme.textSecondary,
                    ),
                  ),
                  if (campaign.startAt != null || campaign.endAt != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      '${campaign.startAt != null ? _formatDate(campaign.startAt!) : "NOW"} — ${campaign.endAt != null ? _formatDate(campaign.endAt!) : "ONGOING"}',
                      style: const TextStyle(
                        fontSize: 9.0,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.0,
                        color: BillyTheme.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Right: Status
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: BillyTheme.space8,
                vertical: BillyTheme.space4,
              ),
              decoration: BoxDecoration(
                border: Border.all(
                  color: isActive ? BillyTheme.black : BillyTheme.borderSubtle,
                  width: BillyTheme.borderWidthThin,
                ),
                color: isActive ? BillyTheme.black : Colors.transparent,
              ),
              child: Text(
                status.displayName,
                style: TextStyle(
                  fontSize: 9.0,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                  color: isActive ? BillyTheme.white : BillyTheme.textSecondary,
                ),
              ),
            ),

            const SizedBox(width: BillyTheme.space12),

            const Icon(
              Icons.chevron_right,
              size: 16,
              color: BillyTheme.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, "0")}-${dt.day.toString().padLeft(2, "0")}';
  }
}
