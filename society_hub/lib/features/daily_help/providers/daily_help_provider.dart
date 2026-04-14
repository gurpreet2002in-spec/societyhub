import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/api_service.dart';

final dailyHelpProvider =
    StateNotifierProvider<DailyHelpNotifier, AsyncValue<List<dynamic>>>((ref) {
  final api = ref.watch(apiServiceProvider);
  return DailyHelpNotifier(api)..load();
});

class DailyHelpNotifier extends StateNotifier<AsyncValue<List<dynamic>>> {
  final ApiService _api;
  DailyHelpNotifier(this._api) : super(const AsyncValue.loading());

  Future<void> load() async {
    try {
      state = const AsyncValue.loading();
      state = AsyncValue.data(await _api.getHelp());
    } catch (e, s) {
      state = AsyncValue.error(e, s);
    }
  }

  Future<void> add(Map<String, dynamic> data) async {
    await _api.addHelp(data);
    await load();
  }

  Future<void> remove(String id) async {
    await _api.deleteHelp(id);
    await load();
  }

  Future<void> markAttendance(String helpId, String date, String status) async {
    await _api.markAttendance(helpId, date, status);
  }
}
