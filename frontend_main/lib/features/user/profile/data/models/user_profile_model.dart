class UserProfileModel {
  final int id;
  final String name;
  final String phone;
  final String avatarUrl;
  final LoyaltyModel loyalty;
  final WalletModel wallet;
  final CountersModel counters;

  UserProfileModel({
    required this.id,
    required this.name,
    required this.phone,
    required this.avatarUrl,
    required this.loyalty,
    required this.wallet,
    required this.counters,
  });

  factory UserProfileModel.fromJson(Map<String, dynamic> json) {
    return UserProfileModel(
      id: json['info'] != null ? json['info']['id'] ?? 0 : 0,
      name: json['info'] != null ? json['info']['name'] ?? '' : '',
      phone: json['info'] != null ? json['info']['phone'] ?? '' : '',
      avatarUrl: json['info'] != null ? json['info']['avatar_url'] ?? '' : '',
      loyalty: LoyaltyModel.fromJson(json['loyalty'] ?? {}),
      wallet: WalletModel.fromJson(json['wallet'] ?? {}),
      counters: CountersModel.fromJson(json['counters'] ?? {}),
    );
  }
}

class LoyaltyModel {
  final String rankName;
  final int currentPoints;
  final String barcode;

  LoyaltyModel({
    required this.rankName,
    required this.currentPoints,
    required this.barcode,
  });

  factory LoyaltyModel.fromJson(Map<String, dynamic> json) {
    return LoyaltyModel(
      rankName: json['rank_name'] ?? 'Thành viên',
      currentPoints: (json['current_points'] as num?)?.toInt() ?? 0,
      barcode: json['barcode'] ?? '',
    );
  }
}

class WalletModel {
  final double balance;
  final String currencyUnit;

  WalletModel({required this.balance, required this.currencyUnit});

  factory WalletModel.fromJson(Map<String, dynamic> json) {
    return WalletModel(
      balance: (json['balance'] as num?)?.toDouble() ?? 0,
      currencyUnit: json['currency_unit'] ?? 'đ',
    );
  }
}

class CountersModel {
  final int unreadNotifications;
  final int availableVouchers;

  CountersModel({required this.unreadNotifications, required this.availableVouchers});

  factory CountersModel.fromJson(Map<String, dynamic> json) {
    return CountersModel(
      unreadNotifications: json['unread_notifications'] ?? 0,
      availableVouchers: json['available_vouchers'] ?? 0,
    );
  }
}