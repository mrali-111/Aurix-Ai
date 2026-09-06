import 'dart:io';
import 'package:aurix_ai/screens/about_screen.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../update_service.dart';
import 'login_screen.dart';

class ProfileSubscriptionScreen extends StatefulWidget {
  const ProfileSubscriptionScreen({super.key});

  @override
  State<ProfileSubscriptionScreen> createState() =>
      _ProfileSubscriptionScreenState();
}

class _ProfileSubscriptionScreenState extends State<ProfileSubscriptionScreen>
    with TickerProviderStateMixin {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final _picker = ImagePicker();

  String _selectedPlan = 'FREE';
  String _photoUrl = '';
  String _localImagePath = '';
  bool _uploadingPhoto = false;

  final _oldPassCtrl = TextEditingController();
  final _newPassCtrl = TextEditingController();
  bool _showOld = false;
  bool _showNew = false;
  bool _passLoading = false;

  final String _whatsappNumber = '923149695093';
  final String _whatsappMessage =
      'I Have Placed an order for *Aurix Ai* Here is my payment screenshot.';

  User? get _user => _auth.currentUser;
  String get _userEmail => _user?.email ?? 'user@aurix.app';
  String get _userName => _user?.displayName ?? _userEmail.split('@').first;

  void _startPlanListener() {
    if (_user == null) return;
    _firestore.collection('users').doc(_user!.uid).snapshots().listen((doc) {
      if (doc.exists && mounted) {
        setState(() {
          _selectedPlan = doc.data()?['plan'] ?? 'FREE';
          _photoUrl = doc.data()?['photoUrl'] ?? _user!.photoURL ?? '';
          _localImagePath = doc.data()?['localImagePath'] ?? '';
        });
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _startPlanListener();
    _loadSavedImage();

  }

  void _checkForAppUpdate() async {
    final update = await UpdateService.checkForUpdate();
    if (update != null && mounted) {
      await UpdateService.showUpdateDialog(context, update);
    }
  }

  Future<void> _loadSavedImage() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPath = prefs.getString('${_user?.uid}_profile_image') ?? '';
    if (savedPath.isNotEmpty && File(savedPath).existsSync()) {
      setState(() => _localImagePath = savedPath);
    }
  }

  @override
  void dispose() {
    _oldPassCtrl.dispose();
    _newPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAndUploadImage() async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 512,
      );
      if (picked == null) return;

      setState(() => _uploadingPhoto = true);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('${_user?.uid}_profile_image', picked.path);

      await _firestore.collection('users').doc(_user!.uid).set({
        'localImagePath': picked.path,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      setState(() {
        _localImagePath = picked.path;
        _uploadingPhoto = false;
      });

      if (mounted) _showSnack('Profile updated successfully');
    } catch (e) {
      if (mounted) setState(() => _uploadingPhoto = false);
      _showSnack('Failed to update profile');
    }
  }

  Future<void> _changePassword() async {
    final oldPass = _oldPassCtrl.text.trim();
    final newPass = _newPassCtrl.text.trim();

    if (oldPass.isEmpty || newPass.isEmpty) {
      _showSnack('Please fill all fields');
      return;
    }
    if (newPass.length < 6) {
      _showSnack('Password must be at least 6 characters');
      return;
    }

    setState(() => _passLoading = true);
    try {
      final cred = EmailAuthProvider.credential(email: _userEmail, password: oldPass);
      await _user!.reauthenticateWithCredential(cred);
      await _user!.updatePassword(newPass);
      setState(() => _passLoading = false);
      _oldPassCtrl.clear();
      _newPassCtrl.clear();
      _showSnack('Password changed successfully');
    } on FirebaseAuthException catch (e) {
      setState(() => _passLoading = false);
      _showSnack(e.code == 'wrong-password' ? 'Incorrect old password' : 'Error: ${e.message}');
    }
  }

  Future<void> _openWhatsApp() async {
    try {
      final message = Uri.encodeComponent(_whatsappMessage);
      final whatsappUrl = 'https://wa.me/$_whatsappNumber?text=$message';
      if (await canLaunchUrl(Uri.parse(whatsappUrl))) {
        await launchUrl(Uri.parse(whatsappUrl), mode: LaunchMode.externalApplication);
      } else {
        _showSnack('WhatsApp not installed');
      }
    } catch (e) {
      _showSnack('Unable to open WhatsApp');
    }
  }

  Future<void> _submitPaymentRequest() async {
    try {
      await _firestore.collection('users').doc(_user!.uid).set({
        'plan': 'PENDING',
        'paymentRequestedAt': FieldValue.serverTimestamp(),
        'paymentMethod': 'JazzCash',
        'paymentAmount': 200,
        'userEmail': _userEmail,
        'userName': _userName,
      }, SetOptions(merge: true));

      await _firestore.collection('payment_requests').add({
        'uid': _user!.uid,
        'email': _userEmail,
        'name': _userName,
        'plan': 'PREMIUM',
        'amount': 200,
        'method': 'JazzCash',
        'status': 'PENDING',
        'requestedAt': FieldValue.serverTimestamp(),
        'adminNote': '',
      });

      setState(() => _selectedPlan = 'PENDING');
      _showSnack('Payment request submitted!');
      await _openWhatsApp();
    } catch (e) {
      _showSnack('Failed to submit request');
    }
  }

  void _logout() {
    showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Logout', style: TextStyle(fontWeight: FontWeight.w700)),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF666666))),
          ),
          ElevatedButton(
            onPressed: () async {
              await _auth.signOut();
              if (mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                      (route) => false,
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: const Color(0xFF7C3AED),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // Premium Header
            SliverToBoxAdapter(
              child: _buildPremiumHeader(),
            ),
            SliverToBoxAdapter(
              child: Container(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _buildPasswordCard(),
                    const SizedBox(height: 24),
                    _buildSubscriptionSection(),
                    const SizedBox(height: 24),
                    _buildContactSupport(),
                    const SizedBox(height: 24),
                    _buildActionButtons(),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPremiumHeader() {
    String badgeText;
    Color badgeColor;
    IconData badgeIcon;

    switch (_selectedPlan) {
      case 'PREMIUM':
        badgeText = 'PREMIUM MEMBER';
        badgeColor = const Color(0xFFF59E0B);
        badgeIcon = Icons.workspace_premium;
        break;
      case 'PENDING':
        badgeText = 'VERIFICATION PENDING';
        badgeColor = const Color(0xFFF59E0B);
        badgeIcon = Icons.hourglass_empty;
        break;
      default:
        badgeText = 'FREE MEMBER';
        badgeColor = const Color(0xFF64748B);
        badgeIcon = Icons.people_outline;
    }

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF7C3AED), Color(0xFFC026D3), Color(0xFFF43F5E)],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
                  ),
                ),
                Container(
                  alignment: Alignment.center, // Center inside container
                  child: Text(
                    'Profile',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                )

              ],
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: _pickAndUploadImage,
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: _uploadingPhoto
                          ? Container(
                        color: Colors.white24,
                        child: const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        ),
                      )
                          : _localImagePath.isNotEmpty && File(_localImagePath).existsSync()
                          ? Image.file(File(_localImagePath), fit: BoxFit.cover)
                          : _photoUrl.isNotEmpty
                          ? Image.network(_photoUrl, fit: BoxFit.cover)
                          : Container(
                        color: Colors.white24,
                        child: const Icon(Icons.person, size: 50, color: Colors.white),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF7C3AED), width: 2),
                    ),
                    child: const Icon(Icons.camera_alt, size: 16, color: Color(0xFF7C3AED)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _userName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _userEmail,
              style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.white.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(badgeIcon, color: Colors.white, size: 16),
                  const SizedBox(width: 8),
                  Text(badgeText, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPasswordCard() {
    return _modernCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF7C3AED), Color(0xFFC026D3)]),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.lock_outline, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Security', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
                    Text('Change your password', style: TextStyle(fontSize: 13, color: Color(0xFF64748B))),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _modernTextField(
            controller: _oldPassCtrl,
            hint: 'Current password',
            icon: Icons.lock_outline,
            obscureText: !_showOld,
            suffixIcon: IconButton(
              icon: Icon(_showOld ? Icons.visibility_off : Icons.visibility, size: 20),
              onPressed: () => setState(() => _showOld = !_showOld),
            ),
          ),
          const SizedBox(height: 12),
          _modernTextField(
            controller: _newPassCtrl,
            hint: 'New password',
            icon: Icons.lock_clock_outlined,
            obscureText: !_showNew,
            suffixIcon: IconButton(
              icon: Icon(_showNew ? Icons.visibility_off : Icons.visibility, size: 20),
              onPressed: () => setState(() => _showNew = !_showNew),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _passLoading ? null : _changePassword,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: _passLoading
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Update Password', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubscriptionSection() {
    return _modernCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFF97316)]),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.workspace_premium, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Subscription', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
                    Text('Choose your plan', style: TextStyle(fontSize: 13, color: Color(0xFF64748B))),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_selectedPlan == 'PENDING')
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.hourglass_empty, color: Color(0xFFF59E0B), size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text('Verification in Progress', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF92400E))),
                        SizedBox(height: 4),
                        Text('Your payment is being verified. Contact support for updates.', style: TextStyle(fontSize: 12, color: Color(0xFF92400E))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          _planTile(
            title: 'Free Plan',
            price: 'Free',
            features: ['3 Active reminders', 'Basic news updates', 'Unlimited voice input', '5 Image generations'],
            isSelected: _selectedPlan == 'FREE',
            isPremium: false,
            onTap: _selectedPlan != 'FREE' && _selectedPlan != 'PREMIUM' && _selectedPlan != 'PENDING'
                ? () async {
              await _firestore.collection('users').doc(_user!.uid).set({'plan': 'FREE'}, SetOptions(merge: true));
              setState(() => _selectedPlan = 'FREE');
              _showSnack('Free plan activated');
            }
                : null,
          ),
          const SizedBox(height: 12),
          _planTile(
            title: 'Premium Plan',
            price: 'Rs 200/month',
            features: [
              'Unlimited AI messages',
              'Unlimited reminders',
              'Live news updates',
              'Full voice support',
              'Unlimited image generation',
              'Priority support',
              'Ad-free experience',
            ],
            isSelected: _selectedPlan == 'PREMIUM',
            isPremium: true,
            onTap: _selectedPlan != 'PREMIUM' && _selectedPlan != 'PENDING' ? _showPremiumDialog : null,
          ),
        ],
      ),
    );
  }

  Widget _planTile({
    required String title,
    required String price,
    required List<String> features,
    required bool isSelected,
    required bool isPremium,
    VoidCallback? onTap,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFF5F3FF) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected ? const Color(0xFF7C3AED) : const Color(0xFFE2E8F0),
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(isPremium ? '💎' : '🆓', style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 8),
                  Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
                ],
              ),
              if (isSelected)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C3AED).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle, size: 14, color: Color(0xFF7C3AED)),
                      SizedBox(width: 4),
                      Text('Active', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF7C3AED))),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(price, style: const TextStyle(fontSize: 13, color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: features.map((feature) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isPremium ? const Color(0xFFF3E8FF) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(feature, style: const TextStyle(fontSize: 11, color: Color(0xFF475569))),
            )).toList(),
          ),
          if (onTap != null && !isSelected) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onTap,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: isPremium ? const Color(0xFF7C3AED) : const Color(0xFFCBD5E1)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: Text(
                  isPremium ? 'Upgrade Now' : 'Select Free Plan',
                  style: TextStyle(color: isPremium ? const Color(0xFF7C3AED) : const Color(0xFF64748B), fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showPremiumDialog() {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF7C3AED), Color(0xFFC026D3)]),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.workspace_premium, color: Colors.white, size: 32),
              ),
              const SizedBox(height: 20),
              const Text('Premium Plan', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              const Text('Rs 200 / month', style: TextStyle(fontSize: 16, color: Color(0xFF7C3AED), fontWeight: FontWeight.w600)),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              Image.asset('assets/Qr.png', width: 120, height: 120, fit: BoxFit.contain),
                              const SizedBox(height: 8),
                              const Text('Scan QR Code', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                        Container(width: 1, height: 100, color: const Color(0xFFE2E8F0)),
                        Expanded(
                          child: Column(
                            children: [
                              const Icon(Icons.call, color: Color(0xFF25D366), size: 32),
                              const SizedBox(height: 8),
                              const Text('JazzCash', style: TextStyle(fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              Text('03011744430', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Color(0xFFF59E0B), size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text('After payment, contact support on WhatsApp for verification', style: TextStyle(fontSize: 12, color: Color(0xFF92400E))),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(_),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(_);
                        _submitPaymentRequest();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF7C3AED),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('I\'ve Paid'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContactSupport() {
    return _modernCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF25D366), Color(0xFF128C7E)]),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.support_agent, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Support', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
                    Text('Get help from our team', style: TextStyle(fontSize: 13, color: Color(0xFF64748B))),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF25D366), Color(0xFF128C7E)]),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.phone, color: Colors.white, size: 40),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text('WhatsApp Support', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                          Text('Chat with our support team', style: TextStyle(color: Colors.white70, fontSize: 12)),
                        ],
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _openWhatsApp,
                      icon: const Icon(Icons.message, size: 18),
                      label: const Text('Chat'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF25D366),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        _actionButton(
          icon: Icons.info_outline,
          label: 'About Aurix AI',
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const AboutScreen())),
          color: const Color(0xFF7C3AED),
        ),
        const SizedBox(height: 12),
        _actionButton(
          icon: Icons.logout,
          label: 'Logout',
          onTap: _logout,
          color: const Color(0xFFEF4444),
        ),
      ],
    );
  }

  Widget _actionButton({required IconData icon, required String label, required VoidCallback onTap, required Color color}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
        trailing: Icon(Icons.chevron_right, color: color),
        onTap: onTap,
      ),
    );
  }

  Widget _modernCard({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: child,
      ),
    );
  }

  Widget _modernTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required bool obscureText,
    required Widget suffixIcon,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        style: const TextStyle(fontSize: 14, color: Color(0xFF1E293B)),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
          prefixIcon: Icon(icon, color: const Color(0xFF7C3AED), size: 20),
          suffixIcon: suffixIcon,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }
}