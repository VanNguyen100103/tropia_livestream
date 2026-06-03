import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tropia_mobile_app_android/core/network/dio_client.dart';
import 'package:tropia_mobile_app_android/core/utils/dashboard_controller.dart';
import 'package:tropia_mobile_app_android/features/user/dashboard/presentation/dashboard_page.dart';
import 'package:tropia_mobile_app_android/features/user/home/domain/repositories/home_repository_impl.dart';
import 'package:tropia_mobile_app_android/features/user/home/presentation/widgets/product_card.dart';
import 'package:tropia_mobile_app_android/features/user/cart/presentation/cart_badge_controller.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../data/models/product_model.dart';
import '../../data/models/category_model.dart';
import '../../domain/entities/category.dart';
import '../../data/datasources/home_remote_datasource.dart';
import '../../domain/repositories/home_repository.dart';

// --- ENUM QUẢN LÝ SẮP XẾP ---
enum SortOption { relevant, newest, priceAsc, priceDesc }

class _LeafCategory {
  final String id;
  final String name;
  final String? imageUrl;

  const _LeafCategory({required this.id, required this.name, this.imageUrl});
}

class SearchPage extends StatefulWidget {
  final String? initialKeyword;
  final String? initialCategoryId;
  final String? initialCategoryName;

  const SearchPage({
    super.key,
    this.initialKeyword,
    this.initialCategoryId,
    this.initialCategoryName,
  });

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
    int? _totalProductCount;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  late final HomeRepository _homeRepository;

  List<String> _searchHistory = [];
  List<ProductModel>? _searchResults;
  bool _isLoading = false;
  bool _isLoadingMore = false;

  static const int _pageSize = 10;
  int _currentPage = 1;
  bool _hasMore = false;

  String? _activeKeyword;
  String? _activeCategoryId;

  // Filter State
  String? _selectedCategoryId;
  String? _selectedCategoryName;
  String? _lastKeyword;

  // Sort State
  SortOption _currentSort = SortOption.relevant;

  late Future<List<CategoryModel>> _categoriesFuture;

  // --- HELPER FUNCTIONS ---
  void _setSearchText(String text) {
    _searchController
      ..text = text
      ..selection = TextSelection.collapsed(offset: text.length);
  }

  String? _pickCategoryImageUrl(CategoryEntity node) {
    final icon = node.icon.trim();
    if (icon.isNotEmpty && icon != '0') return icon;
    final image = node.image.trim();
    if (image.isNotEmpty && image != '0') return image;
    return null;
  }

  CategoryEntity? _findParentCategory(
    List<CategoryModel> roots,
    String targetId,
  ) {
    CategoryEntity? visit(CategoryEntity node) {
      for (final child in node.children) {
        if (child.id == targetId) return node;
        final found = visit(child);
        if (found != null) return found;
      }
      return null;
    }

    for (final root in roots) {
      if (root.id == targetId) {
        return null;
      }
      final found = visit(root);
      if (found != null) return found;
    }
    return null;
  }

  List<_LeafCategory> _extractLeafCategories(List<CategoryModel> roots) {
    final Map<String, _LeafCategory> leavesById = {};

    void visit(CategoryEntity node) {
      final children = node.children;
      if (children.isEmpty) {
        final name = node.name;
        leavesById[node.id] = _LeafCategory(
          id: node.id,
          name: name,
          imageUrl: _pickCategoryImageUrl(node),
        );
        return;
      }
      for (final child in children) {
        visit(child);
      }
    }

    for (final root in roots) {
      visit(root);
    }

    return leavesById.values.toList();
  }

  Widget _buildCategoryAvatar(String? imageUrl, {double radius = 12}) {
    if (imageUrl != null && imageUrl.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: Colors.grey[100],
        backgroundImage: NetworkImage(imageUrl),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: Colors.grey[200],
      child: Icon(Icons.category, size: radius + 2, color: Colors.black54),
    );
  }

  Widget _buildSuggestedCategoryItem(_LeafCategory category) {
    return InkWell(
      onTap: () {
        final previousKeyword = _searchController.text.trim();
        if (previousKeyword.isNotEmpty) {
          _lastKeyword = previousKeyword;
        }
        setState(() {
          _selectedCategoryId = category.id;
          _selectedCategoryName = category.name;
        });
        _setSearchText(category.name);
        _performSearch(categoryId: category.id);
      },
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 84,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildCategoryAvatar(category.imageUrl, radius: 28),
            const SizedBox(height: 8),
            Text(
              category.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                height: 1.15,
                color: Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- LIFECYCLE ---
  @override
  void initState() {
    super.initState();
    final dio = DioClient().dio;
    final dataSource = HomeRemoteDataSourceImpl(client: dio);
    _homeRepository = HomeRepositoryImpl(remoteDataSource: dataSource);

    _categoriesFuture = _homeRepository.getCategories();
    _loadHistory();

    _scrollController.addListener(_onScroll);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.initialCategoryId != null &&
          widget.initialCategoryId!.isNotEmpty) {
        _selectedCategoryId = widget.initialCategoryId;
        _selectedCategoryName = widget.initialCategoryName;
        if (widget.initialCategoryName != null) {
          _searchController.text = widget.initialCategoryName!;
        }
        _performSearch(categoryId: widget.initialCategoryId);
      } else if (widget.initialKeyword != null &&
          widget.initialKeyword!.isNotEmpty) {
        _searchController.text = widget.initialKeyword!;
        _lastKeyword = widget.initialKeyword!;
        _performSearch(keyword: widget.initialKeyword!);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_isLoading || _isLoadingMore || !_hasMore) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  // --- HISTORY LOGIC ---
  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(
        () => _searchHistory = prefs.getStringList('search_history') ?? [],
      );
    }
  }

  Future<void> _saveHistory(String keyword) async {
    if (keyword.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    _searchHistory.remove(keyword);
    _searchHistory.insert(0, keyword);
    if (_searchHistory.length > 10) {
      _searchHistory = _searchHistory.sublist(0, 10);
    }
    await prefs.setStringList('search_history', _searchHistory);
    if (mounted) setState(() {});
  }

  Future<void> _clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('search_history');
    if (mounted) setState(() => _searchHistory = []);
  }

  // --- SEARCH LOGIC ---
  void _clearSearchInput() {
    _searchController.clear();
    setState(() {
      _searchResults = null;
      _selectedCategoryId = null;
      _selectedCategoryName = null;
      _activeKeyword = null;
      _activeCategoryId = null;
      _lastKeyword = null;
      _currentPage = 1;
      _hasMore = false;
      _isLoading = false;
      _isLoadingMore = false;
    });
  }

  void _clearCategoryFilter() {
    setState(() {
      _selectedCategoryId = null;
      _selectedCategoryName = null;
    });

    final keyword = (_lastKeyword ?? '').trim();
    if (keyword.isNotEmpty) {
      _setSearchText(keyword);
      _performSearch(keyword: keyword);
      return;
    }

    _searchController.clear();
    setState(() => _searchResults = null);
  }

  Future<void> _performSearch({String? keyword, String? categoryId}) async {
    final kw = keyword?.trim();
    if ((kw == null || kw.isEmpty) &&
        (categoryId == null || categoryId.isEmpty)) {
      return;
    }

    _searchFocusNode.unfocus();

    if (kw != null && kw.isNotEmpty) {
      _lastKeyword = kw;
      _saveHistory(kw);
    }

    if (categoryId != null && categoryId.isNotEmpty) {
      _selectedCategoryId = categoryId;
    }

    setState(() {
      _isLoading = true;
      _isLoadingMore = false;
      _currentPage = 1;
      _hasMore = false;
      _searchResults = null;

      if (categoryId != null && categoryId.isNotEmpty) {
        _activeCategoryId = categoryId;
        _activeKeyword = null;
      } else {
        _activeCategoryId = null;
        _activeKeyword = kw;
      }
    });

    try {
      // Gọi API, lấy cả response
      final resultsResponse = await _homeRepository.searchProductsWithMeta(
        keyword: kw,
        categoryId: categoryId,
        page: 1,
        limit: _pageSize,
      );
      final results = resultsResponse.products;
      final total = resultsResponse.total;
      if (mounted && (categoryId == null || categoryId.isEmpty)) {
        setState(() {
          _selectedCategoryId = null;
          _selectedCategoryName = null;
        });
      }

      // TODO: sau nay se them tham so sort tu backend, neu backend da co san thi chi can truyen vao day ma khong can sort lai o client
      // Hiện tại giả lập sort client-side nếu API chưa hỗ trợ
      if (_currentSort == SortOption.priceAsc) {
        results.sort((a, b) => a.salePrice.compareTo(b.salePrice));
      } else if (_currentSort == SortOption.priceDesc) {
        results.sort((a, b) => b.salePrice.compareTo(a.salePrice));
      }

      if (mounted) {
        setState(() {
          _searchResults = results;
          _totalProductCount = total;
          _currentSort = _currentSort;
          _currentPage = 1;
          _hasMore = results.length >= _pageSize;
        });

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(0);
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _searchResults = []);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_isLoading || _isLoadingMore || !_hasMore) return;
    if (_searchResults == null) return;

    final nextPage = _currentPage + 1;

    String? keyword;
    String? categoryId;
    if (_activeCategoryId != null && _activeCategoryId!.isNotEmpty) {
      categoryId = _activeCategoryId;
    } else if (_activeKeyword != null && _activeKeyword!.trim().isNotEmpty) {
      keyword = _activeKeyword;
    } else {
      return;
    }

    setState(() => _isLoadingMore = true);

    try {
      final more = await _homeRepository.searchProducts(
        keyword: keyword,
        categoryId: categoryId,
        page: nextPage,
        limit: _pageSize,
      );

      if (!mounted) return;

      if (more.isEmpty) {
        setState(() {
          _hasMore = false;
          _isLoadingMore = false;
        });
        return;
      }

      final existingIds = _searchResults!.map((e) => e.id).toSet();
      final newOnes = more.where((p) => !existingIds.contains(p.id)).toList();

      setState(() {
        if (newOnes.isEmpty) {
          // Tránh vòng lặp load vô hạn nếu backend trả lại items trùng.
          _hasMore = false;
        } else {
          _searchResults = [..._searchResults!, ...newOnes];

          if (_currentSort == SortOption.priceAsc) {
            _searchResults!.sort((a, b) => a.salePrice.compareTo(b.salePrice));
          } else if (_currentSort == SortOption.priceDesc) {
            _searchResults!.sort((a, b) => b.salePrice.compareTo(a.salePrice));
          }

          _currentPage = nextPage;
          _hasMore = more.length >= _pageSize;
        }

        _isLoadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
    }
  }

  void _handleSort(SortOption option) {
    setState(() {
      if (option == SortOption.priceAsc || option == SortOption.priceDesc) {
        // Toggle giá
        if (_currentSort == SortOption.priceAsc) {
          _currentSort = SortOption.priceDesc;
        } else {
          _currentSort = SortOption.priceAsc;
        }
      } else {
        _currentSort = option;
      }
    });

    // Trigger lại search/sort với list hiện tại
    if (_searchResults != null && _searchResults!.isNotEmpty) {
      List<ProductModel> sorted = List.from(_searchResults!);
      if (_currentSort == SortOption.priceAsc) {
        sorted.sort((a, b) => a.salePrice.compareTo(b.salePrice));
      } else if (_currentSort == SortOption.priceDesc) {
        sorted.sort((a, b) => b.salePrice.compareTo(a.salePrice));
      }
      // Đối với 'relevant' và 'newest', bạn cần gọi API
      setState(() => _searchResults = sorted);
    }
  }

  // --- UI BUILDING ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5), // Nền xám nhẹ làm nổi bật thẻ
      appBar: _buildSearchAppBar(),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_searchResults == null) return _buildOriginalDesignView();
    if (_searchResults!.isEmpty) return _buildEmptyState();
    return _buildResultList();
  }

  // Giao diện khi chưa search (Giữ nguyên logic gợi ý & lịch sử)
  Widget _buildOriginalDesignView() {
    return Container(
      color: Colors.white,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FutureBuilder<List<CategoryModel>>(
              future: _categoriesFuture,
              builder: (context, snapshot) {
                final keyword = _searchController.text.trim().toLowerCase();
                if (keyword.isEmpty) return const SizedBox.shrink();
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const SizedBox.shrink();
                }

                final leafCategories = _extractLeafCategories(snapshot.data!);
                final matches = leafCategories
                    .where((c) => c.name.toLowerCase().contains(keyword))
                    .take(10)
                    .toList();
                if (matches.isEmpty) return const SizedBox.shrink();

                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Gợi ý danh mục',
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: matches
                            .map(_buildSuggestedCategoryItem)
                            .toList(),
                      ),
                      const SizedBox(height: 8),
                      const Divider(
                        height: 1,
                        thickness: 5,
                        color: Color(0xFFF5F5F5),
                      ),
                    ],
                  ),
                );
              },
            ),
            if (_searchHistory.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Lịch sử tìm kiếm",
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                    GestureDetector(
                      onTap: _clearHistory,
                      child: const Text(
                        "Xóa",
                        style: TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _searchHistory.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, indent: 16),
                itemBuilder: (context, index) {
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    leading: const Icon(
                      Icons.history,
                      color: Colors.grey,
                      size: 20,
                    ),
                    title: Text(
                      _searchHistory[index],
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 15,
                      ),
                    ),
                    trailing: const Icon(
                      Icons.north_west,
                      size: 16,
                      color: Colors.grey,
                    ),
                    onTap: () {
                      _searchController.text = _searchHistory[index];
                      _performSearch(keyword: _searchHistory[index]);
                    },
                  );
                },
              ),
              const Divider(height: 1, thickness: 5, color: Color(0xFFF5F5F5)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      color: Colors.white,
      width: double.infinity,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            "Không tìm thấy sản phẩm nào cho\n\"${_searchController.text}\"",
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey, fontSize: 16),
          ),
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: () {
              _searchController.clear();
              setState(() => _searchResults = null);
            },
            child: const Text("Tìm từ khóa khác"),
          ),
        ],
      ),
    );
  }

  // --- NEW: KẾT QUẢ TÌM KIẾM CHUYÊN NGHIỆP ---
  Widget _buildResultList() {
    final double itemWidth = (MediaQuery.of(context).size.width - 34) / 2;
    const double desiredHeight = 300;
    final double childAspectRatio = itemWidth / desiredHeight;

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        // 1. Header cố định: Sort Bar + Filter Categories
        SliverToBoxAdapter(
          child: Container(
            color: Colors.white,
            margin: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSortBar(),
                const Divider(height: 1, color: Color(0xFFEEEEEE)),
                _buildHorizontalCategoryFilter(),
              ],
            ),
          ),
        ),

        // 2. Số lượng kết quả
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                const Icon(
                  Icons.check_circle_outline,
                  size: 14,
                  color: Colors.grey,
                ),
                const SizedBox(width: 4),
                Text(
                  'Tìm thấy ${_totalProductCount ?? _searchResults!.length} sản phẩm',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ),
          ),
        ),

        // 3. Grid sản phẩm
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: childAspectRatio,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => ProductCard(
                product: _searchResults![index],
                isFlashSale: false,
              ),
              childCount: _searchResults!.length,
            ),
          ),
        ),

        // Bottom padding
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: _isLoadingMore
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: CircularProgressIndicator(),
                    ),
                  )
                : (!_hasMore
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'Đã tải hết sản phẩm',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                            ),
                          ),
                        )
                      : const SizedBox.shrink()),
          ),
        ),
      ],
    );
  }

  // Widget Thanh Sắp Xếp (Sort Bar)
  Widget _buildSortBar() {
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          _buildSortItem("Liên quan", SortOption.relevant),
          _buildVerticalDivider(),
          _buildSortItem("Mới nhất", SortOption.newest),
          _buildVerticalDivider(),
          _buildSortItem("Giá", SortOption.priceAsc, hasIcon: true),
        ],
      ),
    );
  }

  Widget _buildVerticalDivider() {
    return Container(width: 1, height: 16, color: Colors.grey[300]);
  }

  Widget _buildSortItem(
    String label,
    SortOption option, {
    bool hasIcon = false,
  }) {
    // Logic xác định trạng thái active
    bool isSelected = _currentSort == option;
    if (hasIcon) {
      isSelected =
          _currentSort == SortOption.priceAsc ||
          _currentSort == SortOption.priceDesc;
    }

    return Expanded(
      child: InkWell(
        onTap: () => _handleSort(hasIcon ? SortOption.priceAsc : option),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected ? AppColors.primary : Colors.black87,
              ),
            ),
            if (hasIcon) ...[
              const SizedBox(width: 4),
              Icon(
                _currentSort == SortOption.priceDesc
                    ? Icons.arrow_downward
                    : Icons.arrow_upward,
                size: 14,
                color: isSelected ? AppColors.primary : Colors.grey,
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Widget Danh sách Filter Ngang
  Widget _buildHorizontalCategoryFilter() {
    return FutureBuilder<List<CategoryModel>>(
      future: _categoriesFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }

        final roots = snapshot.data!;
        final leafCategories = _extractLeafCategories(roots);

        // Nếu đã chọn danh mục: hiển thị danh mục đồng cấp (cùng cha)
        if (_selectedCategoryId != null && _selectedCategoryId!.isNotEmpty) {
          final parent = _findParentCategory(roots, _selectedCategoryId!);
          if (parent != null && parent.children.isNotEmpty) {
            final siblings = parent.children
                .map(
                  (e) => _LeafCategory(
                    id: e.id,
                    name: e.name,
                    imageUrl: _pickCategoryImageUrl(e),
                  ),
                )
                .toList();

            // Đảm bảo item đang chọn luôn hiển thị
            final isExist = siblings.any((e) => e.id == _selectedCategoryId);
            if (!isExist) {
              siblings.insert(
                0,
                _LeafCategory(
                  id: _selectedCategoryId!,
                  name: _selectedCategoryName ?? 'Đã chọn',
                ),
              );
            }

            return Container(
              height: 50,
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                scrollDirection: Axis.horizontal,
                itemCount: siblings.length + 1, // +1 cho nút "Tất cả"
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _buildFilterChip(
                      label: "Tất cả",
                      isSelected: _selectedCategoryId == null,
                      onTap: _clearCategoryFilter,
                    );
                  }
                  final category = siblings[index - 1];
                  return _buildFilterChip(
                    label: category.name,
                    imageUrl: category.imageUrl,
                    isSelected: _selectedCategoryId == category.id,
                    onTap: () {
                      final previousKeyword = _searchController.text.trim();
                      if (previousKeyword.isNotEmpty &&
                          previousKeyword != category.name) {
                        _lastKeyword = previousKeyword;
                      }
                      setState(() {
                        _selectedCategoryId = category.id;
                        _selectedCategoryName = category.name;
                      });
                      _setSearchText(category.name);
                      _performSearch(categoryId: category.id);
                    },
                  );
                },
              ),
            );
          }
        }

        final keyword = _searchController.text.trim().toLowerCase().isNotEmpty
            ? _searchController.text.trim().toLowerCase()
            : (_lastKeyword ?? '').trim().toLowerCase();

        // Lấy danh sách gợi ý + danh mục đang chọn (nếu có)
        var suggestions = (keyword.isEmpty)
            ? leafCategories.take(15).toList()
            : leafCategories
                  .where((c) => c.name.toLowerCase().contains(keyword))
                  .take(15)
                  .toList();

        // Đảm bảo item đang chọn luôn hiển thị
        if (_selectedCategoryId != null) {
          final isExist = suggestions.any((e) => e.id == _selectedCategoryId);
          if (!isExist) {
            // Tạo một dummy object để hiển thị nếu nó không nằm trong list gợi ý
            suggestions.insert(
              0,
              _LeafCategory(
                id: _selectedCategoryId!,
                name: _selectedCategoryName ?? 'Đã chọn',
              ),
            );
          }
        }

        return Container(
          height: 50,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            scrollDirection: Axis.horizontal,
            itemCount: suggestions.length + 1, // +1 cho nút "Tất cả"
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              if (index == 0) {
                return _buildFilterChip(
                  label: "Tất cả",
                  isSelected: _selectedCategoryId == null,
                  onTap: _clearCategoryFilter,
                );
              }
              final category = suggestions[index - 1];
              return _buildFilterChip(
                label: category.name,
                imageUrl: category.imageUrl,
                isSelected: _selectedCategoryId == category.id,
                onTap: () {
                  final previousKeyword = _searchController.text.trim();
                  if (previousKeyword.isNotEmpty &&
                      previousKeyword != category.name) {
                    _lastKeyword = previousKeyword;
                  }
                  setState(() {
                    _selectedCategoryId = category.id;
                    _selectedCategoryName = category.name;
                  });
                  _setSearchText(category.name);
                  _performSearch(categoryId: category.id);
                },
              );
            },
          ),
        );
      },
    );
  }

  // Widget Chip Custom (Pill shape)
  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    String? imageUrl,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.08)
              : Colors.white,
          borderRadius: BorderRadius.circular(4), // Bo góc nhẹ giống Shopee
          border: Border.all(
            color: isSelected ? AppColors.primary : Colors.grey[300]!,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (imageUrl != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: Image.network(
                  imageUrl,
                  width: 16,
                  height: 16,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                color: isSelected ? AppColors.primary : Colors.black87,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildSearchAppBar() {
    return AppBar(
      backgroundColor: AppColors.primary,
      elevation: 0,
      leading: const BackButton(color: Colors.white),
      titleSpacing: 0,
      title: Hero(
        tag: 'search_bar_tag',
        child: Material(
          type: MaterialType.transparency,
          child: Container(
            height: 42,
            margin: const EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F3F3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              textInputAction: TextInputAction.search,
              onSubmitted: (value) => _performSearch(keyword: value),
              textAlignVertical: TextAlignVertical.center,
              style: const TextStyle(fontSize: 14, color: Colors.black87),
              decoration: InputDecoration(
                hintText: "Bạn muốn mua gì?",
                hintStyle: const TextStyle(color: Colors.grey, fontSize: 14),
                prefixIcon: const Icon(
                  Icons.search,
                  color: Colors.black,
                  size: 18,
                ),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(
                          Icons.cancel,
                          color: Colors.grey,
                          size: 16,
                        ),
                        onPressed: () {
                          _clearSearchInput();
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                isDense: true,
                fillColor: Colors.transparent,
                filled: true,
              ),
              onChanged: (val) {
                setState(() {
                  if (val.isEmpty) {
                    _searchResults = null;
                    _selectedCategoryId = null;
                    _selectedCategoryName = null;
                    _activeKeyword = null;
                    _activeCategoryId = null;
                    _currentPage = 1;
                    _hasMore = false;
                    _isLoadingMore = false;
                  }
                });
              },
            ),
          ),
        ),
      ),
      actions: [
        ValueListenableBuilder<int>(
          valueListenable: CartBadgeController.instance.count,
          builder: (context, count, _) {
            return Stack(
              clipBehavior: Clip.none,
              children: [
                IconButton(
                  onPressed: () {
                    Navigator.of(context).popUntil((route) => route.isFirst);
                    DashboardController.switchTab(DashboardPage.tabCart);
                  },
                  icon: const Icon(Icons.shopping_cart_outlined, color: Colors.white),
                ),
                if (count > 0)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                      child: Center(
                        child: Text(
                          count > 99 ? '99+' : '$count',
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
