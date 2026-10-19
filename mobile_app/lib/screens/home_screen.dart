import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'chat_room_screen.dart';
import 'tetris_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _roomIdController = TextEditingController();
  final TextEditingController _urlController = TextEditingController();

  String? _selectedVideoPath;
  String? _selectedVideoName;
  String? _selectedSubtitlePath;
  String? _selectedSubtitleName;
  bool _isUrlMode = false;

  // Easter Egg State
  int _easterEggTapCount = 0;
  Timer? _easterEggResetTimer;
  bool _isTetrisUnlocked = false;

  @override
  void initState() {
    super.initState();
    _usernameController.text = 'کاربر هم‌تماشا';
    _roomIdController.text = 'room-${DateTime.now().millisecondsSinceEpoch % 10000}';
    _checkTetrisUnlockStatus();
  }

  Future<void> _checkTetrisUnlockStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _isTetrisUnlocked = prefs.getBool('tetris_easter_egg_unlocked') ?? false;
        });
      }
    } catch (_) {}
  }

  void _handleLogoTap() async {
    _easterEggTapCount++;
    _easterEggResetTimer?.cancel();
    _easterEggResetTimer = Timer(const Duration(seconds: 3), () {
      _easterEggTapCount = 0;
    });

    if (_easterEggTapCount >= 5) {
      _easterEggTapCount = 0;
      _easterEggResetTimer?.cancel();

      // Persist unlock state
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('tetris_easter_egg_unlocked', true);
        if (mounted) {
          setState(() {
            _isTetrisUnlocked = true;
          });
        }
      } catch (_) {}

      if (!mounted) return;

      // Show Easter Egg reveal dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          Future.delayed(const Duration(milliseconds: 2600), () {
            if (Navigator.canPop(ctx)) {
              Navigator.pop(ctx);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TetrisScreen()),
              );
            }
          });

          return Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1E1B4B), Color(0xFF0F172A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: const Color(0xFFF43F5E).withOpacity(0.6), width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFF43F5E).withOpacity(0.3),
                      blurRadius: 30,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.favorite_rounded, color: Color(0xFFF43F5E), size: 56),
                    SizedBox(height: 20),
                    Text(
                      'To my little Atrisa',
                      style: TextStyle(
                        color: Color(0xFFFDA4AF),
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                        fontFamily: 'sans-serif',
                      ),
                    ),
                    SizedBox(height: 12),
                    Text(
                      'راز مخفی کشف شد ❤️',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    }
  }

  Future<void> _pickVideoFile() async {
    if (Platform.isAndroid) {
      await Permission.videos.request();
      await Permission.storage.request();
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: false,
    );

    if (result != null && result.files.single.path != null) {
      setState(() {
        _selectedVideoPath = result.files.single.path!;
        _selectedVideoName = result.files.single.name;
        _isUrlMode = false;
      });
    }
  }

  Future<void> _pickSubtitleFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['srt', 'vtt', 'ass', 'sub'],
      allowMultiple: false,
    );

    if (result != null && result.files.single.path != null) {
      setState(() {
        _selectedSubtitlePath = result.files.single.path!;
        _selectedSubtitleName = result.files.single.name;
      });
    }
  }

  void _startParty() {
    final username = _usernameController.text.trim();
    final roomId = _roomIdController.text.trim();
    final videoSource = _isUrlMode ? _urlController.text.trim() : _selectedVideoPath;

    if (username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لطفاً نام خود را وارد کنید.')),
      );
      return;
    }

    if (roomId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لطفاً کد اتاق را وارد کنید.')),
      );
      return;
    }

    // Video selection is now completely OPTIONAL!
    // If not selected, user enters ChatRoomScreen directly and receives remote video when available.
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatRoomScreen(
          roomId: roomId,
          username: username,
          initialVideoPathOrUrl: (videoSource != null && videoSource.isNotEmpty) ? videoSource : null,
          isNetworkUrl: _isUrlMode,
          initialSubtitlePath: _selectedSubtitlePath,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Action Bar with permanent Easter Egg access if discovered
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (_isTetrisUnlocked)
                      InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const TetrisScreen()),
                          );
                        },
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF43F5E).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFF43F5E).withOpacity(0.4)),
                          ),
                          child: Row(
                            children: const [
                              Icon(Icons.favorite_rounded, color: Color(0xFFF43F5E), size: 16),
                              SizedBox(width: 6),
                              Text(
                                'Atrisa\'s Tetris',
                                style: TextStyle(color: Color(0xFFFDA4AF), fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      const SizedBox.shrink(),

                    // Check Update Icon
                    IconButton(
                      icon: const Icon(Icons.system_update_rounded, color: Color(0xFF94A3B8), size: 20),
                      tooltip: 'بررسی آپدیت جدید',
                      onPressed: () async {
                        final Uri url = Uri.parse('https://github.com/amir21hack/watch-togeter/releases/latest');
                        if (await canLaunchUrl(url)) {
                          await launchUrl(url, mode: LaunchMode.externalApplication);
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // App Logo (Interactive 5-tap Easter Egg trigger)
                Center(
                  child: GestureDetector(
                    onTap: _handleLogoTap,
                    child: Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF6366F1).withOpacity(0.35),
                            blurRadius: 18,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.live_tv_rounded, color: Colors.white, size: 40),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Center(
                  child: Text(
                    'هم‌تماشا',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                const Center(
                  child: Text(
                    'سینمای گروهی با چت‌روم زنده و هسته VLC',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Feature Pill
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withOpacity(0.12),
                    border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: const [
                      Icon(Icons.bolt_rounded, color: Color(0xFF10B981), size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'پخش هماهنگ MKV و لینک مستقیم + اتاق گفتگوی زنده',
                          style: TextStyle(color: Color(0xFF34D399), fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Username & Room Input
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: Column(
                    children: [
                      TextField(
                        controller: _usernameController,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          labelText: 'نام شما در اتاق',
                          labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                          prefixIcon: const Icon(Icons.person_rounded, color: Color(0xFF6366F1), size: 20),
                          filled: true,
                          fillColor: const Color(0xFF0F172A),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _roomIdController,
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'monospace'),
                        decoration: InputDecoration(
                          labelText: 'کد اتاق (ساخت خودکار اتاق جدید)',
                          labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                          prefixIcon: const Icon(Icons.meeting_room_rounded, color: Color(0xFF6366F1), size: 20),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.autorenew_rounded, color: Color(0xFF6366F1)),
                            onPressed: () {
                              setState(() {
                                _roomIdController.text = 'room-${DateTime.now().millisecondsSinceEpoch % 10000}';
                              });
                            },
                          ),
                          filled: true,
                          fillColor: const Color(0xFF0F172A),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Video Source Selector (OPTIONAL)
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'انتخاب ویدیو (اختیاری)',
                            style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _isUrlMode = !_isUrlMode;
                              });
                            },
                            child: Text(
                              _isUrlMode ? 'تغییر به فایل گوشی' : 'تغییر به لینک مستقیم',
                              style: const TextStyle(color: Color(0xFF818CF8), fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                      const Text(
                        'اگر دوستتان قبلاً ویدیو قرار داده نیازی به انتخاب ندارید و خودکار لود می‌شود.',
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                      ),
                      const SizedBox(height: 12),

                      if (!_isUrlMode) ...[
                        OutlinedButton.icon(
                          onPressed: _pickVideoFile,
                          icon: const Icon(Icons.folder_open_rounded, color: Color(0xFF6366F1)),
                          label: Text(
                            _selectedVideoName ?? 'انتخاب فایل از گوشی (MKV / MP4)',
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                            side: const BorderSide(color: Color(0xFF6366F1)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      ] else ...[
                        TextField(
                          controller: _urlController,
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                          decoration: InputDecoration(
                            hintText: 'لینک مستقیم ویدیو (https://...)',
                            hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                            prefixIcon: const Icon(Icons.link_rounded, color: Color(0xFF6366F1)),
                            filled: true,
                            fillColor: const Color(0xFF0F172A),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 12),

                      // Optional Subtitle Picker
                      OutlinedButton.icon(
                        onPressed: _pickSubtitleFile,
                        icon: const Icon(Icons.subtitles_rounded, color: Color(0xFF10B981)),
                        label: Text(
                          _selectedSubtitleName ?? 'انتخاب زیرنویس فارسی (اختیاری)',
                          style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                          side: const BorderSide(color: Color(0xFF334155)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                // Start / Join Party Button
                ElevatedButton(
                  onPressed: _startParty,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    elevation: 6,
                    shadowColor: const Color(0xFF6366F1).withOpacity(0.4),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.meeting_room_rounded, color: Colors.white, size: 22),
                      SizedBox(width: 8),
                      Text(
                        'ورود به اتاق گفتگو و سینما',
                        style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
