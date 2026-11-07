class Visitor {
  final String id;
  final String name;
  final String mobile;
  final String purpose;
  final String status;
  final String? expectedEntry;
  final String? actualEntry;
  final String? exitTime;
  final String? passCode;
  final String? flatNumber;
  final DateTime? passValidUntil;

  Visitor({
    required this.id,
    required this.name,
    required this.mobile,
    required this.purpose,
    required this.status,
    this.expectedEntry,
    this.actualEntry,
    this.exitTime,
    this.passCode,
    this.flatNumber,
    this.passValidUntil,
  });

  /// A pass that can still be used at the gate.
  bool get isActivePass =>
      status == 'Pre-approved' &&
      passCode != null &&
      (passValidUntil == null || passValidUntil!.isAfter(DateTime.now()));

  factory Visitor.fromJson(Map<String, dynamic> json) {
    return Visitor(
      id: '${json['id'] ?? ''}',
      name: '${json['name'] ?? ''}',
      mobile: '${json['mobile'] ?? ''}',
      purpose: '${json['purpose'] ?? ''}',
      status: '${json['status'] ?? 'Pending'}',
      expectedEntry: (json['expected_entry'] ?? json['expectedEntry'])?.toString(),
      actualEntry: (json['checked_in_at'] ?? json['actualEntry'])?.toString(),
      exitTime: (json['checked_out_at'] ?? json['exitTime'])?.toString(),
      passCode: (json['pass_code'] ?? json['passCode'])?.toString(),
      flatNumber: json['flat_number']?.toString(),
      passValidUntil: DateTime.tryParse('${json['pass_valid_until'] ?? ''}')?.toLocal(),
    );
  }
}
