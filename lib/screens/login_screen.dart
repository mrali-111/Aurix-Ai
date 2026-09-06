import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import 'signup_screen.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginState();
}

class _LoginState extends State<LoginScreen> with TickerProviderStateMixin {
  final email    = TextEditingController();
  final password = TextEditingController();
  final auth     = AuthService();
  bool _isLoading   = false;
  bool _obscurePass = true;
  bool _rememberMe  = true;

  late AnimationController _entryCtrl;
  late AnimationController _bgCtrl;
  late Animation<double>   _fadeAnim;
  late Animation<Offset>   _slideAnim;
  late Animation<double>   _bgAnim;

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _bgCtrl    = AnimationController(vsync: this, duration: const Duration(seconds: 5))..repeat(reverse: true);
    _fadeAnim  = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero)
        .animate(CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic));
    _bgAnim    = CurvedAnimation(parent: _bgCtrl, curve: Curves.easeInOut);
    _entryCtrl.forward();
    _checkAndAutoLogin();
  }

  Future<void> _checkAndAutoLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final savedEmail = prefs.getString('saved_email');
    final savedPass  = prefs.getString('saved_password');
    final remember   = prefs.getBool('remember_me') ?? true;
    final token      = prefs.getString('firebase_token');

    if (token != null || (remember && savedEmail != null && savedPass != null)) {
      if (savedEmail != null) email.text = savedEmail;
      if (savedPass  != null) password.text = savedPass;
      _rememberMe = true;
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    }
  }

  Future<void> _saveCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    if (_rememberMe) {
      await prefs.setString('saved_email', email.text.trim());
      await prefs.setString('saved_password', password.text.trim());
      await prefs.setBool('remember_me', true);
      await prefs.setString('firebase_token', 'logged_in');
    } else {
      await prefs.remove('saved_email');
      await prefs.remove('saved_password');
      await prefs.remove('firebase_token');
      await prefs.setBool('remember_me', false);
    }
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _bgCtrl.dispose();
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> _doLogin() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      await auth.login(email: email.text.trim(), password: password.text.trim());
      await _saveCredentials();
      if (mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', ''),
              style: GoogleFonts.plusJakartaSans()),
          backgroundColor: const Color(0xFF6C3CE1),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          margin: const EdgeInsets.all(16),
        ));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: const Color(0xFFF6F4FF),
      body: Stack(
        children: [
          // Top gradient header
          Positioned(
            top: 0, left: 0, right: 0,
            child: AnimatedBuilder(
              animation: _bgAnim,
              builder: (_, __) => Container(
                height: size.height * 0.42,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color.lerp(const Color(0xFF6C3CE1), const Color(0xFF4A1FA8), _bgAnim.value)!,
                      Color.lerp(const Color(0xFFB06AB3), const Color(0xFF6C3CE1), _bgAnim.value)!,
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Decorative circles on header
          Positioned(top: -60, right: -60,
            child: Blob(size: 200, color: Colors.white.withOpacity(0.07))),
          Positioned(top: 80, left: -40,
            child: Blob(size: 130, color: Colors.white.withOpacity(0.05))),

          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: FadeTransition(
                opacity: _fadeAnim,
                child: SlideTransition(
                  position: _slideAnim,
                  child: Column(
                    children: [
                      const SizedBox(height: 36),

                      // Logo + App Name in header area
                      Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.18),
                          border: Border.all(color: Colors.white.withOpacity(0.35), width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.white.withOpacity(0.15),
                              blurRadius: 20,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 36),
                      ),

                      const SizedBox(height: 16),

                      Text(
                        'AURIX AI',
                        style: GoogleFonts.sora(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 4,
                        ),
                      ),

                      SizedBox(height: size.height * 0.07),

                      // White card
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF6C3CE1).withOpacity(0.12),
                              blurRadius: 40,
                              offset: const Offset(0, 16),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(28),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Welcome Back 👋',
                              style: GoogleFonts.sora(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF1A1A2E),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Sign in to continue your AI journey',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                color: const Color(0xFF9CA3AF),
                              ),
                            ),

                            const SizedBox(height: 28),

                            PremiumField(
                              controller: email,
                              label: 'Email Address',
                              hint: 'you@example.com',
                              icon: Icons.email_outlined,
                              keyboardType: TextInputType.emailAddress,
                            ),

                            const SizedBox(height: 16),

                            PremiumField(
                              controller: password,
                              label: 'Password',
                              hint: '••••••••',
                              icon: Icons.lock_outline_rounded,
                              obscure: _obscurePass,
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePass ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                  color: const Color(0xFF9CA3AF),
                                  size: 20,
                                ),
                                onPressed: () => setState(() => _obscurePass = !_obscurePass),
                              ),
                            ),

                            const SizedBox(height: 12),

                            Row(
                              children: [
                                GestureDetector(
                                  onTap: () => setState(() => _rememberMe = !_rememberMe),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    width: 22, height: 22,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(6),
                                      color: _rememberMe ? const Color(0xFF6C3CE1) : Colors.transparent,
                                      border: Border.all(
                                        color: _rememberMe ? const Color(0xFF6C3CE1) : const Color(0xFFD1D5DB),
                                        width: 1.5,
                                      ),
                                    ),
                                    child: _rememberMe
                                        ? const Icon(Icons.check, color: Colors.white, size: 14)
                                        : null,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text('Remember me',
                                    style: GoogleFonts.plusJakartaSans(fontSize: 13, color: const Color(0xFF6B7280))),
                                const Spacer(),
                                GestureDetector(
                                  onTap: () {},
                                  child: Text(
                                    'Forgot password?',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 13,
                                      color: const Color(0xFF6C3CE1),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 24),

                            PremiumButton(
                              label: 'Sign In',
                              isLoading: _isLoading,
                              onTap: _doLogin,
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 28),

                      // Sign up link
                      GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const SignupScreen()),
                        ),
                        child: RichText(
                          text: TextSpan(
                            text: 'New to Aurix?  ',
                            style: GoogleFonts.plusJakartaSans(
                              color: const Color(0xFF9CA3AF),
                              fontSize: 14,
                            ),
                            children: [
                              TextSpan(
                                text: 'Create Account →',
                                style: GoogleFonts.plusJakartaSans(
                                  color: const Color(0xFF6C3CE1),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────
// Shared reusable widgets
// ─────────────────────────────────────────

class Blob extends StatelessWidget {
  final double size;
  final Color color;
  const Blob({required this.size, required this.color});

  @override
  Widget build(BuildContext context) =>
      Container(width: size, height: size,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color));
}

class PremiumField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final bool obscure;
  final Widget? suffixIcon;
  final TextInputType? keyboardType;

  const PremiumField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.obscure = false,
    this.suffixIcon,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.plusJakartaSans(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: const Color(0xFF374151),
          letterSpacing: 0.3,
        )),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboardType,
          style: GoogleFonts.plusJakartaSans(fontSize: 14, color: const Color(0xFF1A1A2E)),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.plusJakartaSans(fontSize: 14, color: const Color(0xFFD1D5DB)),
            prefixIcon: Container(
              margin: const EdgeInsets.all(10),
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF6C3CE1).withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: const Color(0xFF6C3CE1), size: 18),
            ),
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: const Color(0xFFF9F8FF),
            contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE5E7EB), width: 1),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE5E7EB), width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFF6C3CE1), width: 1.8),
            ),
          ),
        ),
      ],
    );
  }
}

class PremiumButton extends StatelessWidget {
  final String label;
  final bool isLoading;
  final VoidCallback onTap;

  const PremiumButton({required this.label, required this.isLoading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        height: 56,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            colors: [Color(0xFF6C3CE1), Color(0xFFB06AB3)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6C3CE1).withOpacity(isLoading ? 0.2 : 0.4),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Center(
          child: isLoading
              ? const SizedBox(width: 22, height: 22,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
              : Text(label, style: GoogleFonts.sora(
                  color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
        ),
      ),
    );
  }
}
