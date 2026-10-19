import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

// Tetris Constants
const int boardWidth = 10;
const int boardHeight = 20;

enum Tetromino { I, J, L, O, S, T, Z }

const Map<Tetromino, Color> tetrominoColors = {
  Tetromino.I: Color(0xFF06B6D4), // Cyan
  Tetromino.J: Color(0xFF3B82F6), // Blue
  Tetromino.L: Color(0xFFF97316), // Orange
  Tetromino.O: Color(0xFFEAB308), // Yellow
  Tetromino.S: Color(0xFF10B981), // Green
  Tetromino.T: Color(0xFFA855F7), // Purple
  Tetromino.Z: Color(0xFFEF4444), // Red
};

class TetrisScreen extends StatefulWidget {
  const TetrisScreen({Key? key}) : super(key: key);

  @override
  State<TetrisScreen> createState() => _TetrisScreenState();
}

class _TetrisScreenState extends State<TetrisScreen> {
  // Game board: boardHeight x boardWidth (null for empty, Color for filled block)
  late List<List<Color?>> board;

  Timer? gameTimer;
  int score = 0;
  int linesCleared = 0;
  bool isGameOver = false;
  bool isPaused = false;

  // Current falling piece
  Tetromino currentPiece = Tetromino.T;
  List<Point<int>> pieceCoordinates = [];
  Color currentPieceColor = Colors.white;

  @override
  void initState() {
    super.initState();
    _initGame();
  }

  void _initGame() {
    board = List.generate(boardHeight, (_) => List.generate(boardWidth, (_) => null));
    score = 0;
    linesCleared = 0;
    isGameOver = false;
    isPaused = false;
    _spawnNewPiece();
    _startGameTimer();
  }

  void _startGameTimer() {
    gameTimer?.cancel();
    final speed = max(150, 500 - (linesCleared ~/ 5) * 40);
    gameTimer = Timer.periodic(Duration(milliseconds: speed), (timer) {
      if (!isPaused && !isGameOver) {
        _moveDown();
      }
    });
  }

  void _spawnNewPiece() {
    final random = Random();
    currentPiece = Tetromino.values[random.nextInt(Tetromino.values.length)];
    currentPieceColor = tetrominoColors[currentPiece]!;

    // Initial shape placement near top middle
    switch (currentPiece) {
      case Tetromino.I:
        pieceCoordinates = [const Point(3, 0), const Point(4, 0), const Point(5, 0), const Point(6, 0)];
        break;
      case Tetromino.J:
        pieceCoordinates = [const Point(3, 0), const Point(3, 1), const Point(4, 1), const Point(5, 1)];
        break;
      case Tetromino.L:
        pieceCoordinates = [const Point(5, 0), const Point(3, 1), const Point(4, 1), const Point(5, 1)];
        break;
      case Tetromino.O:
        pieceCoordinates = [const Point(4, 0), const Point(5, 0), const Point(4, 1), const Point(5, 1)];
        break;
      case Tetromino.S:
        pieceCoordinates = [const Point(4, 0), const Point(5, 0), const Point(3, 1), const Point(4, 1)];
        break;
      case Tetromino.T:
        pieceCoordinates = [const Point(4, 0), const Point(3, 1), const Point(4, 1), const Point(5, 1)];
        break;
      case Tetromino.Z:
        pieceCoordinates = [const Point(3, 0), const Point(4, 0), const Point(4, 1), const Point(5, 1)];
        break;
    }

    // Check if new piece immediately collides (Game Over)
    if (_checkCollision(pieceCoordinates)) {
      setState(() {
        isGameOver = true;
      });
      gameTimer?.cancel();
    } else {
      setState(() {});
    }
  }

  bool _checkCollision(List<Point<int>> piece) {
    for (var point in piece) {
      if (point.x < 0 || point.x >= boardWidth || point.y >= boardHeight) {
        return true;
      }
      if (point.y >= 0 && board[point.y][point.x] != null) {
        return true;
      }
    }
    return false;
  }

  void _moveDown() {
    final newCoords = pieceCoordinates.map((p) => Point(p.x, p.y + 1)).toList();
    if (!_checkCollision(newCoords)) {
      setState(() {
        pieceCoordinates = newCoords;
      });
    } else {
      // Lock piece into board
      for (var point in pieceCoordinates) {
        if (point.y >= 0 && point.y < boardHeight && point.x >= 0 && point.x < boardWidth) {
          board[point.y][point.x] = currentPieceColor;
        }
      }
      _clearFullLines();
      _spawnNewPiece();
    }
  }

  void _moveLeft() {
    if (isPaused || isGameOver) return;
    final newCoords = pieceCoordinates.map((p) => Point(p.x - 1, p.y)).toList();
    if (!_checkCollision(newCoords)) {
      setState(() {
        pieceCoordinates = newCoords;
      });
    }
  }

  void _moveRight() {
    if (isPaused || isGameOver) return;
    final newCoords = pieceCoordinates.map((p) => Point(p.x + 1, p.y)).toList();
    if (!_checkCollision(newCoords)) {
      setState(() {
        pieceCoordinates = newCoords;
      });
    }
  }

  void _hardDrop() {
    if (isPaused || isGameOver) return;
    List<Point<int>> testCoords = pieceCoordinates;
    while (true) {
      final next = testCoords.map((p) => Point(p.x, p.y + 1)).toList();
      if (_checkCollision(next)) break;
      testCoords = next;
    }
    setState(() {
      pieceCoordinates = testCoords;
    });
    _moveDown();
  }

  void _rotate() {
    if (isPaused || isGameOver || currentPiece == Tetromino.O) return;

    // Pivot is pieceCoordinates[1] for standard rotation
    final pivot = pieceCoordinates[1];
    final rotated = pieceCoordinates.map((p) {
      final relX = p.x - pivot.x;
      final relY = p.y - pivot.y;
      // Standard 90 deg clockwise rotation: (x, y) -> (-y, x)
      return Point(pivot.x - relY, pivot.y + relX);
    }).toList();

    if (!_checkCollision(rotated)) {
      setState(() {
        pieceCoordinates = rotated;
      });
    }
  }

  void _clearFullLines() {
    int lines = 0;
    for (int y = boardHeight - 1; y >= 0; y--) {
      if (board[y].every((cell) => cell != null)) {
        lines++;
        board.removeAt(y);
        board.insert(0, List.generate(boardWidth, (_) => null));
        y++; // Check the row that just dropped into y
      }
    }
    if (lines > 0) {
      setState(() {
        linesCleared += lines;
        score += (lines == 1 ? 100 : lines == 2 ? 300 : lines == 3 ? 500 : 800);
      });
      _startGameTimer(); // Update speed if needed
    }
  }

  @override
  void dispose() {
    gameTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        title: Row(
          children: [
            const Icon(Icons.videogame_asset_rounded, color: Color(0xFFF43F5E), size: 24),
            const SizedBox(width: 10),
            const Text(
              'Atrisa\'s Tetris',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded, color: Colors.white),
            onPressed: () {
              setState(() {
                isPaused = !isPaused;
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: () {
              setState(() {
                _initGame();
              });
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Header stats
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildStatBadge('امتیاز', '$score', const Color(0xFF6366F1)),
                  _buildStatBadge('خطوط', '$linesCleared', const Color(0xFF10B981)),
                  _buildStatBadge('سطح', '${(linesCleared ~/ 5) + 1}', const Color(0xFFF59E0B)),
                ],
              ),
            ),

            // Game Board & Overlay
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: boardWidth / boardHeight,
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF090D16),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF334155), width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFF43F5E).withOpacity(0.15),
                          blurRadius: 16,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Stack(
                      children: [
                        // Board Cells
                        GridView.builder(
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: boardWidth * boardHeight,
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: boardWidth,
                          ),
                          itemBuilder: (context, index) {
                            final x = index % boardWidth;
                            final y = index ~/ boardWidth;

                            Color? cellColor = board[y][x];

                            // Check if current active piece occupies (x, y)
                            final isPiece = pieceCoordinates.any((p) => p.x == x && p.y == y);
                            if (isPiece) {
                              cellColor = currentPieceColor;
                            }

                            return Container(
                              margin: const EdgeInsets.all(0.7),
                              decoration: BoxDecoration(
                                color: cellColor ?? Colors.transparent,
                                borderRadius: BorderRadius.circular(3),
                                border: cellColor != null
                                    ? Border.all(color: Colors.white.withOpacity(0.2), width: 0.8)
                                    : Border.all(color: Colors.white.withOpacity(0.03), width: 0.5),
                              ),
                            );
                          },
                        ),

                        // Game Over Dialog
                        if (isGameOver)
                          Container(
                            color: Colors.black.withOpacity(0.85),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.sentiment_dissatisfied_rounded, color: Color(0xFFF43F5E), size: 48),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'بازی تمام شد!',
                                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'امتیاز نهایی: $score',
                                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                                  ),
                                  const SizedBox(height: 18),
                                  ElevatedButton.icon(
                                    onPressed: _initGame,
                                    icon: const Icon(Icons.replay_rounded, color: Colors.white),
                                    label: const Text('بازی دوباره', style: TextStyle(color: Colors.white)),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFF43F5E),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
              ),
            ),

            // Controls
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildControlButton(Icons.arrow_back_rounded, _moveLeft),
                  _buildControlButton(Icons.rotate_right_rounded, _rotate, isPrimary: true),
                  _buildControlButton(Icons.arrow_downward_rounded, _moveDown),
                  _buildControlButton(Icons.keyboard_double_arrow_down_rounded, _hardDrop),
                  _buildControlButton(Icons.arrow_forward_rounded, _moveRight),
                ],
              ),
            ),

            // Permanent Easter Egg Tribute (همواره و همیشه نمایش داده می‌شود)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                border: Border(
                  top: BorderSide(color: const Color(0xFFF43F5E).withOpacity(0.4), width: 1.5),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.favorite_rounded, color: Color(0xFFF43F5E), size: 16),
                  const SizedBox(width: 8),
                  const Text(
                    'To my little Atrisa',
                    style: TextStyle(
                      color: Color(0xFFFDA4AF),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.favorite_rounded, color: Color(0xFFF43F5E), size: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatBadge(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Column(
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
          Text(value, style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildControlButton(IconData icon, VoidCallback onPressed, {bool isPrimary = false}) {
    return Material(
      color: isPrimary ? const Color(0xFFF43F5E) : const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: isPrimary ? const Color(0xFFF43F5E) : const Color(0xFF334155)),
      ),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          child: Icon(icon, color: Colors.white, size: isPrimary ? 28 : 24),
        ),
      ),
    );
  }
}
