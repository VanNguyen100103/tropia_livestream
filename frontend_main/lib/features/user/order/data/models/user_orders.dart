class UserOrder {
  final String id;
  final String? orderCode; // Có ở API danh sách
  final String? customerName;
  final String? phone;
  final String? address;
  final num? totalAmount; // Dùng num để an toàn cho cả int và double
  final String? status;
  final int? statusCode; // 1, 2, ...
  final String? paymentMethod;
  final String? storeName;
  final String? createdAt;
  final String? shippingMethod;
  final String? deliveryDate;
  final String? note;
  final List<OrderProduct>? products; // Chỉ có ở API chi tiết

  UserOrder({
    required this.id,
    this.orderCode,
    this.customerName,
    this.phone,
    this.address,
    this.totalAmount,
    this.status,
    this.statusCode,
    this.paymentMethod,
    this.storeName,
    this.createdAt,
    this.shippingMethod,
    this.deliveryDate,
    this.note,
    this.products,
  });

  // Factory nhận JSON từ API
  factory UserOrder.fromJson(Map<String, dynamic> json) {
    String? readString(List<String> keys) {
      for (final key in keys) {
        final value = json[key];
        if (value != null) return value.toString();
      }
      // Fallback: case-insensitive lookup
      for (final entry in json.entries) {
        final entryKey = entry.key.toString().toLowerCase();
        for (final key in keys) {
          if (entryKey == key.toLowerCase() && entry.value != null) {
            return entry.value.toString();
          }
        }
      }
      return null;
    }

    return UserOrder(
      id: json['id']?.toString() ?? '',
      orderCode: json['order_code']?.toString(),
      customerName: json['customer_name'],
      phone: json['phone'],
      address: json['address'],
      totalAmount: json['total_amount'] as num?,
      status: json['status'],
      statusCode: int.tryParse(json['status_code']?.toString() ?? '0'),
      paymentMethod: json['payment_method'],
      storeName: json['store_name'],
      createdAt: json['created_at'],
      shippingMethod: readString([
        'shipping_method',
        'shippingMethod',
        'delivery_method',
        'deliveryMethod',
        'receive_method',
        'receiveMethod',
      ]),
      deliveryDate: json['delivery_date'],
      note: json['note'],
      // Xử lý list products nếu có (Dành cho API Detail)
      products: json['products'] != null
          ? (json['products'] as List)
                .map((item) => OrderProduct.fromJson(item))
                .toList()
          : null,
    );
  }

  // Chuyển ngược lại JSON (nếu cần dùng sau này)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'order_code': orderCode,
      'customer_name': customerName,
      'phone': phone,
      'address': address,
      'total_amount': totalAmount,
      'status': status,
      'status_code': statusCode,
      'payment_method': paymentMethod,
      'store_name': storeName,
      'created_at': createdAt,
      'shipping_method': shippingMethod,
      'delivery_date': deliveryDate,
      'note': note,
      'products': products?.map((e) => e.toJson()).toList(),
    };
  }
}

// Class con mô tả từng sản phẩm trong đơn hàng (Dành cho API Detail)
class OrderProduct {
  final String id;
  final String? name;
  final int? quantity;
  final num? price;
  final num? total;
  final String? image;

  OrderProduct({
    required this.id,
    this.name,
    this.quantity,
    this.price,
    this.total,
    this.image,
  });

  factory OrderProduct.fromJson(Map<String, dynamic> json) {
    return OrderProduct(
      id: json['id']?.toString() ?? '',
      name: json['name'],
      quantity: int.tryParse(json['quantity']?.toString() ?? '0'),
      price: json['price'] as num?,
      total: json['total'] as num?,
      image: json['image'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'quantity': quantity,
      'price': price,
      'total': total,
      'image': image,
    };
  }
}
