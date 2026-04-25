// lib/screens/login/login_screen.dart
//
// ── CHANGELOG v6.0 (Apr 2026) ────────────────────────────────────────
//   • Removed the "Forgot password?" link and the entire forgot-password
//     dialog/helper. The backend endpoint was a no-op stub and the flow
//     contradicted the admin-only password policy. Staff who forget
//     their password must now ask an admin, who can reset it via the
//     user-management screen.
// ──────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/auth_provider.dart';
import '../../providers/locale_provider.dart';
import '../../constants/app_strings.dart';
import '../../constants/app_colors.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailC = TextEditingController();
  final _passC = TextEditingController();
  final _passFocus = FocusNode();
  bool _obscure = true;

  @override
  void dispose() {
    _emailC.dispose();
    _passC.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    FocusManager.instance.primaryFocus?.unfocus();
    await ref
        .read(authProvider.notifier)
        .login(_emailC.text.trim(), _passC.text);
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final lang = ref.watch(localeProvider).languageCode;
    String t(String k) => AppStrings.get(k, lang);

    ref.listen<AuthState>(authProvider, (previous, next) {
      if (!mounted) return;
      if (next.isAuthenticated &&
          (previous == null || !previous.isAuthenticated)) {
        context.go('/home');
      }
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding:
                const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 20),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                  width: 5,
                                  height: 5,
                                  decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: AppColors.textMuted)),
                              const SizedBox(width: 6),
                              Container(
                                  width: 5,
                                  height: 5,
                                  decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: AppColors.primary)),
                              const SizedBox(width: 6),
                              Container(
                                  width: 5,
                                  height: 5,
                                  decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: AppColors.textMuted)),
                            ]),
                        const SizedBox(height: 16),
                        RichText(
                            text: const TextSpan(children: [
                          TextSpan(
                              text: 'SCENT ',
                              style: TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  letterSpacing: 5)),
                          TextSpan(
                              text: '& SENSE',
                              style: TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.primary,
                                  letterSpacing: 5)),
                        ])),
                        const SizedBox(height: 4),
                        const Text('LABORATORY',
                            style: TextStyle(
                                fontSize: 10,
                                color: AppColors.textMuted,
                                letterSpacing: 4)),
                        const SizedBox(height: 6),
                        Text('"Make Every Breath Special"',
                            style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary
                                    .withValues(alpha: 0.6),
                                fontStyle: FontStyle.italic)),
                      ],
                    ),
                    const SizedBox(height: 40),
                    Text(t('welcomeBack'),
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                    const SizedBox(height: 4),
                    Text(t('signInContinue'),
                        style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary)),

                    const SizedBox(height: 12),
                    if (auth.error != null &&
                        _isConnectionError(auth.error!))
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF9500)
                              .withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: const Color(0xFFFF9500)
                                  .withValues(alpha: 0.3)),
                        ),
                        child: Row(children: [
                          const Icon(Icons.cloud_off_rounded,
                              color: Color(0xFFFF9500), size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(t('serverUnavailable'),
                                  style: const TextStyle(
                                      color: Color(0xFFFF9500),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500))),
                        ]),
                      ),

                    if (auth.error != null &&
                        !_isConnectionError(auth.error!))
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.error.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: AppColors.error
                                    .withValues(alpha: 0.3)),
                          ),
                          child: Row(children: [
                            const Icon(Icons.error_outline_rounded,
                                color: AppColors.error, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                                child: Text(auth.error!,
                                    style: const TextStyle(
                                        color: AppColors.error,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500))),
                          ]),
                        ),
                      ),

                    const SizedBox(height: 8),
                    _formField(
                      t('email'),
                      _emailC,
                      false,
                      TextInputAction.next,
                      (_) => _passFocus.requestFocus(),
                      (v) => v == null || v.isEmpty
                          ? t('pleaseEnterEmail')
                          : !v.contains('@')
                              ? t('invalidEmail')
                              : null,
                    ),
                    const SizedBox(height: 12),
                    _formField(
                      t('password'),
                      _passC,
                      _obscure,
                      TextInputAction.done,
                      (_) => _login(),
                      (v) => v == null || v.isEmpty
                          ? t('pleaseEnterPassword')
                          : null,
                      focusNode: _passFocus,
                      suffix: IconButton(
                        icon: Icon(
                            _obscure
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: AppColors.textSecondary,
                            size: 20),
                        onPressed: () =>
                            setState(() => _obscure = !_obscure),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: auth.isLoading ? null : _login,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          disabledBackgroundColor:
                              AppColors.primary.withValues(alpha: 0.4),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        child: auth.isLoading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white))
                            : Text(t('login'),
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white)),
                      ),
                    ),
                    if (auth.isLoading)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(t('connectingToServer'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary)),
                      ),
                    const SizedBox(height: 32),
                    const Text('v1.1.0',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 11, color: AppColors.textMuted)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool _isConnectionError(String error) {
    final s = error.toLowerCase();
    return s.contains('wifi') ||
        s.contains('connect') ||
        s.contains('timeout') ||
        s.contains('network') ||
        error.contains('เชื่อมต่อ') ||
        error.contains('เซิร์ฟเวอร์') ||
        error.contains('หมดเวลา');
  }

  Widget _formField(
      String label,
      TextEditingController ctrl,
      bool obscure,
      TextInputAction action,
      Function(String) onSubmit,
      String? Function(String?) validator,
      {FocusNode? focusNode,
      Widget? suffix}) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: TextFormField(
        controller: ctrl,
        obscureText: obscure,
        focusNode: focusNode,
        textInputAction: action,
        onFieldSubmitted: onSubmit,
        validator: validator,
        style:
            const TextStyle(color: AppColors.textPrimary, fontSize: 15),
        decoration: InputDecoration(
          labelText: label,
          labelStyle:
              TextStyle(color: AppColors.textSecondary, fontSize: 14),
          suffixIcon: suffix,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                  color: AppColors.primary, width: 1.5)),
          errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.error)),
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 16),
        ),
      ),
    );
  }
}
