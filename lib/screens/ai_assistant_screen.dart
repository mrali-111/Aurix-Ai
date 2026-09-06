import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';

// ==================== IMAGE API CONFIGS ====================
const String _cfAccountId1 = 'd0ecc32901240915c8e84c58dc25eac4';
const String _cfApiToken1 = '';
const String _cfAccountId2 = 'd0ecc32901240915c8e84c58dc25eac4';
const String _cfApiToken2 = '';
const String _cfAccountId3 = '2d06384d2db41af4b01525a181718f7b';
const String _cfApiToken3 = '';
const String _cfAccountId4 = '2d06384d2db41af4b01525a181718f7b';
const String _cfApiToken4 = '';
const String _cfImageModel = '@cf/black-forest-labs/flux-1-schnell';

// Qwen Image API
const String _qwenApiToken = 'tgp_v1_k_HJCJ6vJ02BeYQf5t6TlqfPkwSGTdpWPYgc3w1YHyQ';
const String _qwenAccountId = 'PASTE_QWEN_ACCOUNT_ID';
const String _qwenImageModel = '@cf/qwen/qwen1.5-14b-chat-awq';

// ==================== CHAT API CONFIGS ====================
const String _groqApiKey = '';
const String _groqBaseUrl = 'https://api.groq.com/openai/v1/chat/completions';
const String _groqFreeModel = 'llama-3.1-8b-instant';
const String _groqPremiumModel = 'llama-3.3-70b-versatile';

const String _geminiApiKey = 'REDACTED_GEMINI_API_KEY';
const String _geminiModel = 'gemini-2.5-flash';
const String _geminiEndpoint = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent';

const String _grokApiKey = '';
const String _grokModel = 'llama3-70b-8192';
const String _grokBaseUrl = 'https://api.x.ai/v1/chat/completions';

// ==================== MAIN WIDGET ====================
class AIAssistantScreen extends StatefulWidget {
  const AIAssistantScreen({super.key});

  @override
  State<AIAssistantScreen> createState() => _AIAssistantScreenState();
}

// ==================== MESSAGE MODEL ====================
class Message {
  final String id;
  final String content;
  final bool isUser;
  final DateTime timestamp;
  final Uint8List? imageBytes;
  final String? aspectRatio;

  Message({
    required this.id,
    required this.content,
    required this.isUser,
    required this.timestamp,
    this.imageBytes,
    this.aspectRatio,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'content': content,
    'isUser': isUser,
    'timestamp': timestamp.toIso8601String(),
    'hasImage': imageBytes != null,
  };

  factory Message.fromJson(Map<String, dynamic> json) => Message(
    id: json['id'],
    content: json['content'],
    isUser: json['isUser'],
    timestamp: DateTime.parse(json['timestamp']),
  );
}

// ==================== ENUMS ====================
enum ChatProvider { groq, gemini, grok }
enum ImageProvider { cloudflareFlux, qwen }

// ==================== STATE CLASS ====================
class _AIAssistantScreenState extends State<AIAssistantScreen>
    with TickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final stt.SpeechToText _speechToText = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  late AnimationController _micAnimController;
  late Animation<double> _micAnimation;

  List<Message> _messages = [];
  bool _isLoading = false;
  bool _isListening = false;
  bool _showVoiceMode = false;
  bool _showImageGenMode = false;
  String _recognizedText = '';
  String _typingIndicator = '○○○';
  int _typingCount = 0;
  Timer? _typingTimer;
  String _errorMessage = '';
  String _userPlan = 'FREE';
  String _selectedAspectRatio = '1:1';
  ChatProvider _selectedChatProvider = ChatProvider.groq;
  ImageProvider _selectedImageProvider = ImageProvider.cloudflareFlux;
  int _freeImageCount = 0;
  final int _maxFreeImages = 5;

  final List<Map<String, dynamic>> _aspectRatios = [
    {'value': '1:1', 'icon': Icons.crop_square, 'label': 'Square'},
    {'value': '16:9', 'icon': Icons.crop_16_9, 'label': 'Wide'},
    {'value': '9:16', 'icon': Icons.crop_portrait, 'label': 'Portrait'},
  ];

  static const String _systemPrompt =
      'You are Aurix AI, a smart friendly assistant. '
      'Reply in same language user writes (Urdu/English). '
      'Keep replies short (2-3 sentences). Be warm and conversational. '
      'If asked "who is your owner", reply: "My Owner Name is Ali Khan". '
      'You are text-only. Cannot generate images.';

  User? get _user => _auth.currentUser;


  // ==================== INIT ====================
  @override
  void initState() {
    super.initState();
    _setupMicAnimation();
    _setupTypingIndicator();
    _initializeSpeech();
    _loadMessages();
    _fetchUserPlan();
    _loadFreeImageCount();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    await [Permission.storage, Permission.photos, Permission.microphone].request();
  }

  Future<void> _fetchUserPlan() async {
    if (_user == null) return;
    try {
      final doc = await _firestore.collection('users').doc(_user!.uid).get();
      if (mounted) {
        setState(() {
          _userPlan = doc.data()?['plan'] ?? 'FREE';
        });
      }
    } catch (e) {
      debugPrint('Error fetching plan: $e');
    }
  }

  Future<void> _loadFreeImageCount() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _freeImageCount = prefs.getInt('free_images_used') ?? 0;
    });
  }

  Future<void> _incrementFreeImageCount() async {
    final prefs = await SharedPreferences.getInstance();
    int newCount = _freeImageCount + 1;
    await prefs.setInt('free_images_used', newCount);
    setState(() {
      _freeImageCount = newCount;
    });
  }

  // ==================== DISPLAY HELPERS ====================
  String _getChatModelDisplayName() {
    switch (_selectedChatProvider) {
      case ChatProvider.groq:
        return _userPlan == 'PREMIUM' ? 'Llama 3.3 70B' : 'llama-3.1-8b-instant';
      case ChatProvider.gemini:
        return 'Gemini 2.5 Flash';
      case ChatProvider.grok:
        return 'Grok 2';
    }
  }

  String _getImageModelDisplayName() {
    switch (_selectedImageProvider) {
      case ImageProvider.cloudflareFlux:
        return 'Flux Schnell';
      case ImageProvider.qwen:
        return '@cf/black-forest-labs/flux-1-schnell';
    }
  }

  // ==================== ANIMATIONS ====================
  void _setupMicAnimation() {
    _micAnimController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _micAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _micAnimController, curve: Curves.easeInOut),
    );
  }

  void _setupTypingIndicator() {
    _typingTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (_isLoading && mounted) {
        setState(() {
          _typingCount = (_typingCount + 1) % 4;
          _typingIndicator = '●' * _typingCount + '○' * (3 - _typingCount);
        });
      }
    });
  }

  // ==================== SPEECH ====================
  Future<void> _initializeSpeech() async {
    await _speechToText.initialize(
      onError: (e) => debugPrint('Speech error: ${e.errorMsg}'),
      onStatus: (s) {
        if (s == 'notListening' && mounted) {
          setState(() => _isListening = false);
          _micAnimController.stop();
        }
      },
    );
  }

  void _startListening() async {
    if (_isListening) return;

    try {
      bool available = await _speechToText.initialize(
        onError: (error) {
          debugPrint('Speech error: ${error.errorMsg}');
          if (mounted) {
            _showError('Microphone error: ${error.errorMsg}');
            setState(() => _isListening = false);
            _micAnimController.stop();
          }
        },
        onStatus: (status) {
          debugPrint('Speech status: $status');
          if (status == 'notListening' && mounted) {
            setState(() => _isListening = false);
            _micAnimController.stop();
          }
        },
      );

      if (!available) {
        _showError('Speech recognition not available');
        return;
      }

      if (mounted) setState(() => _isListening = true);
      _micAnimController.repeat(reverse: true);

      _speechToText.listen(
        onResult: (result) {
          debugPrint('Recognized: ${result.recognizedWords}');
          if (mounted) {
            setState(() {
              _recognizedText = result.recognizedWords;
            });
            if (result.finalResult && _recognizedText.isNotEmpty) {
              _stopListeningAndSend();
            }
          }
        },
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 5),
        partialResults: true,
        localeId: 'en_US',
      );
    } catch (e) {
      debugPrint('Start listening error: $e');
      _showError('Failed to start listening');
      setState(() => _isListening = false);
      _micAnimController.stop();
    }
  }

  void _stopListeningAndSend() async {
    try {
      await _speechToText.stop();
      if (mounted) {
        setState(() => _isListening = false);
        _micAnimController.stop();
      }
      if (_recognizedText.isNotEmpty) {
        final text = _recognizedText;
        if (mounted) {
          setState(() => _recognizedText = '');
        }
        await _sendMessage(text);
      } else if (mounted && _recognizedText.isEmpty) {
        _showError('No speech detected. Please try again.');
      }
    } catch (e) {
      debugPrint('Stop listening error: $e');
      if (mounted) {
        setState(() => _isListening = false);
        _micAnimController.stop();
      }
    }
  }

  Future<void> _speakText(String text) async {
    final clean = text.replaceAll(RegExp(r'[^\x00-\x7F\u0600-\u06FF\s\n]'), '');
    await _tts.setLanguage('en-US');
    await _tts.setPitch(1.0);
    await _tts.setSpeechRate(0.45);
    await _tts.speak(clean.trim());
  }

  // ==================== STORAGE ====================
  Future<void> _loadMessages() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('ai_chat_messages') ?? [];
    if (mounted) {
      setState(() {
        _messages = saved
            .map((e) => Message.fromJson(jsonDecode(e)))
            .toList()
            .reversed
            .toList();
      });
    }
  }

  Future<void> _saveMessages() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'ai_chat_messages',
      _messages.where((m) => m.imageBytes == null).map((m) => jsonEncode(m.toJson())).toList().reversed.toList(),
    );
  }

  Future<void> _saveImageToGallery(Uint8List imageBytes) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final tempFile = File('${tempDir.path}/aurix_$timestamp.jpg');
      await tempFile.writeAsBytes(imageBytes);
      final result = await ImageGallerySaverPlus.saveFile(
        tempFile.path,
        name: "AurixAI/aurix_$timestamp",
      );
      await tempFile.delete();
      if (result != null && (result['isSuccess'] == true || result == true)) {
        _showSuccess('✅ Saved to AurixAI folder!');
      } else {
        _showError('Failed to save image');
      }
    } catch (e) {
      _showError('Error: $e');
    }
  }

  // ==================== UI HELPERS ====================
  void _showSuccess(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          duration: const Duration(seconds: 2),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showError(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          duration: const Duration(seconds: 3),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _scrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut);
      }
    });
  }

  void _clearChat() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Clear Chat?'),
        content: const Text('All messages will be deleted permanently.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              if (mounted) setState(() => _messages.clear());
              _saveMessages();
              Navigator.pop(ctx);
            },
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // ==================== MODEL SELECTION UI ====================
  void _showChatModelSelector() {
    if (_userPlan != 'PREMIUM') {
      _showError('Model selection is only for Premium users! 💎');
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Select AI Chat Model',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                _chatModelOption(
                  'Llama 3.3 70B (Groq)',
                  'Fast & reliable',
                  ChatProvider.groq,
                  true,
                ),
                _chatModelOption(
                  'Gemini 2.5 Flash',
                  'Google\'s latest model',
                  ChatProvider.gemini,
                  _geminiApiKey != 'paste',
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _chatModelOption(String title, String subtitle, ChatProvider provider, bool available) {
    final isSelected = _selectedChatProvider == provider;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected ? const Color(0xFF7C4DFF) : Colors.transparent,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: ListTile(
        leading: Icon(
          provider == ChatProvider.groq ? Icons.auto_awesome :
          provider == ChatProvider.gemini ? Icons.star :
          Icons.rocket,
          color: isSelected ? const Color(0xFF7C4DFF) : Colors.grey,
        ),
        title: Text(title, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: isSelected ? const Icon(Icons.check_circle, color: Color(0xFF7C4DFF)) : null,
        enabled: available,
        onTap: available ? () {
          setState(() => _selectedChatProvider = provider);
          Navigator.pop(context);
        } : null,
      ),
    );
  }

  void _showImageModelSelector() {
    if (_userPlan != 'PREMIUM') {
      _showError('Model selection is only for Premium users! 💎');
      return;
    }
    bool fluxAvailable = _cfApiToken1 != 'paste'
        || _cfApiToken2 != 'paste';
    bool qwenAvailable = _qwenApiToken != ' Paste';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Select Image Model',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                _imageModelOption(
                  '(Cloudflare)',
                  'Fast image generation',
                  ImageProvider.cloudflareFlux,
                  fluxAvailable,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _imageModelOption(String title, String subtitle, ImageProvider provider, bool available) {
    final isSelected = _selectedImageProvider == provider;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected ? const Color(0xFF7C4DFF) : Colors.grey.shade300,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: ListTile(
        leading: Icon(
          Icons.image,
          color: isSelected ? const Color(0xFF7C4DFF) : Colors.grey,
        ),
        title: Text(title, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: isSelected ? const Icon(Icons.check_circle, color: Color(0xFF7C4DFF)) : null,
        enabled: available,
        onTap: available ? () {
          setState(() => _selectedImageProvider = provider);
          Navigator.pop(context);
        } : null,
      ),
    );
  }

  // ==================== IMAGE GENERATION ====================
  List<Map<String, String>> _getCloudflareConfigs() {
    final configs = <Map<String, String>>[];
    if (_cfAccountId1 != 'paste' && _cfApiToken1 != 'paste') {
      configs.add({'accountId': _cfAccountId1, 'token': _cfApiToken1});
    }
    if (_cfAccountId2 != 'paste' && _cfApiToken2 != 'paste') {
      configs.add({'accountId': _cfAccountId2, 'token': _cfApiToken2});
    }
    if (_cfAccountId3 != 'paste' && _cfApiToken3 != 'paste') {
      configs.add({'accountId': _cfAccountId3, 'token': _cfApiToken3});
    }
    if (_cfAccountId4 != 'paste' && _cfApiToken4 != 'paste') {
      configs.add({'accountId': _cfAccountId4, 'token': _cfApiToken4});
    }
    return configs;
  }

  Future<Uint8List?> _generateWithCloudflareFlux(String prompt) async {
    final configs = _getCloudflareConfigs();
    if (configs.isEmpty) {
      _showError('No Cloudflare API configured. Please add tokens.');
      return null;
    }

    String enhanced = prompt;
    switch (_selectedAspectRatio) {
      case '16:9':
        enhanced = '$prompt, cinematic wide shot, 16:9 aspect ratio';
        break;
      case '9:16':
        enhanced = '$prompt, portrait orientation, 9:16 aspect ratio';
        break;
      default:
        enhanced = '$prompt, square format, 1:1 aspect ratio';
    }

    for (final config in configs) {
      try {
        final url = Uri.parse(
          'https://api.cloudflare.com/client/v4/accounts/${config['accountId']}/ai/run/$_cfImageModel',
        );

        final response = await http.post(
          url,
          headers: {
            'Authorization': 'Bearer ${config['token']}',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'prompt': enhanced}),
        ).timeout(const Duration(seconds: 30));

        if (response.statusCode == 200) {
          final contentType = response.headers['content-type'] ?? '';

          if (contentType.contains('application/json')) {
            final jsonResponse = jsonDecode(response.body);
            if (jsonResponse['success'] == true && jsonResponse['result'] != null) {
              final result = jsonResponse['result'];
              if (result is Map && result['image'] != null) {
                return base64Decode(result['image']);
              } else if (result is String && result.startsWith('http')) {
                final imageResponse = await http.get(Uri.parse(result));
                if (imageResponse.statusCode == 200) {
                  return imageResponse.bodyBytes;
                }
              }
            }
          } else if (contentType.contains('image/')) {
            return response.bodyBytes;
          } else if (response.bodyBytes.length > 100) {
            return response.bodyBytes;
          }
        }
      } catch (e) {
        debugPrint('Cloudflare attempt failed with config ${config['accountId']}: $e');
        continue;
      }
    }
    return null;
  }

  Future<Uint8List?> _generateWithQwen(String prompt) async {
    if (_qwenApiToken == 'paste' || _qwenAccountId == '') {
      _showError('Qwen API not configured. Please add token.');
      return null;
    }

    String enhanced = prompt;
    switch (_selectedAspectRatio) {
      case '16:9':
        enhanced = '$prompt, cinematic wide shot, 16:9 aspect ratio';
        break;
      case '9:16':
        enhanced = '$prompt, portrait orientation, 9:16 aspect ratio';
        break;
      default:
        enhanced = '$prompt, square format, 1:1 aspect ratio';
    }

    try {
      final url = Uri.parse(
        'https://api.cloudflare.com/client/v4/accounts/$_qwenAccountId/ai/run/$_qwenImageModel',
      );

      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $_qwenApiToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'prompt': enhanced}),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final contentType = response.headers['content-type'] ?? '';

        if (contentType.contains('application/json')) {
          final jsonResponse = jsonDecode(response.body);
          if (jsonResponse['success'] == true && jsonResponse['result'] != null) {
            final result = jsonResponse['result'];
            if (result is Map && result['image'] != null) {
              return base64Decode(result['image']);
            } else if (result is String && result.startsWith('http')) {
              final imageResponse = await http.get(Uri.parse(result));
              if (imageResponse.statusCode == 200) {
                return imageResponse.bodyBytes;
              }
            }
          }
        } else if (contentType.contains('image/')) {
          return response.bodyBytes;
        } else if (response.bodyBytes.length > 100) {
          return response.bodyBytes;
        }
      }
    } catch (e) {
      debugPrint('Qwen generation error: $e');
    }
    return null;
  }

  Future<void> _generateImage(String prompt) async {
    // ✅ Free user limit check pehle
    if (_userPlan != 'PREMIUM') {
      if (_freeImageCount >= _maxFreeImages) {
        _showError('⚠️ Free plan finish $_maxFreeImages Images Only Free! Upgrade Premium 💎');
        return;
      }
    }

    if (prompt.isEmpty) {
      _showError('Please enter an image description');
      return;
    }

    setState(() {
      _isLoading = true;
      _typingCount = 0;
    });

    Uint8List? imageBytes;
    if (_selectedImageProvider == ImageProvider.cloudflareFlux) {
      imageBytes = await _generateWithCloudflareFlux(prompt);
    } else if (_selectedImageProvider == ImageProvider.qwen) {
      imageBytes = await _generateWithQwen(prompt);
    }

    if (imageBytes != null && mounted) {
      // ✅ Free user ka count increase karo (only on success)
      if (_userPlan != 'PREMIUM') {
        await _incrementFreeImageCount();
      }

      final newMessage = Message(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        content: prompt,
        isUser: false,
        timestamp: DateTime.now(),
        imageBytes: imageBytes,
        aspectRatio: _selectedAspectRatio,
      );

      setState(() {
        _messages.insert(0, newMessage);
        _isLoading = false;
        _showImageGenMode = false;
        _messageController.clear();
      });

      _scrollToTop();
      _saveMessages();

      // ✅ Success message with remaining count for free users
      if (_userPlan != 'PREMIUM') {
        int remaining = _maxFreeImages - _freeImageCount;
        _showSuccess('✅ Image generated! $remaining free images left');
      } else {
        _showSuccess('✅ Image generated!');
      }
    } else {
      // ✅ Better error feedback
      if (mounted) {
        _showError('Image generation failed. Check your API keys or try a different prompt.');
        setState(() => _isLoading = false);
      }
    }
  }

  // ==================== CHAT API CALLS ====================
  Future<String?> _callGroqAPI(String message, List<Map<String, dynamic>> history) async {
    try {
      final response = await http.post(
        Uri.parse(_groqBaseUrl),
        headers: {
          'Authorization': 'Bearer $_groqApiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': _userPlan == 'PREMIUM' ? _groqPremiumModel : _groqFreeModel,
          'messages': [
            {'role': 'system', 'content': _systemPrompt},
            ...history,
            {'role': 'user', 'content': message},
          ],
          'temperature': 0.2,
          'max_tokens': 400,
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['choices'][0]['message']['content']?.toString().trim();
      } else {
        final error = jsonDecode(response.body);
        debugPrint('Groq error: ${error['error']?['message']}');
        return null;
      }
    } catch (e) {
      debugPrint('Groq exception: $e');
      return null;
    }
  }

  Future<String?> _callGeminiAPI(String message, List<Map<String, dynamic>> history) async {
    if (_geminiApiKey == 'paste') {
      debugPrint('Gemini API key not configured');
      return null;
    }

    try {
      final url = Uri.parse('$_geminiEndpoint?key=$_geminiApiKey');

      final List<Map<String, dynamic>> contents = [];
      for (final h in history) {
        contents.add({
          'role': h['role'] == 'user' ? 'user' : 'model',
          'parts': [{'text': h['content']}],
        });
      }
      contents.add({
        'role': 'user',
        'parts': [{'text': message}],
      });

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': contents,
          'generationConfig': {
            'temperature': 0.2,
            'maxOutputTokens': 400,
          },
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final candidates = data['candidates'] as List?;
        if (candidates != null && candidates.isNotEmpty) {
          final content = candidates[0]['content'];
          final parts = content?['parts'] as List?;
          if (parts != null && parts.isNotEmpty) {
            return parts[0]['text']?.toString().trim();
          }
        }
      } else {
        debugPrint('Gemini error: ${response.body}');
      }
    } catch (e) {
      debugPrint('Gemini exception: $e');
    }
    return null;
  }

  Future<String?> _callGrokAPI(String message, List<Map<String, dynamic>> history) async {
    if (_grokApiKey == 'paste') {
      debugPrint('Grok API key not configured');
      return null;
    }

    try {
      final response = await http.post(
        Uri.parse(_grokBaseUrl),
        headers: {
          'Authorization': 'Bearer $_grokApiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': _grokModel,
          'messages': [
            {'role': 'system', 'content': _systemPrompt},
            ...history,
            {'role': 'user', 'content': message},
          ],
          'temperature': 0.2,
          'max_tokens': 400,
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['choices'][0]['message']['content']?.toString().trim();
      } else {
        debugPrint('Grok error: ${response.body}');
      }
    } catch (e) {
      debugPrint('Grok exception: $e');
    }
    return null;
  }

  // ==================== SEND MESSAGE ====================
  Future<void> _sendMessage(String message) async {
    final trimmed = message.trim();
    if (trimmed.isEmpty || _isLoading) return;

    String lower = message.toLowerCase();

    if (lower.contains('owner') ||
        lower.contains('created you') ||
        lower.contains('made you') ||
        lower.contains('kis ne banaya') ||
        lower.contains('owner kaun') ||
        lower.contains('tumhara owner')) {
      _addAIMessage("My Owner Name is Ali Khan");
      _speakText("My Owner Name is Ali Khan");
      return;
    }

    setState(() {
      _errorMessage = '';
      _messages.insert(0, Message(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        content: trimmed,
        isUser: true,
        timestamp: DateTime.now(),
      ));
      _isLoading = true;
      _typingCount = 0;
    });
    _messageController.clear();
    _scrollToTop();

    final rawHistory = _messages.skip(1).take(10).toList().reversed.toList();
    final List<Map<String, dynamic>> history = [];
    String? lastRole;
    for (final m in rawHistory) {
      if (m.imageBytes != null) continue;
      final role = m.isUser ? 'user' : 'assistant';
      if (role == lastRole) continue;
      history.add({'role': role, 'content': m.content});
      lastRole = role;
    }

    String? reply;

    if (_userPlan != 'PREMIUM') {
      reply = await _callGroqAPI(trimmed, history);
    } else {
      switch (_selectedChatProvider) {
        case ChatProvider.groq:
          reply = await _callGroqAPI(trimmed, history);
          break;
        case ChatProvider.gemini:
          reply = await _callGeminiAPI(trimmed, history);
          break;
        case ChatProvider.grok:
          reply = await _callGrokAPI(trimmed, history);
          break;
      }
    }

    if (reply != null && reply.isNotEmpty) {
      _addAIMessage(reply);
      if (_showVoiceMode && reply.isNotEmpty) {
        _speakText(reply);
      }
    } else {
      _showError('AI failed to respond. Try switching model or check API keys.');
    }

    if (mounted) setState(() => _isLoading = false);
    _saveMessages();
    _scrollToTop();
  }

  void _addAIMessage(String content) {
    if (mounted) {
      setState(() => _messages.insert(0, Message(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        content: content,
        isUser: false,
        timestamp: DateTime.now(),
      )));
      _saveMessages();
    }
  }

  // ==================== BUILD UI ====================
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvoked: (_) {
        _tts.stop();
        _speechToText.stop();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF3E5F5),
        appBar: _buildAppBar(),
        body: Column(
          children: [
            if (_errorMessage.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                color: Colors.red.shade50,
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red.shade400, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_errorMessage, style: TextStyle(color: Colors.red.shade700, fontSize: 13)),
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _errorMessage = ''),
                      child: Icon(Icons.close, color: Colors.red.shade400, size: 16),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: _messages.isEmpty ? _buildWelcome() : _buildChatList(),
            ),
            // ✅ FIX: Image gen container ab FREE aur PREMIUM dono ke liye dikhega
            if (_showImageGenMode)
              _buildImageGenContainer()
            else if (_showVoiceMode)
              _buildVoiceInput()
            else
              _buildInputBar(),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Color(0xFFF3E5F5),
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFF1A1A1A), size: 20),
        onPressed: () {
          _tts.stop();
          _speechToText.stop();
          Navigator.pop(context);
        },
      ),
      title: SizedBox(
        height: 50,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF9C27B0), Color(0xFF7C4DFF)]),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.smart_toy, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: GestureDetector(
                onTap: _showChatModelSelector,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            _getChatModelDisplayName(),
                            style: const TextStyle(color: Color(0xFF1A1A1A), fontSize: 15, fontWeight: FontWeight.w700),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (_userPlan == 'PREMIUM')
                          const Icon(Icons.arrow_drop_down, color: Color(0xFF7C4DFF), size: 20),
                      ],
                    ),
                    Row(
                      children: [
                        Text(
                          _isLoading ? 'Soch raha hai... 🧠' : 'Online ⚡',
                          style: TextStyle(
                            fontSize: 10,
                            color: _isLoading ? const Color(0xFFFF9800) : const Color(0xFF4CAF50),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                            color: _userPlan == 'PREMIUM' ? const Color(0xFF9C27B0).withOpacity(0.15) : const Color(0xFF4CAF50).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _userPlan == 'PREMIUM' ? '💎' : '🆓',
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w600,
                              color: _userPlan == 'PREMIUM' ? const Color(0xFF9C27B0) : const Color(0xFF4CAF50),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (_userPlan == 'PREMIUM')
          IconButton(
            icon: Icon(
              _selectedImageProvider == ImageProvider.cloudflareFlux ? Icons.image : Icons.image_outlined,
              color: const Color(0xFF7C4DFF),
            ),
            tooltip: 'Image Model: ${_getImageModelDisplayName()}',
            onPressed: _showImageModelSelector,
          ),
        IconButton(
          icon: const Icon(Icons.delete_outline, color: Color(0xFF7C4DFF), size: 20),
          onPressed: _clearChat,
          tooltip: 'Clear Chat',
        ),
      ],
    );
  }

  Widget _buildWelcome() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 20),
          Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF9C27B0), Color(0xFF7C4DFF)]),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: const Color(0xFF7C4DFF).withOpacity(0.35), blurRadius: 28, spreadRadius: 4)
              ],
            ),
            child: const Icon(Icons.smart_toy, color: Colors.white, size: 44),
          ),
          const SizedBox(height: 20),
          const Text('Aurix AI', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A))),
          const SizedBox(height: 8),
          Text(
            'Ask anything in Urdu or English\nVoice or Text — both supported!',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: Color(0xFF888888), height: 1.6),
          ),
          if (_userPlan == 'PREMIUM') ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [Colors.purple.shade100, Colors.deepPurple.shade100]),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.image, size: 16, color: Color(0xFF9C27B0)),
                  SizedBox(width: 4),
                  Text(
                    'Image Generation Enabled',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF9C27B0),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 16)],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('💡 Try asking:', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF7C4DFF), fontSize: 14)),
                const SizedBox(height: 14),
                _chip('Hello! How are you?'),
                _chip('Help me learn Flutter'),
                _chip('Tell me a funny joke 😄'),
                if (_userPlan == 'PREMIUM') ...[
                  _chip('🖼️ Generate image of beautiful sunset'),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () {
          if (text.contains('🖼️')) {
            // Free aur premium dono ke liye image gen mode open karo
            setState(() {
              _showImageGenMode = true;
              _showVoiceMode = false;
              _messageController.text = text.replaceAll('🖼️ Generate image of ', '');
            });
          } else {
            _sendMessage(text.replaceAll('🖼️ ', ''));
          }
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: const Color(0xFFF8F5FF),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF7C4DFF).withOpacity(0.25)),
          ),
          child: Text(text, style: const TextStyle(fontSize: 13, color: Color(0xFF333333))),
        ),
      ),
    );
  }

  Widget _buildChatList() {
    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      itemCount: _messages.length + (_isLoading ? 1 : 0),
      itemBuilder: (ctx, i) {
        if (i == 0 && _isLoading) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                _aiAvatar(),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8)],
                  ),
                  child: Text(_typingIndicator, style: const TextStyle(fontSize: 18, letterSpacing: 2, color: Color(0xFF7C4DFF))),
                ),
              ],
            ),
          );
        }
        final idx = _isLoading ? i - 1 : i;
        if (idx >= _messages.length) return const SizedBox.shrink();
        return _buildBubble(_messages[idx]);
      },
    );
  }

  Widget _aiAvatar() {
    return Container(
      width: 32,
      height: 32,
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [Color(0xFF9C27B0), Color(0xFF7C4DFF)]),
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.smart_toy, color: Colors.white, size: 16),
    );
  }

  Widget _buildBubble(Message msg) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: msg.isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: msg.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!msg.isUser) ...[
                _aiAvatar(),
                const SizedBox(width: 8)
              ],
              Flexible(
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.75,
                  ),
                  decoration: BoxDecoration(
                    gradient: msg.isUser ? const LinearGradient(colors: [Color(0xFF9C27B0), Color(0xFF7C4DFF)]) : null,
                    color: msg.isUser ? null : Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(msg.isUser ? 18 : 4),
                      bottomRight: Radius.circular(msg.isUser ? 4 : 18),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: msg.isUser ? const Color(0xFF7C4DFF).withOpacity(0.25) : Colors.black.withOpacity(0.07),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Column(
                    crossAxisAlignment: msg.isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                    children: [
                      Text(
                        msg.content,
                        style: TextStyle(fontSize: 14, color: msg.isUser ? Colors.white : const Color(0xFF222222), height: 1.4),
                        softWrap: true,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat('hh:mm a').format(msg.timestamp),
                        style: TextStyle(fontSize: 10, color: msg.isUser ? Colors.white.withOpacity(0.55) : const Color(0xFFAAAAAA)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (msg.imageBytes != null) ...[
            const SizedBox(height: 8),
            Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.85,
                maxHeight: msg.aspectRatio == '16:9' ? 200 : (msg.aspectRatio == '9:16' ? 400 : 250),
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: GestureDetector(
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (ctx) => Dialog(
                            backgroundColor: Colors.transparent,
                            child: Stack(
                              children: [
                                InteractiveViewer(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: Image.memory(msg.imageBytes!, fit: BoxFit.contain),
                                  ),
                                ),
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: IconButton(
                                    icon: const Icon(Icons.close, color: Colors.white),
                                    onPressed: () => Navigator.pop(context),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                      child: Image.memory(
                        msg.imageBytes!,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            height: 200,
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.broken_image, size: 48, color: Colors.red),
                                  SizedBox(height: 8),
                                  Text('Failed to load image', style: TextStyle(color: Colors.red)),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.download, color: Colors.white, size: 18),
                        onPressed: () => _saveImageToGallery(msg.imageBytes!),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.aspect_ratio, size: 12, color: Colors.white),
                          const SizedBox(width: 4),
                          Text(
                            msg.aspectRatio ?? '1:1',
                            style: const TextStyle(color: Colors.white, fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildImageGenContainer() {
    return Container(
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // ✅ Image model selector - only for premium
                  if (_userPlan == 'PREMIUM')
                    GestureDetector(
                      onTap: _showImageModelSelector,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0EBFF),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.image, size: 16, color: Color(0xFF7C4DFF)),
                            const SizedBox(width: 4),
                            Text(
                              _getImageModelDisplayName(),
                              style: const TextStyle(fontSize: 12, color: Color(0xFF7C4DFF), fontWeight: FontWeight.w600),
                            ),
                            const Icon(Icons.arrow_drop_down, size: 16, color: Color(0xFF7C4DFF)),
                          ],
                        ),
                      ),
                    )
                  else
                  // ✅ Free users ke liye simple label
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0EBFF),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.image, size: 16, color: Color(0xFF7C4DFF)),
                          const SizedBox(width: 4),
                          Text(
                            'Free: $_freeImageCount/$_maxFreeImages',
                            style: const TextStyle(fontSize: 12, color: Color(0xFF7C4DFF), fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _showImageGenMode = false;
                        _messageController.clear();
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: const Icon(Icons.close, color: Color(0xFF7C4DFF), size: 20),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: _aspectRatios.map((ratio) {
                  final isSelected = _selectedAspectRatio == ratio['value'];
                  return GestureDetector(
                    onTap: () => setState(() => _selectedAspectRatio = ratio['value']),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFF7C4DFF) : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        ratio['icon'],
                        size: 24,
                        color: isSelected ? Colors.white : Colors.grey.shade600,
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F5F5),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: TextField(
                        controller: _messageController,
                        enabled: !_isLoading,
                        decoration: const InputDecoration(
                          hintText: 'Describe image...',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      if (_messageController.text.trim().isNotEmpty) {
                        _generateImage(_messageController.text.trim());
                      }
                    },
                    child: Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFF9C27B0), Color(0xFF7C4DFF)]),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: _isLoading
                          ? const Padding(
                          padding: EdgeInsets.all(13),
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
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

  Widget _buildInputBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.07), blurRadius: 16, offset: const Offset(0, -3))],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              // ✅ Image button - FREE AUR PREMIUM DONO KE LIYE DIKHEGA
              GestureDetector(
                onTap: () {
                  setState(() {
                    _showImageGenMode = true;
                    _showVoiceMode = false;
                  });
                },
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0EBFF),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.image, color: const Color(0xFF7C4DFF), size: 22),
                ),
              ),
              const SizedBox(width: 8),
              // Voice mode button
              GestureDetector(
                onTap: () => setState(() => _showVoiceMode = !_showVoiceMode),
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0EBFF),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(_showVoiceMode ? Icons.keyboard : Icons.mic, color: const Color(0xFF7C4DFF), size: 22),
                ),
              ),
              const SizedBox(width: 8),
              // Text input
              Expanded(
                child: Container(
                  decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(24)),
                  child: TextField(
                    controller: _messageController,
                    enabled: !_isLoading,
                    maxLines: 4,
                    minLines: 1,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (v) {
                      if (v.trim().isNotEmpty && !_isLoading) _sendMessage(v);
                    },
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      hintStyle: const TextStyle(color: Color(0xFFAAAAAA), fontSize: 14),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                      suffixIcon: _messageController.text.isNotEmpty
                          ? IconButton(
                          icon: const Icon(Icons.close, color: Color(0xFFAAAAAA), size: 18),
                          onPressed: () {
                            _messageController.clear();
                            setState(() {});
                          })
                          : null,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Send button
              GestureDetector(
                onTap: () {
                  if (!_isLoading && _messageController.text.trim().isNotEmpty) {
                    _sendMessage(_messageController.text);
                  }
                },
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF9C27B0), Color(0xFF7C4DFF)]),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [BoxShadow(color: const Color(0xFF7C4DFF).withOpacity(0.35), blurRadius: 10)],
                  ),
                  child: _isLoading
                      ? const Padding(
                      padding: EdgeInsets.all(13),
                      child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)))
                      : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVoiceInput() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.07), blurRadius: 16, offset: const Offset(0, -3))],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  icon: Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(30),
                    ),
                    padding: const EdgeInsets.all(8),
                    child: const Icon(Icons.close, color: Color(0xFF7C4DFF), size: 20),
                  ),
                  onPressed: () {
                    setState(() {
                      _showVoiceMode = false;
                      _recognizedText = '';
                      _isListening = false;
                    });
                    _speechToText.stop();
                    _micAnimController.stop();
                  },
                ),
              ),
              if (_recognizedText.isNotEmpty)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0EBFF),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF7C4DFF).withOpacity(0.4)),
                  ),
                  child: Text(_recognizedText, style: const TextStyle(fontSize: 14, color: Color(0xFF333333))),
                ),
              if (_isListening)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text('Listening... 🎙️', style: TextStyle(color: Color(0xFFFF5252), fontWeight: FontWeight.w600)),
                ),
              ScaleTransition(
                scale: _micAnimation,
                child: GestureDetector(
                  onTap: _isListening ? _stopListeningAndSend : _startListening,
                  child: Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: _isListening ? [const Color(0xFFFF6B6B), const Color(0xFFFF5252)] : [const Color(0xFF9C27B0), const Color(0xFF7C4DFF)],
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: (_isListening ? const Color(0xFFFF5252) : const Color(0xFF7C4DFF)).withOpacity(0.45),
                          blurRadius: 24,
                          spreadRadius: 6,
                        )
                      ],
                    ),
                    child: Icon(_isListening ? Icons.stop_rounded : Icons.mic, color: Colors.white, size: 34),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    _speechToText.stop();
    _tts.stop();
    _micAnimController.dispose();
    super.dispose();
  }
}