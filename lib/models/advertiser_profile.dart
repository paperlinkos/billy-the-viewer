/// Supported advertiser account types matching the Supabase `advertiser_type` enum.
enum AdvertiserAccountType {
  individual,
  organization;

  static AdvertiserAccountType fromString(String? value) {
    if (value == null) return AdvertiserAccountType.individual;
    switch (value.toLowerCase().trim()) {
      case 'organization':
        return AdvertiserAccountType.organization;
      case 'individual':
      default:
        return AdvertiserAccountType.individual;
    }
  }

  String get value => name;
}

/// Verification status matching the Supabase `verification_status` enum.
enum AdvertiserVerificationStatus {
  unverified,
  pending,
  verified,
  rejected;

  static AdvertiserVerificationStatus fromString(String? value) {
    if (value == null) return AdvertiserVerificationStatus.unverified;
    switch (value.toLowerCase().trim()) {
      case 'pending':
        return AdvertiserVerificationStatus.pending;
      case 'verified':
        return AdvertiserVerificationStatus.verified;
      case 'rejected':
        return AdvertiserVerificationStatus.rejected;
      case 'unverified':
      default:
        return AdvertiserVerificationStatus.unverified;
    }
  }

  String get value => name;
}

/// Strongly typed AdvertiserProfile model matching `public.advertiser_profiles`.
class AdvertiserProfile {
  final String id;
  final String createdBy;
  final AdvertiserAccountType accountType;
  final String displayName;
  final String? legalName;
  final String contactEmail;
  final String? contactPhone;
  final String? taxOrBusinessId;
  final String? websiteUrl;
  final AdvertiserVerificationStatus verificationStatus;
  final String? billingCustomerId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const AdvertiserProfile({
    required this.id,
    required this.createdBy,
    required this.accountType,
    required this.displayName,
    this.legalName,
    required this.contactEmail,
    this.contactPhone,
    this.taxOrBusinessId,
    this.websiteUrl,
    this.verificationStatus = AdvertiserVerificationStatus.unverified,
    this.billingCustomerId,
    this.createdAt,
    this.updatedAt,
  });

  bool get isIndividual => accountType == AdvertiserAccountType.individual;
  bool get isOrganization => accountType == AdvertiserAccountType.organization;

  /// Validates required fields according to DB constraints:
  /// - Display name cannot be empty.
  /// - Contact email cannot be empty and must look like an email address.
  /// - Organizations MUST have a non-empty legal name.
  static String? validateOrganization({
    required String? legalName,
    required String? displayName,
    required String? contactEmail,
  }) {
    if (displayName == null || displayName.trim().isEmpty) {
      return 'DISPLAY NAME / BRAND NAME IS REQUIRED';
    }
    if (legalName == null || legalName.trim().isEmpty) {
      return 'ORGANIZATION REQUIRES A VALID LEGAL NAME';
    }
    if (contactEmail == null || contactEmail.trim().isEmpty || !contactEmail.contains('@')) {
      return 'A VALID CONTACT EMAIL IS REQUIRED';
    }
    return null;
  }

  static String? validateIndividual({
    required String? displayName,
    required String? contactEmail,
  }) {
    if (displayName == null || displayName.trim().isEmpty) {
      return 'DISPLAY NAME / BRAND NAME IS REQUIRED';
    }
    if (contactEmail == null || contactEmail.trim().isEmpty || !contactEmail.contains('@')) {
      return 'A VALID CONTACT EMAIL IS REQUIRED';
    }
    return null;
  }

  factory AdvertiserProfile.fromJson(Map<String, dynamic> json) {
    return AdvertiserProfile(
      id: json['id']?.toString() ?? '',
      createdBy: json['created_by']?.toString() ?? '',
      accountType: AdvertiserAccountType.fromString(json['account_type']?.toString()),
      displayName: json['display_name']?.toString() ?? '',
      legalName: json['legal_name']?.toString(),
      contactEmail: json['contact_email']?.toString() ?? '',
      contactPhone: json['contact_phone']?.toString(),
      taxOrBusinessId: json['tax_or_business_id']?.toString(),
      websiteUrl: json['website_url']?.toString(),
      verificationStatus: AdvertiserVerificationStatus.fromString(
        json['verification_status']?.toString(),
      ),
      billingCustomerId: json['billing_customer_id']?.toString(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson({bool includeId = true}) {
    final data = <String, dynamic>{
      'created_by': createdBy,
      'account_type': accountType.value,
      'display_name': displayName,
      'legal_name': legalName,
      'contact_email': contactEmail,
      'contact_phone': contactPhone,
      'tax_or_business_id': taxOrBusinessId,
      'website_url': websiteUrl,
      'verification_status': verificationStatus.value,
      'billing_customer_id': billingCustomerId,
    };
    if (includeId && id.isNotEmpty) {
      data['id'] = id;
    }
    if (createdAt != null) {
      data['created_at'] = createdAt!.toIso8601String();
    }
    if (updatedAt != null) {
      data['updated_at'] = updatedAt!.toIso8601String();
    }
    return data;
  }

  AdvertiserProfile copyWith({
    String? id,
    String? createdBy,
    AdvertiserAccountType? accountType,
    String? displayName,
    String? legalName,
    String? contactEmail,
    String? contactPhone,
    String? taxOrBusinessId,
    String? websiteUrl,
    AdvertiserVerificationStatus? verificationStatus,
    String? billingCustomerId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AdvertiserProfile(
      id: id ?? this.id,
      createdBy: createdBy ?? this.createdBy,
      accountType: accountType ?? this.accountType,
      displayName: displayName ?? this.displayName,
      legalName: legalName ?? this.legalName,
      contactEmail: contactEmail ?? this.contactEmail,
      contactPhone: contactPhone ?? this.contactPhone,
      taxOrBusinessId: taxOrBusinessId ?? this.taxOrBusinessId,
      websiteUrl: websiteUrl ?? this.websiteUrl,
      verificationStatus: verificationStatus ?? this.verificationStatus,
      billingCustomerId: billingCustomerId ?? this.billingCustomerId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
