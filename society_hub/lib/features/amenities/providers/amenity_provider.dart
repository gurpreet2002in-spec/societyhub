import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/api_service.dart';

final amenitiesProvider =
    StateNotifierProvider<AmenitiesNotifier, AsyncValue<List<dynamic>>>((ref) {
  final api = ref.watch(apiServiceProvider);
  return AmenitiesNotifier(api)..load();
});

final myBookingsProvider =
    StateNotifierProvider<MyBookingsNotifier, AsyncValue<List<dynamic>>>((ref) {
  final api = ref.watch(apiServiceProvider);
  return MyBookingsNotifier(api)..load();
});

class AmenitiesNotifier extends StateNotifier<AsyncValue<List<dynamic>>> {
  final ApiService _api;
  AmenitiesNotifier(this._api) : super(const AsyncValue.loading());

  Future<void> load() async {
    try {
      state = const AsyncValue.loading();
      state = AsyncValue.data(await _api.getAmenities());
    } catch (e, s) {
      state = AsyncValue.error(e, s);
    }
  }

  Future<void> book(String amenityId, String date, String start, String end, {String? notes}) async {
    await _api.bookAmenity(amenityId, date, start, end, notes: notes);
  }
}

class MyBookingsNotifier extends StateNotifier<AsyncValue<List<dynamic>>> {
  final ApiService _api;
  MyBookingsNotifier(this._api) : super(const AsyncValue.loading());

  Future<void> load() async {
    try {
      state = const AsyncValue.loading();
      state = AsyncValue.data(await _api.getMyBookings());
    } catch (e, s) {
      state = AsyncValue.error(e, s);
    }
  }

  Future<void> cancel(String bookingId) async {
    await _api.cancelBooking(bookingId);
    await load();
  }
}
