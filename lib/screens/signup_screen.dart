import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/auth_service.dart';
import 'home_screen.dart';
import 'login_screen.dart' show _Blob, _PremiumField, _PremiumButton, LoginScreen, Blob, PremiumField, PremiumButton;

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupState();
}

class _SignupState extends State<SignupScreen> with TickerProviderStateMixin {
  final email   = TextEditingController();
  final password = TextEditingController();
  final confirm  = TextEditingController();
  final name     = TextEditingController();
  final auth     = AuthService();
  bool _isLoading  = false;
  bool _obscurePass = true;
  bool _obscureCnf  = true;
  bool _agreed      = false;

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
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _bgCtrl.dispose();
    email.dispose();
    password.dispose();
    confirm.dispose();
    name.dispose();
    super.dispose();
  }

  void _signup() async {
    if (_isLoading) return;
    if (!_agreed) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Please agree to terms & conditions',
            style: GoogleFonts.plusJakartaSans()),
        backgroundColor: Colors.red.shade400,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.all(16),
      ));
      return;
    }
    if (password.text != confirm.text) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Passwords do not match', style: GoogleFonts.plusJakartaSans()),
        backgroundColor: Colors.red.shade400,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.all(16),
      ));
      return;
    }
    setState(() => _isLoading = true);
    try {
      await auth.signup(email: email.text.trim(), password: password.text.trim());
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
                height: size.height * 0.35,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color.lerp(const Color(0xFFB06AB3), const Color(0xFF8E44AD), _bgAnim.value)!,
                      Color.lerp(const Color(0xFF6C3CE1), const Color(0xFF4A1FA8), _bgAnim.value)!,
                    ],
                  ),
                ),
              ),
            ),
          ),

          Positioned(top: -50, left: -50,
              child: Blob(size: 180, color: Colors.white.withOpacity(0.06))),
          Positioned(top: 70, right: -30,
              child: Blob(size: 120, color: Colors.white.withOpacity(0.05))),

          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: FadeTransition(
                opacity: _fadeAnim,
                child: SlideTransition(
                  position: _slideAnim,
                  child: Column(
                    children: [
                      const SizedBox(height: 28),

                      // Back + Logo row
                      Row(
                        children: [
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Container(
                              width: 40, height: 40,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withOpacity(0.15),
                                border: Border.all(color: Colors.white.withOpacity(0.3)),
                              ),
                              child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 16),
                            ),
                          ),
                          const Spacer(),
                          Container(
                            width: 56, height: 56,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withOpacity(0.15),
                              border: Border.all(color: Colors.white.withOpacity(0.3)),
                            ),
                            child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 26),
                          ),
                          const Spacer(),
                          const SizedBox(width: 40),
                        ],
                      ),

                      const SizedBox(height: 20),

                      Text('Create Account', style: GoogleFonts.sora(
                        fontSize: 20, fontWeight: FontWeight.w800,
                        color: Colors.white, letterSpacing: 0.5,
                      )),

                      SizedBox(height: size.height * 0.04),

                      // Card
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
                            Text('Join Aurix AI 🚀', style: GoogleFonts.sora(
                              fontSize: 22, fontWeight: FontWeight.w800, color: const Color(0xFF1A1A2E),
                            )),
                            const SizedBox(height: 6),
                            Text('Start your intelligent journey today', style: GoogleFonts.plusJakartaSans(
                              fontSize: 13, color: const Color(0xFF9CA3AF),
                            )),

                            const SizedBox(height: 24),

                            PremiumField(
                              controller: name,
                              label: 'Full Name',
                              hint: 'Your name',
                              icon: Icons.person_outline_rounded,
                            ),

                            const SizedBox(height: 16),

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
                              hint: 'Min. 6 characters',
                              icon: Icons.lock_outline_rounded,
                              obscure: _obscurePass,
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePass ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                  color: const Color(0xFF9CA3AF), size: 20,
                                ),
                                onPressed: () => setState(() => _obscurePass = !_obscurePass),
                              ),
                            ),

                            const SizedBox(height: 16),

                            PremiumField(
                              controller: confirm,
                              label: 'Confirm Password',
                              hint: 'Repeat password',
                              icon: Icons.lock_outline_rounded,
                              obscure: _obscureCnf,
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscureCnf ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                  color: const Color(0xFF9CA3AF), size: 20,
                                ),
                                onPressed: () => setState(() => _obscureCnf = !_obscureCnf),
                              ),
                            ),

                            const SizedBox(height: 16),

                            // Terms checkbox
                            Row(
                              children: [
                                GestureDetector(
                                  onTap: () => setState(() => _agreed = !_agreed),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    width: 22, height: 22,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(6),
                                      color: _agreed ? const Color(0xFF6C3CE1) : Colors.transparent,
                                      border: Border.all(
                                        color: _agreed ? const Color(0xFF6C3CE1) : const Color(0xFFD1D5DB),
                                        width: 1.5,
                                      ),
                                    ),
                                    child: _agreed
                                        ? const Icon(Icons.check, color: Colors.white, size: 14)
                                        : null,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: RichText(
                                    text: TextSpan(
                                      text: 'I agree to the ',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 12, color: const Color(0xFF6B7280),
                                      ),
                                      children: [
                                        TextSpan(
                                          text: 'Terms & Privacy Policy',
                                          style: GoogleFonts.plusJakartaSans(
                                            color: const Color(0xFF6C3CE1),
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 24),

                            PremiumButton(label: 'Create Account', isLoading: _isLoading, onTap: _signup),
                          ],
                        ),
                      ),

                      const SizedBox(height: 28),

                      GestureDetector(
                        onTap: () => Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (_) => const LoginScreen()),
                        ),
                        child: RichText(
                          text: TextSpan(
                            text: 'Already have an account?  ',
                            style: GoogleFonts.plusJakartaSans(color: const Color(0xFF9CA3AF), fontSize: 14),
                            children: [
                              TextSpan(
                                text: 'Sign In →',
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
