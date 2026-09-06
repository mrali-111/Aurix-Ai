import 'package:aurix_ai/screens/success_screen.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'ai_assistant_screen.dart' hide ImageProvider;
import 'task_model.dart';
import 'reminder_screen.dart';
import 'package:aurix_ai/screens/profile_subscription_screen.dart';
import 'package:xml/xml.dart';
import 'package:image_picker/image_picker.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  int _selectedIndex = 0;
  late Timer _timeTimer;
  late Timer _quoteTimer;
  late Timer _newsTimer;
  String _currentTime = '';
  String _currentDate = '';
  String _currentQuote = '"Every day is a new chance to grow stronger. 🌿"';
  List<Map<String, String>> _newsArticles = [];
  int _currentQuoteIndex = 0;
  String _userPlan = 'FREE';
  String? _profileImagePath;

  late AnimationController _entryCtrl;
  late Animation<double> _entryFade;
  late Animation<Offset> _entrySlide;

  List<TaskModel> _tasks = [];

  final List<String> _quotes = [
    '"Every day is a new chance to grow stronger. 🌿"',
    '"Success is the sum of small efforts repeated day in and day out. 💪"',
    '"Your potential is endless. Keep pushing forward. ⭐"',
    '"Great things never came from comfort zones. 🚀"',
    '"Believe in yourself and you are halfway there. 💖"',
    '"Progress, not perfection. Keep going! 🎯"',
  ];

  User? get _user => _auth.currentUser;

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good Morning ☀️';
    if (h < 17) return 'Good Afternoon 🌤';
    return 'Good Evening 🌙';
  }

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _entryFade = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut);
    _entrySlide = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic));
    _entryCtrl.forward();

    _loadProfileImage();
    _loadQuoteIndex();
    _updateTime();
    _setupTimers();
    _fetchNews();
    _loadTasks();
    _startPlanListener();
  }

  Future<void> _loadProfileImage() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString('${_auth.currentUser?.uid}_profile_image') ?? '';
    if (mounted) setState(() => _profileImagePath = path.isNotEmpty ? path : null);
  }

  ImageProvider? _getProfileImage() {
    if (_profileImagePath != null && _profileImagePath!.isNotEmpty) return FileImage(File(_profileImagePath!));
    if (_user?.photoURL != null && _user!.photoURL!.isNotEmpty) return NetworkImage(_user!.photoURL!);
    return null;
  }

  Future<void> _loadQuoteIndex() async {
    final prefs = await SharedPreferences.getInstance();
    final savedIndex = prefs.getInt('quote_index') ?? 0;
    final lastUpdate = prefs.getString('quote_last_update');
    if (lastUpdate != null) {
      final lastDate = DateTime.parse(lastUpdate);
      final hoursPassed = DateTime.now().difference(lastDate).inHours;
      if (hoursPassed >= 12) {
        final newIndex = (savedIndex + 1) % _quotes.length;
        setState(() { _currentQuoteIndex = newIndex; _currentQuote = _quotes[newIndex]; });
        await _saveQuoteIndex(newIndex);
      } else {
        setState(() { _currentQuoteIndex = savedIndex; _currentQuote = _quotes[savedIndex]; });
      }
    } else {
      setState(() { _currentQuoteIndex = savedIndex; _currentQuote = _quotes[savedIndex]; });
    }
  }

  Future<void> _saveQuoteIndex(int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('quote_index', index);
    await prefs.setString('quote_last_update', DateTime.now().toIso8601String());
  }

  void _startPlanListener() {
    if (_user == null) return;
    _firestore.collection('users').doc(_user!.uid).snapshots().listen((doc) {
      if (doc.exists && mounted) setState(() => _userPlan = doc.data()?['plan'] ?? 'FREE');
    });
  }

  void _updateTime() {
    final now = DateTime.now();
    _currentTime = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    _currentDate = now.hour < 12 ? 'AM' : 'PM';
  }

  void _setupTimers() {
    _timeTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateTime();
      if (mounted) setState(() {});
    });
    _quoteTimer = Timer.periodic(const Duration(hours: 12), (_) {
      if (mounted) {
        final newIndex = (_currentQuoteIndex + 1) % _quotes.length;
        setState(() { _currentQuoteIndex = newIndex; _currentQuote = _quotes[newIndex]; });
        _saveQuoteIndex(newIndex);
      }
    });
    _newsTimer = Timer.periodic(const Duration(hours: 6), (_) => _fetchNews());
  }

  Future<void> _loadTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final tRaw = prefs.getStringList('tasks') ?? [];
    if (mounted) setState(() => _tasks = tRaw.map((e) => TaskModel.fromJson(jsonDecode(e))).toList());
  }

  void _onTasksChanged(List<TaskModel> updated) {
    if (mounted) setState(() => _tasks = updated);
  }

  Future<void> _fetchNews() async {
    const String rssUrl = 'https://news.google.com/rss/search?q=pakistan+today&hl=en-PK&gl=PK&ceid=PK:en';
    try {
      final response = await http.get(Uri.parse(rssUrl), headers: {'User-Agent': 'Mozilla/5.0'})
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200 && mounted) {
        final document = XmlDocument.parse(response.body);
        final int itemCount = (_userPlan == 'PREMIUM') ? 3 : 1;
        final items = document.findAllElements('item').take(itemCount).toList();
        final List<Map<String, String>> fetched = [];
        for (final item in items) {
          final title = item.findElements('title').firstOrNull?.innerText ?? 'News';
          String source = 'Google News';
          final sourceEl = item.findElements('source').firstOrNull;
          if (sourceEl != null) source = sourceEl.innerText;
          String desc = item.findElements('description').firstOrNull?.innerText ?? '';
          desc = desc.replaceAll(RegExp(r'<[^>]*>'), '').replaceAll('&nbsp;', ' ').replaceAll('&amp;', '&').trim();
          if (desc.isEmpty) desc = 'Tap to read full story';
          fetched.add({'title': title, 'description': desc, 'source': source});
        }
        if (fetched.isNotEmpty && mounted) setState(() => _newsArticles = fetched);
      }
    } catch (_) {
      if (_newsArticles.isEmpty && mounted) {
        setState(() => _newsArticles = [
          {'title': 'Pakistan Today Headlines', 'description': 'Connect to internet for live news', 'source': 'Google News'}
        ]);
      }
    }
  }

  @override
  void dispose() {
    _timeTimer.cancel();
    _quoteTimer.cancel();
    _newsTimer.cancel();
    _entryCtrl.dispose();
    super.dispose();
  }

  void _openReminder() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => ReminderScreen(onTasksChanged: _onTasksChanged)))
        .then((_) { _loadTasks(); if (mounted) setState(() => _selectedIndex = 0); });
  }

  void _openAIAssistant() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const AIAssistantScreen()))
        .then((_) { if (mounted) setState(() => _selectedIndex = 0); });
  }

  void _openProfile() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileSubscriptionScreen()))
        .then((_) { _loadProfileImage(); if (mounted) { setState(() => _selectedIndex = 0); _fetchNews(); } });
  }

  void _openSuccess() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const SuccessScreen()))
        .then((_) { if (mounted) setState(() => _selectedIndex = 0); });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F4FF),
      body: FadeTransition(
        opacity: _entryFade,
        child: SlideTransition(
          position: _entrySlide,
          child: _buildHomeContent(),
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildHomeContent() {
    return SafeArea(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTopBar(),
            const SizedBox(height: 20),
            _buildHeroCard(),
            const SizedBox(height: 20),
            _buildQuickActions(),
            const SizedBox(height: 20),
            _buildNewsSection(),
            const SizedBox(height: 20),
            _buildReminderCard(),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final displayName = _user?.displayName ?? _user?.email?.split('@').first ?? 'User';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_greeting, style: GoogleFonts.plusJakartaSans(
                  fontSize: 13, color: const Color(0xFF6C3CE1), fontWeight: FontWeight.w600,
                )),
                const SizedBox(height: 2),
                Text(displayName, style: GoogleFonts.sora(
                  fontSize: 22, fontWeight: FontWeight.w800, color: const Color(0xFF1A1A2E),
                )),
              ],
            ),
          ),

          // Plan badge
          if (_userPlan == 'PREMIUM')
            Container(
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFFFFD700), Color(0xFFFFA500)]),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 13),
                  const SizedBox(width: 4),
                  Text('PRO', style: GoogleFonts.sora(
                    color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1,
                  )),
                ],
              ),
            ),

          GestureDetector(
            onTap: _openProfile,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(colors: [Color(0xFF6C3CE1), Color(0xFFB06AB3)]),
                boxShadow: [
                  BoxShadow(color: const Color(0xFF6C3CE1).withOpacity(0.35), blurRadius: 12, offset: const Offset(0, 4)),
                ],
              ),
              child: CircleAvatar(
                radius: 22,
                backgroundColor: Colors.transparent,
                backgroundImage: _getProfileImage(),
                child: _getProfileImage() == null
                    ? const Icon(Icons.person_rounded, color: Colors.white, size: 22)
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF6C3CE1), Color(0xFF9A4EBF), Color(0xFFB06AB3)],
          ),
          boxShadow: [
            BoxShadow(color: const Color(0xFF6C3CE1).withOpacity(0.4), blurRadius: 30, offset: const Offset(0, 12)),
          ],
        ),
        child: Stack(
          children: [
            // BG decoration
            Positioned(
              right: -30, top: -30,
              child: Container(
                width: 140, height: 140,
                decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.07)),
              ),
            ),
            Positioned(
              right: 20, bottom: -20,
              child: Container(
                width: 80, height: 80,
                decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.05)),
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withOpacity(0.25)),
                        ),
                        child: Row(children: [
                          Container(width: 6, height: 6,
                              decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF00FF88))),
                          const SizedBox(width: 6),
                          Text('AI Ready', style: GoogleFonts.plusJakartaSans(
                            color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600,
                          )),
                        ]),
                      ),
                      const Spacer(),
                      // Clock
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(_currentTime, style: GoogleFonts.sora(
                          fontSize: 13, color: Colors.white, fontWeight: FontWeight.w700, letterSpacing: 1.5,
                        )),
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),

                  Text('Daily Motivation', style: GoogleFonts.plusJakartaSans(
                    fontSize: 12, color: Colors.white.withOpacity(0.7), letterSpacing: 0.5,
                  )),
                  const SizedBox(height: 6),
                  Text(
                    _currentQuote,
                    style: GoogleFonts.sora(
                      fontSize: 15,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontStyle: FontStyle.italic,
                      height: 1.5,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),

                  const SizedBox(height: 20),

                  // Ask AI button
                  GestureDetector(
                    onTap: _openAIAssistant,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 10, offset: const Offset(0, 4)),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.auto_awesome_rounded, color: Color(0xFF6C3CE1), size: 18),
                          const SizedBox(width: 8),
                          Text('Ask Aurix AI', style: GoogleFonts.sora(
                            color: const Color(0xFF6C3CE1), fontWeight: FontWeight.w700, fontSize: 13,
                          )),
                          const SizedBox(width: 8),
                          const Icon(Icons.arrow_forward_rounded, color: Color(0xFF6C3CE1), size: 16),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions() {
    final actions = [
      _QuickAction(icon: Icons.mic_rounded, label: 'Voice AI', gradient: [const Color(0xFF6C3CE1), const Color(0xFFB06AB3)], onTap: _openAIAssistant),
      _QuickAction(icon: Icons.alarm_rounded, label: 'Reminder', gradient: [const Color(0xFF00C9A7), const Color(0xFF007B6E)], onTap: _openReminder),
      _QuickAction(icon: Icons.emoji_events_rounded, label: 'Success', gradient: [const Color(0xFFFF6B6B), const Color(0xFFFFA500)], onTap: _openSuccess),
      _QuickAction(icon: Icons.person_rounded, label: 'Profile', gradient: [const Color(0xFF3D1FA8), const Color(0xFF6C3CE1)], onTap: _openProfile),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Quick Actions', style: GoogleFonts.sora(
            fontSize: 16, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A2E),
          )),
          const SizedBox(height: 14),
          Row(
            children: actions.map((a) => Expanded(
              child: GestureDetector(
                onTap: a.onTap,
                child: Container(
                  margin: const EdgeInsets.only(right: 10),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: a.gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(color: a.gradient[0].withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 6)),
                    ],
                  ),
                  child: Column(
                    children: [
                      Icon(a.icon, color: Colors.white, size: 24),
                      const SizedBox(height: 6),
                      Text(a.label, style: GoogleFonts.plusJakartaSans(
                        color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600,
                      )),
                    ],
                  ),
                ),
              ),
            )).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildNewsSection() {
    final List<List<Color>> gradients = [
      [const Color(0xFF6A1B9A), const Color(0xFFAB47BC)],
      [const Color(0xFF1565C0), const Color(0xFF42A5F5)],
      [const Color(0xFFE65100), const Color(0xFFFFB300)],
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Today\'s News', style: GoogleFonts.sora(
                fontSize: 16, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A2E),
              )),
              const Spacer(),
              if (_userPlan != 'PREMIUM')
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFFFFD700), Color(0xFFFFA500)]),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(children: [
                    const Icon(Icons.lock_rounded, color: Colors.white, size: 10),
                    const SizedBox(width: 4),
                    Text('Pro: 3 articles', style: GoogleFonts.plusJakartaSans(
                      color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700,
                    )),
                  ]),
                ),
            ],
          ),
          const SizedBox(height: 12),

          if (_newsArticles.isEmpty)
            Container(
              height: 80,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 4))],
              ),
              child: const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(
                strokeWidth: 2, color: Color(0xFF6C3CE1),
              ))),
            )
          else
            ...List.generate(_newsArticles.length, (i) {
              final article = _newsArticles[i];
              final colors = gradients[i % gradients.length];
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: colors[0].withOpacity(0.35), blurRadius: 14, offset: const Offset(0, 6))],
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Icon(Icons.newspaper_rounded, size: 18, color: Colors.white),
                    const SizedBox(width: 8),
                    Expanded(child: Text(article['title']!,
                      style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                    )),
                  ]),
                  const SizedBox(height: 8),
                  Text(article['description']!,
                    style: GoogleFonts.plusJakartaSans(fontSize: 11, color: Colors.white.withOpacity(0.85), height: 1.4),
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    Container(width: 5, height: 5, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.7))),
                    const SizedBox(width: 6),
                    Text(article['source']!,
                      style: GoogleFonts.plusJakartaSans(fontSize: 10, color: Colors.white.withOpacity(0.75), fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    Text('Live Update', style: GoogleFonts.plusJakartaSans(
                      fontSize: 9, color: Colors.white.withOpacity(0.6), letterSpacing: 0.5,
                    )),
                  ]),
                ]),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildReminderCard() {
    final upcoming = _tasks.where((t) => t.taskDateTime.isAfter(DateTime.now())).take(2).toList();

    return GestureDetector(
      onTap: _openReminder,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(color: const Color(0xFF6C3CE1).withOpacity(0.1), blurRadius: 20, offset: const Offset(0, 8)),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                right: -20, top: -20,
                child: Container(
                  width: 100, height: 100,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF6C3CE1).withOpacity(0.05)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [Color(0xFF00C9A7), Color(0xFF007B6E)]),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.alarm_rounded, color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Text('Reminders', style: GoogleFonts.sora(
                          fontSize: 16, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A2E),
                        )),
                        const Spacer(),
                        if (_tasks.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6C3CE1).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text('${_tasks.length} tasks', style: GoogleFonts.plusJakartaSans(
                              fontSize: 11, color: const Color(0xFF6C3CE1), fontWeight: FontWeight.w700,
                            )),
                          ),
                        const SizedBox(width: 8),
                        const Icon(Icons.chevron_right_rounded, color: Color(0xFF9CA3AF), size: 22),
                      ],
                    ),

                    const SizedBox(height: 16),

                    if (upcoming.isEmpty)
                      Row(children: [
                        Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                            color: const Color(0xFF6C3CE1).withOpacity(0.08),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.add_rounded, color: Color(0xFF6C3CE1), size: 20),
                        ),
                        const SizedBox(width: 12),
                        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('No upcoming tasks', style: GoogleFonts.sora(
                            fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF1A1A2E),
                          )),
                          Text('Tap to add a reminder →', style: GoogleFonts.plusJakartaSans(
                            fontSize: 11, color: const Color(0xFF9CA3AF),
                          )),
                        ]),
                      ])
                    else
                      ...upcoming.map((t) {
                        final diff = t.taskDateTime.difference(DateTime.now());
                        final isOverdue = diff.isNegative;
                        String timeLeft;
                        if (isOverdue) {
                          timeLeft = 'Time\'s up! ⚡';
                        } else if (diff.inHours > 0) {
                          timeLeft = '${diff.inHours}h ${diff.inMinutes % 60}m left';
                        } else if (diff.inMinutes > 0) {
                          timeLeft = '${diff.inMinutes}m ${diff.inSeconds % 60}s left';
                        } else {
                          timeLeft = '${diff.inSeconds}s left';
                        }
                        final Color taskColor = isOverdue ? Colors.red
                            : diff.inMinutes < 10 ? Colors.red
                            : diff.inMinutes < 60 ? Colors.orange
                            : const Color(0xFF00C9A7);

                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: taskColor.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: taskColor.withOpacity(0.2)),
                          ),
                          child: Row(children: [
                            Icon(Icons.alarm_rounded, color: taskColor, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(t.name, style: GoogleFonts.sora(
                                  fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A2E),
                                ), maxLines: 1, overflow: TextOverflow.ellipsis),
                                Text(timeLeft, style: GoogleFonts.plusJakartaSans(
                                  fontSize: 10, color: taskColor, fontWeight: FontWeight.w600,
                                )),
                              ]),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: taskColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(timeLeft.split(' ').first, style: GoogleFonts.sora(
                                fontSize: 12, fontWeight: FontWeight.w700, color: taskColor,
                              )),
                            ),
                          ]),
                        );
                      }),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    final items = [
      _NavData(icon: Icons.home_rounded, label: 'Home', index: 0),
      _NavData(icon: Icons.alarm_rounded, label: 'Reminder', index: 1),
      _NavData(icon: Icons.emoji_events_rounded, label: 'Success', index: 3),
      _NavData(icon: Icons.person_rounded, label: 'Profile', index: 4),
    ];

    return Container(
      height: 72,
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 20, offset: const Offset(0, -5)),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              ...items.sublist(0, 2).map((item) => _buildNavItem(item)),

              // Center FAB space
              const SizedBox(width: 64),

              ...items.sublist(2).map((item) => _buildNavItem(item)),
            ],
          ),

          // Center FAB
          Positioned(
            top: -12,
            child: GestureDetector(
              onTap: _openAIAssistant,
              child: Container(
                width: 60, height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF6C3CE1), Color(0xFFB06AB3)],
                  ),
                  boxShadow: [
                    BoxShadow(color: const Color(0xFF6C3CE1).withOpacity(0.5), blurRadius: 20, spreadRadius: 2, offset: const Offset(0, 4)),
                  ],
                ),
                child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 28),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(_NavData item) {
    final isSelected = _selectedIndex == item.index;
    final VoidCallback onTap = () {
      setState(() => _selectedIndex = item.index);
      if (item.index == 1) _openReminder();
      else if (item.index == 3) _openSuccess();
      else if (item.index == 4) _openProfile();
    };

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 60, height: 60,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF6C3CE1).withOpacity(0.1) : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                item.icon,
                size: 22,
                color: isSelected ? const Color(0xFF6C3CE1) : const Color(0xFF9CA3AF),
              ),
            ),
            Text(
              item.label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 9.5,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? const Color(0xFF6C3CE1) : const Color(0xFF9CA3AF),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickAction {
  final IconData icon;
  final String label;
  final List<Color> gradient;
  final VoidCallback onTap;
  const _QuickAction({required this.icon, required this.label, required this.gradient, required this.onTap});
}

class _NavData {
  final IconData icon;
  final String label;
  final int index;
  const _NavData({required this.icon, required this.label, required this.index});
}
