import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/api_service.dart';

final complaintsProvider = FutureProvider.autoDispose<List<dynamic>>((ref) async {
  final api = ref.watch(apiServiceProvider);
  return api.getComplaints();
});
