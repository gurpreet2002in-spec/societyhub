// lib/services/supabase_api_service.dart
//
// Drop-in Supabase implementation that EXTENDS ApiService so it is
// type-compatible with every existing provider and screen.

import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
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
        // Both key styles (apartment_number + apartmentNumber) for older screens.
        _user = _camel(row);
        // Society name + type (apartments / villas / mixed) for wording in the app.
        try {
          final info = List<dynamic>.from(await _db.rpc('my_society_info') as List? ?? []);
          if (info.isNotEmpty) {
            _user!['societyName'] = info.first['name'];
            _user!['propertyType'] = info.first['property_type'];
          }
        } catch (_) {}
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

  Future<bool> register(String name, String email, String password,
      {String? societyId, String? joinCode, String? flat, String? occupancyType, String? unitType}) async {
    try {
      final res = await _db.auth.signUp(
        email: email.trim(),
        password: password,
        // The society (from the join code, or the sign-up link) is applied by
        // the handle_new_user trigger in the database; the new resident starts
        // as 'pending' until a society admin approves them.
        data: {
          'name': name.trim(),
          if (joinCode != null && joinCode.trim().isNotEmpty) 'join_code': joinCode.trim().toUpperCase(),
          if (societyId != null) 'society_id': societyId,
          if (flat != null && flat.trim().isNotEmpty) 'apartment_number': flat.trim(),
          if (occupancyType != null) 'occupancy_type': occupancyType,
          if (unitType != null) 'unit_type': unitType,
        },
      );

      // signUp can succeed even if email confirmation is required
      final userId = res.user?.id;
      if (userId == null) throw Exception('Registration failed. Please try again.');

      // If session exists (email confirmation OFF) → load the profile now
      // If no session (email confirmation ON) → user must confirm email first
      if (res.session != null) {
        try {
          // Only fills the name in case the trigger is missing; role, society
          // and status are decided by the database, never by the app.
          await _db.from('users').upsert({'id': userId, 'name': name.trim(), 'email': email.trim()});
        } catch (_) {
          // Non-fatal: the trigger has normally created the row already
        }
        await _loadUserProfile(userId);
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
    final row = _camel(await _db.from('societies').select().eq('id', societyId).single());
    // Totals shown on the Society Settings screen.
    try {
      final residents = await _db
          .from('users')
          .select('id')
          .eq('society_id', societyId)
          .eq('role', 'resident')
          .eq('status', 'active');
      row['totalResidents'] = (residents as List).length;
    } catch (_) {
      row['totalResidents'] = 0;
    }
    row['totalFlats'] = row['total_flats'] ?? 0;
    try {
      final units = await _db.from('units').select('id').eq('society_id', societyId);
      row['unitsInList'] = (units as List).length;
    } catch (_) {
      row['unitsInList'] = 0;
    }
    row['totalBlocks'] = row['totalBlocks'] ?? 0;
    return row;
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
        ? _db.from('users').select().eq('society_id', societyId).order('apartment_number')
        : _db.from('users').select().order('apartment_number');
    return _camelList(await query);
  }

  /// Admin: set a resident's flat and owner/tenant (database tidies the format).
  @override
  Future<void> setUserFlat(String userId, String? flat, String? occupancyType, {String? unitType}) async {
    final updated = await _db
        .from('users')
        .update({
          'apartment_number': (flat ?? '').trim().isEmpty ? null : flat!.trim(),
          'occupancy_type': occupancyType,
          if (unitType != null) 'unit_type': unitType,
        })
        .eq('id', userId)
        .select('id');
    if ((updated as List).isEmpty) throw Exception('You are not allowed to change this user.');
  }

  Future<void> updateUserRole(String userId, String role) async {
    await _db.from('users').update({'role': role}).eq('id', userId);
  }

  Future<void> deleteUser(String userId) async {
    await _db.from('users').delete().eq('id', userId);
  }

  /// Society admin: create a ready-to-use login for a guard or resident.
  /// Runs in the `create-member` Edge Function (service key stays on the server).
  Future<void> adminCreateUser({
    required String name,
    required String email,
    required String password,
    required String role,
    String? contactNumber,
    String? apartmentNumber,
    String? occupancyType,
  }) async {
    try {
      await _db.functions.invoke('create-member', body: {
        'role': role,
        'name': name.trim(),
        'email': email.trim(),
        'password': password,
        'contactNumber': (contactNumber ?? '').trim(),
        'apartmentNumber': (apartmentNumber ?? '').trim(),
        'occupancyType': occupancyType,
      });
    } on FunctionException catch (e) {
      final details = e.details;
      final msg = details is Map && details['error'] != null
          ? details['error'].toString()
          : (e.status == 404
              ? 'The "create-member" function is not deployed yet in Supabase.'
              : 'Could not create the login (${e.status}).');
      throw Exception(msg);
    }
  }

  // ── Super Admin: Societies ────────────────────────────────────────────────
  Future<List<dynamic>> getSuperAdminSocieties() async {
    final rows = _camelList(await _db.from('societies').select('*, users(count)').order('name'));
    for (final r in rows) {
      if (r is Map) {
        final u = r['users'];
        r['total_users'] = (u is List && u.isNotEmpty && u.first is Map) ? (u.first as Map)['count'] ?? 0 : 0;
      }
    }
    return rows;
  }

  String _generateSlug(String name) {
    return name.toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
        .replaceAll(RegExp(r'\s+'), '_');
  }

  Future<void> superAdminCreateSociety({
    required String name,
    required String address,
    required String city,
    required String registrationNumber,
    required String subscriptionPlan,
    String propertyType = 'apartments',
  }) async {
    final reg = registrationNumber.trim();
    final slug = _generateSlug(name);
    
    await _db.from('societies').insert({
      'name': name,
      'slug': slug,
      'address': address,
      'city': city,
      'registration_number': reg.isEmpty ? null : reg,
      'subscription_plan': subscriptionPlan,
      'property_type': propertyType,
    });
  }

  // ── Society join codes & resident approval ───────────────────────────────
  @override
  Future<Map<String, dynamic>?> getSocietyByCode(String code) async {
    final rows = await _db.rpc('get_society_by_code', params: {'p_code': code.trim()});
    final list = List<dynamic>.from(rows as List? ?? []);
    return list.isEmpty ? null : Map<String, dynamic>.from(list.first);
  }

  @override
  Future<String> joinSocietyWithCode(String code, {String? flat, String? occupancyType, String? unitType}) async {
    try {
      final rows = await _db.rpc('join_society_with_code', params: {
        'p_code': code.trim(),
        if (flat != null && flat.trim().isNotEmpty) 'p_flat': flat.trim(),
        if (occupancyType != null) 'p_occupancy': occupancyType,
        if (unitType != null) 'p_unit_type': unitType,
      });
      final list = List<dynamic>.from(rows as List? ?? []);
      await refreshProfile();
      return list.isEmpty ? '' : '${list.first['society_name'] ?? ''}';
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    }
  }

  @override
  Future<String?> mySocietyName() async {
    final name = await _db.rpc('my_society_name');
    return name?.toString();
  }

  @override
  Future<void> refreshProfile() async {
    final uid = _db.auth.currentUser?.id;
    if (uid != null) await _loadUserProfile(uid);
  }

  @override
  Future<void> setUserStatus(String userId, String status) async {
    final updated = await _db.from('users').update({'status': status}).eq('id', userId).select('id');
    if ((updated as List).isEmpty) throw Exception('You are not allowed to change this user.');
  }

  @override
  Future<Map<String, dynamic>?> getSocietyBySlug(String slug) async {
    // Public lookup before login: a DB function that returns only id + name,
    // so the societies table itself is not readable by anonymous visitors.
    final rows = await _db.rpc('get_society_by_slug', params: {'p_slug': slug});
    final list = List<dynamic>.from(rows as List? ?? []);
    return list.isEmpty ? null : Map<String, dynamic>.from(list.first);
  }

  // ── Guard: Visitor Management ─────────────────────────────────────────────
  @override
  Future<List<dynamic>> getSocietyVisitors() async {
    final societyId = _user?['society_id'];
    if (societyId == null) return [];
    
    return List<dynamic>.from(
      await _db.from('visitors')
          .select()
          .eq('society_id', societyId)
          .order('created_at', ascending: false)
          .limit(300)
    );
  }

  @override
  Future<void> checkInVisitor(String visitorId) async {
    await _db.from('visitors').update({
      'status': 'Checked-in',
      'checked_in_at': DateTime.now().toIso8601String(),
      'guard_id': _user?['id'],
    }).eq('id', visitorId);
  }

  @override
  Future<void> checkOutVisitor(String visitorId) async {
    await _db.from('visitors').update({
      'status': 'Checked-out',
      'checked_out_at': DateTime.now().toIso8601String(),
    }).eq('id', visitorId);
  }

  @override
  Future<void> addVisitorEntry({
    required String name,
    required String mobile,
    required String purpose,
    required String flatNumber,
    String? vehicleNumber,
  }) async {
    final societyId = _user?['society_id'];
    if (societyId == null) throw Exception("Society not assigned");

    await _db.from('visitors').insert({
      'name': name,
      'mobile': mobile,
      'purpose': purpose,
      'flat_number': flatNumber,
      'vehicle_number': vehicleNumber,
      'society_id': societyId,
      'status': 'Checked-in',
      'checked_in_at': DateTime.now().toIso8601String(),
      'guard_id': _user?['id'],
    });
  }

  // ── Guard: Vehicle Logs ───────────────────────────────────────────────────
  @override
  Future<List<dynamic>> getVehicleLogs() async {
    final societyId = _user?['society_id'];
    if (societyId == null) return [];
    return List<dynamic>.from(
      await _db.from('vehicle_logs')
          .select()
          .eq('society_id', societyId)
          .order('entry_time', ascending: false)
    );
  }

  @override
  Future<void> addVehicleLog({
    required String vehicleNumber,
    required String vehicleType,
    required String flatNumber,
    String? driverName,
    String? purpose,
  }) async {
    final societyId = _user?['society_id'];
    if (societyId == null) throw Exception("Society not assigned");

    await _db.from('vehicle_logs').insert({
      'vehicle_number': vehicleNumber,
      'vehicle_type': vehicleType,
      'flat_number': flatNumber,
      'driver_name': driverName,
      'purpose': purpose,
      'society_id': societyId,
      'guard_id': _user?['id'],
      'status': 'Inside',
      'entry_time': DateTime.now().toIso8601String(),
    });
  }

  @override
  Future<void> checkOutVehicle(String logId) async {
    await _db.from('vehicle_logs').update({
      'status': 'Out',
      'exit_time': DateTime.now().toIso8601String(),
    }).eq('id', logId);
  }

  // ── Guard: Daily Help ─────────────────────────────────────────────────────
  @override
  Future<List<dynamic>> getDailyHelpStaff() async {
    final societyId = _user?['society_id'];
    if (societyId == null) return [];
    return List<dynamic>.from(
      await _db.from('daily_help')
          .select()
          .eq('society_id', societyId)
    );
  }

  // ── Resident: Vehicle Management ──────────────────────────────────────────
  @override
  Future<List<dynamic>> getMyVehicles() async {
    if (_user == null) return [];
    return List<dynamic>.from(
      await _db.from('resident_vehicles').select().eq('user_id', _user!['id'])
    );
  }

  @override
  Future<void> addMyVehicle({
    required String vehicleNumber,
    required String vehicleType,
    String? brandModel,
    String? color,
  }) async {
    if (_user == null) throw Exception("Not logged in");
    await _db.from('resident_vehicles').insert({
      'vehicle_number': vehicleNumber.toUpperCase(),
      'vehicle_type': vehicleType,
      'brand_model': brandModel,
      'color': color,
      'user_id': _user!['id'],
      'society_id': _user!['society_id'],
    });
  }

  @override
  Future<void> removeMyVehicle(String vehicleId) async {
    await _db.from('resident_vehicles').delete().eq('id', vehicleId);
  }

  @override
  Future<void> updateFcmToken(String? token) async {
    final user = _db.auth.currentUser;
    if (user == null) return;
    await _db.from('users').update({'fcm_token': token}).eq('id', user.id);
  }

  @override
  Future<List<dynamic>> getNotifications() async {
    final user = _db.auth.currentUser;
    if (user == null) return [];
    final res = await _db.from('notifications')
        .select()
        .eq('user_id', user.id)
        .order('created_at', ascending: false);
    return List<dynamic>.from(res);
  }

  @override
  Future<void> markNotificationRead(String id) async {
    await _db.from('notifications').update({'is_read': true}).eq('id', id);
  }

  @override
  Future<void> markAllNotificationsRead() async {
    final user = _db.auth.currentUser;
    if (user == null) return;
    await _db.from('notifications').update({'is_read': true}).eq('user_id', user.id);
  }

  @override
  Future<int> getUnreadNotificationCount() async {
    final user = _db.auth.currentUser;
    if (user == null) return 0;
    final res = await _db.from('notifications')
        .select('id')
        .eq('user_id', user.id)
        .eq('is_read', false);
    return (res as List).length;
  }

  // ── Guard: Vehicle Search ─────────────────────────────────────────────────
  @override
  Future<Map<String, dynamic>?> findResidentByVehicle(String vehicleNumber) async {
    final societyId = _user?['society_id'];
    if (societyId == null) return null;

    final result = await _db
        .from('resident_vehicles')
        .select('*, users(name, apartment_number, contact_number)')
        .eq('society_id', societyId)
        .eq('vehicle_number', vehicleNumber.toUpperCase())
        .maybeSingle();
    
    return result;
  }

  Future<void> superAdminUpdateSociety(String societyId, {
    required String name,
    required String address,
    required String city,
    required String subscriptionStatus,
    required String subscriptionPlan,
    String? propertyType,
  }) async {
    await _db.from('societies').update({
      'name': name,
      'address': address,
      'city': city,
      'subscription_status': subscriptionStatus,
      'subscription_plan': subscriptionPlan,
      if (propertyType != null) 'property_type': propertyType,
    }).eq('id', societyId);
  }

  /// Society admin: change the society type (apartments / villas / mixed).
  @override
  Future<void> setSocietyPropertyType(String propertyType) async {
    final societyId = _user?['society_id'];
    if (societyId == null) throw Exception('No society assigned');
    await _db.from('societies').update({'property_type': propertyType}).eq('id', societyId);
    _user?['propertyType'] = propertyType;
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
    // 1. Check if user already exists in public.users
    final existing = await _db.from('users').select().eq('email', email.trim()).maybeSingle();

    if (existing != null) {
      // User exists (resident who signed up) - upgrade them to admin
      await _db.from('users').update({
        'role': 'admin',
        'society_id': societyId,
        'status': 'active',
        if (contactNumber.trim().isNotEmpty) 'contact_number': contactNumber.trim(),
        if (name.trim().isNotEmpty) 'name': name.trim(),
      }).eq('email', email.trim());
    } else {
      // Brand-new account: created server-side by the `create-admin` Edge
      // Function, which holds the service-role key and checks that the caller
      // is a super admin. (Signing up from this device would log the super
      // admin out, and the service-role key must never ship inside the app.)
      try {
        await _db.functions.invoke('create-admin', body: {
          'name': name.trim(),
          'email': email.trim(),
          'password': password,
          'contactNumber': contactNumber.trim(),
          'societyId': societyId,
        });
      } on FunctionException catch (e) {
        final details = e.details;
        final msg = details is Map && details['error'] != null
            ? details['error'].toString()
            : (e.status == 404
                ? 'The create-admin function is not deployed in Supabase yet.'
                : 'Could not create the admin (error ${e.status}).');
        throw Exception(msg);
      }
    }
  }

  Future<void> superAdminDeleteUser(String userId) async {
    await _db.from('users').delete().eq('id', userId);
  }

  // ── Complaints / Maintenance ──────────────────────────────────────────────
  // Includes the reporter (name, flat) and the number of timeline entries.
  // RLS: residents get their own complaints, admins their society's.
  Future<List<dynamic>> getComplaints() async {
    final societyId = _user?['society_id'];
    const cols = '*, users(name, apartment_number), complaint_comments(count)';
    try {
      final query = societyId != null
          ? _db.from('complaints').select(cols).eq('society_id', societyId).order('created_at', ascending: false)
          : _db.from('complaints').select(cols).order('created_at', ascending: false);
      return List<dynamic>.from(await query);
    } on PostgrestException {
      // complaint_comments table not created yet → plain list
      final query = societyId != null
          ? _db.from('complaints').select('*, users(name, apartment_number)').eq('society_id', societyId).order('created_at', ascending: false)
          : _db.from('complaints').select('*, users(name, apartment_number)').order('created_at', ascending: false);
      return List<dynamic>.from(await query);
    }
  }

  Future<void> addComplaint(
      String title, String description, String priority) async {
    final uid = _db.auth.currentUser?.id;
    final p = priority.trim().toLowerCase();
    await _db.from('complaints').insert({
      'title': title.trim(),
      'description': description.trim(),
      // Stored capitalised ('Low' / 'Medium' / 'High' / 'Critical') everywhere.
      'priority': p.isEmpty ? 'Medium' : '${p[0].toUpperCase()}${p.substring(1)}',
      'status': 'Open',
      'user_id': uid,
      'society_id': _user?['society_id'],
    });
  }

  Future<void> escalateTicket(String id) => updateComplaintStatus(id, 'Escalated');

  Future<void> resolveTicket(String id) => updateComplaintStatus(id, 'Resolved');

  // ── Complaint update thread ──────────────────────────────────────────────
  @override
  Future<List<dynamic>> getComplaintComments(String complaintId) async {
    return List<dynamic>.from(await _db
        .from('complaint_comments')
        .select()
        .eq('complaint_id', complaintId)
        .order('created_at', ascending: true));
  }

  @override
  Future<void> addComplaintComment(String complaintId, String body) async {
    await _db.from('complaint_comments').insert({
      'complaint_id': complaintId,
      'user_id': _db.auth.currentUser?.id,
      'body': body.trim(),
    });
  }

  /// Admin only (checked in the database). Writes a timeline entry too.
  @override
  Future<void> updateComplaintStatus(String complaintId, String status, {String? note}) async {
    try {
      await _db.rpc('update_complaint_status', params: {
        'p_complaint_id': complaintId,
        'p_status': status,
        'p_note': note,
      });
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    }
  }

  Future<void> rateTicket(String id, int rating, String comment) async {
    await _db.from('complaints').update({
      'rating': rating,
      'rating_comment': comment,
    }).eq('id', id);
  }

  // ── Billing & Invoices ────────────────────────────────────────────────────
  // The billing screens were written for the old Node server, which used
  // lowercase statuses and a `totalAmount` field. Supabase stores
  // 'Pending' / 'Under Review' / 'Paid' / 'Overdue' and amount + tax_amount,
  // so rows are normalised here for the UI.
  Map<String, dynamic> _normaliseInvoice(dynamic raw) {
    final row = Map<String, dynamic>.from(raw as Map);
    final amount = (row['amount'] as num?)?.toDouble() ?? 0;
    final tax = (row['tax_amount'] as num?)?.toDouble() ?? 0;
    const statusMap = {
      'Pending': 'unpaid',
      'Overdue': 'overdue',
      'Under Review': 'under_review',
      'Paid': 'paid',
    };
    row['dbStatus'] = row['status'];
    row['status'] = statusMap[row['status']] ?? 'unpaid';
    row['totalAmount'] = amount + tax;
    row['dueDate'] = row['due_date'];
    if (row['users'] != null) row['User'] = row['users'];
    return row;
  }

  Future<List<dynamic>> getInvoices() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return [];
    final rows = await _db
        .from('invoices')
        .select()
        .eq('user_id', uid)
        .order('created_at', ascending: false);
    return (rows as List).map(_normaliseInvoice).toList();
  }

  @override
  Future<List<dynamic>> getSocietyInvoices() async {
    final societyId = _user?['society_id'];
    if (societyId == null) return [];
    final rows = await _db
        .from('invoices')
        .select('*, users(name, apartment_number)')
        .eq('society_id', societyId)
        .order('created_at', ascending: false);
    return (rows as List).map(_normaliseInvoice).toList();
  }

  @override
  Future<void> approveInvoicePayment(String invoiceId) async {
    // Allowed by the database only for admins of the invoice's society.
    final updated = await _db
        .from('invoices')
        .update({'status': 'Paid', 'paid_at': DateTime.now().toIso8601String()})
        .eq('id', invoiceId)
        .select('id');
    if ((updated as List).isEmpty) {
      throw Exception('You are not allowed to approve this invoice.');
    }
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
    // Residents can't mark an invoice "Paid" themselves any more. This tells
    // the society admin "I have paid" (UPI / cash / bank transfer); the admin
    // confirms it from Billing. Enforced in the database by
    // submit_invoice_payment(), so it can't be bypassed from a modified app.
    await _db.rpc('submit_invoice_payment', params: {'p_invoice_id': invoiceId});
    return true;
  }

  // ── Dashboard ─────────────────────────────────────────────────────────────
  // Everything on the dashboard comes from the database (no sample data).
  // Row-level security scopes it: admins see their society, residents their own.
  Future<Map<String, dynamic>> getDashboardStats() async {
    final societyId = _user?['society_id'];
    if (societyId == null) {
      return {
        'openComplaints': 0, 'criticalComplaints': 0, 'pendingComplaints': 0,
        'visitorsToday': 0, 'pendingInvoices': 0,
        'collectionPct': 0, 'totalCollection': '0', 'expected': '0',
        'recentComplaints': <dynamic>[], 'recentNotices': <dynamic>[],
      };
    }

    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day).toUtc().toIso8601String();

    final results = await Future.wait([
      _db.from('complaints').select('id, priority, status')
          .eq('society_id', societyId).neq('status', 'Resolved'),
      _db.from('visitors').select('id')
          .eq('society_id', societyId).gte('created_at', startOfToday),
      _db.from('invoices').select('amount, tax_amount, status')
          .eq('society_id', societyId),
      _db.from('complaints')
          .select('id, title, priority, status, created_at, users(name, apartment_number)')
          .eq('society_id', societyId)
          .order('created_at', ascending: false)
          .limit(3),
      _db.from('notices').select('id, title, body, category, is_pinned, created_at')
          .eq('society_id', societyId)
          .order('created_at', ascending: false)
          .limit(2),
    ]);

    final open = List<Map<String, dynamic>>.from(results[0] as List);
    final visitorsToday = (results[1] as List).length;
    final invoices = List<Map<String, dynamic>>.from(results[2] as List);

    double total = 0, paid = 0;
    int pendingInvoices = 0;
    for (final inv in invoices) {
      final amt = ((inv['amount'] as num?) ?? 0).toDouble() + ((inv['tax_amount'] as num?) ?? 0).toDouble();
      total += amt;
      if (inv['status'] == 'Paid') {
        paid += amt;
      } else {
        pendingInvoices++;
      }
    }

    return {
      'openComplaints': open.length,
      'criticalComplaints': open.where((c) => c['priority'] == 'Critical' || c['priority'] == 'High').length,
      'pendingComplaints': open.where((c) => c['status'] == 'Open').length,
      'visitorsToday': visitorsToday,
      'pendingInvoices': pendingInvoices,
      'collectionPct': total > 0 ? (paid / total * 100).round() : 0,
      'totalCollection': _compactInr(paid),
      'expected': _compactInr(total),
      'recentComplaints': results[3] as List,
      'recentNotices': results[4] as List,
    };
  }

  /// 950 → "950", 12,500 → "12.5K", 4,20,000 → "4.2L", 1,50,00,000 → "1.5Cr"
  String _compactInr(double v) {
    String trim(double x) => x.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '');
    if (v >= 10000000) return '${trim(v / 10000000)}Cr';
    if (v >= 100000) return '${trim(v / 100000)}L';
    if (v >= 1000) return '${trim(v / 1000)}K';
    return v.toStringAsFixed(0);
  }

  // ── Visitor approval (guard asks, flat answers) ───────────────────────────
  /// Guard: create the visitor and ring every resident of that flat.
  /// Returns {visitorId, residents} — residents = how many people were asked.
  @override
  Future<Map<String, dynamic>> requestVisitorApproval({
    required String name,
    required String mobile,
    required String purpose,
    required String flatNumber,
    String? vehicleNumber,
  }) async {
    final rows = await _db.rpc('request_visitor_approval', params: {
      'p_name': name,
      'p_mobile': mobile,
      'p_purpose': purpose,
      'p_flat': flatNumber,
      'p_vehicle': vehicleNumber,
    });
    final r = Map<String, dynamic>.from((rows as List).first as Map);
    return {'visitorId': '${r['visitor_id']}', 'residents': (r['residents'] as num?)?.toInt() ?? 0};
  }

  @override
  Future<void> reaskVisitorApproval(String visitorId) async {
    await _db.rpc('reask_visitor_approval', params: {'p_id': visitorId});
  }

  /// Resident: approve / decline. Returns {status, by, alreadyAnswered}.
  @override
  Future<Map<String, dynamic>> respondToVisitor(String visitorId, bool approve, {String? note}) async {
    final rows = await _db.rpc('respond_to_visitor', params: {
      'p_id': visitorId,
      'p_approve': approve,
      'p_note': note,
    });
    final r = Map<String, dynamic>.from((rows as List).first as Map);
    return {
      'status': r['approval_status'],
      'by': r['decided_by_name'],
      'alreadyAnswered': r['already_answered'] == true,
    };
  }

  @override
  Future<Map<String, dynamic>?> getVisitor(String visitorId) async {
    final row = await _db.from('visitors').select().eq('id', visitorId).maybeSingle();
    return row == null ? null : Map<String, dynamic>.from(row);
  }

  /// Guard: visitor sent back at the gate.
  @override
  Future<void> turnAwayVisitor(String visitorId) async {
    await _db.from('visitors').update({'status': 'Turned away'}).eq('id', visitorId);
  }

  // ── Visitors ──────────────────────────────────────────────────────────────
  Future<List<dynamic>> getVisitors() async {
    final societyId = _user?['society_id'];
    var query = _db.from('visitors').select();
    if (societyId != null) query = query.eq('society_id', societyId);
    return List<dynamic>.from(await query.order('created_at', ascending: false));
  }

  /// Resident: gate pass for an expected visitor. The database fills in the
  /// resident's flat / house and a 6-digit pass code; returns the saved pass.
  @override
  Future<Map<String, dynamic>?> preapproveVisitor(
      String name, String mobile, String purpose, String expectedEntry,
      {DateTime? validUntil}) async {
    final row = await _db.from('visitors').insert({
      'name': name,
      'mobile': mobile,
      'purpose': purpose,
      'expected_entry': expectedEntry,
      'status': 'Pre-approved',
      'society_id': _user?['society_id'],
      'flat_number': _user?['apartment_number'],
      if (validUntil != null) 'pass_valid_until': validUntil.toUtc().toIso8601String(),
    }).select().single();
    return Map<String, dynamic>.from(row);
  }

  /// Guard: check a pass code (typed or scanned). Throws a readable message
  /// if the code is wrong, used or expired.
  @override
  Future<Map<String, dynamic>> verifyVisitorPass(String code) async {
    try {
      final rows = await _db.rpc('verify_visitor_pass', params: {'p_code': code});
      return Map<String, dynamic>.from((rows as List).first as Map);
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    }
  }

  /// Emergency alert to all admins and guards. Returns how many were alerted.
  @override
  Future<int> raiseSos({String? message}) async {
    try {
      final n = await _db.rpc('raise_sos', params: {'p_message': message});
      return (n as num?)?.toInt() ?? 0;
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    }
  }

  Future<void> updateVisitorStatus(String id, String status) async {
    await _db.from('visitors').update({'status': status}).eq('id', id);
  }

  // ── Field-name bridge ─────────────────────────────────────────────────────
  // Several screens were written for the old Node server and read camelCase
  // keys (createdAt, slotNumber, isPinned…). Supabase returns snake_case, so
  // each row also gets camelCase copies of its keys (nested maps too).
  static String _toCamel(String k) =>
      k.replaceAllMapped(RegExp(r'_([a-z0-9])'), (m) => m.group(1)!.toUpperCase());

  static Map<String, dynamic> _camel(dynamic raw) {
    final src = Map<String, dynamic>.from(raw as Map);
    final out = <String, dynamic>{};
    src.forEach((k, v) {
      final val = v is Map ? _camel(v) : v;
      out[k] = val;
      if (k.contains('_')) out.putIfAbsent(_toCamel(k), () => val);
    });
    return out;
  }

  static List<dynamic> _camelList(dynamic rows) =>
      (rows as List? ?? []).map((r) => r is Map ? _camel(r) : r).toList();

  // ── Daily Help ────────────────────────────────────────────────────────────
  Future<List<dynamic>> getHelp() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return [];
    return _camelList(await _db.from('daily_help').select().eq('user_id', uid));
  }

  Future<Map<String, dynamic>> addHelp(Map<String, dynamic> data) async {
    final uid = _db.auth.currentUser?.id;
    final days = data['workingDays'] ?? data['working_days'];
    // Only known fields are saved (unknown keys would break the insert).
    final row = await _db.from('daily_help').insert({
      'name': '${data['name'] ?? ''}'.trim(),
      'mobile': '${data['mobile'] ?? ''}'.trim(),
      'type': data['type'] ?? 'other',
      if ((data['entryTime'] ?? data['entry_time']) != null) 'entry_time': data['entryTime'] ?? data['entry_time'],
      if ((data['exitTime'] ?? data['exit_time']) != null) 'exit_time': data['exitTime'] ?? data['exit_time'],
      if (days != null) 'working_days': days is List ? days.join(',') : '$days',
      'is_active': data['isActive'] ?? data['is_active'] ?? true,
      'user_id': uid,
      'society_id': _user?['society_id'],
    }).select().single();
    return _camel(row);
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
    }, onConflict: 'help_id,date');
  }

  Future<List<dynamic>> getAttendance(String helpId) async {
    return _camelList(await _db.from('help_attendance').select().eq('help_id', helpId));
  }

  // ── Amenities ─────────────────────────────────────────────────────────────
  Future<List<dynamic>> getAmenities() async {
    final societyId = _user?['society_id'];
    var query = _db.from('amenities').select();
    if (societyId != null) query = query.eq('society_id', societyId);
    return _camelList(await query.order('name'));
  }

  Future<List<dynamic>> getMyBookings() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return [];
    final rows = _camelList(await _db
        .from('bookings')
        .select('*, amenities(name, image_emoji)')
        .eq('user_id', uid)
        .order('booking_date', ascending: false));
    for (final r in rows) {
      if (r is Map && r['amenities'] != null) r['Amenity'] = r['amenities'];
    }
    return rows;
  }

  Future<void> bookAmenity(String amenityId, String date, String start,
      String end, {String? notes}) async {
    final uid = _db.auth.currentUser?.id;
    // Amount = hourly price × hours (0 for free amenities).
    double total = 0;
    try {
      final a = await _db.from('amenities').select('price_per_hour').eq('id', amenityId).maybeSingle();
      final price = ((a?['price_per_hour'] as num?) ?? 0).toDouble();
      int mins(String t) {
        final p = t.split(':');
        return (int.tryParse(p[0]) ?? 0) * 60 + (p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0);
      }
      final hours = (mins(end) - mins(start)) / 60.0;
      if (price > 0 && hours > 0) total = price * hours;
    } catch (_) {}
    await _db.from('bookings').insert({
      'amenity_id': amenityId,
      'user_id': uid,
      'booking_date': date,
      'start_time': start,
      'end_time': end,
      'notes': notes ?? '',
      'total_amount': total,
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
    final rows = _camelList(await query.order('created_at', ascending: false));
    for (final r in rows) {
      if (r is Map) r['postedBy'] = {'name': r['posted_by_name'] ?? 'Admin'};
    }
    return rows;
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
  // Results come from get_polls_with_results(): counts are shared, but who
  // voted for what stays private.
  Future<List<dynamic>> getPolls() async {
    List<dynamic> rows;
    try {
      rows = List<dynamic>.from(await _db.rpc('get_polls_with_results') as List);
    } on PostgrestException {
      final societyId = _user?['society_id'];
      var query = _db.from('polls').select();
      if (societyId != null) query = query.eq('society_id', societyId);
      rows = List<dynamic>.from(await query);
    }
    return rows.map((raw) {
      final p = _camel(raw);
      final opts = (p['options'] as List? ?? [])
          .map((o) => o is Map ? '${o['label'] ?? o['text'] ?? ''}' : '$o')
          .toList();
      final counts = (p['vote_counts'] as List? ?? []).map((c) => (c as num).toInt()).toList();
      p['options'] = opts;
      p['voteCounts'] = List<int>.generate(opts.length, (i) => i < counts.length ? counts[i] : 0);
      p['totalVotes'] = (p['total_votes'] as num?)?.toInt() ?? 0;
      p['userVote'] = (p['user_vote'] as num?)?.toInt();
      p['endDate'] = p['ends_at'];
      return p;
    }).toList();
  }

  Future<void> votePoll(String pollId, int optionIndex) async {
    final uid = _db.auth.currentUser?.id;
    await _db.from('poll_votes').upsert({
      'poll_id': pollId,
      'user_id': uid,
      'option_index': optionIndex,
    }, onConflict: 'poll_id,user_id');
  }

  // ── Parking ───────────────────────────────────────────────────────────────
  Future<List<dynamic>> getParkingSlots() async {
    final societyId = _user?['society_id'];
    var query = _db.from('parking_slots').select();
    if (societyId != null) query = query.eq('society_id', societyId);
    final rows = _camelList(await query.order('slot_number'));
    for (final r in rows) {
      if (r is Map) {
        r['status'] = r['is_occupied'] == true ? 'occupied' : 'available';
        r['type'] = '${r['slot_type'] ?? 'car'}'.toLowerCase();
      }
    }
    return rows;
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
  // category: 'all' = everything, 'other' = the "My Ads" tab, else a category.
  Future<List<dynamic>> getMarketplace({String? category}) async {
    final societyId = _user?['society_id'];
    var query = _db.from('marketplace').select();
    if (societyId != null) query = query.eq('society_id', societyId);
    if (category == 'other') {
      query = query.eq('user_id', _db.auth.currentUser?.id ?? '');
    } else if (category != null && category != 'all') {
      query = query.eq('category', category);
    }
    final rows = _camelList(await query.order('created_at', ascending: false));
    for (final r in rows) {
      if (r is Map) {
        r['sellerId'] = r['user_id'];
        r['seller'] = {'name': r['seller_name'] ?? 'Resident', 'flatNumber': r['seller_flat'] ?? ''};
        r['listingType'] = r['listing_type'] ?? 'sale';
        r['price'] = (r['price'] as num?) ?? 0;
      }
    }
    return rows;
  }

  Future<void> createListing(Map<String, dynamic> data) async {
    final uid = _db.auth.currentUser?.id;
    final category = '${data['category'] ?? 'other'}';
    final type = '${data['listingType'] ?? data['listing_type'] ?? 'sale'}';
    // Only known fields are saved; seller name/flat are added by the database.
    await _db.from('marketplace').insert({
      'title': '${data['title'] ?? ''}'.trim(),
      'description': '${data['description'] ?? ''}'.trim(),
      'price': (data['price'] as num?) ?? 0,
      'category': category,
      'condition': data['condition'] ?? 'good',
      'image_emoji': data['imageEmoji'] ?? data['image_emoji'],
      'listing_type': category == 'property' && type == 'rent' ? 'rent' : 'sale',
      'status': 'Available',
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

  // ── Admin setup: polls, amenities, parking ───────────────────────────────
  // All protected by row-level security: only the society's admin can write.
  @override
  Future<void> createPoll(String question, List<String> options, {DateTime? endsAt}) async {
    final opts = options.map((o) => o.trim()).where((o) => o.isNotEmpty).toList();
    if (question.trim().isEmpty || opts.length < 2) {
      throw Exception('Enter a question and at least two options.');
    }
    await _db.from('polls').insert({
      'question': question.trim(),
      'options': opts,
      if (endsAt != null) 'ends_at': endsAt.toUtc().toIso8601String(),
      'society_id': _user?['society_id'],
      'created_by': _db.auth.currentUser?.id,
    });
  }

  @override
  Future<void> deletePoll(String pollId) async {
    await _db.from('polls').delete().eq('id', pollId);
  }

  @override
  Future<void> saveAmenity(Map<String, dynamic> data, {String? id}) async {
    final row = <String, dynamic>{
      'name': '${data['name'] ?? ''}'.trim(),
      'description': '${data['description'] ?? ''}'.trim(),
      'capacity': int.tryParse('${data['capacity'] ?? ''}') ?? 1,
      'image_emoji': data['imageEmoji'] ?? '\u{1F3E2}',
      'price_per_hour': double.tryParse('${data['pricePerHour'] ?? ''}') ?? 0,
      'open_time': data['openTime'] ?? '06:00',
      'close_time': data['closeTime'] ?? '22:00',
    };
    if ((row['name'] as String).isEmpty) throw Exception('Enter the amenity name.');
    if (id == null) {
      await _db.from('amenities').insert({...row, 'society_id': _user?['society_id']});
    } else {
      await _db.from('amenities').update(row).eq('id', id);
    }
  }

  @override
  Future<void> deleteAmenity(String id) async {
    await _db.from('amenities').delete().eq('id', id);
  }

  /// Adds slots, skipping numbers that already exist. Returns how many were added.
  @override
  Future<int> addParkingSlots(List<String> slotNumbers, String slotType) async {
    final societyId = _user?['society_id'];
    final existing = List<Map<String, dynamic>>.from(
        await _db.from('parking_slots').select('slot_number').eq('society_id', societyId));
    final taken = existing.map((e) => '${e['slot_number']}'.trim().toUpperCase()).toSet();
    final rows = <Map<String, dynamic>>[];
    for (final n in slotNumbers.map((s) => s.trim()).where((s) => s.isNotEmpty)) {
      if (taken.add(n.toUpperCase())) {
        rows.add({'slot_number': n, 'slot_type': slotType, 'is_occupied': false, 'society_id': societyId});
      }
    }
    if (rows.isNotEmpty) await _db.from('parking_slots').insert(rows);
    return rows.length;
  }

  @override
  Future<void> deleteParkingSlot(String id) async {
    await _db.from('parking_slots').delete().eq('id', id);
  }

  // ── Flats / houses register (society admin) ──────────────────────────────
  @override
  Future<List<dynamic>> getUnits() async {
    final societyId = _user?['society_id'];
    if (societyId == null) return [];
    return _camelList(await _db.from('units').select().eq('society_id', societyId).order('number'));
  }

  /// Add (id == null) or edit a flat / house. The database tidies the number.
  @override
  Future<void> saveUnit({
    String? id,
    required String number,
    String? unitType,
    String? block,
    String? floor,
    String? ownerName,
    String? ownerPhone,
    String? ownerEmail,
    String? notes,
  }) async {
    final societyId = _user?['society_id'];
    if (societyId == null) throw Exception('No society assigned');
    final row = {
      'number': number.trim(),
      if (unitType != null) 'unit_type': unitType,
      'block': block,
      'floor': floor,
      'owner_name': ownerName,
      'owner_phone': ownerPhone,
      'owner_email': ownerEmail,
      'notes': notes,
    };
    try {
      if (id == null) {
        await _db.from('units').insert({...row, 'society_id': societyId});
      } else {
        final updated = await _db.from('units').update(row).eq('id', id).select('id');
        if ((updated as List).isEmpty) throw Exception('You are not allowed to change this.');
      }
    } on PostgrestException catch (e) {
      if (e.code == '23505') throw Exception('${number.trim().toUpperCase()} already exists in the list.');
      rethrow;
    }
  }

  @override
  Future<void> deleteUnit(String id) async {
    await _db.from('units').delete().eq('id', id);
  }

  /// Bulk add / update. Rows use keys: number, type, block, floor, owner_name,
  /// owner_phone, owner_email, notes, parking ("P-1; P-2").
  @override
  Future<Map<String, dynamic>> importUnits(List<Map<String, dynamic>> rows) async {
    final res = await _db.rpc('import_units', params: {'p_rows': rows});
    final list = List<dynamic>.from(res as List? ?? []);
    final r = list.isEmpty ? <String, dynamic>{} : Map<String, dynamic>.from(list.first as Map);
    return {
      'added': r['added'] ?? 0,
      'updated': r['updated'] ?? 0,
      'skipped': r['skipped'] ?? 0,
      'parkingAssigned': r['parking_assigned'] ?? 0,
      'errors': List<String>.from((r['errors'] as List?) ?? const []),
    };
  }

  @override
  Future<void> setTotalFlats(int totalFlats) async {
    final societyId = _user?['society_id'];
    if (societyId == null) throw Exception('No society assigned');
    await _db.from('societies').update({'total_flats': totalFlats}).eq('id', societyId);
  }

  // ── Reports (society admin) ───────────────────────────────────────────────
  Future<Map<String, dynamic>> getFinancialReport() async {
    final societyId = _user?['society_id'];
    if (societyId == null) return _emptyFinancial();
    final rows = List<Map<String, dynamic>>.from(await _db
        .from('invoices')
        .select('amount, tax_amount, status, due_date')
        .eq('society_id', societyId));
    final today = DateTime.now();
    double billed = 0, collected = 0;
    int paid = 0, unpaid = 0, overdue = 0;
    for (final r in rows) {
      final amt = ((r['amount'] as num?) ?? 0).toDouble() + ((r['tax_amount'] as num?) ?? 0).toDouble();
      billed += amt;
      final due = DateTime.tryParse('${r['due_date']}');
      if (r['status'] == 'Paid') {
        paid++;
        collected += amt;
      } else if (r['status'] == 'Overdue' || (due != null && due.isBefore(DateTime(today.year, today.month, today.day)))) {
        overdue++;
      } else {
        unpaid++;
      }
    }
    return {
      'totalInvoices': rows.length,
      'paid': paid,
      'unpaid': unpaid,
      'overdue': overdue,
      'totalBilled': billed.toStringAsFixed(0),
      'totalCollected': collected.toStringAsFixed(0),
      'totalOutstanding': (billed - collected).toStringAsFixed(0),
      'totalPending': (billed - collected),
      'collectionRate': billed > 0 ? (collected / billed * 100).toStringAsFixed(1) : '0',
    };
  }

  Map<String, dynamic> _emptyFinancial() => {
        'totalInvoices': 0, 'paid': 0, 'unpaid': 0, 'overdue': 0,
        'totalBilled': '0', 'totalCollected': '0', 'totalOutstanding': '0',
        'totalPending': 0.0, 'collectionRate': '0',
      };

  Future<Map<String, dynamic>> getMaintenanceReport() async {
    final societyId = _user?['society_id'];
    final byStatus = <String, dynamic>{'pending': 0, 'in_progress': 0, 'resolved': 0, 'escalated': 0};
    if (societyId == null) {
      return {'total': 0, 'byStatus': byStatus, 'avgResolutionHours': '-', 'avgRating': '-', 'open': 0, 'resolved': 0};
    }
    final rows = List<Map<String, dynamic>>.from(await _db
        .from('complaints')
        .select('status, rating, created_at, resolved_at')
        .eq('society_id', societyId));
    double hoursSum = 0, ratingSum = 0;
    int hoursN = 0, ratingN = 0;
    for (final r in rows) {
      final s = '${r['status'] ?? ''}'.toLowerCase();
      final key = s == 'resolved'
          ? 'resolved'
          : s == 'escalated'
              ? 'escalated'
              : (s == 'in progress' || s == 'in_progress')
                  ? 'in_progress'
                  : 'pending';
      byStatus[key] = (byStatus[key] as int) + 1;
      final c = DateTime.tryParse('${r['created_at']}');
      final done = DateTime.tryParse('${r['resolved_at']}');
      if (c != null && done != null) {
        hoursSum += done.difference(c).inMinutes / 60.0;
        hoursN++;
      }
      if (r['rating'] is num) {
        ratingSum += (r['rating'] as num).toDouble();
        ratingN++;
      }
    }
    return {
      'total': rows.length,
      'byStatus': byStatus,
      'open': byStatus['pending'],
      'resolved': byStatus['resolved'],
      'avgResolutionHours': hoursN > 0 ? (hoursSum / hoursN).toStringAsFixed(1) : '-',
      'avgRating': ratingN > 0 ? (ratingSum / ratingN).toStringAsFixed(1) : '-',
    };
  }

  Future<List<dynamic>> getAmenityReport() async {
    final societyId = _user?['society_id'];
    if (societyId == null) return [];
    final amenities = List<Map<String, dynamic>>.from(
        await _db.from('amenities').select('id, name, image_emoji').eq('society_id', societyId));
    final bookings = List<Map<String, dynamic>>.from(await _db
        .from('bookings')
        .select('amenity_id, status, total_amount, amenities!inner(society_id)')
        .eq('amenities.society_id', societyId));
    return amenities.map((a) {
      final mine = bookings.where((b) => b['amenity_id'] == a['id'] && b['status'] != 'Cancelled');
      return <String, dynamic>{
        'name': a['name'] ?? 'Amenity',
        'emoji': a['image_emoji'] ?? '\u{1F3E2}',
        'bookings': mine.length,
        'revenue': mine.fold<double>(0, (s, b) => s + ((b['total_amount'] as num?) ?? 0).toDouble()),
      };
    }).toList();
  }

  Future<Map<String, dynamic>> getOccupancyReport() async {
    final societyId = _user?['society_id'];
    if (societyId == null) return {'occupied': 0};
    final residents = List<Map<String, dynamic>>.from(await _db
        .from('users')
        .select('apartment_number')
        .eq('society_id', societyId)
        .eq('role', 'resident')
        .eq('status', 'active'));
    final slots = List<Map<String, dynamic>>.from(
        await _db.from('parking_slots').select('is_occupied').eq('society_id', societyId));
    final Map<String, dynamic>? society =
        await _db.from('societies').select('total_flats').eq('id', societyId).maybeSingle();
    final occupiedFlats = residents
        .map((r) => '${r['apartment_number'] ?? ''}'.trim().toUpperCase())
        .where((f) => f.isNotEmpty)
        .toSet()
        .length;
    final totalFlats = (society?['total_flats'] as num?)?.toInt() ?? occupiedFlats;
    final parkingTotal = slots.length;
    final parkingOccupied = slots.where((s) => s['is_occupied'] == true).length;
    return {
      'occupied': residents.length,
      'totalResidents': residents.length,
      'totalFlats': totalFlats,
      'occupiedFlats': occupiedFlats,
      'vacantFlats': (totalFlats - occupiedFlats).clamp(0, 1 << 30),
      'occupancyRate': totalFlats > 0 ? (occupiedFlats / totalFlats * 100).toStringAsFixed(0) : '0',
      'parkingTotal': parkingTotal,
      'parkingOccupied': parkingOccupied,
      'parkingAvailable': parkingTotal - parkingOccupied,
      'parkingUtilization': parkingTotal > 0 ? (parkingOccupied / parkingTotal * 100).toStringAsFixed(0) : '0',
    };
  }

  @override
  Future<List<Map<String, dynamic>>> getAllResidents() async {
    final res = await _db.from('users')
      .select('id, name, email, role')
      .eq('role', 'resident')
      .order('name');
    return List<Map<String, dynamic>>.from(res);
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
    final rows = _camelList(
      await _db.from('invoices').select('*, societies(name)').order('created_at', ascending: false),
    );
    for (final r in rows) {
      if (r is Map) {
        r['societyName'] = (r['societies'] as Map?)?['name'] ?? '';
        r['date'] = '${r['created_at'] ?? ''}'.split('T').first;
        r['amount'] = ((r['amount'] as num?) ?? 0) + ((r['tax_amount'] as num?) ?? 0);
        r['status'] = '${r['status'] ?? ''}'.toLowerCase();
      }
    }
    return rows;
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
