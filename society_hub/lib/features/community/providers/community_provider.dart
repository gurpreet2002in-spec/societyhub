import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/api_service.dart';

final noticesProvider =
    StateNotifierProvider<NoticesNotifier, AsyncValue<List<dynamic>>>((ref) {
  return NoticesNotifier(ref.watch(apiServiceProvider))..load();
});

class NoticesNotifier extends StateNotifier<AsyncValue<List<dynamic>>> {
  final ApiService _api;
  NoticesNotifier(this._api) : super(const AsyncValue.loading());

  Future<void> load() async {
    try {
      state = const AsyncValue.loading();
      state = AsyncValue.data(await _api.getNotices());
    } catch (e, s) {
      state = AsyncValue.error(e, s);
    }
  }

  Future<void> create(String title, String body, String category, bool isPinned) async {
    await _api.createNotice(title, body, category, isPinned);
    await load();
  }

  Future<void> delete(String id) async {
    await _api.deleteNotice(id);
    await load();
  }
}

final pollsProvider =
    StateNotifierProvider<PollsNotifier, AsyncValue<List<dynamic>>>((ref) {
  return PollsNotifier(ref.watch(apiServiceProvider))..load();
});

class PollsNotifier extends StateNotifier<AsyncValue<List<dynamic>>> {
  final ApiService _api;
  PollsNotifier(this._api) : super(const AsyncValue.loading());

  Future<void> load() async {
    try {
      state = const AsyncValue.loading();
      state = AsyncValue.data(await _api.getPolls());
    } catch (e, s) {
      state = AsyncValue.error(e, s);
    }
  }

  Future<void> vote(String pollId, int optionIndex) async {
    await _api.votePoll(pollId, optionIndex);
    await load();
  }
}
