import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/api_service.dart';
import '../models/visitor.dart';

final visitorsProvider = StateNotifierProvider<VisitorsNotifier, AsyncValue<List<Visitor>>>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  return VisitorsNotifier(apiService)..loadVisitors();
});

class VisitorsNotifier extends StateNotifier<AsyncValue<List<Visitor>>> {
  final ApiService _apiService;

  VisitorsNotifier(this._apiService) : super(const AsyncValue.loading());

  Future<void> loadVisitors() async {
    try {
      state = const AsyncValue.loading();
      final visitorsData = await _apiService.getVisitors();
      
      final visitors = visitorsData.map((data) => Visitor.fromJson(data)).toList();
      state = AsyncValue.data(visitors);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  Future<void> preapproveVisitor(String name, String mobile, String purpose, DateTime expectedEntry) async {
    try {
      await _apiService.preapproveVisitor(name, mobile, purpose, expectedEntry.toIso8601String());
      await loadVisitors(); // Reload list
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updateVisitorStatus(String id, String status) async {
    try {
      await _apiService.updateVisitorStatus(id, status);
      await loadVisitors(); // Reload list
    } catch (e) {
      rethrow;
    }
  }
}
