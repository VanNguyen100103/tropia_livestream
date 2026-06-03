import 'package:flutter/material.dart';

enum SearchTargetType { level1, level2, level3 }

class CategorySearchItem {
  final String id;
  final String name;
  final SearchTargetType type;
  final GlobalKey? anchorKey;
  final int level1Index;

  const CategorySearchItem({
    required this.id,
    required this.name,
    required this.type,
    this.anchorKey,
    required this.level1Index,
  });
}

class CategorySearchDelegate extends SearchDelegate<CategorySearchItem?> {
  final List<CategorySearchItem> index;

  CategorySearchDelegate(this.index);

  @override
  String get searchFieldLabel => 'Tìm danh mục...';

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(onPressed: () => query = '', icon: const Icon(Icons.clear)),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      onPressed: () => close(context, null),
      icon: const Icon(Icons.arrow_back),
    );
  }

  String _typeLabel(SearchTargetType t) {
    switch (t) {
      case SearchTargetType.level1:
        return 'Tầng 1';
      case SearchTargetType.level2:
        return 'Tầng 2';
      case SearchTargetType.level3:
        return 'Tầng 3';
    }
  }

  List<CategorySearchItem> _filter() {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return index.take(30).toList();

    final results = index
        .where((e) => e.name.toLowerCase().contains(q))
        .take(60)
        .toList();

    // Ưu tiên match bắt đầu từ đầu chuỗi
    results.sort((a, b) {
      final aq = a.name.toLowerCase();
      final bq = b.name.toLowerCase();
      final ap = aq.startsWith(q) ? 0 : 1;
      final bp = bq.startsWith(q) ? 0 : 1;
      if (ap != bp) return ap - bp;
      return aq.compareTo(bq);
    });

    return results;
  }

  @override
  Widget buildResults(BuildContext context) {
    final results = _filter();
    return ListView.separated(
      itemCount: results.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = results[index];
        return ListTile(
          title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(_typeLabel(item.type)),
          onTap: () => close(context, item),
        );
      },
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return buildResults(context);
  }
}
