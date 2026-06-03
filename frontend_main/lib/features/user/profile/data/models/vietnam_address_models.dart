/// Models cho API: https://provinces.open-api.vn/api/v2/
/// v2 chỉ có 2 cấp: Province → Ward (không có District)
library;

class Province {
  final int code;
  final String name;
  final String divisionType;
  final String codename;
  final int phoneCode;
  final List<Ward> wards;

  Province({
    required this.code,
    required this.name,
    this.divisionType = '',
    this.codename = '',
    this.phoneCode = 0,
    this.wards = const [],
  });

  @override
  bool operator ==(Object other) => other is Province && other.code == code;

  @override
  int get hashCode => code.hashCode;

  factory Province.fromJson(Map<String, dynamic> json) {
    List<Ward> wards = [];
    if (json['wards'] != null && json['wards'] is List) {
      wards = (json['wards'] as List).map((w) => Ward.fromJson(w)).toList();
    }
    return Province(
      code: json['code'] ?? 0,
      name: json['name'] ?? '',
      divisionType: json['division_type'] ?? '',
      codename: json['codename'] ?? '',
      phoneCode: json['phone_code'] ?? 0,
      wards: wards,
    );
  }
}

class Ward {
  final int code;
  final String name;
  final String divisionType;
  final String codename;
  final int provinceCode;

  Ward({
    required this.code,
    required this.name,
    this.divisionType = '',
    this.codename = '',
    this.provinceCode = 0,
  });

  @override
  bool operator ==(Object other) => other is Ward && other.code == code;

  @override
  int get hashCode => code.hashCode;

  factory Ward.fromJson(Map<String, dynamic> json) {
    return Ward(
      code: json['code'] ?? 0,
      name: json['name'] ?? '',
      divisionType: json['division_type'] ?? '',
      codename: json['codename'] ?? '',
      provinceCode: json['province_code'] ?? 0,
    );
  }
}
