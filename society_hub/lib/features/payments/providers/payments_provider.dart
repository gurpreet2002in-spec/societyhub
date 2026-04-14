import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/api_service.dart';

final invoicesProvider = StateNotifierProvider<InvoicesNotifier, AsyncValue<List<dynamic>>>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  return InvoicesNotifier(apiService)..loadInvoices();
});

class InvoicesNotifier extends StateNotifier<AsyncValue<List<dynamic>>> {
  final ApiService _apiService;

  InvoicesNotifier(this._apiService) : super(const AsyncValue.loading());

  Future<void> loadInvoices() async {
    try {
      state = const AsyncValue.loading();
      final invoices = await _apiService.getInvoices();
      state = AsyncValue.data(invoices);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  Future<void> payInvoice(String invoiceId) async {
    try {
      await _apiService.initiateAndVerifyPayment(invoiceId);
      await loadInvoices(); // Reload lists
    } catch (e) {
      rethrow;
    }
  }
}
