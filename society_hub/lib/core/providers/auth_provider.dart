import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/api_service.dart';

final authProvider = StateNotifierProvider<AuthNotifier, bool>((ref) {
  return AuthNotifier(ref.watch(apiServiceProvider));
});

class AuthNotifier extends StateNotifier<bool> {
  final ApiService _apiService;

  AuthNotifier(this._apiService) : super(false) {
    _init();
  }

  Future<void> _init() async {
    await _apiService.init();
    state = _apiService.isAuthenticated;
  }

  Future<void> login(String email, String password) async {
    await _apiService.login(email, password);
    state = true;
  }

  Future<void> register(String name, String email, String password) async {
    await _apiService.register(name, email, password);
    state = true;
  }

  Future<void> logout() async {
    await _apiService.logout();
    state = false;
  }
}
