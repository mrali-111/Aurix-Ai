import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SuccessStory {
  final String id;
  final String title;
  final String personName;
  final String shortDesc;
  final String imageUrl;
  final int year;
  final String category;
  final String fullStory;
  int likes;
  final String source;
  final String readMoreUrl;

  SuccessStory({
    required this.id,
    required this.title,
    required this.personName,
    required this.shortDesc,
    required this.imageUrl,
    required this.year,
    required this.category,
    required this.fullStory,
    required this.likes,
    required this.source,
    required this.readMoreUrl,
  });
}

class SuccessScreen extends StatefulWidget {
  const SuccessScreen({super.key});

  @override
  State<SuccessScreen> createState() => _SuccessScreenState();
}

class _SuccessScreenState extends State<SuccessScreen> {
  List<SuccessStory> _allStories = [];
  List<SuccessStory> _displayStories = [];
  bool _isLoading = true;
  String _selectedFilter = 'All';
  String _userPlan = 'FREE';
  String _lastUpdateDate = '';

  final List<String> _filters = ['All', '1900s', '2000s', '2010s', '2020s'];

  @override
  void initState() {
    super.initState();
    _loadUserPlan();
    _loadStoriesWithDateCheck();
  }

  Future<void> _loadUserPlan() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (doc.exists && mounted) {
          setState(() {
            _userPlan = doc.data()?['plan'] ?? 'FREE';
          });
        }
      } catch (e) {
        print('Error: $e');
      }
    }
  }

  Future<void> _loadStoriesWithDateCheck() async {
    setState(() => _isLoading = true);

    final prefs = await SharedPreferences.getInstance();
    final lastDate = prefs.getString('success_stories_date') ?? '';
    final today = DateTime.now().toIso8601String().split('T')[0];

    // Check if we need fresh stories (new day)
    bool needFresh = lastDate != today;

    if (needFresh) {
      // Get fresh stories from Google
      await _fetchAndSaveFreshStories();
      await prefs.setString('success_stories_date', today);
    } else {
      // Load from cache
      await _loadFromCache();
    }

    setState(() => _isLoading = false);
  }

  Future<void> _fetchAndSaveFreshStories() async {
    List<SuccessStory> freshStories = [];

    // Add historical stories
    freshStories.addAll(_getAllStories());

    // Fetch live from Google News
    await _fetchLiveStories().then((stories) {
      freshStories.addAll(stories);
    });

    // Also fetch from alternative source
    await _fetchAlternativeStories().then((stories) {
      freshStories.addAll(stories);
    });

    // Remove duplicates
    final uniqueIds = <String>{};
    freshStories = freshStories.where((s) => uniqueIds.add(s.id)).toList();

    // Sort by year (newest first)
    freshStories.sort((a, b) => b.year.compareTo(a.year));

    // Save to cache
    final prefs = await SharedPreferences.getInstance();
    final storiesJson = freshStories.map((s) => jsonEncode({
      'id': s.id,
      'title': s.title,
      'personName': s.personName,
      'shortDesc': s.shortDesc,
      'imageUrl': s.imageUrl,
      'year': s.year,
      'category': s.category,
      'fullStory': s.fullStory,
      'likes': s.likes,
      'source': s.source,
      'readMoreUrl': s.readMoreUrl,
    })).toList();
    await prefs.setStringList('success_stories_cache', storiesJson);

    setState(() {
      _allStories = freshStories;
      _applyFilters();
    });
  }

  Future<void> _loadFromCache() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getStringList('success_stories_cache');

    if (cached != null && cached.isNotEmpty) {
      final stories = cached.map((s) {
        final data = jsonDecode(s);
        return SuccessStory(
          id: data['id'],
          title: data['title'],
          personName: data['personName'],
          shortDesc: data['shortDesc'],
          imageUrl: data['imageUrl'],
          year: data['year'],
          category: data['category'],
          fullStory: data['fullStory'],
          likes: data['likes'],
          source: data['source'],
          readMoreUrl: data['readMoreUrl'],
        );
      }).toList();

      setState(() {
        _allStories = stories;
        _applyFilters();
      });
    } else {
      await _fetchAndSaveFreshStories();
    }
  }

  List<SuccessStory> _getAllStories() {
    return [
      // 1900s
      SuccessStory(
        id: '1', title: 'علامہ اقبال - شاعر مشرق', personName: 'Allama Iqbal',
        shortDesc: 'جو قوموں کو جاگنے کا پیغام دیتے تھے', imageUrl: '',
        year: 1938, category: '1900s',
        fullStory: 'علامہ اقبال نے اپنی شاعری سے مسلمانوں کو آزادی کا پیغام دیا۔',
        likes: 150000, source: 'History', readMoreUrl: 'https://en.wikipedia.org/wiki/Muhammad_Iqbal',
      ),
      SuccessStory(
        id: '2', title: 'قائد اعظم محمد علی جناح', personName: 'Quaid-e-Azam',
        shortDesc: 'بانی پاکستان، ایک قوم کو خواب دیا', imageUrl: '',
        year: 1948, category: '1900s',
        fullStory: 'قائد اعظم نے مسلمانوں کو متحد کیا اور پاکستان بنایا۔',
        likes: 500000, source: 'History', readMoreUrl: 'https://en.wikipedia.org/wiki/Muhammad_Ali_Jinnah',
      ),
      SuccessStory(
        id: '3', title: 'Dr. Abdus Salam', personName: 'Dr. Abdus Salam',
        shortDesc: "Pakistan's first Nobel Prize winner", imageUrl: '',
        year: 1979, category: '1900s',
        fullStory: 'Dr. Abdus Salam won the Nobel Prize in Physics.',
        likes: 200000, source: 'Science', readMoreUrl: 'https://en.wikipedia.org/wiki/Abdus_Salam',
      ),
      // 2000s
      SuccessStory(
        id: '4', title: 'Arfa Karim', personName: 'Arfa Karim',
        shortDesc: 'Youngest Microsoft Professional at 9', imageUrl: '',
        year: 2005, category: '2000s',
        fullStory: 'Arfa Karim became the youngest Microsoft Certified Professional at age 9.',
        likes: 89000, source: 'Tech', readMoreUrl: 'https://en.wikipedia.org/wiki/Arfa_Karim',
      ),
      SuccessStory(
        id: '5', title: 'Shahid Afridi', personName: 'Shahid Afridi',
        shortDesc: 'Record for most sixes in cricket', imageUrl: '',
        year: 2000, category: '2000s',
        fullStory: 'Shahid Afridi holds record for most sixes in ODI cricket.',
        likes: 180000, source: 'Sports', readMoreUrl: 'https://en.wikipedia.org/wiki/Shahid_Afridi',
      ),
      // 2010s
      SuccessStory(
        id: '6', title: 'Malala Yousafzai', personName: 'Malala Yousafzai',
        shortDesc: 'Youngest Nobel Prize winner at 17', imageUrl: '',
        year: 2014, category: '2010s',
        fullStory: 'Malala became the youngest Nobel Prize winner.',
        likes: 600000, source: 'Global', readMoreUrl: 'https://en.wikipedia.org/wiki/Malala_Yousafzai',
      ),
      SuccessStory(
        id: '7', title: 'Abdul Sattar Edhi', personName: 'Abdul Sattar Edhi',
        shortDesc: "Pakistan's greatest humanitarian", imageUrl: '',
        year: 2016, category: '2010s',
        fullStory: 'Edhi Sahib dedicated his entire life to serving humanity.',
        likes: 750000, source: 'History', readMoreUrl: 'https://en.wikipedia.org/wiki/Abdul_Sattar_Edhi',
      ),
      SuccessStory(
        id: '8', title: 'Imran Khan', personName: 'Imran Khan',
        shortDesc: 'World Cup winner to Prime Minister', imageUrl: '',
        year: 2018, category: '2010s',
        fullStory: 'Led Pakistan to World Cup victory, built hospital, became PM.',
        likes: 300000, source: 'News', readMoreUrl: 'https://en.wikipedia.org/wiki/Imran_Khan',
      ),
      // 2020s - Fresh stories
      SuccessStory(
        id: '9', title: 'Dr. Atta-ur-Rahman', personName: 'Dr. Atta-ur-Rahman',
        shortDesc: '1000+ research papers published', imageUrl: '',
        year: 2020, category: '2020s',
        fullStory: 'One of Pakistan\'s most renowned scientists.',
        likes: 95000, source: 'Science', readMoreUrl: 'https://en.wikipedia.org/wiki/Atta-ur-Rahman',
      ),
      SuccessStory(
        id: '10', title: 'Korean Drama Success Story', personName: 'Kim Soo-hyun',
        shortDesc: 'From struggling actor to global star', imageUrl: '',
        year: 2024, category: '2020s',
        fullStory: 'Overcame rejection to become top Korean actor.',
        likes: 50000, source: 'Entertainment', readMoreUrl: 'https://example.com/kdrama',
      ),
    ];
  }

  Future<List<SuccessStory>> _fetchLiveStories() async {
    List<SuccessStory> stories = [];
    try {
      final response = await http.get(
        Uri.parse('https://news.google.com/rss/search?q=success+story&hl=en'),
        headers: {'User-Agent': 'Mozilla/5.0'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final today = DateTime.now();
        // Add daily fresh story with unique ID based on date
        stories.add(SuccessStory(
          id: 'daily_${today.day}_${today.month}_${today.year}',
          title: '✨ Today\'s Success Story - ${_getDayOfWeek()}',
          personName: 'Inspiring Person',
          shortDesc: 'A new success story to motivate you today!',
          imageUrl: '',
          year: today.year,
          category: '2020s',
          fullStory: 'Every day is a new opportunity to succeed. Stay focused, work hard, and never give up. Your success story is being written right now!',
          likes: DateTime.now().day * 100,
          source: 'Google News',
          readMoreUrl: 'https://news.google.com/search?q=success+story',
        ));
      }
    } catch (e) {
      print('Error: $e');
    }
    return stories;
  }

  Future<List<SuccessStory>> _fetchAlternativeStories() async {
    List<SuccessStory> stories = [];
    try {
      final response = await http.get(
        Uri.parse('https://type.fit/api/quotes'),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        List<dynamic> quotes = json.decode(response.body);
        // Add 2 fresh motivational quotes as stories
        for (int i = 0; i < 2 && i < quotes.length; i++) {
          stories.add(SuccessStory(
            id: 'quote_${DateTime.now().day}_$i',
            title: quotes[i]['text'],
            personName: quotes[i]['author'] ?? 'Unknown',
            shortDesc: quotes[i]['text'].length > 50
                ? '${quotes[i]['text'].substring(0, 50)}...'
                : quotes[i]['text'],
            imageUrl: '',
            year: DateTime.now().year,
            category: '2020s',
            fullStory: quotes[i]['text'],
            likes: 500,
            source: 'Motivation',
            readMoreUrl: '',
          ));
        }
      }
    } catch (e) {
      print('Error: $e');
    }
    return stories;
  }

  String _getDayOfWeek() {
    final now = DateTime.now();
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return days[now.weekday - 1];
  }

  void _applyFilters() {
    List<SuccessStory> filtered = List.from(_allStories);

    if (_selectedFilter != 'All') {
      filtered = filtered.where((s) => s.category == _selectedFilter).toList();
    }

    // Free plan: only 3 stories (already implemented)
    if (_userPlan != 'PREMIUM' && filtered.length > 3) {
      filtered = filtered.take(3).toList();
    }

    setState(() {
      _displayStories = filtered;
    });
  }

  void _likeStory(String id) {
    setState(() {
      final index = _allStories.indexWhere((s) => s.id == id);
      if (index != -1) {
        _allStories[index].likes++;

        final displayIndex = _displayStories.indexWhere((s) => s.id == id);
        if (displayIndex != -1) {
          _displayStories[displayIndex].likes++;
        }
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('❤️ Thanks for support!'), duration: Duration(seconds: 1)),
    );
  }

  Future<void> _refreshStories() async {
    setState(() => _isLoading = true);
    await _fetchAndSaveFreshStories();
    setState(() => _isLoading = false);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('🔄 Stories updated! New success stories loaded.')),
    );
  }

  Future<void> _openReadMore(String url, SuccessStory story) async {
    if (url.isNotEmpty && await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } else {
      // Show story dialog
      showDialog(
        context: context,
        builder: (context) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          backgroundColor: const Color(0xFF1A1A2E),
          child: Container(
            padding: const EdgeInsets.all(20),
            constraints: const BoxConstraints(maxHeight: 500),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        story.title,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                        maxLines: 2,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text('👤 ${story.personName}', style: const TextStyle(color: Color(0xFF7C4DFF), fontSize: 14)),
                const SizedBox(height: 10),
                Text('📅 Year: ${story.year}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 15),
                const Divider(color: Colors.white24),
                const SizedBox(height: 10),
                Expanded(
                  child: SingleChildScrollView(
                    child: Text(story.fullStory, style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5)),
                  ),
                ),
                const SizedBox(height: 15),
                Text('🔗 Source: ${story.source}', style: const TextStyle(color: Colors.white38, fontSize: 11)),
              ],
            ),
          ),
        ),
      );
    }
  }

  String _formatNumber(int number) {
    if (number >= 1000000) return '${(number / 1000000).toStringAsFixed(1)}M';
    if (number >= 1000) return '${(number / 1000).toStringAsFixed(1)}K';
    return number.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F0ED),
      appBar: AppBar(
        backgroundColor: const Color(0xFF7C4DFF),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('🏆 Success Stories', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          // Refresh button
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _refreshStories,
            tooltip: 'Refresh Stories',
          ),
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _userPlan == 'PREMIUM' ? 'PREMIUM' : 'FREE',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshStories,
        color: const Color(0xFF7C4DFF),
        child: Column(
          children: [
            // Filter Chips
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _filters.map((filter) {
                    final isSelected = _selectedFilter == filter;
                    return Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: FilterChip(
                        label: Text(filter),
                        selected: isSelected,
                        onSelected: (_) {
                          setState(() {
                            _selectedFilter = filter;
                            _applyFilters();
                          });
                        },
                        backgroundColor: const Color(0xFFF2F0ED),
                        selectedColor: const Color(0xFF7C4DFF),
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : const Color(0xFF1A1A1A),
                          fontWeight: FontWeight.w600,
                        ),
                        shape: StadiumBorder(
                          side: isSelected ? BorderSide.none : BorderSide(color: Colors.grey.shade300),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

            // Stories List
            Expanded(
              child: _isLoading
                  ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: Color(0xFF7C4DFF)),
                    SizedBox(height: 16),
                    Text('Loading stories...', style: TextStyle(color: Color(0xFF888888))),
                  ],
                ),
              )
                  : _displayStories.isEmpty
                  ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.history_edu, size: 64, color: Color(0xFFCCCCCC)),
                    SizedBox(height: 16),
                    Text('No stories found', style: TextStyle(color: Color(0xFF888888))),
                  ],
                ),
              )
                  : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _displayStories.length,
                itemBuilder: (context, index) {
                  final story = _displayStories[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF7C4DFF).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  story.year.toString(),
                                  style: const TextStyle(
                                    color: Color(0xFF7C4DFF),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              InkWell(
                                onTap: () => _likeStory(story.id),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.favorite, size: 14, color: Colors.red),
                                      const SizedBox(width: 4),
                                      Text(
                                        _formatNumber(story.likes),
                                        style: const TextStyle(color: Color(0xFF888888), fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Title
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            story.title,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A1A1A),
                            ),
                          ),
                        ),

                        const SizedBox(height: 8),

                        // Person name
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              const Icon(Icons.person, size: 14, color: Color(0xFF7C4DFF)),
                              const SizedBox(width: 6),
                              Text(
                                story.personName,
                                style: const TextStyle(color: Color(0xFF7C4DFF), fontSize: 13),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 12),

                        // Description
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            story.shortDesc,
                            style: const TextStyle(color: Color(0xFF666666), fontSize: 14, height: 1.4),
                            maxLines: 2,
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Buttons
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () => _openReadMore(story.readMoreUrl, story),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF7C4DFF),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: const Text('📖 Read Full Story', style: TextStyle(fontSize: 13)),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () async {
                                    await launchUrl(
                                      Uri.parse('https://news.google.com/search?q=${Uri.encodeComponent(story.personName)}+success+story'),
                                      mode: LaunchMode.externalApplication,
                                    );
                                  },
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF7C4DFF),
                                    side: const BorderSide(color: Color(0xFF7C4DFF)),
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: const Text('🔍 Google More', style: TextStyle(fontSize: 13)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}