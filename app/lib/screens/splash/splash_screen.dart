import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/auth_provider.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_theme.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});
  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {

  late AnimationController _titleCtrl;
  late AnimationController _lineCtrl;
  late AnimationController _subCtrl;
  late AnimationController _tagCtrl;
  late AnimationController _loaderCtrl;

  late Animation<double> _titleOpacity;
  late Animation<Offset> _titleSlide;
  late Animation<double> _lineWidth;
  late Animation<double> _subOpacity;
  late Animation<double> _tagOpacity;
  late Animation<double> _loaderOpacity;

  @override
  void initState() {
    super.initState();
    _titleCtrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _lineCtrl   = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _subCtrl    = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _tagCtrl    = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _loaderCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));

    _titleOpacity = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: _titleCtrl, curve: Curves.easeOut));
    _titleSlide   = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(CurvedAnimation(parent: _titleCtrl, curve: Curves.easeOut));
    _lineWidth    = Tween<double>(begin: 0, end: 52).animate(CurvedAnimation(parent: _lineCtrl,  curve: Curves.easeOut));
    _subOpacity   = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: _subCtrl,   curve: Curves.easeIn));
    _tagOpacity   = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: _tagCtrl,   curve: Curves.easeIn));
    _loaderOpacity= Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: _loaderCtrl,curve: Curves.easeIn));

    _runSequence();
  }

  Future<void> _runSequence() async {
    final prefs = await SharedPreferences.getInstance();
    final isFirstLaunch = prefs.getBool('hasLaunched') != true;

    if (isFirstLaunch) {
      await prefs.setBool('hasLaunched', true);
      await Future.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;
      _titleCtrl.forward();
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      _lineCtrl.forward();
      await Future.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;
      _subCtrl.forward();
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      _tagCtrl.forward();
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      _loaderCtrl.forward();
      await Future.delayed(const Duration(milliseconds: 1200));
    }

    // v5.2.1 (Apr 2026): removed the hardcoded Render wake-up ping. The
    // internal app now targets a LAN backend (see AppConfig.apiBaseUrl),
    // which does not cold-start. No wake-up needed.

    // ★ FIX: อ่าน ref ก่อน async gap เพื่อป้องกัน "ref after dispose"
    int waitCount = 0;
    while (mounted && waitCount < 30) {
      final auth = ref.read(authProvider);
      if (!auth.isLoading) break;
      await Future.delayed(const Duration(milliseconds: 100));
      waitCount++;
    }

    if (!mounted) return;

    // ★ FIX: อ่าน auth state ครั้งเดียว แล้วเก็บไว้ก่อน navigate
    final auth = ref.read(authProvider);
    final targetRoute = auth.isAuthenticated ? '/home' : '/login';

    if (!mounted) return;
    context.go(targetRoute);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _lineCtrl.dispose();
    _subCtrl.dispose();
    _tagCtrl.dispose();
    _loaderCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(children: [
        Center(child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SlideTransition(
              position: _titleSlide,
              child: FadeTransition(
                opacity: _titleOpacity,
                child: RichText(text: const TextSpan(children: [
                  TextSpan(text: 'SCENT ', style: TextStyle(
                    fontFamily: AppTheme.fontFamily, fontSize: 24, fontWeight: FontWeight.w700,
                    letterSpacing: 5, color: Colors.white)),
                  TextSpan(text: '& SENSE', style: TextStyle(
                    fontFamily: AppTheme.fontFamily, fontSize: 24, fontWeight: FontWeight.w700,
                    letterSpacing: 5, color: AppColors.primary)),
                ])),
              ),
            ),
            const SizedBox(height: 10),
            AnimatedBuilder(
              animation: _lineWidth,
              builder: (_, __) => Container(
                width: _lineWidth.value, height: 1.5,
                decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 8),
            FadeTransition(
              opacity: _subOpacity,
              child: const Text('L A B O R A T O R Y', style: TextStyle(fontSize: 9, letterSpacing: 6, color: AppColors.textMuted)),
            ),
            const SizedBox(height: 12),
            FadeTransition(
              opacity: _tagOpacity,
              child: Text('"Make Every Breath Special"', style: TextStyle(
                fontSize: 11, fontStyle: FontStyle.italic,
                color: AppColors.textMuted.withValues(alpha: 0.7))),
            ),
          ],
        )),
        Positioned(
          bottom: 48, left: 0, right: 0,
          child: FadeTransition(
            opacity: _loaderOpacity,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _PulseDot(delay: const Duration(milliseconds: 0)),
              const SizedBox(width: 7),
              _PulseDot(delay: const Duration(milliseconds: 200)),
              const SizedBox(width: 7),
              _PulseDot(delay: const Duration(milliseconds: 400)),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _PulseDot extends StatefulWidget {
  final Duration delay;
  const _PulseDot({required this.delay});
  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _anim = Tween<double>(begin: 0.2, end: 1.0).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    Future.delayed(widget.delay, () { if (mounted) _ctrl.repeat(reverse: true); });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _anim,
    child: Container(width: 5, height: 5,
      decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.primary)),
  );
}
