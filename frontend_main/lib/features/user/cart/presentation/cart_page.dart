import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

// --- CORE IMPORTS ---
import 'package:tropia_mobile_app_android/core/network/dio_client.dart';
import 'package:tropia_mobile_app_android/features/user/auth/data/datasources/app_auth_remote_datasource.dart';
import 'package:tropia_mobile_app_android/features/user/auth/data/repositories/app_auth_repository.dart';
import 'package:tropia_mobile_app_android/features/user/cart/domain/repositories/cart_repository_impl.dart';
import 'package:tropia_mobile_app_android/features/user/cart/presentation/cart_badge_controller.dart';
import 'package:tropia_mobile_app_android/core/utils/dashboard_controller.dart';
import '../../../../../core/constants/app_colors.dart';

// --- CART FEATURE IMPORTS ---
import 'package:tropia_mobile_app_android/features/user/cart/data/datasources/cart_remote_datasource.dart';
import 'package:tropia_mobile_app_android/features/user/cart/data/models/cart_model.dart';
import 'package:tropia_mobile_app_android/features/user/cart/data/models/user_address_model.dart';
import 'package:tropia_mobile_app_android/features/user/cart/data/datasources/checkout_remote_datasource.dart';
import 'package:tropia_mobile_app_android/features/user/cart/data/repositories/checkout_repository.dart';
// --- MỚI: Import StoreModel ---
import 'package:tropia_mobile_app_android/features/user/cart/data/models/store_model.dart';

// --- ADDRESS CREATE (PROFILE REPO) ---
import 'package:tropia_mobile_app_android/features/user/profile/data/models/address_model.dart'
    as profile_models;
import 'package:tropia_mobile_app_android/features/user/profile/data/repositories/address_repository.dart'
    as profile_repo;
import 'package:tropia_mobile_app_android/features/user/profile/data/models/vietnam_address_models.dart';
import 'package:tropia_mobile_app_android/features/user/profile/data/models/voucher_model.dart';
import 'package:tropia_mobile_app_android/features/user/profile/data/repositories/voucher_repository.dart';
import 'package:tropia_mobile_app_android/features/user/profile/data/repositories/unused_voucher_repository.dart';

// --- WIDGET IMPORTS ---
import 'widgets/cart_item_widget.dart';
import 'widgets/delivery_time_sheet.dart';
import 'widgets/cart_address_section.dart';
import 'widgets/cart_payment_section.dart';
import 'widgets/cart_bottom_bar.dart';
import 'widgets/cart_promotion_widget.dart';
import 'order_confirm_page.dart';
import 'screens/map_address_picker_screen.dart';

import 'package:tropia_mobile_app_android/features/user/payment/data/datasources/payment_remote_datasource.dart';
import 'package:tropia_mobile_app_android/features/user/payment/presentation/payment_page.dart';

class CartPage extends StatefulWidget {
  const CartPage({super.key});

  @override
  State<CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  // ... existing code ...

  // Thêm key để force rebuild khi cần
  Key _addressSectionKey = UniqueKey();
  // --- BIẾN UI & LOGIC ---
  bool _isDelivery = true; // true: Giao hàng, false: Tại quán
  // Promotions UI state (embedded widget)
  final TextEditingController _voucherController = TextEditingController();
  String? _selectedVoucherCode;
  List<VoucherModel> _savedVouchers = [];
  double _appliedDiscount = 0.0;
  double _baselineTotal = 0.0;

  // --- POINTS PREVIEW ---
  Timer? _pointsPreviewTimer;
  bool _isPointsPreviewLoading = false;
  int? _earnedPointsPreview;
  int _lastPreviewAmount = 0;
  int? _amountForPointsFromServer;
  bool _isCartSyncing = false;

  // --- BIẾN DỮ LIỆU ---
  List<UserAddressModel> _addressList = [];
  UserAddressModel? _selectedAddress;
  CartModel? _cartData;

  // --- MỚI: Biến lưu danh sách cửa hàng ---
  List<StoreModel> _storeList = [];
  StoreModel? _selectedStore;

  // --- BIẾN CHECKOUT ---
  String _paymentMethod = "cod";
  DateTime _selectedDate = DateTime.now();
  String _selectedTimeSlot = "";

  // --- NOTE ---
  final TextEditingController _noteController = TextEditingController();
  final FocusNode _noteFocusNode = FocusNode();

  static const int _deliveryStartHour = 8;
  static const int _deliveryEndHour = 19; // slots: 08-09 ... 18-19

  List<String> _buildTimeSlotsForDate(DateTime date) {
    final now = DateTime.now();
    final day = DateTime(date.year, date.month, date.day);
    final today = DateTime(now.year, now.month, now.day);
    final isToday = day == today;

    int firstHour = _deliveryStartHour;
    if (isToday) {
      firstHour = now.hour + (now.minute > 0 ? 1 : 0);
      if (firstHour < _deliveryStartHour) firstHour = _deliveryStartHour;
    }

    final slots = <String>[];
    for (int h = firstHour; h < _deliveryEndHour; h++) {
      final start = h.toString().padLeft(2, '0');
      final end = (h + 1).toString().padLeft(2, '0');
      slots.add('$start:00-$end:00');
    }
    return slots;
  }

  void _applyInitialTimeSuggestion() {
    final now = DateTime.now();
    final todaySlots = _buildTimeSlotsForDate(now);
    if (todaySlots.isNotEmpty) {
      _selectedDate = now;
      _selectedTimeSlot = todaySlots.first;
      return;
    }

    final tomorrow = now.add(const Duration(days: 1));
    final tomorrowSlots = _buildTimeSlotsForDate(tomorrow);
    _selectedDate = tomorrow;
    _selectedTimeSlot = tomorrowSlots.isNotEmpty
        ? tomorrowSlots.first
        : '08:00-09:00';
  }

  // --- TRẠNG THÁI ---
  bool _isLoading = true;
  String _message = "";
  double _currentTotalPayment = 0.0;
  int _currentTotalItems = 0;

  String _generateTempOrderId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final r = Random();
    final suffix = List.generate(
      6,
      (_) => chars[r.nextInt(chars.length)],
    ).join();
    return 'TMP-${DateTime.now().millisecondsSinceEpoch}-$suffix';
  }

  @override
  void initState() {
    super.initState();
    _applyInitialTimeSuggestion();
    _loadCartData().then((_) => _fetchSavedVouchers());

    // Đăng ký listener để reload khi chuyển sang tab Cart từ nơi khác
    DashboardController.registerCartListener(_onCartTabActivated);
  }

  void _onCartTabActivated() {
    // Reload cart + vouchers khi được kích hoạt từ bên ngoài
    _loadCartData().then((_) => _fetchSavedVouchers());
  }

  @override
  void dispose() {
    DashboardController.unregisterCartListener();
    _pointsPreviewTimer?.cancel();
    _voucherController.dispose();
    _noteController.dispose();
    _noteFocusNode.dispose();
    super.dispose();
  }

  void _schedulePointsPreview({required int orderAmount}) {
    if (orderAmount <= 0) {
      if (mounted) {
        setState(() {
          _earnedPointsPreview = null;
          _isPointsPreviewLoading = false;
        });
      }
      return;
    }

    if (orderAmount == _lastPreviewAmount && _earnedPointsPreview != null) {
      return;
    }

    _pointsPreviewTimer?.cancel();
    _pointsPreviewTimer = Timer(const Duration(milliseconds: 700), () {
      _fetchPointsPreview(orderAmount: orderAmount);
    });
  }

  Future<void> _fetchPointsPreview({required int orderAmount}) async {
    if (!mounted) return;

    setState(() => _isPointsPreviewLoading = true);

    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id');
    if (userId == null || userId == 0) {
      if (mounted) {
        setState(() {
          _isPointsPreviewLoading = false;
          _earnedPointsPreview = null;
        });
      }
      return;
    }

    final dio = DioClient().dio;
    final repo = CheckoutRepository(
      remoteDataSource: CheckoutRemoteDataSource(client: dio),
    );

    final result = await repo.getPointsPreview(
      userId: userId,
      orderAmount: orderAmount,
    );

    if (!mounted) return;

    setState(() {
      _isPointsPreviewLoading = false;
      if (result != null && result.success) {
        _earnedPointsPreview = result.earnedPoints;
        _lastPreviewAmount = orderAmount;
      } else {
        _earnedPointsPreview = null;
      }
    });
  }

  Future<void> _refreshCartFromServer() async {
    try {
      setState(() => _isCartSyncing = true);

      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('user_id');
      if (userId == null || userId == 0) {
        if (mounted) setState(() => _isCartSyncing = false);
        return;
      }

      final cartRepo = await _buildCartRepo();
      final cartModel = await cartRepo.getCart(userId);

      if (!mounted) return;

      if (cartModel != null) {
        setState(() {
          _cartData = cartModel;
          _currentTotalPayment = cartModel.summary.totalPayment;
          _baselineTotal = cartModel.summary.totalPayment;
          _currentTotalItems = cartModel.summary.totalItems;
          if (_currentTotalItems == 0 && cartModel.items.isNotEmpty) {
            _currentTotalItems = cartModel.items.fold(
              0,
              (sum, item) => sum + item.quantity,
            );
          }

          // Use server subtotal to calculate points preview (before discount)
          _amountForPointsFromServer = cartModel.summary.subtotal.round();
        });

        unawaited(CartBadgeController.instance.setCount(_currentTotalItems));

        if (_amountForPointsFromServer != null) {
          _schedulePointsPreview(orderAmount: _amountForPointsFromServer!);
        }
      }
    } catch (_) {
      if (mounted) setState(() => _isCartSyncing = false);
      return;
    }

    if (mounted) setState(() => _isCartSyncing = false);
  }

  Future<int?> _getCurrentUserId() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id');
    if (userId == null || userId == 0) return null;
    return userId;
  }

  // Method để refresh address section
  void _refreshAddressSection() {
    setState(() {
      _addressSectionKey = UniqueKey();
    });
  }

  Future<CartRepositoryImpl> _buildCartRepo() async {
    final dio = DioClient().dio;
    final cartDataSource = CartRemoteDataSourceImpl(client: dio);
    return CartRepositoryImpl(remoteDataSource: cartDataSource);
  }

  Future<void> _reloadAddresses({
    String? preferReceiverName,
    String? preferPhone,
    String? preferFullAddress,
  }) async {
    final dio = DioClient().dio;
    try {
      final appAuthRepo = AppAuthRepository(
        remoteDataSource: AppAuthRemoteDataSourceImpl(client: dio),
      );
      await appAuthRepo.authenticateApp();

      final userId = await _getCurrentUserId();
      if (userId == null) return;

      final cartRepo = await _buildCartRepo();
      final newList = await cartRepo.getUserAddresses(userId);

      debugPrint('[CartPage][_reloadAddresses] fetched ${newList.length} addresses');
      try {
        final debugStr = newList.map((e) => '${e.id}|${e.receiverName}|${e.phone}').join(' ; ');
        debugPrint('[CartPage][_reloadAddresses] addresses: $debugStr');
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _addressList = newList;

        if (_addressList.isEmpty) {
          _selectedAddress = null;
          return;
        }

        // Ưu tiên: nếu vừa tạo xong thì chọn đúng địa chỉ mới theo nội dung
        UserAddressModel? matched;
        if (preferReceiverName != null &&
            preferPhone != null &&
            preferFullAddress != null) {
          matched = _addressList.cast<UserAddressModel?>().firstWhere(
            (e) =>
                e != null &&
                e.receiverName.trim() == preferReceiverName.trim() &&
                e.phone.trim() == preferPhone.trim() &&
                e.fullAddress.trim() == preferFullAddress.trim(),
            orElse: () => null,
          );
        }

        _selectedAddress =
            matched ??
            _addressList.firstWhere(
              (e) => e.isDefault == true,
              orElse: () => _addressList.first,
            );
      });
    } catch (_) {
      // Không hard-fail UI khi refresh địa chỉ; giữ state hiện tại.
    }
  }

  void _showChangeAddressOptions() {
    if (_isLoading) return;
    // Always show options (create / pick / map) even when address list is empty

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              const Text(
                "Địa chỉ nhận hàng",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(
                  Icons.add_location_alt_outlined,
                  color: AppColors.primary,
                ),
                title: const Text("Tạo địa chỉ mới"),
                onTap: () {
                  Navigator.pop(ctx);
                  _showCreateAddressSheet();
                },
              ),
              ListTile(
                leading: const Icon(Icons.my_location, color: AppColors.primary),
                title: const Text("Lấy địa chỉ trực tiếp"),
                onTap: () async {
                  Navigator.pop(ctx);
                  final selectedAddress = await Navigator.push<String?>(
                    context,
                    MaterialPageRoute(builder: (context) => const MapAddressPickerScreen()),
                  );
                  if (selectedAddress != null && selectedAddress.isNotEmpty) {
                    _showCreateAddressSheet(prefillAddress: selectedAddress);
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.list_alt, color: AppColors.primary),
                title: const Text("Chọn địa chỉ đã có"),
                onTap: () {
                  Navigator.pop(ctx);
                  _showAddressPicker();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _showAddressPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        if (_addressList.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(20),
            height: 200,
            child: const Center(child: Text("Bạn chưa lưu địa chỉ nào.")),
          );
        }

        return Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Chọn địa chỉ nhận hàng",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 10),
              const Divider(),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _addressList.length,
                  separatorBuilder: (ctx, index) => const Divider(height: 1),
                  itemBuilder: (ctx, index) {
                    final item = _addressList[index];
                    final bool isSelected = (_selectedAddress?.id == item.id);
                    return ListTile(
                      onTap: () {
                        setState(() => _selectedAddress = item);
                        Navigator.pop(sheetContext);
                      },
                      leading: Icon(
                        item.type == 'office' ? Icons.business : Icons.home,
                        color: isSelected ? AppColors.primary : Colors.grey,
                      ),
                      title: Row(
                        children: [
                          Text(
                            item.receiverName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            "| ${item.phone}",
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.grey,
                            ),
                          ),
                          if (item.isDefault == true)
                            Container(
                              margin: const EdgeInsets.only(left: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(color: AppColors.primary),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                "Mặc định",
                                style: TextStyle(
                                  fontSize: 9,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                        ],
                      ),
                      subtitle: Text(
                        item.fullAddress,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: isSelected
                          ? const Icon(
                              Icons.check_circle,
                              color: AppColors.primary,
                            )
                          : const Icon(
                              Icons.circle_outlined,
                              color: Colors.grey,
                            ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // --- API HELPERS: Lấy dữ liệu Tỉnh/Phường (v2 – chỉ 2 cấp) ---
  static const _addressApiBase = 'https://provinces.open-api.vn/api/v2';

  Future<List<Province>> _fetchProvinces() async {
    final res = await http.get(Uri.parse('$_addressApiBase/p/'));
    if (res.statusCode == 200) {
      final List data = json.decode(utf8.decode(res.bodyBytes));
      return data.map((e) => Province.fromJson(e)).toList();
    }
    return [];
  }

  Future<List<Ward>> _fetchWards(int provinceCode) async {
    final res = await http.get(Uri.parse('$_addressApiBase/p/$provinceCode?depth=2'));
    if (res.statusCode == 200) {
      final data = json.decode(utf8.decode(res.bodyBytes));
      return Province.fromJson(data).wards;
    }
    return [];
  }

  // --- HELPER: DROPDOWN BUILDER ---
  Widget _buildAddressDropdown<T>({
    Key? key,
    required String label,
    required IconData icon,
    required bool isLoading,
    required List<T> items,
    required T? value,
    required String Function(T) itemLabel,
    required ValueChanged<T?>? onChanged,
  }) {
    const inputFill = Color(0xFFF3F4F6);
    return Container(
      key: key,
      decoration: BoxDecoration(
        color: inputFill,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey[400], size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: isLoading
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      "Đang tải...",
                      style: TextStyle(color: Colors.grey[400], fontSize: 14),
                    ),
                  )
                : DropdownButtonFormField<T>(
                    initialValue: value,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 14),
                      isDense: true,
                    ),
                    isExpanded: true,
                    hint: Text(
                      label,
                      style: TextStyle(color: Colors.grey[500], fontSize: 14),
                    ),
                    style: const TextStyle(
                      color: Color(0xFF1A1A1A),
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                    dropdownColor: Colors.white,
                    icon: Icon(Icons.keyboard_arrow_down, color: Colors.grey[400]),
                    items: items.map((item) {
                      return DropdownMenuItem<T>(
                        value: item,
                        child: Text(itemLabel(item), overflow: TextOverflow.ellipsis),
                      );
                    }).toList(),
                    onChanged: onChanged,
                    validator: (_) => null,
                  ),
          ),
        ],
      ),
    );
  }

  // --- HELPER: MODERN TEXT FIELD ---
  Widget _buildAddressTextField(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    bool isPhone = false,
    int maxLines = 1,
    bool isAddress = false,
    VoidCallback? onMapTap,
  }) {
    const inputFill = Color(0xFFF3F4F6);
    const primaryBlack = Color(0xFF1A1A1A);
    return TextFormField(
      controller: ctrl,
      keyboardType: isPhone ? TextInputType.phone : TextInputType.text,
      maxLines: maxLines,
      style: const TextStyle(color: primaryBlack, fontWeight: FontWeight.w500),
      validator: (value) =>
          (value == null || value.isEmpty) ? 'Vui lòng nhập thông tin' : null,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey[500], fontSize: 13),
        floatingLabelStyle: const TextStyle(
          color: primaryBlack,
          fontWeight: FontWeight.bold,
        ),
        prefixIcon: Icon(icon, color: Colors.grey[400], size: 20),
        suffixIcon: isAddress
            ? Container(
                margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                decoration: BoxDecoration(
                  color: primaryBlack,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: IconButton(
                  icon: const Icon(Icons.map, size: 20),
                  color: Colors.white,
                  onPressed: onMapTap,
                  tooltip: "Mở bản đồ",
                ),
              )
            : null,
        filled: true,
        fillColor: inputFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryBlack, width: 1),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }

  // --- HELPER: PILL CHIP ---
  Widget _buildAddressPillChip(
    String label,
    String value,
    String groupValue,
    Function(String) onSelected,
  ) {
    const primaryBlack = Color(0xFF1A1A1A);
    bool isSelected = groupValue == value;
    return GestureDetector(
      onTap: () => onSelected(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? primaryBlack : Colors.white,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: isSelected ? primaryBlack : Colors.grey.shade300,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black87,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  void _showCreateAddressSheet({String? prefillAddress}) {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final detailCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    // Nếu có prefillAddress từ bản đồ → ẩn dropdown 2 cấp
    bool isFromMap = false;
    if (prefillAddress != null && prefillAddress.isNotEmpty) {
      detailCtrl.text = prefillAddress;
      isFromMap = true;
    }

    String type = "home";
    bool isDefault = false;

    // --- State cho cascading dropdown (v2: 2 cấp Province → Ward) ---
    List<Province> provinces = [];
    Province? selectedProvince;
    List<Ward> wards = [];
    Ward? selectedWard;
    bool isLoadingProvinces = true;
    bool isLoadingWards = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.9,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
            top: 24,
            left: 24,
            right: 24,
          ),
          child: StatefulBuilder(
            builder: (context, setSheetState) {
              // Load provinces lần đầu (chỉ khi không phải từ bản đồ)
              if (!isFromMap && isLoadingProvinces && provinces.isEmpty) {
                _fetchProvinces().then((list) {
                  setSheetState(() {
                    provinces = list;
                    isLoadingProvinces = false;
                  });
                });
              }

              return Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Center(
                        child: Text(
                          "Thêm địa chỉ mới",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A1A1A),
                          ),
                        ),
                      ),
                      const SizedBox(height: 30),
                      _buildAddressTextField(
                        nameCtrl,
                        "Tên người nhận",
                        Icons.person_outline,
                      ),
                      const SizedBox(height: 16),
                      _buildAddressTextField(
                        phoneCtrl,
                        "Số điện thoại",
                        Icons.phone_outlined,
                        isPhone: true,
                      ),
                      const SizedBox(height: 24),

                      // --- CASCADING DROPDOWN: Tỉnh/Thành (ẩn khi từ bản đồ) ---
                      if (!isFromMap) ...[
                        Text(
                          "Khu vực",
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildAddressDropdown<Province>(
                          label: "Tỉnh / Thành phố",
                          icon: Icons.location_city_outlined,
                          isLoading: isLoadingProvinces,
                          items: provinces,
                          value: selectedProvince,
                          itemLabel: (p) => p.name,
                          onChanged: (p) {
                            setSheetState(() {
                              selectedProvince = p;
                              selectedWard = null;
                              wards = [];
                              isLoadingWards = true;
                            });
                            if (p != null) {
                              _fetchWards(p.code).then((list) {
                                setSheetState(() {
                                  wards = list;
                                  isLoadingWards = false;
                                });
                              });
                            }
                          },
                        ),
                        const SizedBox(height: 12),

                        // --- Phường/Xã ---
                        _buildAddressDropdown<Ward>(
                          key: ValueKey('ward_${selectedProvince?.code}'),
                          label: "Phường / Xã",
                          icon: Icons.holiday_village_outlined,
                          isLoading: isLoadingWards,
                          items: wards,
                          value: selectedWard,
                          itemLabel: (w) => w.name,
                          onChanged: selectedProvince == null
                              ? null
                              : (w) {
                                  setSheetState(() {
                                    selectedWard = w;
                                  });
                                },
                        ),
                        const SizedBox(height: 16),
                      ],

                      // --- Địa chỉ chi tiết / Địa chỉ từ bản đồ ---
                      _buildAddressTextField(
                        detailCtrl,
                        isFromMap ? "Địa chỉ từ bản đồ" : "Số nhà, tên đường...",
                        Icons.edit_location_alt_outlined,
                        maxLines: 2,
                        isAddress: true,
                        onMapTap: () async {
                          final selected = await Navigator.push<String?>(
                            context,
                            MaterialPageRoute(
                              builder: (ctx) => const MapAddressPickerScreen(),
                            ),
                          );
                          if (selected != null && selected.isNotEmpty) {
                            detailCtrl.text = selected;
                            // Ẩn dropdown khi đã pick từ bản đồ
                            setSheetState(() {
                              isFromMap = true;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 24),

                      Text(
                        "Loại địa chỉ",
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _buildAddressPillChip(
                            "Nhà riêng",
                            "home",
                            type,
                            (val) => setSheetState(() => type = val),
                          ),
                          const SizedBox(width: 12),
                          _buildAddressPillChip(
                            "Văn phòng",
                            "office",
                            type,
                            (val) => setSheetState(() => type = val),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          "Đặt làm mặc định",
                          style: TextStyle(fontWeight: FontWeight.w500),
                        ),
                        value: isDefault,
                        activeThumbColor: const Color(0xFF1A1A1A),
                        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
                        inactiveThumbColor: Colors.white,
                        inactiveTrackColor: Colors.grey[300],
                        onChanged: (v) => setSheetState(() => isDefault = v),
                      ),
                      const SizedBox(height: 24),

                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1A1A1A),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),
                          onPressed: () {
                            if (formKey.currentState!.validate()) {
                              String fullAddress;

                              if (isFromMap) {
                                // Địa chỉ từ bản đồ → dùng trực tiếp
                                fullAddress = detailCtrl.text.trim();
                                if (fullAddress.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text("Vui lòng nhập hoặc chọn địa chỉ từ bản đồ"),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                  return;
                                }
                              } else {
                                // Luồng thường → validate dropdowns
                                if (selectedProvince == null || selectedWard == null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text("Vui lòng chọn đầy đủ Tỉnh/Thành phố và Phường/Xã"),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                  return;
                                }

                                // Ghép fullAddress từ dropdown
                                final detail = detailCtrl.text.trim();
                                final parts = <String>[];
                                if (detail.isNotEmpty) parts.add(detail);
                                parts.add(selectedWard!.name);
                                parts.add(selectedProvince!.name);
                                fullAddress = parts.join(', ');
                              }

                              Navigator.pop(sheetContext);
                              final newAddr = profile_models.AddressModel(
                                receiverName: nameCtrl.text.trim(),
                                phone: phoneCtrl.text.trim(),
                                fullAddress: fullAddress,
                                isDefault: isDefault,
                                type: type,
                              );
                              _createNewAddress(newAddr);
                            }
                          },
                          child: const Text(
                            "Lưu địa chỉ",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _createNewAddress(profile_models.AddressModel newAddr) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final dio = DioClient().dio;

      final appAuthRepo = AppAuthRepository(
        remoteDataSource: AppAuthRemoteDataSourceImpl(client: dio),
      );
      await appAuthRepo.authenticateApp();

      final userId = await _getCurrentUserId();
      if (userId == null) {
        if (mounted) Navigator.of(context, rootNavigator: true).pop();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Vui lòng đăng nhập."),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final repo = profile_repo.AddressRepository(client: dio);
      final result = await repo.addUserAddress(userId, newAddr);
      final resStr = result.toString();
      debugPrint('[CartPage][_createNewAddress] addUserAddress result: $resStr, mounted=$mounted');

      if (mounted) Navigator.of(context, rootNavigator: true).pop();

      if (!mounted) return;

      if (resStr == "SUCCESS" || resStr.toLowerCase().contains('thêm địa chỉ') || resStr.toLowerCase().contains('success')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Thêm địa chỉ thành công!"),
            backgroundColor: Colors.green,
          ),
        );

        // Thử reload addresses nhiều lần để tránh race condition khi backend
        // chưa kịp persist data ngay lập tức.
        const int maxAttempts = 3;
        int attempt = 0;
        while (attempt < maxAttempts) {
          debugPrint('[CartPage][_createNewAddress] reload attempt ${attempt + 1}');
          await _reloadAddresses(
            preferReceiverName: newAddr.receiverName,
            preferPhone: newAddr.phone,
            preferFullAddress: newAddr.fullAddress,
          );

          debugPrint('[CartPage][_createNewAddress] after reload attempt ${attempt + 1}, _addressList.length=${_addressList.length}');

          // Nếu đã có địa chỉ mới trong danh sách thì dừng retry
          if (_addressList.isNotEmpty) break;

          attempt++;
          // Thời gian chờ giữa các lần thử (tăng lên 1s)
          await Future.delayed(const Duration(seconds: 1));
        }

        // Nếu sau các lần retry server vẫn chưa trả về địa chỉ,
        // thêm tạm địa chỉ vừa tạo vào local list để UX mượt ngay lập tức.
        if (_addressList.isEmpty) {
          final tempId = DateTime.now().millisecondsSinceEpoch;
          final fallback = UserAddressModel(
            id: tempId,
            receiverName: newAddr.receiverName,
            phone: newAddr.phone,
            fullAddress: newAddr.fullAddress,
            isDefault: newAddr.isDefault,
            type: newAddr.type,
          );
          debugPrint('[CartPage][_createNewAddress] using fallback address id=$tempId');
          setState(() {
            _addressList = [fallback, ..._addressList];
            _selectedAddress = fallback;
          });
        }

        // Force refresh address section để đảm bảo UI được rebuild
        _refreshAddressSection();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        try {
          Navigator.of(context, rootNavigator: true).pop();
        } catch (_) {}
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Lỗi hệ thống: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // --- 1. HÀM TẢI DỮ LIỆU (CẬP NHẬT) ---
  Future<void> _loadCartData() async {
    final dio = DioClient().dio;
    try {
      // Authenticate
      final appAuthRepo = AppAuthRepository(
        remoteDataSource: AppAuthRemoteDataSourceImpl(client: dio),
      );
      await appAuthRepo.authenticateApp();

      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('user_id');

      if (userId == null || userId == 0) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _message = "Vui lòng đăng nhập.";
          });
        }
        return;
      }

      // Init Repo
      final cartDataSource = CartRemoteDataSourceImpl(client: dio);
      final cartRepo = CartRepositoryImpl(remoteDataSource: cartDataSource);

      // --- MỚI: Gọi API getStores song song với getCart và getAddress ---
      final results = await Future.wait([
        cartRepo.getCart(userId),
        cartRepo.getUserAddresses(userId),
        cartRepo.getListStores(), // Gọi thêm API store
      ]);

      final cartModel = results[0] as CartModel?;
      final addressList = results[1] as List<UserAddressModel>;
      final storeList = results[2] as List<StoreModel>; // Nhận kết quả store

      if (mounted) {
        setState(() {
          _isLoading = false;
          // Setup Cart
          if (cartModel != null) {
            _cartData = cartModel;
            _currentTotalPayment = cartModel.summary.totalPayment;
            _baselineTotal = cartModel.summary.totalPayment;
            _currentTotalItems = cartModel.summary.totalItems;

            // Fallback nếu API trả total_items = 0 nhưng có items.
            if (_currentTotalItems == 0 && cartModel.items.isNotEmpty) {
              _currentTotalItems = cartModel.items.fold(
                0,
                (sum, item) => sum + item.quantity,
              );
            }

            // Use server subtotal for points preview
            _amountForPointsFromServer = cartModel.summary.subtotal.round();
          } else {
            _message = "Giỏ hàng trống";
          }

          // Setup Address
          _addressList = addressList;
          if (_addressList.isNotEmpty) {
            _selectedAddress = _addressList.firstWhere(
              (e) => e.isDefault == true,
              orElse: () => _addressList.first,
            );
          }

          // --- MỚI: Setup Store ---
          _storeList = storeList;
          if (_storeList.isNotEmpty) {
            // Mặc định chọn store đầu tiên hoặc store ID = 1 nếu có
            _selectedStore = _storeList.firstWhere(
              (element) => element.storeId == 1,
              orElse: () => _storeList.first,
            );
          }
        });

        if (_amountForPointsFromServer != null) {
          _schedulePointsPreview(orderAmount: _amountForPointsFromServer!);
        }

        unawaited(CartBadgeController.instance.setCount(_currentTotalItems));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _message = "Lỗi: $e";
        });
      }
    }
  }

  Future<void> _fetchSavedVouchers() async {
    final dio = DioClient().dio;
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('user_id');
      if (userId == null || userId == 0) return;
      final repo = VoucherRepository(client: dio);
      final vouchers = await repo.getUserVouchers(userId, status: 'active');
      if (!mounted) return;
      setState(() {
        _savedVouchers = vouchers;
      });

      // Auto-apply pending voucher từ trang Voucher
      final pendingCode = DashboardController.pendingVoucherCode;
      if (pendingCode != null && pendingCode.isNotEmpty) {
        DashboardController.pendingVoucherCode = null; // clear ngay
        VoucherModel? found;
        try {
          found = _savedVouchers.firstWhere((v) => v.code == pendingCode);
        } catch (_) {
          found = null;
        }
        if (found != null) {
          _applyVoucher(found);
        }
      }
    } catch (_) {}
  }

  Future<void> _saveVoucherFromCart(String code) async {
    final dio = DioClient().dio;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      final userId = prefs.getInt('user_id');
      final authToken = prefs.getString('app_auth_token') ?? prefs.getString('auth_token') ?? prefs.getString('access_token') ?? '';
      if (userId == null || userId == 0) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Vui lòng đăng nhập để lưu mã'),
          backgroundColor: Colors.red,
        ));
        return;
      }
      if (authToken.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Token không hợp lệ. Vui lòng đăng nhập lại.'),
          backgroundColor: Colors.red,
        ));
        return;
      }

      final repo = UnusedVoucherRepository(client: dio);
      final res = await repo.saveVoucher(authToken: authToken, userId: userId, code: code);
      if (!mounted) return;
      final ok = res['Result'] == true;
      final msg = (res['message'] ?? res['Message'] ?? 'Lưu mã thất bại').toString();
      if (ok) {
        await _fetchSavedVouchers();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        VoucherModel? found;
        try {
          found = _savedVouchers.firstWhere((v) => v.code == code);
        } catch (_) {
          found = null;
        }
        if (found != null) {
          _applyVoucher(found);
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lưu mã thất bại'), backgroundColor: Colors.red));
    }
  }

  void _applyVoucher(VoucherModel voucher) {
    if (_cartData == null) return;
    final subtotal = _cartData!.summary.subtotal;
    if (subtotal < voucher.minOrderValue) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Yêu cầu đơn tối thiểu ${NumberFormat.currency(locale: 'vi_VN', symbol: 'đ').format(voucher.minOrderValue)}')),
      );
      return;
    }

    double discount = 0.0;
    if (voucher.discountType == 'fixed_amount') {
      discount = voucher.discountValue;
    } else if (voucher.discountType == 'percent') {
      discount = subtotal * (voucher.discountValue / 100);
      if (voucher.maxDiscountAmount != null) {
        discount = min(discount, voucher.maxDiscountAmount!);
      }
    }

    setState(() {
      _selectedVoucherCode = voucher.code;
      _appliedDiscount = discount;
      _currentTotalPayment = (_baselineTotal - _appliedDiscount).clamp(0.0, double.infinity);
    });
  }

  void _clearVoucher() {
    setState(() {
      _selectedVoucherCode = null;
      _appliedDiscount = 0.0;
      _currentTotalPayment = _baselineTotal;
      _voucherController.clear();
    });
  }

  // --- 2. HÀM XỬ LÝ ĐẶT HÀNG (CẬP NHẬT) ---
  Future<void> _handleCheckout() async {
    if (_cartData == null || _cartData!.items.isEmpty) return;

    if (_isDelivery && _selectedAddress == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Vui lòng chọn địa chỉ giao hàng"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // --- MỚI: Validate Store ---
    if (_selectedStore == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Vui lòng chọn cửa hàng"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      final dio = DioClient().dio;
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      final userId = prefs.getInt('user_id');

      if (userId == null || userId == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Vui lòng đăng nhập."),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final String formattedDate = DateFormat(
        'yyyy-MM-dd',
      ).format(_selectedDate);

      final noteText = _noteController.text.trim();

      final Map<String, dynamic> orderBody = {
        'user_id': userId.toString(),
        'payment_method': _paymentMethod,
        'shipping_method': _isDelivery ? 'home_delivery' : 'store_pickup',
        if (_isDelivery) 'user_address_id': _selectedAddress?.id,
        'store_id': _selectedStore?.storeId,
        'delivery_options': {
          'service_type': 'economy',
          'selected_date': formattedDate,
          'time_slot': _selectedTimeSlot,
        },
        'note': noteText.isEmpty ? null : noteText,
        'voucher_code': _selectedVoucherCode,
      };

      final confirmed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => OrderConfirmPage(
            cartData: _cartData!,
            isDelivery: _isDelivery,
            selectedAddress: _selectedAddress,
            selectedStore: _selectedStore!,
            paymentMethod: _paymentMethod,
            selectedDate: _selectedDate,
            selectedTimeSlot: _selectedTimeSlot,
            note: noteText,
            totalPayment: _currentTotalPayment,
          ),
        ),
      );
      if (!mounted) return;

      if (confirmed != true) return;

      // --- BANK TRANSFER (MoMo) FLOW ---
      if (_paymentMethod == 'bank_transfer') {
        final pendingPayload = orderBody;

        final tempOrderId = _generateTempOrderId();
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => const Center(child: CircularProgressIndicator()),
        );

        final paymentDs = PaymentRemoteDataSourceImpl(client: dio);
        final paymentInfo = await paymentDs.createPayment(
          orderId: tempOrderId,
          amount: _currentTotalPayment,
          orderInfo: 'Thanh toán đơn hàng $tempOrderId',
          extraData: tempOrderId,
        );

        if (mounted) {
          Navigator.of(context, rootNavigator: true).pop();
        }
        if (!mounted) return;

        if (paymentInfo == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Tạo thanh toán thất bại. Vui lòng thử lại.'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        final finalized = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => PaymentPage(
              paymentInfo: paymentInfo,
              pendingCheckoutPayload: pendingPayload,
            ),
          ),
        );

        if (finalized == true) {
          _showSuccessDialog();
        }
        return;
      }

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(child: CircularProgressIndicator()),
      );

      final dataSource = CartRemoteDataSourceImpl(client: dio);
      final response = await dataSource.checkout(orderBody);

      if (mounted) Navigator.of(context, rootNavigator: true).pop();

      if (response != null &&
          (response['Result'] == true || response['status'] == 200)) {
        _showSuccessDialog();
      } else {
        String error =
            response?['StatusMess'] ??
            response?['message'] ??
            "Đặt hàng thất bại";
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        try {
          Navigator.of(context, rootNavigator: true).pop();
        } catch (_) {}
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Lỗi hệ thống: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ... (Giữ nguyên các hàm _showSuccessDialog, _onItemQtyChanged)
  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        Future.delayed(const Duration(seconds: 2), () {
          if (ctx.mounted && Navigator.of(ctx).canPop()) {
            Navigator.of(ctx).pop();
          }
          if (mounted) {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              setState(() {
                _loadCartData();
              });
            }
          }
        });
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          contentPadding: const EdgeInsets.symmetric(
            vertical: 24,
            horizontal: 20,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.check_circle, color: Colors.green, size: 60),
              SizedBox(height: 16),
              Text(
                "Đặt hàng thành công!",
                style: TextStyle(
                  color: Colors.green,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 8),
              Text(
                "Cảm ơn bạn đã mua hàng.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ],
          ),
        );
      },
    );
  }

  void _onItemQtyChanged(int index, int newQty, double priceDiff, int qtyDiff) {
    setState(() {
      _currentTotalPayment += priceDiff;
      if (_currentTotalPayment < 0) _currentTotalPayment = 0;

      _currentTotalItems += qtyDiff;
      if (_currentTotalItems < 0) _currentTotalItems = 0;

      if (newQty == 0 && _cartData != null) {
        _cartData!.items.removeAt(index);
      }
    });

    unawaited(CartBadgeController.instance.setCount(_currentTotalItems));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: Column(
        children: [
          Expanded(child: _buildMainContent()),
          // Show applied discount
          if (_appliedDiscount > 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              // child: Text(
              //   'Giảm: -${NumberFormat.currency(locale: 'vi_VN', symbol: 'đ').format(_appliedDiscount)}',
              //   style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
              // ),
            ),
          CartBottomBar(
            totalPrice: _currentTotalPayment,
            totalItems: _currentTotalItems,
            earnedPointsPreview: _earnedPointsPreview,
            isPointsPreviewLoading: _isPointsPreviewLoading || _isCartSyncing,
            onOrderPressed: _handleCheckout,
          ),
        ],
      ),
    );
  }

  // Promotions UI has been extracted to widgets/cart_promotion_widget.dart

  Widget _buildMainContent() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_cartData == null || _cartData!.items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.remove_shopping_cart,
              size: 60,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            Text(
              _message.isNotEmpty ? _message : "Giỏ hàng trống",
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _loadCartData,
              child: const Text("Tải lại"),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          _buildDeliveryToggle(),
          const SizedBox(height: 12),

          // --- MỚI: Sử dụng CartAddressSection với StoreModel ---
          if (_isDelivery)
            CartAddressSection(
              key: _addressSectionKey, // Thêm key để force rebuild
              // Truyền danh sách store và store đang chọn
              storeList: _storeList,
              selectedStore: _selectedStore,
              onStoreChanged: (store) => setState(() => _selectedStore = store),

              addressList: _addressList,
              selectedAddress: _selectedAddress,
              onAddressChanged: (addr) =>
                  setState(() => _selectedAddress = addr),
              onChangeAddressTap: _showChangeAddressOptions,
              onRefreshData: _refreshAddressSection, // Gọi refresh khi cần
            )
          else
            _buildStorePickupInfo(),

          const SizedBox(height: 12),
          _buildTimePickerButton(),
          const SizedBox(height: 12),

          ListView.builder(
            primary: false,
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _cartData!.items.length,
            itemBuilder: (context, index) {
              final item = _cartData!.items[index];
              return CartItemWidget(
                key: ValueKey(
                  '${item.productId}:${item.option?.optionId ?? 0}',
                ),
                item: item,
                onQuantityChanged: (qty, diff, qtyDiff) =>
                    _onItemQtyChanged(index, qty, diff, qtyDiff),
                onCartUpdated: _refreshCartFromServer,
              );
            },
          ),
          const SizedBox(height: 0),

          // Tạm khoá chọn phương thức thanh toán (chưa tích hợp luồng thanh toán).
          CartPaymentSection(
            currentPaymentMethod: _paymentMethod,
            onPaymentChanged: (method) =>
                setState(() => _paymentMethod = method),
          ),
          const SizedBox(height: 12),
          _buildNoteSection(),
          // Promotions widget embedded inside cart
          CartPromotionWidget(
            subtotal: _cartData?.summary.subtotal ?? 0.0,
            voucherController: _voucherController,
            savedVouchers: _savedVouchers,
            selectedVoucherCode: _selectedVoucherCode,
            onApplyVoucher: _applyVoucher,
            onClearVoucher: _clearVoucher,
            onSaveCode: _saveVoucherFromCart,
          ),
        ],
      ),
    );
  }

  Widget _buildNoteSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Ghi chú',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _noteController,
            focusNode: _noteFocusNode,
            maxLines: 2,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _noteFocusNode.unfocus(),
            onTapOutside: (_) => _noteFocusNode.unfocus(),
            decoration: InputDecoration(
              hintText: 'Ví dụ: Gọi trước khi đến',
              filled: true,
              fillColor: const Color(0xFFF6F6F6),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ... (Giữ nguyên các widget con: _buildDeliveryToggle, _buildTabItem, _buildTimePickerButton, _showTimePicker)

  // Widget phụ trợ giữ nguyên
  Widget _buildDeliveryToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          _buildTabItem(
            text: "Giao hàng tận nơi",
            isSelected: _isDelivery,
            onTap: () => setState(() => _isDelivery = true),
          ),
          _buildTabItem(
            text: "Nhận tại cửa hàng",
            isSelected: !_isDelivery,
            onTap: () => setState(() => _isDelivery = false),
          ),
        ],
      ),
    );
  }

  Widget _buildTabItem({
    required String text,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            boxShadow: isSelected
                ? [const BoxShadow(color: Colors.black12, blurRadius: 2)]
                : null,
          ),
          child: Text(
            text,
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? AppColors.primary : Colors.grey[600],
            ),
          ),
        ),
      ),
    );
  }

  void _showStorePickerForPickup() {
    if (_storeList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Không có danh sách cửa hàng."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 20),
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.7,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Chọn cửa hàng",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 10),
                const Divider(),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _storeList.length,
                    separatorBuilder: (ctx, index) => const Divider(height: 1),
                    itemBuilder: (ctx, index) {
                      final item = _storeList[index];
                      final isSelected =
                          _selectedStore?.storeId == item.storeId;

                      return ListTile(
                        onTap: () {
                          setState(() => _selectedStore = item);
                          Navigator.pop(sheetContext);
                        },
                        leading: Icon(
                          Icons.store,
                          color: isSelected ? AppColors.primary : Colors.grey,
                        ),
                        title: Text(
                          item.storeName,
                          style: TextStyle(
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isSelected
                                ? AppColors.primary
                                : Colors.black87,
                          ),
                        ),
                        subtitle: Text(
                          item.storeAddress,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: isSelected
                            ? const Icon(Icons.check, color: AppColors.primary)
                            : null,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStorePickupInfo() {
    // --- MỚI: Hiển thị Store nào đang được chọn khi pick-up ---
    return Container(
      padding: const EdgeInsets.all(16),
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          const Text(
            "Bạn sẽ đến cửa hàng sau để nhận món:",
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 8),
          Text(
            _selectedStore?.storeName ?? "Chưa chọn cửa hàng",
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: AppColors.primary,
            ),
          ),
          Text(
            _selectedStore?.storeAddress ?? "",
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13),
          ),
          TextButton(
            onPressed: _showStorePickerForPickup,
            child: const Text("Đổi cửa hàng khác"),
          ),
        ],
      ),
    );
  }

  Widget _buildTimePickerButton() {
    String displayDate = DateFormat('dd/MM').format(_selectedDate);
    String displayString = "$displayDate | $_selectedTimeSlot";
    return InkWell(
      onTap: () => _showTimePicker(context),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Thời gian giao hàng:",
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 4),
                Text(
                  displayString,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Icon(Icons.edit_calendar, color: AppColors.primary, size: 20),
          ],
        ),
      ),
    );
  }

  void _showTimePicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DeliveryTimeSheet(
        onTimeSelected: (date, slot) {
          setState(() {
            _selectedDate = date;
            _selectedTimeSlot = slot;
          });
        },
      ),
    );
  }
}
