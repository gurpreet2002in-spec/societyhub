import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../services/api_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/unit_labels.dart';

class LoginScreen extends ConsumerStatefulWidget {
  final String? societyId;
  final String? societySlug;
  const LoginScreen({super.key, this.societyId, this.societySlug});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();
  final _flatController = TextEditingController();
  String _occupancy = 'owner';
  bool _isLoading = false;
  late bool _isLogin;
  bool _obscurePassword = true;
  String? _currentSocietyId;
  String? _currentSocietyName;
  // Society type ('apartments' | 'villas' | 'mixed') — decides "Flat" vs "House".
  String? _propertyType;
  String _unitType = 'flat';
  String? _codeSocietyName;
  Timer? _codeDebounce;

  @override
  void initState() {
    super.initState();
    _isLogin = (widget.societyId == null && widget.societySlug == null);
    _currentSocietyId = widget.societyId;
    _codeController.addListener(_onCodeChanged);
    _loadSocietyBySlug();
  }

  @override
  void dispose() {
    _codeDebounce?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _codeController.dispose();
    _flatController.dispose();
    super.dispose();
  }

  // Look the code up shortly after the resident stops typing, so the form
  // can say "Flat" or "House" to match their society.
  void _onCodeChanged() {
    _codeDebounce?.cancel();
    final code = _codeController.text.trim();
    if (code.length < 4) {
      if (_codeSocietyName != null || _propertyType != null) {
        setState(() { _codeSocietyName = null; _propertyType = null; });
      }
      return;
    }
    _codeDebounce = Timer(const Duration(milliseconds: 600), () async {
      try {
        final soc = await ref.read(apiServiceProvider).getSocietyByCode(code);
        if (!mounted || _codeController.text.trim() != code) return;
        setState(() {
          _codeSocietyName = soc?['name'];
          _propertyType = soc?['property_type'];
        });
      } catch (_) {}
    });
  }

  String? get _effectiveUnitType {
    switch (_propertyType) {
      case 'villas':
        return 'house';
      case 'mixed':
        return _unitType;
      case 'apartments':
        return 'flat';
      default:
        return null;
    }
  }

  Future<void> _loadSocietyBySlug() async {
    if (widget.societySlug != null) {
      setState(() => _isLoading = true);
      try {
        final society = await ref.read(apiServiceProvider).getSocietyBySlug(widget.societySlug!);
        if (society != null) {
          setState(() {
            _currentSocietyId = society['id'];
            _currentSocietyName = society['name'];
            _propertyType = society['property_type'];
            _isLogin = true; // Default to login if slug is provided
          });
        }
      } catch (e) {
        // Fallback to normal if error
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _submit() async {
    setState(() => _isLoading = true);
    try {
      if (_isLogin) {
        await ref.read(authProvider.notifier).login(
          _emailController.text,
          _passwordController.text,
        );
      } else {
        if (_nameController.text.trim().isEmpty ||
            _emailController.text.trim().isEmpty ||
            _passwordController.text.length < 8) {
          throw Exception('Enter your name, email and a password of at least 8 characters.');
        }
        if (_flatController.text.trim().isEmpty) {
          throw Exception('Enter your ${unitNoun(_propertyType ?? 'mixed', unitType: _effectiveUnitType).toLowerCase()} number.');
        }
        String? joinCode;
        if (_currentSocietyId == null) {
          // No society link: the resident must enter their society's code.
          joinCode = _codeController.text.trim().toUpperCase();
          if (joinCode.isEmpty) {
            throw Exception('Enter the society code from your society admin.');
          }
          final society = await ref.read(apiServiceProvider).getSocietyByCode(joinCode);
          if (society == null) {
            throw Exception('Invalid society code. Check it with your society admin.');
          }
          if (society['property_type'] == 'mixed' && _propertyType != 'mixed') {
            // The Flat / House choice wasn't on screen yet — show it first.
            setState(() => _propertyType = 'mixed');
            throw Exception('Please choose whether you live in a flat or a house / villa.');
          }
          _propertyType = society['property_type'] ?? _propertyType;
          if (!mounted) return;
          setState(() => _isLoading = false);
          final ok = await showDialog<bool>(
            context: context,
            builder: (dCtx) => AlertDialog(
              title: Text('Join ${society['name']}?'),
              content: const Text(
                  'Your request goes to the society admin. You can use the app once they approve you.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.pop(dCtx, true), child: const Text('Yes, join')),
              ],
            ),
          );
          if (ok != true || !mounted) return;
          setState(() => _isLoading = true);
        }
        await ref.read(authProvider.notifier).register(
          _nameController.text,
          _emailController.text,
          _passwordController.text,
          societyId: _currentSocietyId,
          joinCode: joinCode,
          flat: _flatController.text.trim(),
          occupancyType: _occupancy,
          unitType: _effectiveUnitType,
        );
      }
      if (!mounted) return;
      final user = ref.read(apiServiceProvider).user;
      final role = user?['role'];
      final status = user?['status'];
      if (role == 'super_admin') {
        context.go('/super_admin/dashboard');
      } else if (user?['society_id'] == null || (status != null && status != 'active')) {
        context.go('/pending');
      } else if (role == 'guard') {
        context.go('/guard/dashboard');
      } else {
        context.go('/dashboard');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().replaceAll('Exception: ', ''),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: Stack(
        children: [
          // \u2500\u2500 Soft background gradients (Stitch style) \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
          Positioned(
            top: 0,
            right: 0,
            child: Container(
              width: 200,
              height: 300,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [AppTheme.primaryFixed.withValues(alpha: 0.4), Colors.transparent],
                  radius: 1.0,
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            child: Container(
              width: 160,
              height: 200,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [AppTheme.secondaryContainer.withValues(alpha: 0.25), Colors.transparent],
                  radius: 1.0,
                ),
              ),
            ),
          ),

          // \u2500\u2500 Main content \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // \u2500\u2500 Branding \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
                    Column(
                      children: [
                        Transform.rotate(
                          angle: -0.1,
                          child: Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: AppTheme.primaryContainer,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.primary.withValues(alpha: 0.3),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: const Icon(Icons.apartment_rounded, color: Colors.white, size: 36),
                          ),
                        ),
                        const SizedBox(height: 28),
                        Text(
                          _currentSocietyName != null
                              ? (_isLogin ? 'Welcome to $_currentSocietyName' : 'Join $_currentSocietyName')
                              : (_isLogin ? 'Welcome to Elite Living' : 'Join Elite Living'),
                          style: GoogleFonts.manrope(
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.onSurface,
                            letterSpacing: -1.0,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _isLogin
                              ? 'Sign in to access your community'
                              : 'Create your resident account',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: AppTheme.onSurfaceVariant,
                            fontWeight: FontWeight.w400,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),

                    const SizedBox(height: 48),

                    // \u2500\u2500 Login Card \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
                    Container(
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 50,
                            offset: const Offset(0, 20),
                          ),
                        ],
                        border: Border.all(
                          color: AppTheme.outlineVariant.withValues(alpha: 0.15),
                        ),
                      ),
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Name field (register only)
                          if (!_isLogin) ...[
                            _StitchLabel(label: 'Full Name'),
                            const SizedBox(height: 8),
                            _StitchField(
                              controller: _nameController,
                              hint: 'Your full name',
                              prefixIcon: Icons.person_outlined,
                            ),
                            const SizedBox(height: 24),
                            if (_currentSocietyId == null) ...[
                              _StitchLabel(label: 'Society Code'),
                              const SizedBox(height: 8),
                              _StitchField(
                                controller: _codeController,
                                hint: 'e.g. EKTA-7F3K',
                                prefixIcon: Icons.apartment_rounded,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _codeSocietyName != null
                                    ? '\u2713 $_codeSocietyName'
                                    : 'Ask your society admin for this code.',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: _codeSocietyName != null ? FontWeight.w600 : FontWeight.normal,
                                  color: _codeSocietyName != null ? Colors.green.shade700 : AppTheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 24),
                            ],
                            if (_propertyType == 'mixed') ...[
                              _StitchLabel(label: 'I live in a'),
                              const SizedBox(height: 8),
                              SegmentedButton<String>(
                                segments: const [
                                  ButtonSegment(value: 'flat', label: Text('Flat'), icon: Icon(Icons.apartment_rounded)),
                                  ButtonSegment(value: 'house', label: Text('House / Villa'), icon: Icon(Icons.house_outlined)),
                                ],
                                selected: {_unitType},
                                onSelectionChanged: (s) => setState(() => _unitType = s.first),
                              ),
                              const SizedBox(height: 16),
                            ],
                            _StitchLabel(label: unitNumberLabel(_propertyType ?? 'mixed', unitType: _effectiveUnitType)),
                            const SizedBox(height: 8),
                            _StitchField(
                              controller: _flatController,
                              hint: unitHint(_propertyType ?? 'mixed', unitType: _effectiveUnitType),
                              prefixIcon: unitIcon(_propertyType ?? 'mixed', unitType: _effectiveUnitType),
                            ),
                            const SizedBox(height: 12),
                            SegmentedButton<String>(
                              segments: const [
                                ButtonSegment(value: 'owner', label: Text('Owner'), icon: Icon(Icons.home_outlined)),
                                ButtonSegment(value: 'tenant', label: Text('Tenant'), icon: Icon(Icons.key_outlined)),
                              ],
                              selected: {_occupancy},
                              onSelectionChanged: (s) => setState(() => _occupancy = s.first),
                            ),
                            const SizedBox(height: 24),
                          ],

                          // Email
                          _StitchLabel(label: 'Email Address'),
                          const SizedBox(height: 8),
                          _StitchField(
                            controller: _emailController,
                            hint: 'you@example.com',
                            prefixIcon: Icons.email_outlined,
                            keyboardType: TextInputType.emailAddress,
                          ),
                          const SizedBox(height: 24),

                          // Password
                          _StitchLabel(label: 'Password'),
                          const SizedBox(height: 8),
                          _StitchField(
                            controller: _passwordController,
                            hint: '\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022',
                            prefixIcon: Icons.lock_outline_rounded,
                            obscureText: _obscurePassword,
                            suffixIcon: GestureDetector(
                              onTap: () => setState(() => _obscurePassword = !_obscurePassword),
                              child: Icon(
                                _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                color: AppTheme.onSurfaceVariant,
                                size: 20,
                              ),
                            ),
                          ),

                          const SizedBox(height: 32),

                          // \u2500\u2500 CTA Button \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
                          GestureDetector(
                            onTap: _isLoading ? null : _submit,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              height: 56,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [AppTheme.primaryContainer, AppTheme.primary],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(50),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppTheme.primary.withValues(alpha: 0.25),
                                    blurRadius: 16,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              alignment: Alignment.center,
                              child: _isLoading
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2.5,
                                      ),
                                    )
                                  : Text(
                                      _isLogin ? 'SIGN IN' : 'CREATE ACCOUNT',
                                      style: GoogleFonts.inter(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                        letterSpacing: 1.5,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 28),

                    // \u2500\u2500 Toggle login/register \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
                    GestureDetector(
                      onTap: () => setState(() => _isLogin = !_isLogin),
                      child: Text(
                        _isLogin
                            ? 'New resident? Register here \u2192'
                            : 'Already registered? Sign in \u2192',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),

                    const SizedBox(height: 32),

                    // \u2500\u2500 Security badge \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.verified_user_outlined,
                            size: 14, color: AppTheme.outlineVariant),
                        const SizedBox(width: 6),
                        Text(
                          'SECURE BANK-GRADE ENCRYPTION',
                          style: GoogleFonts.inter(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.0,
                            color: AppTheme.outlineVariant,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    Text(
                      'By continuing, you agree to our Terms of Service',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: AppTheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StitchLabel extends StatelessWidget {
  final String label;
  const _StitchLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        label.toUpperCase(),
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
          color: AppTheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _StitchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData prefixIcon;
  final bool obscureText;
  final Widget? suffixIcon;
  final TextInputType? keyboardType;

  const _StitchField({
    required this.controller,
    required this.hint,
    required this.prefixIcon,
    this.obscureText = false,
    this.suffixIcon,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      style: GoogleFonts.inter(
        fontWeight: FontWeight.w600,
        fontSize: 14,
        color: AppTheme.onSurface,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.inter(
          color: AppTheme.outlineVariant,
          fontWeight: FontWeight.w400,
        ),
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 16, right: 12),
          child: Icon(prefixIcon, color: AppTheme.onSurfaceVariant, size: 20),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        suffixIcon: suffixIcon != null
            ? Padding(padding: const EdgeInsets.only(right: 16), child: suffixIcon)
            : null,
        suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        filled: true,
        fillColor: AppTheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppTheme.primary.withValues(alpha: 0.3), width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }
}
