import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:tropia_mobile_app_android/livestream/core/constants/app_constants.dart';
import 'package:tropia_mobile_app_android/livestream/core/services/auth_service.dart';
import 'package:tropia_mobile_app_android/livestream/core/utils/logger.dart';
import 'package:tropia_mobile_app_android/livestream/features/main/screens/main_screen.dart';

const _tag = 'LoginScreen';

String _apiError(DioException e, String fallback) {
  final data = e.response?.data;
  if (data is Map) {
    return (data['error'] ?? data['message'] ?? fallback) as String;
  }
  return fallback;
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey      = GlobalKey<FormState>();
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool _isLoading    = false;
  bool _obscurePass  = true;
  bool _isRegister   = false;
  final _nameCtrl     = TextEditingController();
  final _phoneCtrl    = TextEditingController();
  final _shopCtrl     = TextEditingController();
  String _role        = 'buyer';

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _shopCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      if (_isRegister) {
        await AuthService.instance.register(
          email:    _emailCtrl.text.trim(),
          password: _passwordCtrl.text,
          name:     _nameCtrl.text.trim(),
          role:     _role,
          phone:    _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
          shopName: _role == 'seller' && _shopCtrl.text.trim().isNotEmpty
              ? _shopCtrl.text.trim() : null,
        );
        AppLogger.logUserEvent(action: 'register_success', context: _tag);
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => VerifyEmailScreen(
                email:    _emailCtrl.text.trim(),
                password: _passwordCtrl.text,
              ),
            ),
          );
        }
        return;
      }
      await AuthService.instance.login(
        username: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );
      AppLogger.logUserEvent(action: 'login_success', context: _tag);
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const MainScreen()),
          (_) => false,
        );
      }
    } on DioException catch (e) {
      _showError(_apiError(e, 'Lỗi kết nối máy chủ'));
      AppLogger.logError(_tag, 'Login/register failed', e, null);
    } catch (e) {
      _showError('Có lỗi xảy ra, thử lại sau');
      AppLogger.logError(_tag, 'Unexpected error', e, null);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loginGoogle() async {
    try {
      await AuthService.instance.loginWithGoogle();
    } catch (e) {
      _showError('Không thể mở đăng nhập Google');
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red[700]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSizes.lg),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: AppSizes.xxl),

                // Logo
                const Icon(Icons.eco, size: 64, color: AppColors.primary),
                const SizedBox(height: AppSizes.sm),
                const Text(
                  'Tropia',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: AppSizes.xs),
                Text(
                  _isRegister ? 'Tạo tài khoản mới' : 'Đăng nhập để tiếp tục',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: AppSizes.fontMd,
                    color: AppColors.textSecondary,
                  ),
                ),

                const SizedBox(height: AppSizes.xxl),

                // Register-only fields
                if (_isRegister) ...[
                  _Field(
                    controller: _nameCtrl,
                    label: 'Họ tên',
                    icon: Icons.person_outline,
                    validator: (v) => (v == null || v.trim().length < 2)
                        ? 'Nhập tên ít nhất 2 ký tự' : null,
                  ),
                  const SizedBox(height: AppSizes.md),
                  _Field(
                    controller: _phoneCtrl,
                    label: 'Số điện thoại',
                    icon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Nhập số điện thoại';
                      if (!RegExp(r'^(0|\+84)\d{9}$').hasMatch(v.trim())) {
                        return 'Số điện thoại không hợp lệ';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: AppSizes.md),
                ],

                // Email (đăng ký) / SĐT hoặc Email (đăng nhập)
                _Field(
                  controller: _emailCtrl,
                  label: _isRegister ? 'Email' : 'SĐT hoặc Email',
                  icon: _isRegister ? Icons.email_outlined : Icons.account_circle_outlined,
                  keyboardType:
                      _isRegister ? TextInputType.emailAddress : TextInputType.text,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return _isRegister ? 'Nhập email' : 'Nhập SĐT hoặc email';
                    }
                    if (_isRegister && !v.contains('@')) return 'Email không hợp lệ';
                    return null;
                  },
                ),
                const SizedBox(height: AppSizes.md),

                // Password
                _Field(
                  controller: _passwordCtrl,
                  label: 'Mật khẩu',
                  icon: Icons.lock_outline,
                  obscureText: _obscurePass,
                  suffix: IconButton(
                    icon: Icon(_obscurePass
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscurePass = !_obscurePass),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Nhập mật khẩu';
                    if (_isRegister) {
                      if (v.length < 8) return 'Tối thiểu 8 ký tự';
                      if (!v.contains(RegExp(r'[A-Z]'))) return 'Phải có chữ in hoa';
                      if (!v.contains(RegExp(r'[0-9]'))) return 'Phải có số';
                    }
                    return null;
                  },
                ),

                // Role selector (register only)
                if (_isRegister) ...[
                  const SizedBox(height: AppSizes.md),
                  Row(children: [
                    Expanded(
                      child: _RoleChip(
                        label: 'Người mua',
                        icon: Icons.person_outline,
                        selected: _role == 'buyer',
                        onTap: () => setState(() => _role = 'buyer'),
                      ),
                    ),
                    const SizedBox(width: AppSizes.sm),
                    Expanded(
                      child: _RoleChip(
                        label: 'Người bán',
                        icon: Icons.storefront,
                        selected: _role == 'seller',
                        onTap: () => setState(() => _role = 'seller'),
                      ),
                    ),
                  ]),
                  // Shop name — chỉ hiện khi chọn Người bán
                  if (_role == 'seller') ...[
                    const SizedBox(height: AppSizes.md),
                    _Field(
                      controller: _shopCtrl,
                      label: 'Tên cửa hàng',
                      icon: Icons.store_outlined,
                      validator: (v) {
                        if (_role == 'seller' && (v == null || v.trim().length < 2)) {
                          return 'Nhập tên cửa hàng ít nhất 2 ký tự';
                        }
                        return null;
                      },
                    ),
                  ],
                ],

                const SizedBox(height: AppSizes.xl),

                // Submit button
                FilledButton(
                  onPressed: _isLoading ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white,
                          ),
                        )
                      : Text(
                          _isRegister ? 'Đăng ký' : 'Đăng nhập',
                          style: const TextStyle(
                            fontSize: AppSizes.fontMd,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),

                const SizedBox(height: AppSizes.md),

                // Google login
                OutlinedButton.icon(
                  onPressed: _isLoading ? null : _loginGoogle,
                  icon: const Icon(Icons.g_mobiledata, size: 24),
                  label: const Text('Tiếp tục với Google'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                    ),
                  ),
                ),

                const SizedBox(height: AppSizes.lg),

                // Forgot password (login mode only)
                if (!_isRegister) ...[
                  Align(
                    alignment: Alignment.centerRight,
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
                      ),
                      child: const Text(
                        'Quên mật khẩu?',
                        style: TextStyle(color: AppColors.primary, fontSize: AppSizes.fontSm),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSizes.sm),
                ],

                // Toggle login/register
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _isRegister ? 'Đã có tài khoản? ' : 'Chưa có tài khoản? ',
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _isRegister = !_isRegister),
                      child: Text(
                        _isRegister ? 'Đăng nhập' : 'Đăng ký ngay',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final Widget? suffix;

  const _Field({
    required this.controller,
    required this.label,
    required this.icon,
    this.obscureText = false,
    this.keyboardType,
    this.validator,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller:   controller,
      obscureText:  obscureText,
      keyboardType: keyboardType,
      validator:    validator,
      decoration: InputDecoration(
        labelText:   label,
        prefixIcon:  Icon(icon, color: AppColors.textSecondary),
        suffixIcon:  suffix,
        border:      OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        ),
        filled:      true,
        fillColor:   AppColors.surface,
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _RoleChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryContainer : AppColors.surface,
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.divider,
            width: selected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16,
                color: selected ? AppColors.primary : AppColors.textSecondary),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: AppSizes.fontSm,
                fontWeight: FontWeight.w600,
                color: selected ? AppColors.primary : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// VerifyEmailScreen  – nhập OTP 6 số sau khi đăng ký
// ─────────────────────────────────────────────────────────────────────────────

class VerifyEmailScreen extends StatefulWidget {
  final String email;
  final String password;
  const VerifyEmailScreen({super.key, required this.email, required this.password});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final List<TextEditingController> _otpCtrls =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  bool _isVerifying = false;
  bool _isResending = false;
  bool _resentOk    = false;
  int  _resendCooldown = 0;

  @override
  void dispose() {
    for (final c in _otpCtrls) c.dispose();
    for (final f in _focusNodes) f.dispose();
    super.dispose();
  }

  String get _otpValue => _otpCtrls.map((c) => c.text).join();

  Future<void> _verify() async {
    final otp = _otpValue;
    if (otp.length != 6) {
      _showError('Vui lòng nhập đủ 6 số');
      return;
    }
    setState(() => _isVerifying = true);
    try {
      await AuthService.instance.verifyOtp(email: widget.email, otp: otp);
      // Auto-login sau xác thực OTP (email cũng là username hợp lệ)
      await AuthService.instance.login(
        username: widget.email,
        password: widget.password,
      );
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const MainScreen()),
          (_) => false,
        );
      }
    } on DioException catch (e) {
      _showError(_apiError(e, 'Mã OTP không đúng'));
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  Future<void> _resend() async {
    if (_resendCooldown > 0) return;
    setState(() { _isResending = true; _resentOk = false; });
    try {
      await AuthService.instance.resendVerifyEmail(widget.email);
      if (mounted) {
        setState(() { _resentOk = true; _resendCooldown = 60; });
        _startCooldown();
      }
    } on DioException catch (e) {
      _showError(_apiError(e, 'Lỗi kết nối'));
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  void _startCooldown() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() => _resendCooldown--);
      return _resendCooldown > 0;
    });
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red[700]),
    );
  }

  void _onOtpChanged(int index, String value) {
    if (value.length > 1) {
      // Paste: distribute digits across boxes
      final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
      for (int i = 0; i < 6 && i < digits.length; i++) {
        _otpCtrls[i].text = digits[i];
        _otpCtrls[i].selection = TextSelection.collapsed(offset: 1);
      }
      final next = (digits.length < 6) ? digits.length : 5;
      _focusNodes[next].requestFocus();
      if (_otpValue.length == 6) _verify();
      return;
    }
    if (value.length == 1 && index < 5) {
      _focusNodes[index + 1].requestFocus();
    } else if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
    if (_otpValue.length == 6) _verify();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSizes.lg),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height
                  - MediaQuery.of(context).padding.top
                  - MediaQuery.of(context).padding.bottom
                  - AppSizes.lg * 2,
            ),
            child: IntrinsicHeight(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
              const Icon(Icons.verified_outlined, size: 72, color: AppColors.primary),
              const SizedBox(height: AppSizes.md),
              const Text(
                'Xác thực email',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: AppSizes.fontXxl, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSizes.sm),
              Text(
                'Nhập mã OTP 6 số đã gửi đến\n${widget.email}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  height: 1.6,
                  fontSize: AppSizes.fontMd,
                ),
              ),
              const SizedBox(height: AppSizes.xxl),

              // ── 6 ô OTP ───────────────────────────────────────────────────
              Row(
                children: List.generate(6, (i) => Expanded(
                  child: _OtpBox(
                    controller: _otpCtrls[i],
                    focusNode:  _focusNodes[i],
                    onChanged:  (v) => _onOtpChanged(i, v),
                    autofocus:  i == 0,
                  ),
                )),
              ),

              const SizedBox(height: AppSizes.xxl),

              // ── Nút xác thực ──────────────────────────────────────────────
              FilledButton(
                onPressed: _isVerifying ? null : _verify,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                  ),
                ),
                child: _isVerifying
                    ? const SizedBox(
                        width: 22, height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text(
                        'Xác thực',
                        style: TextStyle(fontSize: AppSizes.fontMd, fontWeight: FontWeight.w600),
                      ),
              ),

              const SizedBox(height: AppSizes.md),

              // ── Gửi lại OTP ───────────────────────────────────────────────
              if (_resentOk && _resendCooldown > 0)
                Center(
                  child: Text(
                    'Đã gửi lại! Gửi lại sau ${_resendCooldown}s',
                    style: const TextStyle(color: AppColors.primary, fontSize: AppSizes.fontSm),
                  ),
                )
              else
                TextButton(
                  onPressed: (_isResending || _resendCooldown > 0) ? null : _resend,
                  child: _isResending
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Gửi lại mã OTP'),
                ),

              TextButton(
                onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (_) => false,
                ),
                child: const Text(
                  'Quay lại đăng nhập',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OtpBox extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final bool autofocus;

  const _OtpBox({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        border: Border.all(color: AppColors.divider, width: 1.5),
      ),
      child: TextField(
        controller:  controller,
        focusNode:   focusNode,
        autofocus:   autofocus,
        textAlign:   TextAlign.center,
        keyboardType: TextInputType.number,
        maxLength:   1,
        onChanged:   onChanged,
        enableInteractiveSelection: false,
        style: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
        decoration: const InputDecoration(
          counterText: '',
          border:      InputBorder.none,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ForgotPasswordScreen
// ─────────────────────────────────────────────────────────────────────────────

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey   = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  bool _isLoading  = false;
  bool _sent       = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      await AuthService.instance.forgotPassword(_emailCtrl.text.trim());
      if (mounted) setState(() => _sent = true);
    } on DioException catch (e) {
      final msg = _apiError(e, 'Lỗi kết nối');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red[700]),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Quên mật khẩu'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.lg),
          child: _sent ? _buildSuccess() : _buildForm(),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSizes.xl),
          const Icon(Icons.lock_reset, size: 64, color: AppColors.primary),
          const SizedBox(height: AppSizes.md),
          const Text(
            'Nhập email đã đăng ký để nhận link đặt lại mật khẩu.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, height: 1.5),
          ),
          const SizedBox(height: AppSizes.xl),
          _Field(
            controller: _emailCtrl,
            label: 'Email',
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            validator: (v) {
              if (v == null || v.isEmpty) return 'Nhập email';
              if (!v.contains('@')) return 'Email không hợp lệ';
              return null;
            },
          ),
          const SizedBox(height: AppSizes.xl),
          FilledButton(
            onPressed: _isLoading ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSizes.radiusMd),
              ),
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 22, height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Gửi link đặt lại', style: TextStyle(fontSize: AppSizes.fontMd, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccess() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.mark_email_read_outlined, size: 80, color: AppColors.primary),
        const SizedBox(height: AppSizes.md),
        const Text(
          'Đã gửi!',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: AppSizes.fontXxl, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: AppSizes.xs),
        Text(
          'Nếu email ${_emailCtrl.text} tồn tại, bạn sẽ nhận được hướng dẫn trong vài phút.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary, height: 1.5),
        ),
        const SizedBox(height: AppSizes.xl),
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Quay lại đăng nhập'),
        ),
      ],
    );
  }
}
