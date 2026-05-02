import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'supabase_api_service.dart';

// ── apiServiceProvider now delegates to the Supabase implementation ──────────
// All existing screens that watch(apiServiceProvider) get SupabaseApiService.
final apiServiceProvider =
    Provider<ApiService>((ref) => ref.watch(supabaseApiServiceProvider));


class ApiService {
  // Development default - will be overridden by stored URL after QR scan
  String _baseUrl = 'https://your-app.railway.app/api';
  String? _token;
  Map<String, dynamic>? _user;

  Map<String, dynamic>? get user => _user;
  bool get isAuthenticated => _token != null;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Check for custom server URL first (stored or from env)
    final customUrl = prefs.getString('serverUrl');
    if (customUrl != null) {
      _baseUrl = customUrl;
    }
    
    _token = prefs.getString('token');
    final userStr = prefs.getString('user');
    if (userStr != null) {
      _user = jsonDecode(userStr);
    }
  }

  Future<void> setServerUrl(String url) async {
    _baseUrl = url.endsWith('/api') ? url : '$url/api';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('serverUrl', _baseUrl);
  }

  Future<bool> testConnection(String societyId) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/test?societyId=$societyId'),
      headers: {'Content-Type': 'application/json'},
    );
    if (response.statusCode == 200) {
      return true;
    }
    throw Exception('Could not connect to server');
  }

  String get baseUrl => _baseUrl;

  Future<bool> login(String email, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      _token = data['token'];
      _user = data['user'];
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('token', _token!);
      await prefs.setString('user', jsonEncode(_user));
      return true;
    }
    throw Exception(jsonDecode(response.body)['error'] ?? 'Login failed');
  }

  Future<bool> register(String name, String email, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'name': name, 'email': email, 'password': password, 'role': 'resident'}),
    );
    if (response.statusCode == 201) {
      // after register, try to login automatically
      return login(email, password);
    }
    throw Exception(jsonDecode(response.body)['error'] ?? 'Registration failed');
  }

  Future<void> logout() async {
    _token = null;
    _user = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('user');
  }

  Future<void> updateProfile({String? name, String? contactNumber, String? apartmentNumber}) async {
    if (_token == null) throw Exception("Unauthorized");
    final response = await http.put(
      Uri.parse('$baseUrl/profile'),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $_token'},
      body: jsonEncode({
        if (name != null) 'name': name,
        if (contactNumber != null) 'contactNumber': contactNumber,
        if (apartmentNumber != null) 'apartmentNumber': apartmentNumber,
      }),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      _user = data;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user', jsonEncode(_user));
    } else {
      throw Exception(jsonDecode(response.body)['error'] ?? 'Failed to update profile');
    }
  }

  Future<void> changePassword(String currentPassword, String newPassword) async {
    if (_token == null) throw Exception("Unauthorized");
    final response = await http.put(
      Uri.parse('$baseUrl/profile/password'),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $_token'},
      body: jsonEncode({'currentPassword': currentPassword, 'newPassword': newPassword}),
    );
    if (response.statusCode != 200) {
      throw Exception(jsonDecode(response.body)['error'] ?? 'Failed to change password');
    }
  }

  // ---- ADMIN: USER MANAGEMENT ----
  Future<List<dynamic>> getUsers() async {
    if (_token == null) throw Exception("Unauthorized");
    final r = await http.get(Uri.parse('$baseUrl/admin/users'),
        headers: {'Authorization': 'Bearer $_token'});
    if (r.statusCode == 200) return jsonDecode(r.body);
    throw Exception(jsonDecode(r.body)['error'] ?? 'Failed to load users');
  }

  Future<void> updateUserRole(String userId, String role) async {
    if (_token == null) throw Exception("Unauthorized");
    final r = await http.put(Uri.parse('$baseUrl/admin/users/$userId/role'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $_token'},
        body: jsonEncode({'role': role}));
    if (r.statusCode != 200) throw Exception(jsonDecode(r.body)['error'] ?? 'Failed to update role');
  }

  Future<void> deleteUser(String userId) async {
    if (_token == null) throw Exception("Unauthorized");
    final r = await http.delete(Uri.parse('$baseUrl/admin/users/$userId'),
        headers: {'Authorization': 'Bearer $_token'});
    if (r.statusCode != 200) throw Exception(jsonDecode(r.body)['error'] ?? 'Failed to delete user');
  }

  Future<void> adminCreateUser({
    required String name,
    required String email,
    required String password,
    required String role,
    String? contactNumber,
    String? apartmentNumber,
  }) async {
    if (_token == null) throw Exception("Unauthorized");
    final r = await http.post(Uri.parse('$baseUrl/admin/users'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $_token'},
        body: jsonEncode({
          'name': name, 'email': email, 'password': password, 'role': role,
          if (contactNumber != null && contactNumber.isNotEmpty) 'contactNumber': contactNumber,
          if (apartmentNumber != null && apartmentNumber.isNotEmpty) 'apartmentNumber': apartmentNumber,
        }));
    if (r.statusCode != 201) throw Exception(jsonDecode(r.body)['error'] ?? 'Failed to create user');
  }

  // ---- ADMIN: SOCIETY SETTINGS ----
  Future<Map<String, dynamic>> getSocietySettings() async {
    if (_token == null) throw Exception("Unauthorized");
    final r = await http.get(Uri.parse('$baseUrl/admin/society'),
        headers: {'Authorization': 'Bearer $_token'});
    if (r.statusCode == 200) return jsonDecode(r.body);
    throw Exception(jsonDecode(r.body)['error'] ?? 'Failed to load society settings');
  }

  Future<void> updateSocietySettings({
    required String name,
    required String address,
    required String city,
    required String registrationNumber,
  }) async {
    if (_token == null) throw Exception("Unauthorized");
    final r = await http.put(Uri.parse('$baseUrl/admin/society'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $_token'},
        body: jsonEncode({'name': name, 'address': address, 'city': city, 'registrationNumber': registrationNumber}));
    if (r.statusCode != 200) throw Exception(jsonDecode(r.body)['error'] ?? 'Failed to update society settings');
  }

  // ---- SUPER ADMIN: PLATFORM MANAGEMENT ----
  Future<List<dynamic>> getSuperAdminSocieties() async {
    if (_token == null) throw Exception("Unauthorized");
    final r = await http.get(Uri.parse('$baseUrl/super-admin/societies'),
        headers: {'Authorization': 'Bearer $_token'});
    if (r.statusCode == 200) return jsonDecode(r.body);
    throw Exception(jsonDecode(r.body)['error'] ?? 'Failed to load platform societies');
  }

  Future<void> superAdminCreateSociety({
    required String name, required String address, required String city,
    required String registrationNumber, required String subscriptionPlan
  }) async {
    if (_token == null) throw Exception("Unauthorized");
    final r = await http.post(Uri.parse('$baseUrl/super-admin/societies'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $_token'},
        body: jsonEncode({'name': name, 'address': address, 'city': city, 'registrationNumber': registrationNumber, 'subscriptionPlan': subscriptionPlan}));
    if (r.statusCode != 201) throw Exception(jsonDecode(r.body)['error'] ?? 'Failed to create society');
  }

  Future<void> superAdminUpdateSociety(String societyId, {
    required String name, required String address, required String city,
    required String subscriptionStatus, required String subscriptionPlan
  }) async {
    if (_token == null) throw Exception("Unauthorized");
    final r = await http.put(Uri.parse('$baseUrl/super-admin/societies/$societyId'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $_token'},
        body: jsonEncode({'name': name, 'address': address, 'city': city, 'subscriptionStatus': subscriptionStatus, 'subscriptionPlan': subscriptionPlan}));
    if (r.statusCode != 200) throw Exception(jsonDecode(r.body)['error'] ?? 'Failed to update society');
  }

  Future<List<dynamic>> getSuperAdminSocietyAdmins(String societyId) async {
    if (_token == null) throw Exception("Unauthorized");
    final r = await http.get(Uri.parse('$baseUrl/super-admin/societies/$societyId/admins'),
        headers: {'Authorization': 'Bearer $_token'});
    if (r.statusCode == 200) return jsonDecode(r.body);
    throw Exception(jsonDecode(r.body)['error'] ?? 'Failed to load admins for society');
  }

  Future<void> superAdminCreateSocietyAdmin(String societyId, {
    required String name, required String email, required String password, required String contactNumber
  }) async {
    if (_token == null) throw Exception("Unauthorized");
    final r = await http.post(Uri.parse('$baseUrl/super-admin/societies/$societyId/admins'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $_token'},
        body: jsonEncode({'name': name, 'email': email, 'password': password, 'contactNumber': contactNumber}));
    if (r.statusCode != 201) throw Exception(jsonDecode(r.body)['error'] ?? 'Failed to create society admin');
  }

  Future<void> superAdminDeleteUser(String userId) async {
    if (_token == null) throw Exception("Unauthorized");
    final r = await http.delete(Uri.parse('$baseUrl/super-admin/users/$userId'),
        headers: {'Authorization': 'Bearer $_token'});
    if (r.statusCode != 200) throw Exception(jsonDecode(r.body)['error'] ?? 'Failed to delete user');
  }

  // Complaints / Maintenance
  Future<List<dynamic>> getComplaints() async {
    if (_token == null) throw Exception("Unauthorized");
    final response = await http.get(
      Uri.parse('$baseUrl/maintenance'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      },
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to load complaints');
  }

  Future<void> addComplaint(String title, String description, String priority) async {
    if (_token == null) throw Exception("Unauthorized");
    final response = await http.post(
      Uri.parse('$baseUrl/maintenance'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      },
      body: jsonEncode({
        'title': title,
        'description': description,
        'priority': priority
      }),
    );
    if (response.statusCode != 201 && response.statusCode != 200) {
      throw Exception('Failed to add complaint');
    }
  }

  // Billing & Invoices
  Future<List<dynamic>> getInvoices() async {
    if (_token == null) throw Exception("Unauthorized");
    final response = await http.get(
      Uri.parse('$baseUrl/invoices'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      },
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to load invoices');
  }

  // Razorpay Integration (Mock/Simulated for MVP Frontend)
  Future<bool> initiateAndVerifyPayment(String invoiceId) async {
    if (_token == null) throw Exception("Unauthorized");
    
    // 1. Create Order
    final orderResponse = await http.post(
      Uri.parse('$baseUrl/payments/razorpay/order'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      },
      body: jsonEncode({'invoiceId': invoiceId}),
    );
    
    if (orderResponse.statusCode != 200 && orderResponse.statusCode != 201) {
      throw Exception('Failed to initiate payment');
    }
    
    final orderData = jsonDecode(orderResponse.body);
    final paymentId = orderData['paymentId'];

    // 2. Simulate User entering details on a gateway and succeeding
    // Under normal circumstances, you'd open Razorpay Checkout here.
    // For MVP, we auto-verify as success.
    final verifyResponse = await http.post(
      Uri.parse('$baseUrl/payments/razorpay/verify'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      },
      body: jsonEncode({
        'paymentId': paymentId,
        'razorpay_payment_id': 'mock_txn_${DateTime.now().millisecondsSinceEpoch}',
        'razorpay_signature': 'mock_signature',
        'status': 'success'
      }),
    );

    if (verifyResponse.statusCode == 200) {
      return true;
    }
    throw Exception('Payment verification failed');
  }

  // Dashboard
  Future<Map<String, dynamic>> getDashboardStats() async {
    if (_token == null) throw Exception("Unauthorized");
    final response = await http.get(
      Uri.parse('$baseUrl/dashboard'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      },
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to load dashboard stats');
  }

  // Visitors
  Future<List<dynamic>> getVisitors() async {
    if (_token == null) throw Exception("Unauthorized");
    final response = await http.get(
      Uri.parse('$baseUrl/visitors'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      },
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to load visitors');
  }

  Future<void> preapproveVisitor(String name, String mobile, String purpose, String expectedEntry) async {
    if (_token == null) throw Exception("Unauthorized");
    final response = await http.post(
      Uri.parse('$baseUrl/visitors/preapprove'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      },
      body: jsonEncode({
        'name': name,
        'mobile': mobile,
        'purpose': purpose,
        'expectedEntry': expectedEntry,
      }),
    );
    if (response.statusCode != 201 && response.statusCode != 200) {
      throw Exception('Failed to preapprove visitor');
    }
  }

  Future<void> updateVisitorStatus(String id, String status) async {
    if (_token == null) throw Exception("Unauthorized");
    final response = await http.put(
      Uri.parse('$baseUrl/visitors/$id/status'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      },
      body: jsonEncode({
        'status': status,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to update visitor status');
    }
  }

  // Admin Billing
  Future<void> generateBulkInvoices(
      String title, double amount, double taxAmount, String dueDate) async {
    if (_token == null) throw Exception("Unauthorized");
    final response = await http.post(
      Uri.parse('$baseUrl/invoices/generate'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      },
      body: jsonEncode({
        'title': title,
        'amount': amount,
        'taxAmount': taxAmount,
        'dueDate': dueDate,
      }),
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
          jsonDecode(response.body)['error'] ?? 'Failed to generate invoices');
    }
  }

  // ---- DAILY HELP ----
  Future<List<dynamic>> getHelp() async {
    if (_token == null) throw Exception("Unauthorized");
    final r = await http.get(Uri.parse('$baseUrl/help'),
        headers: {'Authorization': 'Bearer $_token'});
    if (r.statusCode == 200) return jsonDecode(r.body);
    throw Exception('Failed to load daily help');
  }

  Future<Map<String, dynamic>> addHelp(Map<String, dynamic> data) async {
    if (_token == null) throw Exception("Unauthorized");
    final r = await http.post(Uri.parse('$baseUrl/help'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $_token'},
        body: jsonEncode(data));
    if (r.statusCode == 201) return jsonDecode(r.body);
    throw Exception(jsonDecode(r.body)['error'] ?? 'Failed to add help');
  }

  Future<void> deleteHelp(String id) async {
    if (_token == null) throw Exception("Unauthorized");
    await http.delete(Uri.parse('$baseUrl/help/$id'),
        headers: {'Authorization': 'Bearer $_token'});
  }

  Future<void> markAttendance(String helpId, String date, String status) async {
    if (_token == null) throw Exception("Unauthorized");
    await http.post(Uri.parse('$baseUrl/help/$helpId/attendance'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $_token'},
        body: jsonEncode({'date': date, 'status': status}));
  }

  Future<List<dynamic>> getAttendance(String helpId) async {
    if (_token == null) throw Exception("Unauthorized");
    final r = await http.get(Uri.parse('$baseUrl/help/$helpId/attendance'),
        headers: {'Authorization': 'Bearer $_token'});
    if (r.statusCode == 200) return jsonDecode(r.body);
    throw Exception('Failed to load attendance');
  }

  // ---- AMENITIES ----
  Future<List<dynamic>> getAmenities() async {
    if (_token == null) throw Exception("Unauthorized");
    final r = await http.get(Uri.parse('$baseUrl/amenities'),
        headers: {'Authorization': 'Bearer $_token'});
    if (r.statusCode == 200) return jsonDecode(r.body);
    throw Exception('Failed to load amenities');
  }

  Future<List<dynamic>> getMyBookings() async {
    if (_token == null) throw Exception("Unauthorized");
    final r = await http.get(Uri.parse('$baseUrl/bookings/my'),
        headers: {'Authorization': 'Bearer $_token'});
    if (r.statusCode == 200) return jsonDecode(r.body);
    throw Exception('Failed to load bookings');
  }

  Future<void> bookAmenity(String amenityId, String date, String start, String end, {String? notes}) async {
    if (_token == null) throw Exception("Unauthorized");
    final r = await http.post(Uri.parse('$baseUrl/amenities/$amenityId/book'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $_token'},
        body: jsonEncode({'bookingDate': date, 'startTime': start, 'endTime': end, 'notes': notes ?? ''}));
    if (r.statusCode != 201) {
      throw Exception(jsonDecode(r.body)['error'] ?? 'Booking failed');
    }
  }

  Future<void> cancelBooking(String bookingId) async {
    if (_token == null) throw Exception("Unauthorized");
    await http.put(Uri.parse('$baseUrl/bookings/$bookingId/cancel'),
        headers: {'Authorization': 'Bearer $_token'});
  }

  // ---- NOTICES ----
  Future<List<dynamic>> getNotices() async {
    if (_token == null) throw Exception("Unauthorized");
    final r = await http.get(Uri.parse('$baseUrl/notices'),
        headers: {'Authorization': 'Bearer $_token'});
    if (r.statusCode == 200) return jsonDecode(r.body);
    throw Exception('Failed to load notices');
  }

  Future<void> createNotice(String title, String body, String category, bool isPinned) async {
    if (_token == null) throw Exception("Unauthorized");
    final r = await http.post(Uri.parse('$baseUrl/notices'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $_token'},
        body: jsonEncode({'title': title, 'body': body, 'category': category, 'isPinned': isPinned}));
    if (r.statusCode != 201) throw Exception(jsonDecode(r.body)['error'] ?? 'Failed to post notice');
  }

  Future<void> deleteNotice(String id) async {
    if (_token == null) throw Exception("Unauthorized");
    await http.delete(Uri.parse('$baseUrl/notices/$id'),
        headers: {'Authorization': 'Bearer $_token'});
  }

  // ---- POLLS ----
  Future<List<dynamic>> getPolls() async {
    if (_token == null) throw Exception("Unauthorized");
    final r = await http.get(Uri.parse('$baseUrl/polls'),
        headers: {'Authorization': 'Bearer $_token'});
    if (r.statusCode == 200) return jsonDecode(r.body);
    throw Exception('Failed to load polls');
  }

  Future<void> votePoll(String pollId, int optionIndex) async {
    if (_token == null) throw Exception("Unauthorized");
    final r = await http.post(Uri.parse('$baseUrl/polls/$pollId/vote'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $_token'},
        body: jsonEncode({'optionIndex': optionIndex}));
    if (r.statusCode != 201) throw Exception(jsonDecode(r.body)['error'] ?? 'Vote failed');
  }

  // ---- HELPDESK ESCALATION ----
  Future<void> escalateTicket(String id) async {
    if (_token == null) throw Exception("Unauthorized");
    await http.put(Uri.parse('$baseUrl/maintenance/$id/escalate'),
        headers: {'Authorization': 'Bearer $_token'});
  }

  Future<void> resolveTicket(String id) async {
    if (_token == null) throw Exception("Unauthorized");
    await http.put(Uri.parse('$baseUrl/maintenance/$id/resolve'),
        headers: {'Authorization': 'Bearer $_token'});
  }

  Future<void> rateTicket(String id, int rating, String comment) async {
    if (_token == null) throw Exception("Unauthorized");
    await http.put(Uri.parse('$baseUrl/maintenance/$id/rate'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $_token'},
        body: jsonEncode({'rating': rating, 'comment': comment}));
  }

  // ---- PARKING ----
  Future<List<dynamic>> getParkingSlots() async {
    if (_token == null) throw Exception("Unauthorized");
    final r = await http.get(Uri.parse('$baseUrl/parking/slots'),
        headers: {'Authorization': 'Bearer $_token'});
    if (r.statusCode == 200) return jsonDecode(r.body);
    throw Exception('Failed to load parking');
  }

  Future<void> allocateParking(String slotId, String flatId, String vehicleNo, String vehicleType) async {
    if (_token == null) throw Exception("Unauthorized");
    final r = await http.post(Uri.parse('$baseUrl/parking/allocate'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $_token'},
        body: jsonEncode({'slotId': slotId, 'flatId': flatId, 'vehicleNo': vehicleNo, 'vehicleType': vehicleType}));
    if (r.statusCode != 201) throw Exception(jsonDecode(r.body)['error'] ?? 'Allocation failed');
  }

  Future<void> releaseParking(String slotId) async {
    if (_token == null) throw Exception("Unauthorized");
    final r = await http.put(Uri.parse('$baseUrl/parking/release/$slotId'),
        headers: {'Authorization': 'Bearer $_token'});
    if (r.statusCode != 200) throw Exception('Release failed');
  }

  // ---- MARKETPLACE ----
  Future<List<dynamic>> getMarketplace({String? category}) async {
    if (_token == null) throw Exception("Unauthorized");
    final uri = Uri.parse('$baseUrl/marketplace${category != null && category != 'all' ? '?category=$category' : ''}');
    final r = await http.get(uri, headers: {'Authorization': 'Bearer $_token'});
    if (r.statusCode == 200) return jsonDecode(r.body);
    throw Exception('Failed to load marketplace');
  }

  Future<void> createListing(Map<String, dynamic> data) async {
    if (_token == null) throw Exception("Unauthorized");
    final r = await http.post(Uri.parse('$baseUrl/marketplace'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $_token'},
        body: jsonEncode(data));
    if (r.statusCode != 201) throw Exception(jsonDecode(r.body)['error'] ?? 'Failed to post listing');
  }

  Future<void> markListingSold(String id) async {
    if (_token == null) throw Exception("Unauthorized");
    await http.put(Uri.parse('$baseUrl/marketplace/$id/sold'),
        headers: {'Authorization': 'Bearer $_token'});
  }

  Future<void> removeListing(String id) async {
    if (_token == null) throw Exception("Unauthorized");
    await http.delete(Uri.parse('$baseUrl/marketplace/$id'),
        headers: {'Authorization': 'Bearer $_token'});
  }

  // ---- REPORTS ----
  Future<Map<String, dynamic>> getFinancialReport() async {
    if (_token == null) throw Exception("Unauthorized");
    final r = await http.get(Uri.parse('$baseUrl/reports/financial'),
        headers: {'Authorization': 'Bearer $_token'});
    if (r.statusCode == 200) return jsonDecode(r.body);
    throw Exception('Failed to load financial report');
  }

  Future<Map<String, dynamic>> getMaintenanceReport() async {
    if (_token == null) throw Exception("Unauthorized");
    final r = await http.get(Uri.parse('$baseUrl/reports/maintenance'),
        headers: {'Authorization': 'Bearer $_token'});
    if (r.statusCode == 200) return jsonDecode(r.body);
    throw Exception('Failed to load maintenance report');
  }

  Future<List<dynamic>> getAmenityReport() async {
    if (_token == null) throw Exception("Unauthorized");
    final r = await http.get(Uri.parse('$baseUrl/reports/amenity'),
        headers: {'Authorization': 'Bearer $_token'});
    if (r.statusCode == 200) return jsonDecode(r.body);
    throw Exception('Failed to load amenity report');
  }

  Future<Map<String, dynamic>> getOccupancyReport() async {
    if (_token == null) throw Exception("Unauthorized");
    final r = await http.get(Uri.parse('$baseUrl/reports/occupancy'),
        headers: {'Authorization': 'Bearer $_token'});
    if (r.statusCode == 200) return jsonDecode(r.body);
    throw Exception('Failed to load occupancy report');
  }

  // ---- IN-APP NOTIFICATIONS ----
  Future<List<dynamic>> getNotifications() async {
    if (_token == null) throw Exception("Unauthorized");
    final r = await http.get(Uri.parse('$baseUrl/notifications'),
        headers: {'Authorization': 'Bearer $_token'});
    if (r.statusCode == 200) return jsonDecode(r.body);
    throw Exception('Failed to load notifications');
  }

  Future<int> getUnreadNotificationCount() async {
    if (_token == null) return 0;
    final r = await http.get(Uri.parse('$baseUrl/notifications/count'),
        headers: {'Authorization': 'Bearer $_token'});
    if (r.statusCode == 200) return jsonDecode(r.body)['count'] as int;
    return 0;
  }

  Future<void> markNotificationRead(String id) async {
    if (_token == null) throw Exception("Unauthorized");
    await http.put(Uri.parse('$baseUrl/notifications/$id/read'),
        headers: {'Authorization': 'Bearer $_token'});
  }

  Future<void> markAllNotificationsRead() async {
    if (_token == null) throw Exception("Unauthorized");
    await http.put(Uri.parse('$baseUrl/notifications/read-all'),
        headers: {'Authorization': 'Bearer $_token'});
  }

  // ---- SUPER ADMIN ----
  Future<Map<String, dynamic>> getSuperAdminStats() async {
    if (_token == null) throw Exception("Unauthorized");
    final r = await http.get(Uri.parse('$baseUrl/superadmin/stats'),
        headers: {'Authorization': 'Bearer $_token'});
    if (r.statusCode == 200) return jsonDecode(r.body);
    throw Exception('Failed to load super admin stats');
  }

  Future<Map<String, dynamic>> getSuperAdminSettings() async {
    if (_token == null) throw Exception("Unauthorized");
    final r = await http.get(Uri.parse('$baseUrl/superadmin/settings'),
        headers: {'Authorization': 'Bearer $_token'});
    if (r.statusCode == 200) return jsonDecode(r.body);
    throw Exception('Failed to load global settings');
  }

  Future<List<dynamic>> getSuperAdminInvoices() async {
    if (_token == null) throw Exception("Unauthorized");
    final r = await http.get(Uri.parse('$baseUrl/superadmin/invoices'),
        headers: {'Authorization': 'Bearer $_token'});
    if (r.statusCode == 200) return jsonDecode(r.body);
    throw Exception('Failed to load society invoices');
  }

  Future<void> updateSuperAdminSetting(String key, dynamic value) async {
    if (_token == null) throw Exception("Unauthorized");
    final r = await http.post(Uri.parse('$baseUrl/superadmin/settings'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $_token'},
        body: jsonEncode({'key': key, 'value': value}));
    if (r.statusCode != 200) throw Exception('Failed to update platform settings');
  }

  Future<Map<String, dynamic>> getSuperAdminReports() async {
    if (_token == null) throw Exception("Unauthorized");
    final r = await http.get(Uri.parse('$baseUrl/superadmin/reports'),
        headers: {'Authorization': 'Bearer $_token'});
    if (r.statusCode == 200) return jsonDecode(r.body);
    throw Exception('Failed to load platform reports');
  }

  Future<List<dynamic>> getSuperAdminLogs() async {
    if (_token == null) throw Exception("Unauthorized");
    final r = await http.get(Uri.parse('$baseUrl/superadmin/logs'),
        headers: {'Authorization': 'Bearer $_token'});
    if (r.statusCode == 200) return jsonDecode(r.body);
    throw Exception('Failed to load audit logs');
  }
}
