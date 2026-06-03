import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';
import 'package:geocoding/geocoding.dart' as geocoding;

class MapAddressPickerScreen extends StatefulWidget {
  const MapAddressPickerScreen({super.key});

  @override
  State<MapAddressPickerScreen> createState() => _MapAddressPickerScreenState();
}

class _MapAddressPickerScreenState extends State<MapAddressPickerScreen> {
  late GoogleMapController _controller;
  final Location _location = Location();
  LatLng? _currentPosition;
  final Set<Marker> _markers = {};
  
  // Trạng thái UI
  String _selectedAddress = '';
  bool _isLoadingAddress = false;
  
  // Màu chủ đạo
  final Color _primaryColor = const Color(0xFF2E86C1);

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isLoadingAddress = true);
    
    bool serviceEnabled = await _location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await _location.requestService();
      if (!serviceEnabled) {
        setState(() => _isLoadingAddress = false);
        return;
      }
    }

    PermissionStatus permission = await _location.hasPermission();
    if (permission == PermissionStatus.denied) {
      permission = await _location.requestPermission();
      if (permission != PermissionStatus.granted) {
        setState(() => _isLoadingAddress = false);
        return;
      }
    }

    LocationData locationData = await _location.getLocation();
    LatLng currentLatLng = LatLng(locationData.latitude!, locationData.longitude!);
    
    setState(() {
      _currentPosition = currentLatLng;
      _addMarker(currentLatLng);
    });
    
    // Di chuyển camera đến vị trí hiện tại
    _controller.animateCamera(CameraUpdate.newLatLngZoom(currentLatLng, 16));
    
    await _getAddressFromLatLng(currentLatLng);
  }

  void _addMarker(LatLng position) {
    setState(() {
      _markers.clear();
      _markers.add(
        Marker(
          markerId: const MarkerId('selected'),
          position: position,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
      );
    });
  }

  // Hàm format địa chỉ sạch sẽ hơn
  String _formatAddress(geocoding.Placemark place) {
    List<String> components = [
      place.street ?? '',
      place.subAdministrativeArea ?? '',
      place.administrativeArea ?? '',
      place.country ?? ''
    ];
    return components.where((element) => element.isNotEmpty).join(', ');
  }

  Future<void> _getAddressFromLatLng(LatLng position) async {
    setState(() {
      _isLoadingAddress = true;
      _selectedAddress = 'Đang lấy địa chỉ...';
    });

    try {
      List<geocoding.Placemark> placemarks =
          await geocoding.placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      
      if (placemarks.isNotEmpty) {
        String formattedAddress = _formatAddress(placemarks[0]);
        setState(() {
          _selectedAddress = formattedAddress;
        });
      }
    } catch (e) {
      setState(() {
        _selectedAddress = 'Không thể định vị địa chỉ này';
      });
    } finally {
      setState(() {
        _isLoadingAddress = false;
      });
    }
  }

  void _onMapTap(LatLng position) {
    _addMarker(position);
    _getAddressFromLatLng(position);
  }
  
  void _confirmSelection() {
    if (_selectedAddress.isNotEmpty && !_isLoadingAddress) {
      // Return the selected address to the caller.
      Navigator.pop(context, _selectedAddress);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 1. Bản đồ (Full màn hình)
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _currentPosition ?? const LatLng(21.028511, 105.854444),
              zoom: 15,
            ),
            markers: _markers,
            myLocationEnabled: true,
            myLocationButtonEnabled: false, 
            zoomControlsEnabled: false,
            onMapCreated: (controller) => _controller = controller,
            onTap: _onMapTap,
            // Đẩy logo Google lên cao để không bị khu vực bottom che mất
            padding: const EdgeInsets.only(bottom: 280), 
          ),

          // 2. Header Area
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 16,
            right: 16,
            child: Container(
              height: 50,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(25),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Expanded(
                    child: Text(
                      "Chọn vị trí giao hàng",
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.search),
                    onPressed: () {},
                  ),
                ],
              ),
            ),
          ),

          // 3. CỤM BOTTOM (Gồm Nút Định Vị + Thẻ Địa Chỉ)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min, // Chỉ chiếm chiều cao vừa đủ nội dung
              crossAxisAlignment: CrossAxisAlignment.end, // Đẩy nút FAB sang phải
              children: [
                
                // A. Nút Vị trí hiện tại (Luôn nằm trên thẻ)
                Padding(
                  padding: const EdgeInsets.only(right: 16, bottom: 16),
                  child: FloatingActionButton(
                    backgroundColor: Colors.white,
                    foregroundColor: _primaryColor,
                    onPressed: _getCurrentLocation,
                    elevation: 4,
                    child: const Icon(Icons.my_location),
                  ),
                ),

                // B. Thẻ thông tin địa chỉ
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 20,
                        offset: Offset(0, -5),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 20),
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      
                      Text(
                        'Địa chỉ đã chọn',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 10),
                      
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.location_on, color: _primaryColor, size: 28),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _isLoadingAddress
                                ? Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(width: 150, height: 15, color: Colors.grey[200]),
                                      const SizedBox(height: 5),
                                      Container(width: 100, height: 15, color: Colors.grey[200]),
                                    ],
                                  )
                                : Text(
                                    _selectedAddress.isEmpty
                                        ? 'Chạm vào bản đồ để chọn'
                                        : _selectedAddress,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      height: 1.3,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: (_selectedAddress.isNotEmpty && !_isLoadingAddress)
                              ? _confirmSelection
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primaryColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          child: _isLoadingAddress
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'Xác nhận địa chỉ này',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}