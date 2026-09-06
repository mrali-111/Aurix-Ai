import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';

class PremiumPaymentScreen extends StatefulWidget {
  const PremiumPaymentScreen({super.key});

  @override
  State<PremiumPaymentScreen> createState() => _PremiumPaymentScreenState();
}

class _PremiumPaymentScreenState extends State<PremiumPaymentScreen> {
  final _picker = ImagePicker();
  final _firestore = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;
  final _auth = FirebaseAuth.instance;

  File? _screenshotFile;
  bool _uploading = false;
  bool _submitted = false;

  // ── APNI DETAILS YAHAN BADLO ──────────────────────────────────
  static const _jazzCashNumber = '03011744430';
  static const _whatsappNumber = '923011744430'; // 92 + number (0 hata do)
  static const _whatsappGroupLink = 'https://chat.whatsapp.com/L8ehSNUEkPX75r4kGJ1EqN'; // apna group link
  static const _amount = 'Rs 200';
  // ─────────────────────────────────────────────────────────────

  User? get _user => _auth.currentUser;

  // ── Screenshot pick karo gallery se ──────────────────────────
  Future<void> _pickScreenshot() async {
    final XFile? picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null) return;
    setState(() => _screenshotFile = File(picked.path));
  }

  // ── Screenshot upload karo aur request Firestore mein save karo
  Future<void> _submitScreenshot() async {
    if (_screenshotFile == null) {
      _showSnack('⚠️ Pehle screenshot select karein');
      return;
    }
    if (_user == null) {
      _showSnack('❌ Pehle login karein');
      return;
    }

    setState(() => _uploading = true);

    try {
      // 1. Screenshot Firebase Storage mein upload karo
      final ref = _storage
          .ref()
          .child('payment_screenshots')
          .child('${_user!.uid}_${DateTime.now().millisecondsSinceEpoch}.jpg');

      await ref.putFile(
        _screenshotFile!,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final screenshotUrl = await ref.getDownloadURL();

      // 2. Firestore mein payment request save karo
      await _firestore.collection('payment_requests').doc(_user!.uid).set({
        'uid': _user!.uid,
        'email': _user!.email ?? '',
        'screenshotUrl': screenshotUrl,
        'amount': _amount,
        'status': 'pending', // admin 'approved' karega
        'submittedAt': FieldValue.serverTimestamp(),
        'plan': 'PREMIUM',
      });

      // 3. User ko pending state mein rakhو
      await _firestore.collection('users').doc(_user!.uid).set(
        {'paymentStatus': 'pending'},
        SetOptions(merge: true),
      );

      setState(() {
        _uploading = false;
        _submitted = true;
      });
    } catch (e) {
      setState(() => _uploading = false);
      _showSnack('❌ Submit nahi hua. Dobara try karein.');
    }
  }

  // ── WhatsApp pe directly message karo ─────────────────────────
  Future<void> _openWhatsApp() async {
    final msg = Uri.encodeComponent(
        'Assalam o Alaikum! Maine Premium payment kar di hai (${_amount}). Please activate kar dein. 🙏');
    final url = 'https://wa.me/$_whatsappNumber?text=$msg';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  // ── WhatsApp Group join karo ───────────────────────────────────
  Future<void> _openGroup() async {
    if (await canLaunchUrl(Uri.parse(_whatsappGroupLink))) {
      await launchUrl(Uri.parse(_whatsappGroupLink),
          mode: LaunchMode.externalApplication);
    }
  }

  // ── JazzCash number copy karo ─────────────────────────────────
  void _copyNumber() {
    Clipboard.setData(const ClipboardData(text: _jazzCashNumber));
    _showSnack('✅ Number copy ho gaya!');
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w600)),
      backgroundColor: const Color(0xFF7C4DFF),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F0ED),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: _submitted ? _buildSubmittedUI() : _buildPaymentUI(),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  SUBMITTED — waiting for admin approval
  // ══════════════════════════════════════════════════════════════
  Widget _buildSubmittedUI() {
    return Column(
      children: [
        const SizedBox(height: 40),
        Container(
          width: 110,
          height: 110,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
                colors: [Color(0xFF25D366), Color(0xFF128C7E)]),
            boxShadow: [
              BoxShadow(
                  color: const Color(0xFF25D366).withOpacity(0.4),
                  blurRadius: 30,
                  offset: const Offset(0, 10))
            ],
          ),
          child: const Icon(Icons.check_circle_outline,
              color: Colors.white, size: 60),
        ),
        const SizedBox(height: 28),
        const Text('Screenshot Submit Ho Gaya! ✅',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: Color(0xFF1A1A1A))),
        const SizedBox(height: 12),
        const Text(
          'Hum aapki payment verify karenge.\nThodi der mein Premium active ho jayega.\n\nGroup join karein jab tak:',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 13, color: Color(0xFF666666), height: 1.7),
        ),
        const SizedBox(height: 28),

        // Group join button
        _greenButton(
          icon: Icons.group,
          label: 'WhatsApp Group Join Karein',
          onTap: _openGroup,
        ),
        const SizedBox(height: 14),

        // Back button
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFDDDDDD)),
            ),
            child: const Text('Wapis Jao',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Color(0xFF555555),
                    fontWeight: FontWeight.w700,
                    fontSize: 14)),
          ),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  PAYMENT UI
  // ══════════════════════════════════════════════════════════════
  Widget _buildPaymentUI() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Back
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2))
              ],
            ),
            child: const Icon(Icons.arrow_back_ios_new,
                size: 16, color: Color(0xFF333333)),
          ),
        ),

        const SizedBox(height: 24),

        // Header card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF9C27B0),
                Color(0xFF7C4DFF),
                Color(0xFFFFB74D)
              ],
              stops: [0.0, 0.5, 1.0],
            ),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                  color: const Color(0xFF7C4DFF).withOpacity(0.35),
                  blurRadius: 24,
                  offset: const Offset(0, 10))
            ],
          ),
          child: Column(
            children: [
              const Text('💎 Premium Plan',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text(
                _amount + ' / month',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 15,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              _featureRow('Unlimited AI Access 🚀'),
              _featureRow('Saare Reminders & Alerts'),
              _featureRow('Live News Updates'),
              _featureRow('Priority Support ⭐'),
            ],
          ),
        ),

        const SizedBox(height: 28),

        // ── STEP 1: Pay karo ─────────────────────────────────────
        _stepLabel('Step 1', 'JazzCash se Payment Karein'),
        const SizedBox(height: 12),

        // QR image
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 4))
            ],
          ),
          child: Column(
            children: [
              // QR Image
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  'assets/Qr.png',
                  width: 160,
                  height: 160,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 12),
              const Text('YA',
                  style: TextStyle(
                      color: Color(0xFF999999),
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),

              // Number copy row
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F3FF),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: const Color(0xFF7C4DFF).withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('JazzCash Number',
                            style: TextStyle(
                                fontSize: 11, color: Color(0xFF888888))),
                        Text(_jazzCashNumber,
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF7C4DFF),
                                letterSpacing: 1)),
                      ],
                    ),
                    GestureDetector(
                      onTap: _copyNumber,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [
                            Color(0xFF9C27B0),
                            Color(0xFF7C4DFF)
                          ]),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text('Copy',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 13)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // ── STEP 2: Screenshot submit karo ──────────────────────
        _stepLabel('Step 2', 'Payment Screenshot Submit Karein'),
        const SizedBox(height: 12),

        // Screenshot picker
        GestureDetector(
          onTap: _pickScreenshot,
          child: Container(
            width: double.infinity,
            height: _screenshotFile != null ? 200 : 110,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _screenshotFile != null
                    ? const Color(0xFF7C4DFF)
                    : const Color(0xFFDDDDDD),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 3))
              ],
            ),
            child: _screenshotFile != null
                ? ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Image.file(_screenshotFile!, fit: BoxFit.cover),
            )
                : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_photo_alternate_outlined,
                    size: 36,
                    color: const Color(0xFF7C4DFF).withOpacity(0.6)),
                const SizedBox(height: 8),
                const Text('Screenshot Select Karein',
                    style: TextStyle(
                        color: Color(0xFF888888),
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                const Text('Gallery se JazzCash payment screenshot',
                    style: TextStyle(
                        color: Color(0xFFAAAAAA), fontSize: 11)),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Submit button
        GestureDetector(
          onTap: _uploading ? null : _submitScreenshot,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF9C27B0), Color(0xFF7C4DFF)]),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                    color: const Color(0xFF7C4DFF).withOpacity(0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 6))
              ],
            ),
            child: _uploading
                ? const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2.5),
              ),
            )
                : const Text('Screenshot Submit Karein 📤',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15)),
          ),
        ),

        const SizedBox(height: 24),

        // ── STEP 3: Group join karo ───────────────────────────────
        _stepLabel('Step 3', 'WhatsApp Group Join Karein'),
        const SizedBox(height: 12),

        _greenButton(
          icon: Icons.group,
          label: 'Premium Group Join Karein',
          onTap: _openGroup,
        ),

        const SizedBox(height: 12),

        // Direct WhatsApp button
        GestureDetector(
          onTap: _openWhatsApp,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: const Color(0xFF25D366).withOpacity(0.4)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.chat_bubble_outline,
                    color: Color(0xFF25D366), size: 18),
                SizedBox(width: 8),
                Text('WhatsApp pe directly message karein',
                    style: TextStyle(
                        color: Color(0xFF25D366),
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
              ],
            ),
          ),
        ),

        const SizedBox(height: 40),
      ],
    );
  }

  Widget _featureRow(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline,
              color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Text(text,
              style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _stepLabel(String step, String title) {
    return Row(
      children: [
        Container(
          padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFF9C27B0), Color(0xFF7C4DFF)]),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(step,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 10),
        Text(title,
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A1A))),
      ],
    );
  }

  Widget _greenButton(
      {required IconData icon,
        required String label,
        required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [Color(0xFF25D366), Color(0xFF128C7E)]),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: const Color(0xFF25D366).withOpacity(0.3),
                blurRadius: 14,
                offset: const Offset(0, 5))
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14)),
          ],
        ),
      ),
    );
  }
}