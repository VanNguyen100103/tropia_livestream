import 'package:flutter/material.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../data/models/user_address_model.dart';
// Import model Store vừa tạo
import '../../data/models/store_model.dart';
// Import screen bản đồ
import '../screens/map_address_picker_screen.dart';
// Import screen thêm địa chỉ
import '../screens/add_address_screen.dart';

class CartAddressSection extends StatelessWidget {
  // --- 1. Dữ liệu Địa chỉ ---
  final List<UserAddressModel> addressList;
  final UserAddressModel? selectedAddress;
  final Function(UserAddressModel) onAddressChanged;

  // --- 1.1. Điều khiển hành vi khi bấm "Thay đổi" địa chỉ ---
  // Nếu null thì widget sẽ dùng picker mặc định.
  final VoidCallback? onChangeAddressTap;

  // --- 1.2. Callback cho thêm địa chỉ từ bản đồ ---
  final Function(String selectedAddress)? onAddNewAddress;

  // --- 2. Dữ liệu Cửa hàng (Đã sửa đổi để dùng Model) ---
  final List<StoreModel> storeList; // Danh sách store từ API truyền vào
  final StoreModel? selectedStore; // Store đang được chọn
  final Function(StoreModel)
  onStoreChanged; // Callback trả về cả object store (có id)

  // --- 3. Callback để refresh data từ parent ---
  final VoidCallback? onRefreshData;

  const CartAddressSection({
    super.key,
    required this.addressList,
    required this.selectedAddress,
    required this.onAddressChanged,
    this.onChangeAddressTap,
    this.onAddNewAddress, // Thêm callback mới
    required this.storeList, // <-- Nhận từ parent
    required this.selectedStore, // <-- Nhận từ parent
    required this.onStoreChanged,
    this.onRefreshData, // <-- Thêm callback refresh
  });

  @override
  Widget build(BuildContext context) {
    debugPrint('[CartAddressSection] build: addressList=${addressList.length} selected=${selectedAddress?.id ?? 'null'} name=${selectedAddress?.receiverName ?? ''}');
    // Xử lý hiển thị dữ liệu địa chỉ
    final bool hasAddress = selectedAddress != null;

    final String displayAddress = hasAddress
        ? (selectedAddress!.fullAddress)
        : "Vui lòng chọn địa chỉ nhận hàng";

    final String displayName = hasAddress
        ? (selectedAddress!.receiverName)
        : "---";

    final String displayPhone = hasAddress ? (selectedAddress!.phone) : "---";

    // Xử lý hiển thị tên cửa hàng
    final String displayStoreName = selectedStore?.storeName ?? "Chọn cửa hàng";

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
          // ================= PHẦN 1: ĐỊA CHỈ NHẬN HÀNG =================
          _buildHeaderRow(
            context,
            title: "Địa chỉ nhận hàng",
            onChangeTap:
                onChangeAddressTap ?? () => _showAddressPicker(context),
          ),
          const SizedBox(height: 8),

          if (hasAddress) ...[
            Row(
              children: [
                const Icon(
                  Icons.location_on,
                  size: 16,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    displayAddress,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (selectedAddress?.type != null)
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      selectedAddress!.type.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 20),
              child: Text(
                "$displayName | $displayPhone",
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ),
          ] else ...[
            GestureDetector(
              onTap: onChangeAddressTap ?? () => _showAddressPicker(context),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  "Bấm vào đây để chọn địa chỉ",
                  style: TextStyle(
                    color: Colors.red,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ),
          ],

          const Divider(height: 24, thickness: 0.5),

          // ================= PHẦN 2: CỬA HÀNG GIAO (STORE) =================
          _buildHeaderRow(
            context,
            title: "Giao từ cửa hàng",
            onChangeTap: () => _showStorePicker(context),
          ),
          const SizedBox(height: 8),

          Row(
            children: [
              const Icon(Icons.storefront, size: 18, color: Colors.grey),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  displayStoreName,
                  style: TextStyle(
                    color: selectedStore == null ? Colors.grey : Colors.black87,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderRow(
    BuildContext context, {
    required String title,
    required VoidCallback onChangeTap,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        InkWell(
          onTap: onChangeTap,
          child: Row(
            children: const [
              Text(
                "Thay đổi",
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Icon(Icons.chevron_right, size: 14, color: AppColors.primary),
            ],
          ),
        ),
      ],
    );
  }

  // --- MODAL 1: CHỌN ĐỊA CHỈ (GIỮ NGUYÊN) ---
  void _showAddressPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        if (addressList.isEmpty) {
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
              // Thêm nút tạo địa chỉ mới ở đầu
              ListTile(
                leading: const Icon(
                  Icons.add_location_alt_outlined,
                  color: AppColors.primary,
                ),
                title: const Text(
                  "Tạo địa chỉ mới",
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  // Gọi callback để parent xử lý tạo địa chỉ mới
                  onChangeAddressTap?.call();
                },
              ),
              // Thêm nút lấy địa chỉ trực tiếp
              ListTile(
                leading: const Icon(
                  Icons.my_location,
                  color: AppColors.primary,
                ),
                title: const Text(
                  "Lấy địa chỉ trực tiếp",
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  // Mở bản đồ để chọn địa chỉ
                  _navigateToMapAddressPicker(context);
                },
              ),
              const Divider(),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: addressList.length,
                  separatorBuilder: (ctx, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = addressList[index];
                    final bool isSelected = (selectedAddress?.id == item.id);
                    return ListTile(
                      onTap: () {
                        onAddressChanged(item);
                        Navigator.pop(context);
                        // Gọi callback refresh để parent cập nhật data nếu cần
                        onRefreshData?.call();
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

  // --- METHOD MỚI: NAVIGATE ĐẾN BẢN ĐỒ CHỌN ĐỊA CHỈ ---
  void _navigateToMapAddressPicker(BuildContext context) async {
    final selectedAddress = await Navigator.push<String?>(
      context,
      MaterialPageRoute(builder: (context) => const MapAddressPickerScreen()),
    );
    if (!context.mounted) return;

    if (selectedAddress != null && selectedAddress.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => AddAddressScreen(preFilledAddress: selectedAddress),
        ),
      );
    }
  }

  // --- MODAL 2: CHỌN STORE (CẬP NHẬT LOGIC DÙNG MODEL) ---
  void _showStorePicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        // Kiểm tra nếu chưa có danh sách store
        if (storeList.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(20),
            height: 150,
            child: const Center(
              child: Text("Đang tải danh sách cửa hàng hoặc không có dữ liệu."),
            ),
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
                "Chọn cửa hàng giao hàng",
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
                  itemCount: storeList.length,
                  separatorBuilder: (ctx, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final StoreModel item = storeList[index];
                    // So sánh dựa trên ID
                    final bool isSelected =
                        selectedStore?.storeId == item.storeId;

                    return ListTile(
                      onTap: () {
                        onStoreChanged(item); // Trả về object StoreModel
                        Navigator.pop(context);
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
                        item.storeAddress, // Hiển thị thêm địa chỉ store
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
        );
      },
    );
  }
}
