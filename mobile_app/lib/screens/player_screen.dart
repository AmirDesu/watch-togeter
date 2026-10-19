import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';
import 'package:file_picker/file_picker.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../services/socket_service.dart';
import '../models/chat_message.dart';

class PlayerScreen extends StatefulWidget {
  final String roomId;
  final String username;
  final String videoPathOrUrl;
  final bool isNetworkUrl;
  final String? subtitlePath;

  const PlayerScreen({
    Key? key,
    required this.roomId,
    required this.username,
    required this.videoPathOrUrl,
    required this.isNetworkUrl,
    this.subtitlePath,
  }) : super(key: key);

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late VlcPlayerController _vlcController;
  final SocketService _socket = SocketService();
  final TextEditingController _chatController = TextEditingController();

  String _currentVideoPathOrUrl = '';
  String? _currentSubtitlePath;

  bool _isControlsVisible = true;
  bool _isChatOpen = false;
  bool _showNewMessageBadge = false;
  String? _latestMessageSender;
  Timer? _controlsTimer;
  Timer? _progressReportTimer;

  // Remote Sync state
  String _partnerName = 'در انتظار دوست...';
  double _partnerTime = 0;
  bool _partnerPlaying = false;
  int? _countdownSec;
  bool _isSyncingFromRemote = false;

  final List<ChatMessage> _messages = [];

  @override
  void initState() {
    super.initState();

    _currentVideoPathOrUrl = widget.videoPathOrUrl;
    _currentSubtitlePath = widget.subtitlePath;

    // Immersive landscape cinema experience
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    // Keep screen awake
    WakelockPlus.enable();

    // Initialize VLC Controller
    if (widget.isNetworkUrl) {
      _vlcController = VlcPlayerController.network(
        _currentVideoPathOrUrl,
        hwAcc: HwAcc.auto,
        autoPlay: false,
        options: VlcPlayerOptions(
          advanced: VlcAdvancedOptions([
            VlcAdvancedOptions.networkCaching(2000),
          ]),
          subtitle: VlcSubtitleOptions([
            VlcSubtitleOptions.color(VlcSubtitleColor.white),
            VlcSubtitleOptions.fontSize(32),
          ]),
        ),
      );
    } else {
      _vlcController = VlcPlayerController.file(
        File(_currentVideoPathOrUrl),
        hwAcc: HwAcc.auto,
        autoPlay: false,
        options: VlcPlayerOptions(
          subtitle: VlcSubtitleOptions([
            VlcSubtitleOptions.color(VlcSubtitleColor.white),
            VlcSubtitleOptions.fontSize(32),
          ]),
        ),
      );
    }

    // Attach listener to automatically load subtitle once VLC player initializes
    _vlcController.addOnInitListener(() async {
      _applyInitialSubtitle();
    });

    _setupSocketListeners();
    _startProgressReporter();
  }

  Future<void> _applyInitialSubtitle() async {
    if (_currentSubtitlePath != null && _currentSubtitlePath!.isNotEmpty) {
      final subFile = File(_currentSubtitlePath!);
      if (subFile.existsSync()) {
        try {
          await _vlcController.addSubtitleFromFile(subFile, isSelected: true);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('زیرنویس با موفقیت فعال شد.')),
            );
          }
        } catch (e) {
          debugPrint('[VLC] Subtitle loading error: $e');
        }
      }
    }
  }

  void _setupSocketListeners() {
    _socket.connect(
      serverUrl: 'https://watch.manageyar.ir',
      roomId: widget.roomId,
      username: widget.username,
    );

    _socket.onRemotePlay = (targetTime) async {
      _isSyncingFromRemote = true;
      if (targetTime != null) {
        final diff = (_vlcController.value.position.inSeconds - targetTime).abs();
        if (diff > 2) {
          _vlcController.setTime((targetTime * 1000).toInt());
        }
      }
      _vlcController.play();
      Future.delayed(const Duration(milliseconds: 500), () => _isSyncingFromRemote = false);
    };

    _socket.onRemotePause = (targetTime) async {
      _isSyncingFromRemote = true;
      if (targetTime != null) {
        final diff = (_vlcController.value.position.inSeconds - targetTime).abs();
        if (diff > 2) {
          _vlcController.setTime((targetTime * 1000).toInt());
        }
      }
      _vlcController.pause();
      Future.delayed(const Duration(milliseconds: 500), () => _isSyncingFromRemote = false);
    };

    _socket.onRemoteSeek = (targetTime) async {
      _isSyncingFromRemote = true;
      if (targetTime != null) {
        _vlcController.setTime((targetTime * 1000).toInt());
      }
      Future.delayed(const Duration(milliseconds: 500), () => _isSyncingFromRemote = false);
    };

    _socket.onCountdown = (seconds) {
      setState(() {
        _countdownSec = seconds;
      });
      Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_countdownSec == null || _countdownSec! <= 1) {
          timer.cancel();
          setState(() {
            _countdownSec = null;
          });
          _vlcController.play();
        } else {
          setState(() {
            _countdownSec = _countdownSec! - 1;
          });
        }
      });
    };

    _socket.onVideoChanged = (videoState, by) async {
      final newUrl = videoState['url']?.toString();
      if (newUrl != null && newUrl.isNotEmpty && newUrl != _currentVideoPathOrUrl) {
        _currentVideoPathOrUrl = newUrl;
        await _vlcController.setMediaFromNetwork(
          newUrl,
          hwAcc: HwAcc.auto,
          autoPlay: true,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('ویدیوی جدید توسط ${by ?? 'کاربر'} بارگذاری شد!')),
          );
        }
      }
    };

    _socket.onUserProgress = (data) {
      setState(() {
        _partnerName = data['username'] ?? 'دوست شما';
        _partnerTime = (data['currentTime'] as num?)?.toDouble() ?? 0;
        _partnerPlaying = data['isPlaying'] == true;
      });
    };

    _socket.onChatMessage = (msg) {
      if (mounted) {
        setState(() {
          _messages.add(msg);
          if (!_isChatOpen && msg.sender != widget.username) {
            _showNewMessageBadge = true;
            _latestMessageSender = msg.sender;
          }
        });
        if (!_isChatOpen && msg.sender != widget.username) {
          Future.delayed(const Duration(seconds: 4), () {
            if (mounted) setState(() => _showNewMessageBadge = false);
          });
        }
      }
    };
  }

  void _startProgressReporter() {
    _progressReportTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_vlcController.value.isInitialized) {
        final positionSec = _vlcController.value.position.inSeconds.toDouble();
        final isPlaying = _vlcController.value.isPlaying;
        _socket.sendProgress(positionSec, isPlaying);
      }
    });
  }

  void _togglePlayPause() async {
    if (!_vlcController.value.isInitialized) return;

    final isPlaying = _vlcController.value.isPlaying;
    final posSec = _vlcController.value.position.inSeconds.toDouble();

    if (isPlaying) {
      _vlcController.pause();
      _socket.sendPause(posSec);
    } else {
      _vlcController.play();
      _socket.sendPlay(posSec);
    }
    _resetControlsTimer();
  }

  void _seekRelative(int seconds) {
    if (!_vlcController.value.isInitialized) return;
    final currentMs = _vlcController.value.position.inMilliseconds;
    final targetMs = (currentMs + (seconds * 1000)).clamp(0, _vlcController.value.duration.inMilliseconds);
    _vlcController.setTime(targetMs);
    _socket.sendSeek(targetMs / 1000.0);
    _resetControlsTimer();
  }

  void _syncToPartner() {
    _vlcController.setTime((_partnerTime * 1000).toInt());
    if (_partnerPlaying) {
      _vlcController.play();
      _socket.sendPlay(_partnerTime);
    } else {
      _vlcController.pause();
      _socket.sendPause(_partnerTime);
    }
  }

  void _triggerCountdown() {
    _socket.triggerCountdown(seconds: 3);
  }

  void _resetControlsTimer() {
    _controlsTimer?.cancel();
    setState(() {
      _isControlsVisible = true;
    });
    _controlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _vlcController.value.isInitialized && _vlcController.value.isPlaying) {
        setState(() {
          _isControlsVisible = false;
        });
      }
    });
  }

  void _sendChatMessage() {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;
    _socket.sendChatMessage(text);
    _chatController.clear();
  }

  void _showSubtitleSelector() async {
    Map<int, String> spuTracks = {};
    int activeSpuTrack = -1;
    try {
      spuTracks = await _vlcController.getSpuTracks();
      activeSpuTrack = (await _vlcController.getSpuTrack()) ?? -1;
    } catch (_) {}

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'تنظیمات زیرنویس',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white70),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Pick local subtitle file
                  ElevatedButton.icon(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      final result = await FilePicker.platform.pickFiles(
                        type: FileType.custom,
                        allowedExtensions: ['srt', 'vtt', 'ass', 'sub'],
                      );
                      if (result != null && result.files.single.path != null) {
                        final file = File(result.files.single.path!);
                        _currentSubtitlePath = file.path;
                        await _vlcController.addSubtitleFromFile(file, isSelected: true);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('زیرنویس ${result.files.single.name} اعمال شد.')),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.folder_open_rounded, color: Colors.white),
                    label: const Text('انتخاب فایل زیرنویس از گوشی (SRT / VTT)', style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (spuTracks.isNotEmpty) ...[
                    const Text(
                      'تِرک‌های زیرنویس موجود در فیلم:',
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    ListTile(
                      dense: true,
                      title: const Text('غیرفعال کردن زیرنویس', style: TextStyle(color: Colors.white70)),
                      leading: Icon(
                        activeSpuTrack == -1 ? Icons.radio_button_checked : Icons.radio_button_off,
                        color: const Color(0xFF6366F1),
                      ),
                      onTap: () async {
                        await _vlcController.setSpuTrack(-1);
                        Navigator.pop(ctx);
                      },
                    ),
                    ...spuTracks.entries.map((entry) {
                      final isSelected = entry.key == activeSpuTrack;
                      return ListTile(
                        dense: true,
                        title: Text(entry.value, style: const TextStyle(color: Colors.white)),
                        leading: Icon(
                          isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                          color: const Color(0xFF6366F1),
                        ),
                        onTap: () async {
                          await _vlcController.setSpuTrack(entry.key);
                          Navigator.pop(ctx);
                        },
                      );
                    }).toList(),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    if (duration.inHours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();
    _progressReportTimer?.cancel();
    _vlcController.stopRendererScanning();
    _vlcController.dispose();
    WakelockPlus.disable();

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: GestureDetector(
          onTap: () {
            setState(() {
              _isControlsVisible = !_isControlsVisible;
            });
            if (_isControlsVisible) {
              _resetControlsTimer();
            }
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 1. VLC Native Video View
              Center(
                child: VlcPlayer(
                  controller: _vlcController,
                  aspectRatio: 16 / 9,
                  placeholder: const Center(
                    child: CircularProgressIndicator(color: Color(0xFF6366F1)),
                  ),
                ),
              ),

              // 1.5. Intercept taps over the native video view
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    setState(() {
                      _isControlsVisible = !_isControlsVisible;
                    });
                    if (_isControlsVisible) {
                      _resetControlsTimer();
                    }
                  },
                  child: const SizedBox.expand(),
                ),
              ),

              // 2. Countdown Banner if active
              if (_countdownSec != null)
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withOpacity(0.9),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF6366F1).withOpacity(0.5),
                          blurRadius: 24,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'شمارش معکوس هماهنگی',
                          style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '$_countdownSec',
                          style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.w900, fontFamily: 'monospace'),
                        ),
                      ],
                    ),
                  ),
                ),

              // 3. Top Status Bar: Return to Chat & Partner Status
              if (_isControlsVisible)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: () {},
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.black.withOpacity(0.85), Colors.transparent],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Return to Chat Room Button
                          ElevatedButton.icon(
                            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 18),
                            label: const Text('چت‌روم', style: TextStyle(color: Colors.white, fontSize: 12)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1E293B).withOpacity(0.9),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            ),
                            onPressed: () => Navigator.pop(context),
                          ),

                          // Room & Partner Chip
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B).withOpacity(0.85),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFF334155)),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _partnerPlaying ? Icons.play_arrow_rounded : Icons.pause_rounded,
                                  color: _partnerPlaying ? const Color(0xFF10B981) : Colors.amber,
                                  size: 16,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '$_partnerName: ${_formatDuration(Duration(seconds: _partnerTime.toInt()))}',
                                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: _syncToPartner,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF6366F1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Text('یکی شدن', style: TextStyle(color: Colors.white, fontSize: 10)),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Quick Chat Drawer Toggle
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              IconButton(
                                icon: Icon(
                                  _isChatOpen ? Icons.chat_bubble_rounded : Icons.chat_bubble_outline_rounded,
                                  color: const Color(0xFF818CF8),
                                ),
                                onPressed: () {
                                  setState(() {
                                    _isChatOpen = !_isChatOpen;
                                    _showNewMessageBadge = false;
                                  });
                                },
                              ),
                              if (_showNewMessageBadge)
                                Positioned(
                                  top: 0,
                                  right: 0,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.redAccent,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      _latestMessageSender != null ? 'پیام از $_latestMessageSender' : 'پیام جدید',
                                      style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // 4. Bottom Controls: Play/Pause, Seek, Progress Slider, Subtitle
              if (_isControlsVisible)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: () {},
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.transparent, Colors.black.withOpacity(0.9)],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Progress Slider
                          ValueListenableBuilder<VlcPlayerValue>(
                            valueListenable: _vlcController,
                            builder: (context, value, child) {
                              final duration = value.duration.inMilliseconds.toDouble();
                              final position = value.position.inMilliseconds.toDouble();

                              return Row(
                                children: [
                                  Text(
                                    _formatDuration(value.position),
                                    style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'monospace'),
                                  ),
                                  Expanded(
                                    child: Slider(
                                      value: position.clamp(0.0, duration > 0 ? duration : 1.0),
                                      max: duration > 0 ? duration : 1.0,
                                      activeColor: const Color(0xFF6366F1),
                                      inactiveColor: const Color(0xFF334155),
                                      onChanged: (val) {
                                        _vlcController.setTime(val.toInt());
                                        _socket.sendSeek(val / 1000.0);
                                      },
                                    ),
                                  ),
                                  Text(
                                    _formatDuration(value.duration),
                                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontFamily: 'monospace'),
                                  ),
                                ],
                              );
                            },
                          ),
                          // Action Buttons
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.replay_10_rounded, color: Colors.white, size: 28),
                                onPressed: () => _seekRelative(-10),
                              ),
                              const SizedBox(width: 16),
                              ValueListenableBuilder<VlcPlayerValue>(
                                valueListenable: _vlcController,
                                builder: (context, value, child) {
                                  return FloatingActionButton(
                                    backgroundColor: const Color(0xFF6366F1),
                                    mini: true,
                                    onPressed: _togglePlayPause,
                                    child: Icon(
                                      value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                      color: Colors.white,
                                      size: 26,
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(width: 16),
                              IconButton(
                                icon: const Icon(Icons.forward_10_rounded, color: Colors.white, size: 28),
                                onPressed: () => _seekRelative(10),
                              ),
                              const SizedBox(width: 20),
                              // Subtitle Button
                              IconButton(
                                icon: const Icon(Icons.subtitles_rounded, color: Color(0xFF10B981), size: 26),
                                tooltip: 'تنظیمات زیرنویس',
                                onPressed: _showSubtitleSelector,
                              ),
                              const SizedBox(width: 14),
                              // Countdown Button
                              ElevatedButton.icon(
                                onPressed: _triggerCountdown,
                                icon: const Icon(Icons.timer_rounded, size: 16, color: Colors.white),
                                label: const Text('شروع هم‌زمان (۳ ثانیه)', style: TextStyle(fontSize: 11)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF334155),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // 5. In-Screen Quick Chat Sidebar
              if (_isChatOpen)
                Positioned(
                  top: 60,
                  bottom: 70,
                  right: 16,
                  width: 320,
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A).withOpacity(0.92),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: const BoxDecoration(
                            border: Border(bottom: BorderSide(color: Color(0xFF334155))),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('گفتگوی زنده', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                              IconButton(
                                icon: const Icon(Icons.close_rounded, color: Colors.white, size: 18),
                                onPressed: () => setState(() => _isChatOpen = false),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.all(8),
                            itemCount: _messages.length,
                            itemBuilder: (context, index) {
                              final msg = _messages[index];
                              final isMe = msg.sender == widget.username;
                              return Align(
                                alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                                child: Container(
                                  margin: const EdgeInsets.symmetric(vertical: 2),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: isMe ? const Color(0xFF6366F1) : const Color(0xFF1E293B),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '${msg.sender}: ${msg.text}',
                                    style: const TextStyle(color: Colors.white, fontSize: 11),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _chatController,
                                  style: const TextStyle(color: Colors.white, fontSize: 11),
                                  decoration: InputDecoration(
                                    hintText: 'پیام...',
                                    hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                                    filled: true,
                                    fillColor: const Color(0xFF1E293B),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                                  ),
                                  onSubmitted: (_) => _sendChatMessage(),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.send_rounded, color: Color(0xFF6366F1), size: 18),
                                onPressed: _sendChatMessage,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
