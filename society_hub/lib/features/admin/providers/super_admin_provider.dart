import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/api_service.dart';

final superAdminStatsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  return ref.read(apiServiceProvider).getSuperAdminStats();
});

final superAdminSettingsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  return ref.read(apiServiceProvider).getSuperAdminSettings();
});

final superAdminInvoicesProvider = FutureProvider<List<dynamic>>((ref) async {
  return ref.read(apiServiceProvider).getSuperAdminInvoices();
});

final superAdminReportsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  return ref.read(apiServiceProvider).getSuperAdminReports();
});

final superAdminLogsProvider = FutureProvider<List<dynamic>>((ref) async {
  return ref.read(apiServiceProvider).getSuperAdminLogs();
});
