/// Account roles supported by Billy The Viewer.
enum AccountRole {
  consumer,
  advertiser,
}

extension AccountRoleExtension on AccountRole {
  String get displayName {
    switch (this) {
      case AccountRole.consumer:
        return 'VIEWER';
      case AccountRole.advertiser:
        return 'ADVERTISER';
    }
  }
}

/// Represents an account profile within Billy's local/session architecture.
/// Extensible for future Firebase, Supabase, or OAuth integrations.
class Account {
  final String id;
  final String email;
  final String displayName;
  final AccountRole role;
  final DateTime createdAt;

  const Account({
    required this.id,
    required this.email,
    required this.displayName,
    required this.role,
    required this.createdAt,
  });

  bool get isAdvertiser => role == AccountRole.advertiser;
  bool get isConsumer => role == AccountRole.consumer;

  Account copyWith({
    String? id,
    String? email,
    String? displayName,
    AccountRole? role,
    DateTime? createdAt,
  }) {
    return Account(
      id: id ?? this.id,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      role: role ?? this.role,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'displayName': displayName,
      'role': role.name,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory Account.fromJson(Map<String, dynamic> json) {
    final roleName = json['role'] as String? ?? 'consumer';
    final role = AccountRole.values.firstWhere(
      (r) => r.name == roleName,
      orElse: () => AccountRole.consumer,
    );

    return Account(
      id: json['id'] as String,
      email: json['email'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      role: role,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  @override
  String toString() => 'Account(id: $id, name: $displayName, role: ${role.displayName})';
}
