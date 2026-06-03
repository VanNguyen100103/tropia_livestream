class CustomerModel {
  final String id;
  final String name;
  final String email;
  final String area;
  final String status;

  CustomerModel({
    required this.id,
    required this.name,
    required this.email,
    required this.area,
    required this.status,
  });

  factory CustomerModel.fromJson(Map<String, dynamic> json) {
    return CustomerModel(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Khách hàng',
      email: json['email'] ?? '',
      area: json['area'] ?? '',
      status: json['status'] ?? 'active',
    );
  }
}