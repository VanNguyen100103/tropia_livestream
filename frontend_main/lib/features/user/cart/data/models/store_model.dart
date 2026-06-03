class StoreModel {
  final int storeId;
  final String storeName;
  final String storeAddress;

  StoreModel({
    required this.storeId,
    required this.storeName,
    required this.storeAddress,
  });

  factory StoreModel.fromJson(Map<String, dynamic> json) {
    return StoreModel(
      storeId: json['store_id'] ?? 0,
      storeName: json['store_name'] ?? '',
      storeAddress: json['store_address'] ?? '',
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is StoreModel && other.storeId == storeId;
  }

  @override
  int get hashCode => storeId.hashCode;
}