import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../../core/network/dio_client.dart';
import '../../../auth/data/datasources/app_auth_remote_datasource.dart';
import '../../../auth/data/repositories/app_auth_repository.dart';
import '../../../profile/data/models/address_model.dart';
import '../../../profile/data/models/vietnam_address_models.dart';
import '../../../profile/data/repositories/address_repository.dart';
import 'map_address_picker_screen.dart';

class AddAddressScreen extends StatefulWidget {
  final String? preFilledAddress;

  const AddAddressScreen({super.key, this.preFilledAddress});

  @override
  State<AddAddressScreen> createState() => _AddAddressScreenState();
}

class _AddAddressScreenState extends State<AddAddressScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _detailController = TextEditingController();

  // --- Theme ---
  final Color _primaryBlack = const Color(0xFF1A1A1A);
  final Color _inputFill = const Color(0xFFF3F4F6);

  // --- Cascading dropdown (v2: Province → Ward) ---
  static const _apiBase = 'https://provinces.open-api.vn/api/v2';
  List<Province> _provinces = [];
  Province? _selectedProvince;
  List<Ward> _wards = [];
  Ward? _selectedWard;
  bool _isLoadingProvinces = true;
  bool _isLoadingWards = false;
  String _addressType = 'home';
  bool _isDefault = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.preFilledAddress != null) {
      _detailController.text = widget.preFilledAddress!;
    }
    _fetchProvinces();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _detailController.dispose();
    super.dispose();
  }

  // --- API: Lấy tỉnh ---
  Future<void> _fetchProvinces() async {
    try {
      final res = await http.get(Uri.parse('$_apiBase/p/'));
      if (res.statusCode == 200) {
        final List data = json.decode(utf8.decode(res.bodyBytes));
        if (mounted) {
          setState(() {
            _provinces = data.map((e) => Province.fromJson(e)).toList();
            _isLoadingProvinces = false;
          });
        }
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingProvinces = false);
    }
  }

  // --- API: Lấy phường/xã từ tỉnh (v2 depth=2) ---
  Future<void> _fetchWards(int provinceCode) async {
    setState(() {
      _isLoadingWards = true;
      _wards = [];
      _selectedWard = null;
    });
    try {
      final res =
          await http.get(Uri.parse('$_apiBase/p/$provinceCode?depth=2'));
      if (res.statusCode == 200) {
        final data = json.decode(utf8.decode(res.bodyBytes));
        if (mounted) {
          setState(() {
            _wards = Province.fromJson(data).wards;
            _isLoadingWards = false;
          });
        }
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingWards = false);
    }
  }

  // --- Lưu địa chỉ ---
  Future<void> _saveAddress() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedProvince == null || _selectedWard == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng chọn đầy đủ Tỉnh/Thành phố và Phường/Xã'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    // Ghép fullAddress giống user_address_page
    final detail = _detailController.text.trim();
    final parts = <String>[];
    if (detail.isNotEmpty) parts.add(detail);
    parts.add(_selectedWard!.name);
    parts.add(_selectedProvince!.name);
    final fullAddress = parts.join(', ');

    try {
      final dio = DioClient().dio;
      final appAuthRepo = AppAuthRepository(
        remoteDataSource: AppAuthRemoteDataSourceImpl(client: dio),
      );
      await appAuthRepo.authenticateApp();

      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('user_id');
      if (userId == null) throw Exception('Chưa đăng nhập');

      final addressRepo = AddressRepository(client: dio);
      final newAddr = AddressModel(
        receiverName: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        fullAddress: fullAddress,
        isDefault: _isDefault,
        type: _addressType,
      );
      final result = await addressRepo.addUserAddress(userId, newAddr);
      if (result != 'SUCCESS') throw Exception(result);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Địa chỉ đã được thêm thành công'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        title: const Text(
          'Thêm địa chỉ mới',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
        backgroundColor: Colors.white,
        foregroundColor: _primaryBlack,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- Tên người nhận ---
              _buildModernTextField(
                _nameController,
                'Tên người nhận',
                Icons.person_outline,
              ),
              const SizedBox(height: 14),

              // --- Số điện thoại ---
              _buildModernTextField(
                _phoneController,
                'Số điện thoại',
                Icons.phone_outlined,
                isPhone: true,
              ),
              const SizedBox(height: 20),

              // --- Khu vực ---
              Text(
                'Khu vực',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 10),

              // --- Tỉnh/Thành phố ---
              _buildDropdown<Province>(
                label: 'Tỉnh / Thành phố',
                icon: Icons.location_city_outlined,
                isLoading: _isLoadingProvinces,
                items: _provinces,
                value: _selectedProvince,
                itemLabel: (p) => p.name,
                onChanged: (p) {
                  setState(() {
                    _selectedProvince = p;
                    _selectedWard = null;
                    _wards = [];
                  });
                  if (p != null) _fetchWards(p.code);
                },
              ),
              const SizedBox(height: 10),

              // --- Phường/Xã ---
              _buildDropdown<Ward>(
                key: ValueKey('ward_${_selectedProvince?.code}'),
                label: 'Phường / Xã',
                icon: Icons.holiday_village_outlined,
                isLoading: _isLoadingWards,
                items: _wards,
                value: _selectedWard,
                itemLabel: (w) => w.name,
                onChanged: _selectedProvince == null
                    ? null
                    : (w) => setState(() => _selectedWard = w),
              ),
              const SizedBox(height: 14),

              // --- Địa chỉ chi tiết + nút bản đồ ---
              _buildModernTextField(
                _detailController,
                'Số nhà, tên đường...',
                Icons.edit_location_alt_outlined,
                maxLines: 2,
                isAddress: true,
                onMapTap: () async {
                  final selected = await Navigator.push<String?>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const MapAddressPickerScreen(),
                    ),
                  );
                  if (selected != null && selected.isNotEmpty) {
                    _detailController.text = selected;
                  }
                },
              ),
              const SizedBox(height: 20),

              // --- Loại địa chỉ ---
              Text(
                'Loại địa chỉ',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _buildPillChip('Nhà riêng', 'home'),
                  const SizedBox(width: 12),
                  _buildPillChip('Văn phòng', 'office'),
                ],
              ),
              const SizedBox(height: 16),

              // --- Mặc định ---
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Đặt làm mặc định',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                value: _isDefault,
                activeThumbColor: _primaryBlack,
                trackOutlineColor:
                    WidgetStateProperty.all(Colors.transparent),
                inactiveThumbColor: Colors.white,
                inactiveTrackColor: Colors.grey[300],
                onChanged: (v) => setState(() => _isDefault = v),
              ),
              const SizedBox(height: 20),

              // --- Nút Lưu ---
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryBlack,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  onPressed: _isSaving ? null : _saveAddress,
                  child: _isSaving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Lưu địa chỉ',
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
      ),
    );
  }

  // ======================== HELPER WIDGETS ========================

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
        suffixIcon: isAddress
            ? Container(
                margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                decoration: BoxDecoration(
                  color: _primaryBlack,
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
                  tooltip: 'Mở bản đồ',
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
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }

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
                      'Đang tải...',
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
                    dropdownColor: Colors.white,
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
                    validator: (_) => null,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPillChip(String label, String value) {
    final isSelected = _addressType == value;
    return GestureDetector(
      onTap: () => setState(() => _addressType = value),
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
}