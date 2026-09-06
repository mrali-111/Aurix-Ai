import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math' as math;
import 'login_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final PageController _pageCtrl = PageController();
  int _currentPage = 0;

  late AnimationController _bgCtrl;
  late AnimationController _entryCtrl;
  late Animation<double> _bgAnim;
  late Animation<double> _entryFade;
  late Animation<Offset> _entrySlide;

  final List<_OnboardPage> pages = const [
    _OnboardPage(
      gradient: [Color(0xFF6C3CE1), Color(0xFF3D1FA8)],
      glowColor: Color(0xFF6C3CE1),
      icon: Icons.auto_awesome_rounded,
      iconSecondary: Icons.psychology_alt_rounded,
      title: 'AI That\nUnderstands You',
      subtitle: 'Experience next-gen intelligence powered by the world\'s most advanced language models — Gemini, GPT, Llama & more.',
      badge: '⚡ Powered by Llama 3.3 & Gemini 2.5',
    ),
    _OnboardPage(
      gradient: [Color(0xFFB06AB3), Color(0xFF8E44AD)],
      glowColor: Color(0xFFB06AB3),
      icon: Icons.image_rounded,
      iconSecondary: Icons.mic_rounded,
      title: 'Create, Listen\n& Visualize',
      subtitle: 'Generate stunning AI images, talk with your assistant using voice, and bring your ideas to life in seconds.',
      badge: '🎨 Image + Voice Generation',
    ),
    _OnboardPage(
      gradient: [Color(0xFF00C9A7), Color(0xFF007B6E)],
      glowColor: Color(0xFF00C9A7),
      icon: Icons.workspace_premium_rounded,
      iconSecondary: Icons.alarm_rounded,
      title: 'Stay Organised,\nGo Premium',
      subtitle: 'Smart reminders, daily news, motivational quotes & exclusive Pro features — all in one beautiful app.',
      badge: '👑 Upgrade to Pro — Unlock All',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _bgCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat(reverse: true);
    _entryCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _bgAnim   = CurvedAnimation(parent: _bgCtrl, curve: Curves.easeInOut);
    _entryFade  = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut));
    _entrySlide = Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero).animate(CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic));
    _entryCtrl.forward();
  }

  void _animateEntry() {
    _entryCtrl.reset();
    _entryCtrl.forward();
  }

  @override
  void dispose() {
    _bgCtrl.dispose();
    _entryCtrl.dispose();
    _pageCtrl.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('seen_onboarding', true);
    if (mounted) {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const LoginScreen(),
          transitionDuration: const Duration(milliseconds: 600),
          transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
        ),
      );
    }
  }

  void _next() {
    if (_currentPage < pages.length - 1) {
      _pageCtrl.nextPage(duration: const Duration(milliseconds: 500), curve: Curves.easeInOutCubic);
    } else {
      _finish();
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = pages[_currentPage];
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              page.gradient[0],
              page.gradient[1],
              Colors.black.withOpacity(0.6),
            ],
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // Animated background mesh
            AnimatedBuilder(
              animation: _bgAnim,
              builder: (_, __) => Positioned(
                top: -80 + _bgAnim.value * 30,
                right: -80 + _bgAnim.value * 20,
                child: Container(
                  width: size.width * 0.7,
                  height: size.width * 0.7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.05 + _bgAnim.value * 0.04),
                  ),
                ),
              ),
            ),
            AnimatedBuilder(
              animation: _bgAnim,
              builder: (_, __) => Positioned(
                bottom: -60 - _bgAnim.value * 20,
                left: -60 - _bgAnim.value * 10,
                child: Container(
                  width: size.width * 0.5,
                  height: size.width * 0.5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.04 + _bgAnim.value * 0.03),
                  ),
                ),
              ),
            ),

            // Main content via PageView
            PageView.builder(
              controller: _pageCtrl,
              itemCount: pages.length,
              onPageChanged: (i) {
                setState(() => _currentPage = i);
                _animateEntry();
              },
              itemBuilder: (_, index) => _OnboardContent(
                p: pages[index],
                fadeAnim: _entryFade,
                slideAnim: _entrySlide,
              ),
            ),

            // Bottom controls
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                padding: EdgeInsets.fromLTRB(32, 24, 32, MediaQuery.of(context).padding.bottom + 32),
                child: Column(
                  children: [
                    // Dots
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(pages.length, (i) => AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: i == _currentPage ? 28 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          color: i == _currentPage
                              ? Colors.white
                              : Colors.white.withOpacity(0.35),
                        ),
                      )),
                    ),
                    const SizedBox(height: 28),

                    // Primary CTA button
                    GestureDetector(
                      onTap: _next,
                      child: Container(
                        width: double.infinity,
                        height: 58,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            _currentPage < pages.length - 1 ? 'Continue  →' : 'Get Started  🚀',
                            style: GoogleFonts.sora(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: page.gradient[0],
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Skip
                    if (_currentPage < pages.length - 1)
                      GestureDetector(
                        onTap: _finish,
                        child: Text(
                          'Skip for now',
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.white.withOpacity(0.55),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardContent extends StatelessWidget {
  final _OnboardPage p;
  final Animation<double> fadeAnim;
  final Animation<Offset> slideAnim;

  const _OnboardContent({required this.p, required this.fadeAnim, required this.slideAnim});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return FadeTransition(
      opacity: fadeAnim,
      child: SlideTransition(
        position: slideAnim,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: size.height * 0.12),

              // Icon cluster
              Stack(
                alignment: Alignment.center,
                children: [
                  // Glow ring
                  Container(
                    width: 160,
                    height: 160,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.07),
                    ),
                  ),
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.10),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.white.withOpacity(0.15),
                          blurRadius: 40,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: Icon(p.icon, color: Colors.white, size: 56),
                  ),
                  // Small secondary icon
                  Positioned(
                    right: 16,
                    bottom: 20,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.white.withOpacity(0.1),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: Icon(p.iconSecondary, color: Colors.white, size: 20),
                    ),
                  ),
                ],
              ),

              SizedBox(height: size.height * 0.06),

              // Badge chip
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.3)),
                ),
                child: Text(
                  p.badge,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: Colors.white.withOpacity(0.9),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Title
              Text(
                p.title,
                style: GoogleFonts.sora(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  height: 1.15,
                  letterSpacing: -0.5,
                ),
              ),

              const SizedBox(height: 16),

              // Subtitle
              Text(
                p.subtitle,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  color: Colors.white.withOpacity(0.75),
                  height: 1.6,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardPage {
  final List<Color> gradient;
  final Color glowColor;
  final IconData icon;
  final IconData iconSecondary;
  final String title;
  final String subtitle;
  final String badge;

  const _OnboardPage({
    required this.gradient,
    required this.glowColor,
    required this.icon,
    required this.iconSecondary,
    required this.title,
    required this.subtitle,
    required this.badge,
  });
}
