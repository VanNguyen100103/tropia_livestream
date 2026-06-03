import 'package:flutter/material.dart';
import 'dart:async';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:tropia_mobile_app_android/core/network/dio_client.dart';
import 'package:tropia_mobile_app_android/features/user/home/data/datasources/home_remote_datasource.dart';
import 'package:tropia_mobile_app_android/features/user/home/data/models/category_model.dart';
import 'package:tropia_mobile_app_android/features/user/home/domain/entities/category.dart';
import 'package:tropia_mobile_app_android/features/user/home/presentation/pages/search_page.dart';

import 'widgets/category_left_sidebar.dart';
import 'widgets/category_right_panel.dart';

class CategoryMenuPage extends StatefulWidget {
  const CategoryMenuPage({super.key});

  static Route<void> route() {
    return PageRouteBuilder<void>(
      settings: const RouteSettings(name: '/category-menu'),
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (context, animation, secondaryAnimation) {
        return const CategoryMenuPage();
      },
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curve = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );

        return FadeTransition(
          opacity: curve,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(-1.0, 0),
              end: Offset.zero,
            ).animate(curve),
            child: child,
          ),
        );
      },
    );
  }

  @override
  State<CategoryMenuPage> createState() => _CategoryMenuPageState();
}

class _CategoryMenuPageState extends State<CategoryMenuPage> {
  late final Future<List<CategoryModel>> _categoriesFuture;

  final ItemScrollController _leftItemScrollController = ItemScrollController();
  final ItemScrollController _rightItemScrollController =
      ItemScrollController();

  final ItemPositionsListener _rightItemPositionsListener =
      ItemPositionsListener.create();

  final ItemPositionsListener _leftItemPositionsListener =
      ItemPositionsListener.create();

  Timer? _leftScrollThrottle;
  late final VoidCallback _leftPositionsListener;

  Timer? _rightSyncThrottle;
  late final VoidCallback _rightPositionsListener;

  bool _suppressLeftToRightSync = false;
  Timer? _suppressLeftToRightTimer;

  int _activeLevel1Index = 0;
  bool _syncEnabled = false;
  bool _programmaticScrollInFlight = false;

  bool _hasValidMedia(String? value) {
    if (value == null) return false;
    final v = value.trim();
    return v.isNotEmpty && v != '0';
  }

  String? _pickImageUrl(CategoryEntity node) {
    if (_hasValidMedia(node.image)) return node.image;
    if (_hasValidMedia(node.icon)) return node.icon;
    return null;
  }

  Widget _buildAvatar(CategoryEntity node, {double size = 44}) {
    final url = _pickImageUrl(node);
    final radius = size / 2;

    if (url != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.network(
          url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(radius),
              ),
              child: Icon(
                Icons.category,
                size: size * 0.5,
                color: Colors.black54,
              ),
            );
          },
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(Icons.category, size: size * 0.5, color: Colors.black54),
    );
  }

  void _openSearch(CategoryEntity category) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SearchPage(
          initialCategoryId: category.id,
          initialCategoryName: category.name,
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    final dio = DioClient().dio;
    final dataSource = HomeRemoteDataSourceImpl(client: dio);
    _categoriesFuture = dataSource.getCategories();

    _leftPositionsListener = _handleLeftPositionsChanged;
    _leftItemPositionsListener.itemPositions.addListener(
      _leftPositionsListener,
    );

    _rightPositionsListener = _handleRightPositionsChanged;
    _rightItemPositionsListener.itemPositions.addListener(
      _rightPositionsListener,
    );
  }

  @override
  void dispose() {
    _leftScrollThrottle?.cancel();
    _leftItemPositionsListener.itemPositions.removeListener(
      _leftPositionsListener,
    );

    _rightSyncThrottle?.cancel();
    _rightItemPositionsListener.itemPositions.removeListener(
      _rightPositionsListener,
    );

    _suppressLeftToRightTimer?.cancel();
    super.dispose();
  }

  void _ensureLeftSidebarVisible(
    int index, {
    bool suppressLeftToRight = false,
  }) {
    if (!_leftItemScrollController.isAttached) return;

    if (suppressLeftToRight) {
      _suppressLeftToRightSync = true;
      _suppressLeftToRightTimer?.cancel();
      _suppressLeftToRightTimer = Timer(
        const Duration(milliseconds: 350),
        () => _suppressLeftToRightSync = false,
      );
    }

    _leftItemScrollController.scrollTo(
      index: index,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: 0.15,
    );
  }

  int? _centerVisibleIndex(Iterable<ItemPosition> positions) {
    final visible = positions
        .where((p) => p.itemTrailingEdge > 0 && p.itemLeadingEdge < 1)
        .toList();
    if (visible.isEmpty) return null;

    // Pick the item whose center is closest to viewport center (0.5).
    visible.sort((a, b) {
      final ac = (a.itemLeadingEdge + a.itemTrailingEdge) / 2;
      final bc = (b.itemLeadingEdge + b.itemTrailingEdge) / 2;
      return (ac - 0.5).abs().compareTo((bc - 0.5).abs());
    });
    return visible.first.index;
  }

  void _handleLeftPositionsChanged() {
    if (!mounted) return;
    if (_programmaticScrollInFlight) return;
    if (_suppressLeftToRightSync) return;
    if (!_syncEnabled) return;

    _leftScrollThrottle?.cancel();
    _leftScrollThrottle = Timer(const Duration(milliseconds: 70), () {
      if (!mounted) return;
      if (_programmaticScrollInFlight) return;

      final active = _centerVisibleIndex(
        _leftItemPositionsListener.itemPositions.value,
      );
      if (active == null) return;
      if (active == _activeLevel1Index) return;

      // Schedule to end of frame to avoid mutating during sliver layout.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_programmaticScrollInFlight) return;
        if (_suppressLeftToRightSync) return;

        setState(() => _activeLevel1Index = active);
        if (_rightItemScrollController.isAttached) {
          _rightItemScrollController.jumpTo(index: active, alignment: 0.0);
        }
      });
    });
  }

  void _handleRightPositionsChanged() {
    if (!mounted) return;
    if (_programmaticScrollInFlight) return;
    if (!_syncEnabled) return;

    _rightSyncThrottle?.cancel();
    _rightSyncThrottle = Timer(const Duration(milliseconds: 70), () {
      if (!mounted) return;
      if (_programmaticScrollInFlight) return;

      final active = _centerVisibleIndex(
        _rightItemPositionsListener.itemPositions.value,
      );
      if (active == null) return;
      if (active == _activeLevel1Index) return;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_programmaticScrollInFlight) return;

        setState(() => _activeLevel1Index = active);

        // Keep the left selected item visible without triggering left->right sync.
        _ensureLeftSidebarVisible(active, suppressLeftToRight: true);
      });
    });
  }

  Future<void> _scrollToLevel1Index(int index) async {
    if (index < 0) return;

    // Tap is an explicit interaction; enable syncing.
    _syncEnabled = true;

    _programmaticScrollInFlight = true;
    if (mounted) setState(() => _activeLevel1Index = index);

    // Keep left highlight visible.
    _ensureLeftSidebarVisible(index);

    if (_rightItemScrollController.isAttached) {
      await _rightItemScrollController.scrollTo(
        index: index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        alignment: 0.0,
      );
    }

    _programmaticScrollInFlight = false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: Builder(
          builder: (context) {
            const titleStyle = TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.w700,
              fontSize: 18,
            );

            return Text.rich(
              TextSpan(
                children: [
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Image.asset(
                        'assets/images/logo.png',
                        height: 20,
                        fit: BoxFit.contain,
                        semanticLabel: 'Tropia',
                        errorBuilder: (context, error, stackTrace) {
                          return Text('Tropia', style: titleStyle);
                        },
                      ),
                    ),
                  ),
                  const TextSpan(text: 'Danh mục'),
                ],
              ),
              style: titleStyle,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            );
          },
        ),
        actions: const [],
      ),
      body: FutureBuilder<List<CategoryModel>>(
        future: _categoriesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Lỗi: ${snapshot.error}'));
          }
          final categories = snapshot.data ?? const <CategoryModel>[];
          if (categories.isEmpty) {
            return const Center(child: Text('Không có danh mục'));
          }

          if (_activeLevel1Index >= categories.length) {
            _activeLevel1Index = 0;
          }

          return Row(
            children: [
              // Sử dụng Sidebar mới tách
              CategoryLeftSidebar(
                categories: categories,
                selectedIndex: _activeLevel1Index,
                itemScrollController: _leftItemScrollController,
                itemPositionsListener: _leftItemPositionsListener,
                onScrollNotification: (n) {
                  if (n is ScrollUpdateNotification) {
                    final delta = n.scrollDelta ?? 0.0;
                    if (delta.abs() > 0.0) {
                      _syncEnabled = true;
                    }
                  }
                  return false;
                },
                buildAvatar: _buildAvatar,
                onTap: (index) {
                  _scrollToLevel1Index(index);
                },
              ),
              Expanded(
                // Sử dụng RightPanel mới tách
                child: CategoryRightPanel(
                  itemScrollController: _rightItemScrollController,
                  itemPositionsListener: _rightItemPositionsListener,
                  roots: categories,
                  activeLevel1Index: _activeLevel1Index,
                  buildAvatar: _buildAvatar,
                  onTapCategory: _openSearch,
                  onViewAll: _openSearch,
                  onScrollEnd: null,
                  onScrollNotification: (n) {
                    if (n is ScrollUpdateNotification) {
                      final delta = n.scrollDelta ?? 0.0;
                      if (delta.abs() > 0.0) {
                        _syncEnabled = true;
                      }
                    }
                    return false;
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
