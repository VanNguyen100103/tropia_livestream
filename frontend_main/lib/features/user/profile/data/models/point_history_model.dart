class PointHistoryModel {
  final List<TransactionItem> items;
  final Pagination pagination;

  const PointHistoryModel({
    required this.items,
    required this.pagination,
  });

  factory PointHistoryModel.fromJson(Map<String, dynamic> json) {
    final itemsJson = (json['items'] as List?) ?? [];
    final paginationJson = (json['pagination'] as Map<String, dynamic>?) ?? {};

    return PointHistoryModel(
      items: itemsJson
          .map((e) => TransactionItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      pagination: Pagination.fromJson(paginationJson),
    );
  }
}

class TransactionItem {
  final int id;
  final String? orderId;
  final String type;
  final int points;
  final int? basePoints;
  final int? multiplier;
  final String? rank;
  final String? reason;
  final String createdAt;

  const TransactionItem({
    required this.id,
    required this.type,
    required this.points,
    required this.createdAt,
    this.orderId,
    this.basePoints,
    this.multiplier,
    this.rank,
    this.reason,
  });

  factory TransactionItem.fromJson(Map<String, dynamic> json) {
    return TransactionItem(
      id: _toInt(json['id']) ?? 0,
      orderId: json['order_id']?.toString(),
      type: json['type']?.toString() ?? '',
      points: _toInt(json['points']) ?? 0,
      basePoints: _toInt(json['base_points']),
      multiplier: _toInt(json['multiplier']),
      rank: json['rank']?.toString(),
      reason: json['reason']?.toString(),
      createdAt: json['created_at']?.toString() ?? '',
    );
  }

  static int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }
}

class Pagination {
  final int total;
  final int page;
  final int limit;
  final int totalPages;

  const Pagination({
    required this.total,
    required this.page,
    required this.limit,
    required this.totalPages,
  });

  factory Pagination.fromJson(Map<String, dynamic> json) {
    return Pagination(
      total: _toInt(json['total']) ?? 0,
      page: _toInt(json['page']) ?? 1,
      limit: _toInt(json['limit']) ?? 10,
      totalPages: _toInt(json['total_pages']) ?? 1,
    );
  }

  static int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }
}
