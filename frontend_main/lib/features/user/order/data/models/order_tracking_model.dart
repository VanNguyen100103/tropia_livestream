/// Order Tracking Models
/// Handles real-time order tracking with shipper location, status, and delivery history
library;

class OrderTrackingModel {
  final String orderId;
  final String status; // order_placed, waiting_pickup, in_warehouse, in_transit, delivered
  final String? estimatedDelivery;
  final ShipperInfo? shipper;
  final List<TrackingHistoryItem> trackingHistory;

  OrderTrackingModel({
    required this.orderId,
    required this.status,
    this.estimatedDelivery,
    this.shipper,
    required this.trackingHistory,
  });

  /// Parse JSON response from /api/order-tracking
  factory OrderTrackingModel.fromJson(Map<String, dynamic> json) {
    final data = json['data'] ?? {};
    
    return OrderTrackingModel(
      orderId: data['order_id'] ?? '',
      status: data['status'] ?? 'order_placed',
      estimatedDelivery: data['estimated_delivery'],
      shipper: data['shipper'] != null 
          ? ShipperInfo.fromJson(data['shipper'])
          : null,
      trackingHistory: _parseTrackingHistory(data['tracking_history'] ?? []),
    );
  }

  /// Check if shipper is available (not waiting for driver)
  bool get hasShipperInfo => 
      shipper != null && 
      (shipper?.name ?? '').isNotEmpty &&
      shipper?.currentLocation != null;

  /// Check if order is in transit
  bool get isInTransit => status == 'in_transit' && hasShipperInfo;

  /// Check if order is delivered
  bool get isDelivered => status == 'delivered';

  /// Get current step from tracking history
  String get currentStep => 
      trackingHistory.firstWhere(
        (item) => !item.isCompleted,
        orElse: () => trackingHistory.last,
      ).step;

  static List<TrackingHistoryItem> _parseTrackingHistory(List<dynamic> items) {
    return items.map((item) {
      return TrackingHistoryItem.fromJson(item);
    }).toList();
  }
}

/// Shipper Information with Location
class ShipperInfo {
  final String name;
  final String phone;
  final Location? currentLocation;
  final String? avatar;

  ShipperInfo({
    required this.name,
    required this.phone,
    this.currentLocation,
    this.avatar,
  });

  factory ShipperInfo.fromJson(Map<String, dynamic> json) {
    return ShipperInfo(
      name: json['name'] ?? '',
      phone: json['phone'] ?? '',
      currentLocation: json['current_location'] != null
          ? Location.fromJson(json['current_location'])
          : null,
      avatar: json['avatar'],
    );
  }

  /// Check if shipper is waiting to be assigned
  bool get isWaiting => name.isEmpty && currentLocation == null;

  /// Check if phone is available for calling
  bool get hasPhone => phone.isNotEmpty;

  /// Format phone for display
  String get displayPhone {
    if (phone.isEmpty) return 'Chưa cập nhật';
    // Hide phone format: 090xxx xxxx -> 090* * *
    if (phone.length >= 10) {
      final visible = phone.substring(0, 3);
      return '$visible*** ****';
    }
    return phone;
  }
}

/// GPS Location with bearing
class Location {
  final double lat;
  final double lng;
  final double? bearing;

  Location({
    required this.lat,
    required this.lng,
    this.bearing,
  });

  factory Location.fromJson(Map<String, dynamic> json) {
    return Location(
      lat: _toDouble(json['lat']) ?? 0.0,
      lng: _toDouble(json['lng']) ?? 0.0,
      bearing: _toDouble(json['bearing']),
    );
  }

  /// Convert to LatLng string format for maps
  String get latLngString => '$lat,$lng';

  static double? _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}

/// Individual Tracking History Item
class TrackingHistoryItem {
  final String step; // order_placed, waiting_pickup, in_warehouse, in_transit, delivered
  final String title;
  final String? description;
  final Location? location;
  final DateTime time;
  final bool isCompleted;

  TrackingHistoryItem({
    required this.step,
    required this.title,
    this.description,
    this.location,
    required this.time,
    required this.isCompleted,
  });

  factory TrackingHistoryItem.fromJson(Map<String, dynamic> json) {
    return TrackingHistoryItem(
      step: json['step'] ?? '',
      title: json['title'] ?? '',
      description: json['description'],
      location: json['location'] != null
          ? Location.fromJson(json['location'])
          : null,
      time: _parseDateTime(json['time']),
      isCompleted: json['is_completed'] ?? false,
    );
  }

  /// Get icon for timeline based on completion status
  String get statusIcon {
    if (isCompleted) return '✓'; // Completed
    return '●'; // Pending/Current
  }

  /// Get icon color
  String get iconColor {
    if (isCompleted) return 'primary'; // Green
    return 'grey'; // Grey
  }

  /// Format time as "HH:mm - dd/MM"
  String get formattedTime {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')} - ${time.day.toString().padLeft(2, '0')}/${time.month.toString().padLeft(2, '0')}';
  }

  /// Check if this is a future estimated time
  bool get isEstimated {
    return !isCompleted && time.isAfter(DateTime.now());
  }

  static DateTime _parseDateTime(dynamic value) {
    if (value is String) {
      try {
        return DateTime.parse(value);
      } catch (e) {
        return DateTime.now();
      }
    }
    return DateTime.now();
  }
}
