import 'package:flutter/material.dart';
import 'package:tropia_mobile_app_android/core/network/dio_client.dart';
import 'package:tropia_mobile_app_android/features/admin/customers/data/models/customer_model.dart';
import 'package:tropia_mobile_app_android/features/admin/customers/data/repositories/customer_repository.dart';
import 'package:tropia_mobile_app_android/features/admin/customers/presentation/pages/customer_detail_screen.dart';
import 'package:tropia_mobile_app_android/features/user/auth/data/datasources/app_auth_remote_datasource.dart';
import 'package:tropia_mobile_app_android/features/user/auth/data/repositories/app_auth_repository.dart';

class CustomersListScreen extends StatefulWidget {
  const CustomersListScreen({super.key});

  @override
  State<CustomersListScreen> createState() => _CustomersListScreenState();
}

class _CustomersListScreenState extends State<CustomersListScreen> {
  bool _isLoading = true;
  List<CustomerModel> _allCustomers = [];
  List<CustomerModel> _filteredCustomers = [];
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    final dio = DioClient().dio;
    final authRepo = AppAuthRepository(
       remoteDataSource: AppAuthRemoteDataSourceImpl(client: dio),
    );
    await authRepo.authenticateApp();
    await _fetchCustomers();
  }

  Future<void> _fetchCustomers() async {
    setState(() => _isLoading = true);
    final dio = DioClient().dio;
    final repo = CustomerRepository(client: dio);
    
    final data = await repo.getCustomers();

    if (mounted) {
      setState(() {
        _allCustomers = data;
        _filterCustomers();
        _isLoading = false;
      });
    }
  }

  void _filterCustomers() {
    String query = _searchController.text.toLowerCase();
    setState(() {
      _filteredCustomers = _allCustomers.where((cus) {
        return cus.name.toLowerCase().contains(query) || 
               cus.id.toLowerCase().contains(query);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchCustomers,
              color: Colors.orange,
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 100),
                itemCount: _filteredCustomers.isEmpty ? 2 : _filteredCustomers.length + 1,
                separatorBuilder: (_, index) => index == 0 ? const SizedBox.shrink() : const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  if (index == 0) return _buildHeader(context);
                  
                  if (_filteredCustomers.isEmpty) {
                    return Container(
                      height: 300,
                      alignment: Alignment.center,
                      child: const Text("Không tìm thấy khách hàng", style: TextStyle(color: Colors.grey)),
                    );
                  }

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _buildCustomerItem(_filteredCustomers[index - 1]),
                  );
                },
              ),
            ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final double topPadding = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.fromLTRB(20, topPadding + 20, 20, 10),
      color: const Color(0xFFF7F8FA),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Quản lý khách hàng",
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 2))],
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => _filterCustomers(),
              decoration: const InputDecoration(
                hintText: "Tìm tên hoặc ID khách...",
                prefixIcon: Icon(Icons.search, color: Colors.grey),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerItem(CustomerModel customer) {
    bool isActive = customer.status == 'active';

    return GestureDetector(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => CustomerDetailScreen(customer: customer)),
        );
        _fetchCustomers(); // Reload khi quay lại
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Row(
          children: [
            // Avatar
            CircleAvatar(
              radius: 24,
              backgroundColor: isActive ? Colors.blue.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1),
              child: Text(
                customer.name.isNotEmpty ? customer.name[0].toUpperCase() : "C",
                style: TextStyle(
                  color: isActive ? Colors.blue : Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    customer.name,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    customer.area,
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                  ),
                ],
              ),
            ),
            // Status Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isActive ? Colors.green.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                isActive ? "Active" : "Banned",
                style: TextStyle(
                  color: isActive ? Colors.green : Colors.red,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}