import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tropia_mobile_app_android/core/network/dio_client.dart';
import 'package:tropia_mobile_app_android/features/user/auth/data/datasources/app_auth_remote_datasource.dart';
import 'package:tropia_mobile_app_android/features/user/auth/data/repositories/app_auth_repository.dart';
import 'package:tropia_mobile_app_android/features/user/profile/data/models/address_model.dart';
import 'package:tropia_mobile_app_android/features/user/profile/data/models/vietnam_address_models.dart';
import 'package:tropia_mobile_app_android/features/user/profile/data/repositories/address_repository.dart';
import 'package:tropia_mobile_app_android/features/user/cart/presentation/screens/map_address_picker_screen.dart';

class UserAddressPage extends StatefulWidget {
  const UserAddressPage({super.key});

  @override
  State<UserAddressPage> createState() => _UserAddressPageState();
}

class _UserAddressPageState extends State<UserAddressPage> {
  // --- STATE VARIABLES ---
  bool _isLoading = true;
  List<AddressModel> _addresses = [];
  // ignore: unused_field
  String _message = "";
  int _currentUserId = 0;

  // --- THEME COLORS (Black & White Minimalist) ---
  final Color _primaryBlack = const Color(0xFF1A1A1A); // Đen
  final Color _bgWhite = Colors.white;
  final Color _bgGrey = const Color(0xFFF9FAFB); // Nền xám nhạt
  final Color _inputFill = const Color(0xFFF3F4F6); // Nền ô nhập liệu

  @override
  void initState() {
    super.initState();
    _loadAddresses();
  }

  // --- LOGIC: TẢI ĐỊA CHỈ ---
  Future<void> _loadAddresses() async {
    final dio = DioClient().dio;
    try {
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
            _message = "Vui lòng đăng nhập";
          });
        }
        return;
      }

      _currentUserId = userId;
      final repo = AddressRepository(client: dio);
      final addresses = await repo.getUserAddresses(userId);

      if (mounted) {
        setState(() {
          _addresses = addresses;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _message = "Lỗi kết nối";
        });
      }
    }
  }

  // --- LOGIC: THÊM & XÓA ---
  void _addNewAddress(AddressModel newAddr) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) =>
          Center(child: CircularProgressIndicator(color: _primaryBlack)),
    );

    try {
      final dio = DioClient().dio;
      final repo = AddressRepository(client: dio);
      final result = await repo.addUserAddress(_currentUserId, newAddr);

      if (mounted) Navigator.of(context, rootNavigator: true).pop();

      if (result == "SUCCESS") {
        if (mounted) {
          _loadAddresses();
        }
      }
    } catch (e) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }
  }

  Future<void> _deleteAddress(int addressId) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) =>
          Center(child: CircularProgressIndicator(color: _primaryBlack)),
    );

    try {
      final dio = DioClient().dio;
      final repo = AddressRepository(client: dio);
      final success = await repo.deleteUserAddress(addressId);

      if (mounted) Navigator.of(context, rootNavigator: true).pop();

      if (success && mounted) _loadAddresses();
    } catch (e) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }
  }

  // --- UI: DIALOG XÁC NHẬN XÓA ---
  void _showDeleteConfirmation(int addressId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _bgWhite,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          "Xóa địa chỉ",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text(
          "Bạn chắc chắn muốn xóa địa chỉ này khỏi danh sách?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text("Hủy", style: TextStyle(color: Colors.grey[600])),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryBlack,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _deleteAddress(addressId);
            },
            child: const Text("Xóa"),
          ),
        ],
      ),
    );
  }

  // --- API HELPERS: Lấy dữ liệu Tỉnh/Phường (v2 – chỉ 2 cấp) ---
  static const _apiBase = 'https://provinces.open-api.vn/api/v2';

  Future<List<Province>> _fetchProvinces() async {
    final res = await http.get(Uri.parse('$_apiBase/p/'));
    if (res.statusCode == 200) {
      final List data = json.decode(utf8.decode(res.bodyBytes));
      return data.map((e) => Province.fromJson(e)).toList();
    }
    return [];
  }

  /// v2: Lấy danh sách Ward (Phường/Xã) trực tiếp từ Province với depth=2
  Future<List<Ward>> _fetchWards(int provinceCode) async {
    final res = await http.get(Uri.parse('$_apiBase/p/$provinceCode?depth=2'));
    if (res.statusCode == 200) {
      final data = json.decode(utf8.decode(res.bodyBytes));
      return Province.fromJson(data).wards;
    }
    return [];
  }

  // --- UI: BOTTOM SHEET ---
  void _showAddAddressBottomSheet() {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final detailCtrl = TextEditingController();
    String type = "home";
    bool isDefault = false;
    final formKey = GlobalKey<FormState>();

    // --- State cho cascading dropdown (v2: 2 cấp Province → Ward) ---
    bool isFromMap = false;
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
      builder: (ctx) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.9,
          ),
          decoration: BoxDecoration(
            color: _bgWhite,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            top: 24,
            left: 24,
            right: 24,
          ),
          child: StatefulBuilder(
            builder: (context, setStateModal) {
              // Load provinces lần đầu (chỉ khi không phải từ bản đồ)
              if (!isFromMap && isLoadingProvinces && provinces.isEmpty) {
                _fetchProvinces().then((list) {
                  setStateModal(() {
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

                      Center(
                        child: Text(
                          "Thêm địa chỉ mới",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: _primaryBlack,
                          ),
                        ),
                      ),
                      const SizedBox(height: 30),

                      _buildModernTextField(
                        nameCtrl,
                        "Tên người nhận",
                        Icons.person_outline,
                      ),
                      const SizedBox(height: 16),
                      _buildModernTextField(
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

                        _buildDropdown<Province>(
                          label: "Tỉnh / Thành phố",
                          icon: Icons.location_city_outlined,
                          isLoading: isLoadingProvinces,
                          items: provinces,
                          value: selectedProvince,
                          itemLabel: (p) => p.name,
                          onChanged: (p) {
                            setStateModal(() {
                              selectedProvince = p;
                              selectedWard = null;
                              wards = [];
                              isLoadingWards = true;
                            });
                            if (p != null) {
                              _fetchWards(p.code).then((list) {
                                setStateModal(() {
                                  wards = list;
                                  isLoadingWards = false;
                                });
                              });
                            }
                          },
                        ),
                        const SizedBox(height: 12),

                        // --- Phường/Xã ---
                        _buildDropdown<Ward>(
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
                                  setStateModal(() {
                                    selectedWard = w;
                                  });
                                },
                        ),
                        const SizedBox(height: 16),
                      ],

                      // --- Địa chỉ chi tiết / Địa chỉ từ bản đồ ---
                      _buildModernTextField(
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
                            setStateModal(() {
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
                          _buildPillChip(
                            "Nhà riêng",
                            "home",
                            type,
                            (val) => setStateModal(() => type = val),
                          ),
                          const SizedBox(width: 12),
                          _buildPillChip(
                            "Văn phòng",
                            "office",
                            type,
                            (val) => setStateModal(() => type = val),
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
                        activeThumbColor: _primaryBlack,
                        trackOutlineColor: WidgetStateProperty.all(
                          Colors.transparent,
                        ),
                        inactiveThumbColor: Colors.white,
                        inactiveTrackColor: Colors.grey[300],
                        onChanged: (v) => setStateModal(() => isDefault = v),
                      ),

                      const SizedBox(height: 24),

                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primaryBlack,
                            foregroundColor: _bgWhite,
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
                                if (selectedProvince == null ||
                                    selectedWard == null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        "Vui lòng chọn đầy đủ Tỉnh/Thành phố và Phường/Xã",
                                      ),
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

                              Navigator.pop(ctx);
                              final newAddr = AddressModel(
                                receiverName: nameCtrl.text,
                                phone: phoneCtrl.text,
                                fullAddress: fullAddress,
                                isDefault: isDefault,
                                type: type,
                              );
                              _addNewAddress(newAddr);
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

  // --- HELPER: DROPDOWN BUILDER ---
  Widget _buildDropdown<T>({
    Key? key,
    required String label,
    required IconData icon,
    required bool isLoading,
    required List<T> items,
    required T? value,
    required String Function(T) itemLabel,
    required ValueChanged<T?>? onChanged,
  }) {
    return Container(
      key: key,
      decoration: BoxDecoration(
        color: _inputFill,
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
                    style: TextStyle(
                      color: _primaryBlack,
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                    dropdownColor: _bgWhite,
                    icon: Icon(
                      Icons.keyboard_arrow_down,
                      color: Colors.grey[400],
                    ),
                    items: items.map((item) {
                      return DropdownMenuItem<T>(
                        value: item,
                        child: Text(
                          itemLabel(item),
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: onChanged,
                    validator: (_) => null, // Validation custom ở nút Lưu
                  ),
          ),
        ],
      ),
    );
  }

  // --- HELPER 1: MODERN TEXT FIELD (Cập nhật Suffix Icon) ---
  Widget _buildModernTextField(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    bool isPhone = false,
    int maxLines = 1,
    bool isAddress = false,
    VoidCallback? onMapTap,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: isPhone ? TextInputType.phone : TextInputType.text,
      maxLines: maxLines,
      style: TextStyle(color: _primaryBlack, fontWeight: FontWeight.w500),
      validator: (value) =>
          (value == null || value.isEmpty) ? 'Vui lòng nhập thông tin' : null,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey[500], fontSize: 13),
        floatingLabelStyle: TextStyle(
          color: _primaryBlack,
          fontWeight: FontWeight.bold,
        ),

        prefixIcon: Icon(icon, color: Colors.grey[400], size: 20),

        // --- NÚT BẢN ĐỒ NỔI BẬT ---
        // Sử dụng Container màu đen, icon trắng để tạo tương phản mạnh
        suffixIcon: isAddress
            ? Container(
                margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                decoration: BoxDecoration(
                  color: _primaryBlack, // Nền đen
                  borderRadius: BorderRadius.circular(10), // Bo góc vuông mềm
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: IconButton(
                  icon: const Icon(Icons.map, size: 20), // Icon map
                  color: Colors.white, // Icon trắng
                  onPressed: onMapTap,
                  tooltip: "Mở bản đồ",
                ),
              )
            : null,

        filled: true,
        fillColor: _inputFill,

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
          borderSide: BorderSide(color: _primaryBlack, width: 1),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
    );
  }

  // --- HELPER 2: PILL CHIP ---
  Widget _buildPillChip(
    String label,
    String value,
    String groupValue,
    Function(String) onSelected,
  ) {
    bool isSelected = groupValue == value;
    return GestureDetector(
      onTap: () => onSelected(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? _primaryBlack : Colors.white,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: isSelected ? _primaryBlack : Colors.grey.shade300,
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

  // --- UI: ADDRESS LIST ITEM ---
  Widget _buildAddressItem(AddressModel address) {
    bool isOffice = address.type.toLowerCase() == 'office';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: _bgWhite,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(
                        address.receiverName.toUpperCase(),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: _primaryBlack,
                        ),
                      ),
                      const SizedBox(width: 10),
                      if (address.isDefault)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _primaryBlack,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            "Mặc định",
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  InkWell(
                    onTap: () {
                      int? id = int.tryParse(address.id.toString());
                      if (id != null) _showDeleteConfirmation(id);
                    },
                    child: Icon(Icons.close, color: Colors.grey[400], size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                address.phone,
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
              ),

              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Divider(
                  height: 1,
                  thickness: 0.5,
                  color: Colors.grey[200],
                ),
              ),

              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    isOffice ? Icons.business : Icons.home_filled,
                    size: 18,
                    color: _primaryBlack,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      address.fullAddress,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        color: _primaryBlack,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgGrey,
      appBar: AppBar(
        title: Text(
          "SỔ ĐỊA CHỈ",
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: _primaryBlack,
            fontSize: 16,
            letterSpacing: 0.5,
          ),
        ),
        centerTitle: true,
        backgroundColor: _bgWhite,
        foregroundColor: _primaryBlack,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),

      floatingActionButton: (!_isLoading && _addresses.isNotEmpty)
          ? FloatingActionButton(
              onPressed: _showAddAddressBottomSheet,
              backgroundColor: _primaryBlack,
              shape: const CircleBorder(),
              elevation: 4,
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,

      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: _primaryBlack))
          : _addresses.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.location_off_outlined,
                    size: 64,
                    color: Colors.grey[300],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "Chưa có địa chỉ nào",
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    onPressed: _showAddAddressBottomSheet,
                    icon: const Icon(Icons.add, color: Colors.black),
                    label: const Text(
                      "Thêm mới",
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.black),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: _addresses.length,
              itemBuilder: (context, index) =>
                  _buildAddressItem(_addresses[index]),
            ),
    );
  }
}
