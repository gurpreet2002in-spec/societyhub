import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/api_service.dart';
import '../../services/notification_service.dart';

final authProvider = StateNotifierProvider<AuthNotifier, bool>((ref) {
  return AuthNotifier(ref);
});

class AuthNotifier extends StateNotifier<bool> {
  final Ref _ref;

  AuthNotifier(this._ref) : super(false) {
    _init();
  }

  ApiService get _apiService => _ref.read(apiServiceProvider);

  Future<void> _init() async {
    await _apiService.init();
    final isAuth = _apiService.isAuthenticated;
    state = isAuth;
    // If already logged in from a previous session, refresh the FCM token
    if (isAuth) {
      _ref.read(notificationServiceProvider).saveFcmTokenForCurrentUser();
    }
  }

  Future<void> login(String email, String password) async {
    await _apiService.login(email, password);
    state = true;
    // Save FCM token now that the user is authenticated
    _ref.read(notificationServiceProvider).saveFcmTokenForCurrentUser();
  }

  Future<void> register(String name, String email, String password,
      {String? societyId, String? joinCode, String? flat, String? occupancyType, String? unitType}) async {
    await _apiService.register(name, email, password,
        societyId: societyId, joinCode: joinCode, flat: flat, occupancyType: occupancyType, unitType: unitType);
    state = true;
    // Save FCM token after registration
    _ref.read(notificationServiceProvider).saveFcmTokenForCurrentUser();
  }

  Future<void> logout() async {
    // Clear FCM token from Supabase before logging out
    try {
      await _apiService.updateFcmToken(null);
    } catch (_) {}
    await _apiService.logout();
    state = false;
  }
}
