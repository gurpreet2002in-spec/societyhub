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
  });

  factory Visitor.fromJson(Map<String, dynamic> json) {
    return Visitor(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      mobile: json['mobile'] ?? '',
      purpose: json['purpose'] ?? '',
      status: json['status'] ?? 'Pending',
      expectedEntry: json['expectedEntry'],
      actualEntry: json['actualEntry'],
      exitTime: json['exitTime'],
      passCode: json['passCode']?.toString(), // Handle if numeric from DB
    );
  }
}
