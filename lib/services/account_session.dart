import 'package:flutter/foundation.dart';
import '../models/account.dart';

/// Manages the active user session in Billy.
/// In-memory local session abstraction, extensible for future auth backends.
class AccountSession extends ChangeNotifier {
  static final AccountSession _instance = AccountSession._internal();
  factory AccountSession() => _instance;
  AccountSession._internal();

  Account? _currentAccount;

  Account? get currentAccount => _currentAccount;
  bool get isSignedIn => _currentAccount != null;
  bool get isAdvertiser => _currentAccount?.isAdvertiser ?? false;
  bool get isConsumer => _currentAccount?.isConsumer ?? false;

  void signIn(Account account) {
    _currentAccount = account;
    debugPrint('AccountSession: Signed in as ${account.displayName} (${account.role.displayName}).');
    notifyListeners();
  }

  void signOut() {
    debugPrint('AccountSession: Signed out.');
    _currentAccount = null;
    notifyListeners();
  }

  /// Fast-path local session creator for Consumers / Viewers.
  Account signInAsConsumer({String? id, String? displayName}) {
    final account = Account(
      id: id ?? 'viewer-${DateTime.now().millisecondsSinceEpoch}',
      email: 'viewer@billy.local',
      displayName: displayName ?? 'Billy Viewer',
      role: AccountRole.consumer,
      createdAt: DateTime.now(),
    );
    signIn(account);
    return account;
  }

  /// Fast-path local session creator for Advertisers.
  Account signInAsAdvertiser({String? id, String? displayName}) {
    final account = Account(
      id: id ?? 'advertiser-${DateTime.now().millisecondsSinceEpoch}',
      email: 'advertiser@billy.local',
      displayName: displayName ?? 'Billy Advertiser',
      role: AccountRole.advertiser,
      createdAt: DateTime.now(),
    );
    signIn(account);
    return account;
  }

  /// Clears session state for test isolation.
  void reset() {
    _currentAccount = null;
  }
}
