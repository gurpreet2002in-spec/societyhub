import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/api_service.dart';

final dashboardStatsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final api = ref.watch(apiServiceProvider);
  return api.getDashboardStats();
});
