import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/api_service.dart';

final marketplaceProvider =
    StateNotifierProvider.family<MarketplaceNotifier, AsyncValue<List<dynamic>>, String>(
        (ref, category) {
  return MarketplaceNotifier(ref.watch(apiServiceProvider), category)..load();
});

class MarketplaceNotifier extends StateNotifier<AsyncValue<List<dynamic>>> {
  final ApiService _api;
  final String category;

  MarketplaceNotifier(this._api, this.category) : super(const AsyncValue.loading());

  Future<void> load() async {
    try {
      state = const AsyncValue.loading();
      state = AsyncValue.data(await _api.getMarketplace(category: category));
    } catch (e, s) {
      state = AsyncValue.error(e, s);
    }
  }

  Future<void> add(Map<String, dynamic> data) async {
    await _api.createListing(data);
    await load();
  }

  Future<void> markSold(String id) async {
    await _api.markListingSold(id);
    await load();
  }

  Future<void> remove(String id) async {
    await _api.removeListing(id);
    await load();
  }
}
