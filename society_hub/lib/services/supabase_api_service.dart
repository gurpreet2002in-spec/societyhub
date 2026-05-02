// lib/services/supabase_api_service.dart
//
// Drop-in Supabase implementation that EXTENDS ApiService so it is
// type-compatible with every existing provider and screen.

import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'api_service.dart';

// ── Convenience getter ─────────────────────────────────────────────────────
SupabaseClient get _db => Supabase.instance.client;

// ── Riverpod provider ──────────────────────────────────────────────────────
final supabaseApiServiceProvider =
    Provider<SupabaseApiService>((ref) => SupabaseApiService());

// ══════════════════════════════════════════════════════════════════════════════
class SupabaseApiService extends ApiService {
  Map<String, dynamic>? _user;

  Map<String, dynamic>? get user => _user;
  bool get isAuthenticated => _db.auth.currentSession != null;

  // ── Init (called from AuthNotifier) ─────────────────────────────────────
  Future<void> init() async {
    final session = _db.auth.currentSession;
    if (session != null) {
      await _loadUserProfile(session.user.id);
    }
  }

  Future<void> _loadUserProfile(String uid) async {
    try {
      var row = await _db
          .from('users')
          .select()
          .eq('id', uid)
          .maybeSingle();

      if (row == null) {
        // If the user row doesn't exist but they are authenticated, create it.
        // This handles cases where the trigger failed or user was created manually.
        final authUser = _db.auth.currentUser;
        if (authUser != null) {
          final email = authUser.email ?? '';
          final name = authUser.userMetadata?['name'] ?? email.split('@').first;
          
          await _db.from('users').upsert({
            'id': uid,
            'name': name,
            'email': email,
            'role': 'resident',
          });
          
          row = await _db
              .from('users')
              .select()
              .eq('id', uid)
              .maybeSingle();
        }
      }

      if (row != null) {
        _user = Map<String, dynamic>.from(row);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user', jsonEncode(_user));
      }
    } catch (_) {}
  }

  // ── Auth ─────────────────────────────────────────────────────────────
  Future<bool> login(String email, String password) async {
    try {
      final res = await _db.auth.signInWithPassword(
        email: email,
        password: password,
      );
      if (res.session == null) throw Exception('Login failed. Check your credentials.');
      await _loadUserProfile(res.user!.id);
      return true;
    } on AuthException catch (e) {
      throw Exception(e.message);
    } catch (e) {
      throw Exception('Login failed. Please try again.');
    }
  }

  Future<bool> register(String name, String email, String password) async {
    try {
      final res = await _db.auth.signUp(
        email: email,
        password: password,
        data: {'name': name},
      );

      // signUp can succeed even if email confirmation is required
      final userId = res.user?.id;
      if (userId == null) throw Exception('Registration failed. Please try again.');

      // If session exists (email confirmation OFF) → insert user row now
      // If no session (email confirmation ON) → user must confirm email first
      if (res.session != null) {
        try {
          // Clear any orphaned or pre-existing records with this email to avoid UNIQUE constraint violations
          await _db.from('users').delete().eq('email', email);
          
          await _db.from('users').upsert({
            'id': userId,
            'name': name,
            'email': email,
            'role': 'resident',
          });
          await _loadUserProfile(userId);
        } catch (dbErr) {
          // Non-fatal: trigger may have already inserted the row
        }
        return true;
      } else {
        // Email confirmation required — inform user
        throw Exception(
          'Confirmation email sent to $email. Please verify your email then sign in.',
        );
      }
    } on AuthException catch (e) {
      throw Exception(e.message);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> logout() async {
    await _db.auth.signOut();
    _user = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user');
  }

  // ── Profile ───────────────────────────────────────────────────────────────
  Future<void> updateProfile({
    String? name,
    String? contactNumber,
    String? apartmentNumber,
  }) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) throw Exception('Unauthorized');
    final updates = <String, dynamic>{};
    if (name != null) updates['name'] = name;
    if (contactNumber != null) updates['contact_number'] = contactNumber;
    if (apartmentNumber != null) updates['apartment_number'] = apartmentNumber;
    await _db.from('users').update(updates).eq('id', uid);
    await _loadUserProfile(uid);
  }

  Future<void> changePassword(
      String currentPassword, String newPassword) async {
    final res = await _db.auth.updateUser(
      UserAttributes(password: newPassword),
    );
    if (res.user == null) throw Exception('Failed to change password');
  }

  // ── Society settings ──────────────────────────────────────────────────────
  Future<Map<String, dynamic>> getSocietySettings() async {
    final societyId = _user?['society_id'];
    if (societyId == null) throw Exception('No society assigned');
    final row = await _db.from('societies').select().eq('id', societyId).single();
    return Map<String, dynamic>.from(row);
  }

  Future<void> updateSocietySettings({
    required String name,
    required String address,
    required String city,
    required String registrationNumber,
  }) async {
    final societyId = _user?['society_id'];
    if (societyId == null) throw Exception('No society assigned');
    await _db.from('societies').update({
      'name': name,
      'address': address,
      'city': city,
      'registration_number': registrationNumber,
    }).eq('id', societyId);
  }

  // ── Admin: Users ──────────────────────────────────────────────────────────
  Future<List<dynamic>> getUsers() async {
    final societyId = _user?['society_id'];
    final query = societyId != null
        ? _db.from('users').select().eq('society_id', societyId)
        : _db.from('users').select();
    return List<dynamic>.from(await query);
  }

  Future<void> updateUserRole(String userId, String role) async {
    await _db.from('users').update({'role': role}).eq('id', userId);
  }

  Future<void> deleteUser(String userId) async {
    await _db.from('users').delete().eq('id', userId);
  }

  Future<void> adminCreateUser({
    required String name,
    required String email,
    required String password,
    required String role,
    String? contactNumber,
    String? apartmentNumber,
  }) async {
    // Supabase admin user creation via edge function or server-side;
    // For now insert a placeholder row (auth sign-up must happen on device).
    await _db.from('users').insert({
      'name': name,
      'email': email,
      'role': role,
      'society_id': _user?['society_id'],
      if (contactNumber != null) 'contact_number': contactNumber,
      if (apartmentNumber != null) 'apartment_number': apartmentNumber,
    });
  }

  // ── Super Admin: Societies ────────────────────────────────────────────────
  Future<List<dynamic>> getSuperAdminSocieties() async {
    return List<dynamic>.from(await _db.from('societies').select());
  }

  Future<void> superAdminCreateSociety({
    required String name,
    required String address,
    required String city,
    required String registrationNumber,
    required String subscriptionPlan,
  }) async {
    final reg = registrationNumber.trim();
    await _db.from('societies').insert({
      'name': name,
      'address': address,
      'city': city,
      'registration_number': reg.isEmpty ? null : reg,
      'subscription_plan': subscriptionPlan,
    });
  }

  Future<void> superAdminUpdateSociety(String societyId, {
    required String name,
    required String address,
    required String city,
    required String subscriptionStatus,
    required String subscriptionPlan,
  }) async {
    await _db.from('societies').update({
      'name': name,
      'address': address,
      'city': city,
      'subscription_status': subscriptionStatus,
      'subscription_plan': subscriptionPlan,
    }).eq('id', societyId);
  }

  Future<List<dynamic>> getSuperAdminSocietyAdmins(String societyId) async {
    return List<dynamic>.from(
      await _db.from('users').select().eq('society_id', societyId).eq('role', 'admin'),
    );
  }

  Future<void> superAdminCreateSocietyAdmin(String societyId, {
    required String name,
    required String email,
    required String password,
    required String contactNumber,
  }) async {
    await _db.from('users').insert({
      'name': name,
      'email': email,
      'role': 'admin',
      'society_id': societyId,
      'contact_number': contactNumber,
    });
  }

  Future<void> superAdminDeleteUser(String userId) async {
    await _db.from('users').delete().eq('id', userId);
  }

  // ── Complaints / Maintenance ──────────────────────────────────────────────
  Future<List<dynamic>> getComplaints() async {
    final societyId = _user?['society_id'];
    final query = societyId != null
        ? _db.from('complaints').select().eq('society_id', societyId).order('created_at', ascending: false)
        : _db.from('complaints').select().order('created_at', ascending: false);
    return List<dynamic>.from(await query);
  }

  Future<void> addComplaint(
      String title, String description, String priority) async {
    final uid = _db.auth.currentUser?.id;
    await _db.from('complaints').insert({
      'title': title,
      'description': description,
      'priority': priority,
      'status': 'Open',
      'user_id': uid,
      'society_id': _user?['society_id'],
    });
  }

  Future<void> escalateTicket(String id) async {
    await _db.from('complaints').update({'status': 'Escalated'}).eq('id', id);
  }

  Future<void> resolveTicket(String id) async {
    await _db.from('complaints').update({'status': 'Resolved'}).eq('id', id);
  }

  Future<void> rateTicket(String id, int rating, String comment) async {
    await _db.from('complaints').update({
      'rating': rating,
      'rating_comment': comment,
    }).eq('id', id);
  }

  // ── Billing & Invoices ────────────────────────────────────────────────────
  Future<List<dynamic>> getInvoices() async {
    final uid = _db.auth.currentUser?.id;
    return List<dynamic>.from(
      await _db.from('invoices').select().eq('user_id', uid!).order('created_at', ascending: false),
    );
  }

  Future<void> generateBulkInvoices(
      String title, double amount, double taxAmount, String dueDate) async {
    final societyId = _user?['society_id'];
    // Fetch all residents of this society
    final residents = await _db
        .from('users')
        .select('id')
        .eq('society_id', societyId)
        .eq('role', 'resident');
    final rows = ((residents as List?) ?? []).map((r) => {
      'title': title,
      'amount': amount,
      'tax_amount': taxAmount,
      'due_date': dueDate,
      'status': 'Pending',
      'user_id': r['id'],
      'society_id': societyId,
    }).toList();
    if (rows.isNotEmpty) await _db.from('invoices').insert(rows);
  }

  Future<bool> initiateAndVerifyPayment(String invoiceId) async {
    // Mark invoice as paid (real Razorpay integration would go here)
    await _db.from('invoices').update({
      'status': 'Paid',
      'paid_at': DateTime.now().toIso8601String(),
    }).eq('id', invoiceId);
    return true;
  }

  // ── Dashboard ─────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> getDashboardStats() async {
    final societyId = _user?['society_id'];
    var qComplaints = _db.from('complaints').select('id').eq('status', 'Open');
    if (societyId != null) qComplaints = qComplaints.eq('society_id', societyId);
    final complaints = await qComplaints;

    var qVisitors = _db.from('visitors').select('id');
    if (societyId != null) qVisitors = qVisitors.eq('society_id', societyId);
    final visitors = await qVisitors;

    var qInvoices = _db.from('invoices').select('id').eq('status', 'Pending');
    if (societyId != null) qInvoices = qInvoices.eq('society_id', societyId);
    final invoices = await qInvoices;

    return {
      'openComplaints': ((complaints as List?) ?? []).length,
      'visitorsToday': ((visitors as List?) ?? []).length,
      'pendingInvoices': ((invoices as List?) ?? []).length,
    };
  }

  // ── Visitors ──────────────────────────────────────────────────────────────
  Future<List<dynamic>> getVisitors() async {
    final societyId = _user?['society_id'];
    var query = _db.from('visitors').select();
    if (societyId != null) query = query.eq('society_id', societyId);
    return List<dynamic>.from(await query.order('created_at', ascending: false));
  }

  Future<void> preapproveVisitor(
      String name, String mobile, String purpose, String expectedEntry) async {
    await _db.from('visitors').insert({
      'name': name,
      'mobile': mobile,
      'purpose': purpose,
      'expected_entry': expectedEntry,
      'status': 'Pre-approved',
      'society_id': _user?['society_id'],
    });
  }

  Future<void> updateVisitorStatus(String id, String status) async {
    await _db.from('visitors').update({'status': status}).eq('id', id);
  }

  // ── Daily Help ────────────────────────────────────────────────────────────
  Future<List<dynamic>> getHelp() async {
    final uid = _db.auth.currentUser?.id;
    return List<dynamic>.from(
      await _db.from('daily_help').select().eq('user_id', uid!),
    );
  }

  Future<Map<String, dynamic>> addHelp(Map<String, dynamic> data) async {
    final uid = _db.auth.currentUser?.id;
    final row = await _db.from('daily_help').insert({
      ...data,
      'user_id': uid,
      'society_id': _user?['society_id'],
    }).select().single();
    return Map<String, dynamic>.from(row);
  }

  Future<void> deleteHelp(String id) async {
    await _db.from('daily_help').delete().eq('id', id);
  }

  Future<void> markAttendance(
      String helpId, String date, String status) async {
    await _db.from('help_attendance').upsert({
      'help_id': helpId,
      'date': date,
      'status': status,
    });
  }

  Future<List<dynamic>> getAttendance(String helpId) async {
    return List<dynamic>.from(
      await _db.from('help_attendance').select().eq('help_id', helpId),
    );
  }

  // ── Amenities ─────────────────────────────────────────────────────────────
  Future<List<dynamic>> getAmenities() async {
    final societyId = _user?['society_id'];
    var query = _db.from('amenities').select();
    if (societyId != null) query = query.eq('society_id', societyId);
    return List<dynamic>.from(await query);
  }

  Future<List<dynamic>> getMyBookings() async {
    final uid = _db.auth.currentUser?.id;
    return List<dynamic>.from(
      await _db.from('bookings').select().eq('user_id', uid!),
    );
  }

  Future<void> bookAmenity(String amenityId, String date, String start,
      String end, {String? notes}) async {
    final uid = _db.auth.currentUser?.id;
    await _db.from('bookings').insert({
      'amenity_id': amenityId,
      'user_id': uid,
      'booking_date': date,
      'start_time': start,
      'end_time': end,
      'notes': notes ?? '',
    });
  }

  Future<void> cancelBooking(String bookingId) async {
    await _db.from('bookings').update({'status': 'Cancelled'}).eq('id', bookingId);
  }

  // ── Notices ───────────────────────────────────────────────────────────────
  Future<List<dynamic>> getNotices() async {
    final societyId = _user?['society_id'];
    var query = _db.from('notices').select();
    if (societyId != null) query = query.eq('society_id', societyId);
    return List<dynamic>.from(await query.order('created_at', ascending: false));
  }

  Future<void> createNotice(
      String title, String body, String category, bool isPinned) async {
    await _db.from('notices').insert({
      'title': title,
      'body': body,
      'category': category,
      'is_pinned': isPinned,
      'society_id': _user?['society_id'],
      'created_by': _db.auth.currentUser?.id,
    });
  }

  Future<void> deleteNotice(String id) async {
    await _db.from('notices').delete().eq('id', id);
  }

  // ── Polls ─────────────────────────────────────────────────────────────────
  Future<List<dynamic>> getPolls() async {
    final societyId = _user?['society_id'];
    var query = _db.from('polls').select();
    if (societyId != null) query = query.eq('society_id', societyId);
    return List<dynamic>.from(await query);
  }

  Future<void> votePoll(String pollId, int optionIndex) async {
    final uid = _db.auth.currentUser?.id;
    await _db.from('poll_votes').upsert({
      'poll_id': pollId,
      'user_id': uid,
      'option_index': optionIndex,
    });
  }

  // ── Parking ───────────────────────────────────────────────────────────────
  Future<List<dynamic>> getParkingSlots() async {
    final societyId = _user?['society_id'];
    var query = _db.from('parking_slots').select();
    if (societyId != null) query = query.eq('society_id', societyId);
    return List<dynamic>.from(await query);
  }

  Future<void> allocateParking(String slotId, String flatId,
      String vehicleNo, String vehicleType) async {
    await _db.from('parking_slots').update({
      'flat_id': flatId,
      'vehicle_no': vehicleNo,
      'vehicle_type': vehicleType,
      'is_occupied': true,
    }).eq('id', slotId);
  }

  Future<void> releaseParking(String slotId) async {
    await _db.from('parking_slots').update({
      'flat_id': null,
      'vehicle_no': null,
      'vehicle_type': null,
      'is_occupied': false,
    }).eq('id', slotId);
  }

  // ── Marketplace ───────────────────────────────────────────────────────────
  Future<List<dynamic>> getMarketplace({String? category}) async {
    final societyId = _user?['society_id'];
    var query = _db.from('marketplace').select();
    if (societyId != null) query = query.eq('society_id', societyId);
    if (category != null && category != 'all') {
      query = query.eq('category', category);
    }
    return List<dynamic>.from(await query.order('created_at', ascending: false));
  }

  Future<void> createListing(Map<String, dynamic> data) async {
    final uid = _db.auth.currentUser?.id;
    await _db.from('marketplace').insert({
      ...data,
      'user_id': uid,
      'society_id': _user?['society_id'],
    });
  }

  Future<void> markListingSold(String id) async {
    await _db.from('marketplace').update({'status': 'Sold'}).eq('id', id);
  }

  Future<void> removeListing(String id) async {
    await _db.from('marketplace').delete().eq('id', id);
  }

  // ── Reports ───────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> getFinancialReport() async {
    final societyId = _user?['society_id'];
    var qPaid = _db.from('invoices').select('amount').eq('status', 'Paid');
    if (societyId != null) qPaid = qPaid.eq('society_id', societyId);
    final paid = await qPaid;

    var qPending = _db.from('invoices').select('amount').eq('status', 'Pending');
    if (societyId != null) qPending = qPending.eq('society_id', societyId);
    final pending = await qPending;

    double totalCollected = ((paid as List?) ?? []).fold(0, (s, r) => s + (r['amount'] ?? 0));
    double totalPending = ((pending as List?) ?? []).fold(0, (s, r) => s + (r['amount'] ?? 0));
    return {
      'totalCollected': totalCollected,
      'totalPending': totalPending,
      'collectionRate': totalCollected + totalPending > 0
          ? ((totalCollected / (totalCollected + totalPending)) * 100).toStringAsFixed(1)
          : '0',
    };
  }

  Future<Map<String, dynamic>> getMaintenanceReport() async {
    final societyId = _user?['society_id'];
    var query = _db.from('complaints').select('status');
    if (societyId != null) query = query.eq('society_id', societyId);
    final all = await query;
    final open = ((all as List?) ?? []).where((r) => r['status'] == 'Open').length;
    final resolved = all.where((r) => r['status'] == 'Resolved').length;
    return {'total': all.length, 'open': open, 'resolved': resolved};
  }

  Future<List<dynamic>> getAmenityReport() async {
    final societyId = _user?['society_id'];
    var query = _db.from('bookings').select('*, amenities!inner(name)');
    if (societyId != null) query = query.eq('amenities.society_id', societyId);
    return List<dynamic>.from(await query);
  }

  Future<Map<String, dynamic>> getOccupancyReport() async {
    final societyId = _user?['society_id'];
    var query = _db.from('users').select('id').eq('role', 'resident');
    if (societyId != null) query = query.eq('society_id', societyId);
    final flats = await query;
    return {'occupied': ((flats as List?) ?? []).length};
  }

  // ── Notifications ─────────────────────────────────────────────────────────
  Future<List<dynamic>> getNotifications() async {
    final uid = _db.auth.currentUser?.id;
    return List<dynamic>.from(
      await _db.from('notifications').select().eq('user_id', uid!).order('created_at', ascending: false),
    );
  }

  Future<int> getUnreadNotificationCount() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return 0;
    final res = await _db
        .from('notifications')
        .select('id')
        .eq('user_id', uid)
        .eq('is_read', false);
    return ((res as List?) ?? []).length;
  }

  Future<void> markNotificationRead(String id) async {
    await _db.from('notifications').update({'is_read': true}).eq('id', id);
  }

  Future<void> markAllNotificationsRead() async {
    final uid = _db.auth.currentUser?.id;
    await _db.from('notifications').update({'is_read': true}).eq('user_id', uid!);
  }

  // ── Super Admin Stats / Settings ──────────────────────────────────────────
  Future<Map<String, dynamic>> getSuperAdminStats() async {
    final societies = await _db.from('societies').select('subscription_status');
    final users = await _db.from('users').select('id');
    final invoices = await _db.from('invoices').select('amount, status');

    final activeSocieties = ((societies as List?) ?? []).where((s) => s['subscription_status'] == 'active').length;
    final totalUsers = ((users as List?) ?? []).length;
    
    final paidInvoices = ((invoices as List?) ?? []).where((i) => i['status'] == 'Paid');
    final totalRevenue = paidInvoices.fold(0.0, (sum, i) => sum + (i['amount'] ?? 0).toDouble());
    final pendingInvoices = ((invoices as List?) ?? []).where((i) => i['status'] == 'Pending').length;

    return {
      'activeSocieties': activeSocieties,
      'totalUsers': totalUsers,
      'mrr': totalRevenue.toStringAsFixed(2), // Simplified MRR as total revenue for now
      'totalRevenue': totalRevenue.toStringAsFixed(2),
      'pendingInvoices': pendingInvoices,
    };
  }

  Future<Map<String, dynamic>> getSuperAdminSettings() async {
    final rows = await _db.from('platform_settings').select();
    final settings = <String, dynamic>{};
    for (var r in ((rows as List?) ?? [])) {
      try {
        settings[r['key']] = jsonDecode(r['value']);
      } catch (e) {
        settings[r['key']] = r['value'];
      }
    }
    
    // Provide safe defaults to prevent UI crashes if table is empty
    settings['platformName'] ??= 'SocietyHub Platform';
    settings['supportEmail'] ??= 'support@societyhub.com';
    settings['maintenanceMode'] ??= false;
    settings['payment'] ??= {};
    settings['plans'] ??= [
      {'id': '1', 'name': 'Free Tier', 'price': 0},
      {'id': '2', 'name': 'Basic Tier', 'price': 999},
      {'id': '3', 'name': 'Premium Tier', 'price': 2999},
    ];

    return settings;
  }

  Future<List<dynamic>> getSuperAdminInvoices() async {
    return List<dynamic>.from(
      await _db.from('invoices').select('*, societies(name)').order('created_at', ascending: false),
    );
  }

  Future<void> updateSuperAdminSetting(String key, dynamic value) async {
    await _db.from('platform_settings').upsert({'key': key, 'value': jsonEncode(value)});
  }

  Future<Map<String, dynamic>> getSuperAdminReports() async {
    final stats = await getSuperAdminStats();
    return {
      'planDistribution': {'free': 0, 'basic': 0, 'premium': 0},
      'societies': [],
      'growth': [],
      ...stats,
    };
  }

  Future<List<dynamic>> getSuperAdminLogs() async {
    return List<dynamic>.from(
      await _db.from('audit_logs').select().order('created_at', ascending: false).limit(100),
    );
  }

  // ── Server URL / QR scan (legacy compat) ─────────────────────────────────
  Future<void> setServerUrl(String url) async {}
  Future<bool> testConnection(String societyId) async => true;
}
