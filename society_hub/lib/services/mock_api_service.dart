
class MockApiService {
  Future<bool> login(String mobileNumber) async {
    await Future.delayed(const Duration(seconds: 1));
    return mobileNumber.length == 10;
  }

  Future<Map<String, dynamic>> getDashboardStats() async {
    await Future.delayed(const Duration(milliseconds: 800));
    return {
      'collection': '85%',
      'collectionAmount': '4.2L',
      'openComplaints': 12,
      'visitorsToday': 45,
    };
  }

  Future<List<Map<String, String>>> getComplaints() async {
    await Future.delayed(const Duration(seconds: 1));
    return [
      {'title': 'Water Leakage', 'status': 'Critical', 'flat': 'A-101'},
      {'title': 'Lift Not Working', 'status': 'Investigating', 'flat': 'Wing B'},
    ];
  }

  Future<bool> approveVisitor(String visitorId) async {
    await Future.delayed(const Duration(seconds: 1));
    return true; // Mock real-time approval
  }

  Future<bool> addParkingVehicle(String vehicleNo) async {
    await Future.delayed(const Duration(seconds: 1));
    return true;
  }
}
