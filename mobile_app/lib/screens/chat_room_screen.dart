import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import '../services/socket_service.dart';
import '../models/chat_message.dart';
import 'player_screen.dart';

class ChatRoomScreen extends StatefulWidget {
  final String roomId;
  final String username;
  final String? initialVideoPathOrUrl;
  final bool isNetworkUrl;
  final String? initialSubtitlePath;

  const ChatRoomScreen({
    Key? key,
    required this.roomId,
    required this.username,
    this.initialVideoPathOrUrl,
    this.isNetworkUrl = true,
    this.initialSubtitlePath,
  }) : super(key: key);

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final SocketService _socket = SocketService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final List<ChatMessage> _messages = [];
  int _userCount = 1;
  bool _isConnected = false;

  // Active room video state
  String? _currentVideoUrl;
  String? _localVideoPath;
  String? _subtitlePath;
  bool _isVideoActive = false;

  @override
  void initState() {
    super.initState();

    _subtitlePath = widget.initialSubtitlePath;
    if (widget.isNetworkUrl) {
      _currentVideoUrl = widget.initialVideoPathOrUrl;
    } else {
      _localVideoPath = widget.initialVideoPathOrUrl;
    }

    _setupSocket();
  }

  void _setupSocket() {
    _socket.connect(
      serverUrl: 'https://watch.manageyar.ir',
      roomId: widget.roomId,
      username: widget.username,
    );

    // If an initial URL was passed from the home screen, broadcast it
    if (_currentVideoUrl != null && _currentVideoUrl!.isNotEmpty) {
      _socket.sendChangeVideo(url: _currentVideoUrl!);
      _isVideoActive = true;
    }

    _socket.onConnectionChanged = (connected) {
      if (mounted) {
        setState(() {
          _isConnected = connected;
        });
      }
    };

    _socket.onChatMessage = (msg) {
      if (mounted) {
        setState(() {
          _messages.add(msg);
        });
        _scrollToBottom();
      }
    };

    _socket.onUsersUpdate = (users) {
      if (mounted) {
        setState(() {
          _userCount = users.length;
        });
      }
    };

    _socket.onVideoChanged = (videoState, by) {
      if (mounted) {
        final newUrl = videoState['url']?.toString();
        setState(() {
          if (newUrl != null && newUrl.isNotEmpty) {
            _currentVideoUrl = newUrl;
            _isVideoActive = true;
          }
        });

        if (by != null && by != widget.username) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$by ویدیوی جدیدی اضافه کرد! برای تماشا وارد سینما شوید.'),
              backgroundColor: const Color(0xFF6366F1),
              action: SnackBarAction(
                label: 'ورود به سینما',
                textColor: Colors.white,
                onPressed: _enterCinema,
              ),
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    };
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    _socket.sendChatMessage(text);
    _messageController.clear();
  }

  void _showAddVideoDialog() {
    final urlInputController = TextEditingController(text: _currentVideoUrl ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 24,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'انتخاب یا ارسال ویدیو برای اتاق',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white70),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'لینک مستقیم اینترنتی (به طور خودکار برای همه شروع می‌شود):',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: urlInputController,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'https://domain.com/video.mp4',
                    hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                    prefixIcon: const Icon(Icons.link_rounded, color: Color(0xFF6366F1)),
                    filled: true,
                    fillColor: const Color(0xFF0F172A),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () {
                    final url = urlInputController.text.trim();
                    if (url.isNotEmpty) {
                      _socket.sendChangeVideo(url: url);
                      setState(() {
                        _currentVideoUrl = url;
                        _localVideoPath = null;
                        _isVideoActive = true;
                      });
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('لینک ویدیو برای همه اعضای اتاق ارسال شد!')),
                      );
                    }
                  },
                  icon: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                  label: const Text('پخش این لینک برای همه اعضای اتاق', style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(color: Color(0xFF334155)),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    final result = await FilePicker.platform.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: ['mp4', 'mkv', 'avi', 'mov', 'webm'],
                    );
                    if (result != null && result.files.single.path != null) {
                      setState(() {
                        _localVideoPath = result.files.single.path;
                        _currentVideoUrl = null;
                        _isVideoActive = true;
                      });
                      Navigator.pop(ctx);
                      _enterCinema();
                    }
                  },
                  icon: const Icon(Icons.folder_open_rounded, color: Color(0xFF10B981)),
                  label: const Text('انتخاب فایل ویدیویی از گوشی من (پخش لوکال)', style: TextStyle(color: Colors.white)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: Color(0xFF10B981)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _enterCinema() {
    final videoSource = _currentVideoUrl ?? _localVideoPath;
    final isNetwork = _currentVideoUrl != null;

    if (videoSource == null || videoSource.isEmpty) {
      _showAddVideoDialog();
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PlayerScreen(
          roomId: widget.roomId,
          username: widget.username,
          videoPathOrUrl: videoSource,
          isNetworkUrl: isNetwork,
          subtitlePath: _subtitlePath,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _socket.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'اتاق: ${widget.roomId}',
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.copy_rounded, color: Color(0xFF94A3B8), size: 16),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: widget.roomId));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('کد اتاق کپی شد!')),
                    );
                  },
                ),
              ],
            ),
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _isConnected ? const Color(0xFF10B981) : Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _isConnected ? '$_userCount نفر آنلاین' : 'در حال اتصال...',
                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                ),
              ],
            ),
          ],
        ),
        actions: [
          // Go to Cinema Button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: ElevatedButton.icon(
              onPressed: _enterCinema,
              icon: const Icon(Icons.live_tv_rounded, color: Colors.white, size: 18),
              label: const Text('سینما', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                elevation: 4,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          children: [
            // Video Status Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B).withOpacity(0.9),
                border: const Border(
                  bottom: BorderSide(color: Color(0xFF334155)),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _isVideoActive ? Icons.play_circle_fill_rounded : Icons.info_outline_rounded,
                    color: _isVideoActive ? const Color(0xFF10B981) : const Color(0xFF6366F1),
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _isVideoActive
                          ? 'فیلم در حال پخش: ${_currentVideoUrl ?? _localVideoPath?.split('/').last ?? 'ویدیو'}'
                          : 'هنوز فیلمی انتخاب نشده است. با دکمه سنجاق (+) زیر لینک بفرستید.',
                      style: TextStyle(
                        color: _isVideoActive ? const Color(0xFF34D399) : const Color(0xFF94A3B8),
                        fontSize: 12,
                        fontWeight: _isVideoActive ? FontWeight.bold : FontWeight.normal,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_isVideoActive)
                    GestureDetector(
                      onTap: _enterCinema,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6366F1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text('تماشا', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    ),
                ],
              ),
            ),

            // Message List
            Expanded(
              child: _messages.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.forum_outlined, color: Color(0xFF334155), size: 54),
                          SizedBox(height: 12),
                          Text(
                            'هنوز پیامی ارسال نشده است.\nسلامی به دوستانتان در اتاق بگویید!',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final msg = _messages[index];
                        final isMe = msg.sender == widget.username;

                        if (msg.isSystem) {
                          return Center(
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E293B).withOpacity(0.8),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: const Color(0xFF334155)),
                              ),
                              child: Text(
                                msg.text,
                                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                              ),
                            ),
                          );
                        }

                        final timeStr = DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(msg.timestamp));

                        return Align(
                          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: isMe ? const Color(0xFF6366F1) : const Color(0xFF1E293B),
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(16),
                                topRight: const Radius.circular(16),
                                bottomLeft: Radius.circular(isMe ? 16 : 4),
                                bottomRight: Radius.circular(isMe ? 4 : 16),
                              ),
                              border: isMe ? null : Border.all(color: const Color(0xFF334155)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (!isMe)
                                  Text(
                                    msg.sender,
                                    style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                if (!isMe) const SizedBox(height: 2),
                                Text(
                                  msg.text,
                                  style: const TextStyle(color: Colors.white, fontSize: 13),
                                ),
                                const SizedBox(height: 4),
                                Align(
                                  alignment: Alignment.bottomLeft,
                                  child: Text(
                                    timeStr,
                                    style: TextStyle(
                                      color: isMe ? Colors.white70 : const Color(0xFF64748B),
                                      fontSize: 9,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),

            // Input Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: const BoxDecoration(
                color: Color(0xFF1E293B),
                border: Border(
                  top: BorderSide(color: Color(0xFF334155)),
                ),
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    // Attachment (+) button for video link
                    IconButton(
                      icon: const Icon(Icons.add_link_rounded, color: Color(0xFF6366F1), size: 26),
                      onPressed: _showAddVideoDialog,
                      tooltip: 'افزودن لینک ویدیو برای اتاق',
                    ),
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendMessage(),
                        decoration: InputDecoration(
                          hintText: 'پیام خود را بنویسید...',
                          hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                          filled: true,
                          fillColor: const Color(0xFF0F172A),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Send Button
                    Container(
                      decoration: const BoxDecoration(
                        color: Color(0xFF6366F1),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                        onPressed: _sendMessage,
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
