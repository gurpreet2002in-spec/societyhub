import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/api_service.dart';

final parkingProvider =
    StateNotifierProvider<ParkingNotifier, AsyncValue<List<dynamic>>>((ref) {
  return ParkingNotifier(ref.watch(apiServiceProvider))..load();
});

class ParkingNotifier extends StateNotifier<AsyncValue<List<dynamic>>> {
  final ApiService _api;
  ParkingNotifier(this._api) : super(const AsyncValue.loading());

  Future<void> load() async {
    try {
      state = const AsyncValue.loading();
      state = AsyncValue.data(await _api.getParkingSlots());
    } catch (e, s) {
      state = AsyncValue.error(e, s);
    }
  }

  Future<void> allocate(String slotId, String flatId, String vehicleNo, String vehicleType) async {
    await _api.allocateParking(slotId, flatId, vehicleNo, vehicleType);
    await load();
  }

  Future<void> release(String slotId) async {
    await _api.releaseParking(slotId);
    await load();
  }
}
