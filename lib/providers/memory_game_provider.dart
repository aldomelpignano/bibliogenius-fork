import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/memory_game.dart';
import '../services/ffi_service.dart';

/// Phases of the memory game lifecycle.
enum GamePhase { setup, playing, matchCheck, complete }

/// Manages the state of a memory game session.
///
/// Uses FFI direct calls to the Rust backend (no HTTP detour).
/// Handles card flipping logic, match detection, timing,
/// error counting, and scoring.
class MemoryGameProvider extends ChangeNotifier {
  final FfiService _ffi = FfiService();

  // --- Setup state ---
  List<String> _availableDifficulties = [];
  String? _selectedDifficulty;
  bool _isLoading = false;
  String? _error;

  // --- Game state ---
  GamePhase _phase = GamePhase.setup;
  List<MemoryCard> _cards = [];
  int? _firstFlippedIndex;
  int? _secondFlippedIndex;
  int _matchedPairs = 0;
  int _totalPairs = 0;
  int _errors = 0;

  // --- Timer ---
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _displayTimer;
  double _elapsedSeconds = 0;

  // --- Score ---
  MemoryGameScore? _lastScore;
  List<MemoryGameScore> _topScores = [];

  // --- Getters ---
  List<String> get availableDifficulties => _availableDifficulties;
  String? get selectedDifficulty => _selectedDifficulty;
  bool get isLoading => _isLoading;
  String? get error => _error;
  GamePhase get phase => _phase;
  List<MemoryCard> get cards => _cards;
  int get matchedPairs => _matchedPairs;
  int get totalPairs => _totalPairs;
  int get errors => _errors;
  double get elapsedSeconds => _elapsedSeconds;
  MemoryGameScore? get lastScore => _lastScore;
  List<MemoryGameScore> get topScores => _topScores;
  bool get isMatchChecking => _phase == GamePhase.matchCheck;

  /// Formatted elapsed time as mm:ss
  String get formattedTime {
    final minutes = _elapsedSeconds ~/ 60;
    final seconds = (_elapsedSeconds % 60).toInt();
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  // --- Setup ---

  /// Load available difficulties from the backend via FFI.
  Future<void> loadDifficulties() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _availableDifficulties = await _ffi.getMemoryDifficulties();
    } catch (e) {
      _error = e.toString();
      debugPrint('MemoryGameProvider: loadDifficulties error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Select a difficulty level.
  void selectDifficulty(String difficulty) {
    _selectedDifficulty = difficulty;
    notifyListeners();
  }

  // --- Game lifecycle ---

  /// Start a new game with the selected difficulty.
  Future<void> startGame() async {
    if (_selectedDifficulty == null) return;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final frbCards = await _ffi.setupMemoryGame(_selectedDifficulty!);
      _cards = frbCards
          .map((c) => MemoryCard(
                bookId: c.bookId,
                title: c.title,
                coverUrl: c.coverUrl,
              ))
          .toList();
      _totalPairs = _cards.length ~/ 2;
      _matchedPairs = 0;
      _errors = 0;
      _firstFlippedIndex = null;
      _secondFlippedIndex = null;
      _lastScore = null;
      _phase = GamePhase.playing;

      // Start timer
      _stopwatch.reset();
      _stopwatch.start();
      _elapsedSeconds = 0;
      _displayTimer?.cancel();
      _displayTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) {
          _elapsedSeconds = _stopwatch.elapsedMilliseconds / 1000.0;
          notifyListeners();
        },
      );
    } catch (e) {
      _error = e.toString();
      debugPrint('MemoryGameProvider: startGame error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Flip a card at the given index.
  ///
  /// If it's the first card, just flip it.
  /// If it's the second card, check for a match after a short delay.
  void flipCard(int index) {
    if (_phase != GamePhase.playing) return;
    if (index < 0 || index >= _cards.length) return;

    final card = _cards[index];

    // Ignore already matched or already flipped cards
    if (card.isMatched || card.isFlipped) return;

    card.isFlipped = true;

    if (_firstFlippedIndex == null) {
      // First card of the pair
      _firstFlippedIndex = index;
      notifyListeners();
    } else {
      // Second card of the pair
      _secondFlippedIndex = index;
      _phase = GamePhase.matchCheck;
      notifyListeners();

      // Check match after a short delay (let the player see both cards)
      Future.delayed(const Duration(milliseconds: 800), () {
        _checkMatch();
      });
    }
  }

  /// Check if the two flipped cards match.
  void _checkMatch() {
    if (_firstFlippedIndex == null || _secondFlippedIndex == null) return;

    final first = _cards[_firstFlippedIndex!];
    final second = _cards[_secondFlippedIndex!];

    if (first.bookId == second.bookId) {
      // Match found
      first.isMatched = true;
      second.isMatched = true;
      _matchedPairs++;

      if (_matchedPairs >= _totalPairs) {
        _finishGame();
        return;
      }
    } else {
      // No match — flip back
      first.isFlipped = false;
      second.isFlipped = false;
      _errors++;
    }

    _firstFlippedIndex = null;
    _secondFlippedIndex = null;
    _phase = GamePhase.playing;
    notifyListeners();
  }

  /// All pairs matched — stop timer and submit score via FFI.
  Future<void> _finishGame() async {
    _stopwatch.stop();
    _displayTimer?.cancel();
    _elapsedSeconds = _stopwatch.elapsedMilliseconds / 1000.0;
    _phase = GamePhase.complete;
    _firstFlippedIndex = null;
    _secondFlippedIndex = null;
    notifyListeners();

    try {
      final frbScore = await _ffi.finishMemoryGame(
        difficulty: _selectedDifficulty!,
        elapsedSeconds: _elapsedSeconds,
        errors: _errors,
        pairsCount: _totalPairs,
      );
      _lastScore = MemoryGameScore(
        id: frbScore.id,
        difficulty: frbScore.difficulty,
        pairsCount: frbScore.pairsCount,
        elapsedSeconds: frbScore.elapsedSeconds,
        errors: frbScore.errors,
        normalizedScore: frbScore.normalizedScore,
        playedAt: frbScore.playedAt,
        newAchievements: frbScore.newAchievements,
      );
      notifyListeners();
    } catch (e) {
      debugPrint('MemoryGameProvider: finishGame error: $e');
    }
  }

  /// Load top scores from the backend via FFI.
  Future<void> loadTopScores() async {
    try {
      final frbScores = await _ffi.getMemoryTopScores();
      _topScores = frbScores
          .map((s) => MemoryGameScore(
                id: s.id,
                difficulty: s.difficulty,
                pairsCount: s.pairsCount,
                elapsedSeconds: s.elapsedSeconds,
                errors: s.errors,
                normalizedScore: s.normalizedScore,
                playedAt: s.playedAt,
              ))
          .toList();
      notifyListeners();
    } catch (e) {
      debugPrint('MemoryGameProvider: loadTopScores error: $e');
    }
  }

  /// Reset to setup phase for a new game.
  void resetToSetup() {
    _stopwatch.stop();
    _stopwatch.reset();
    _displayTimer?.cancel();
    _phase = GamePhase.setup;
    _cards = [];
    _firstFlippedIndex = null;
    _secondFlippedIndex = null;
    _matchedPairs = 0;
    _totalPairs = 0;
    _errors = 0;
    _elapsedSeconds = 0;
    _lastScore = null;
    _error = null;
    notifyListeners();
  }

  /// Play again with the same difficulty.
  Future<void> playAgain() async {
    _phase = GamePhase.setup;
    _cards = [];
    _firstFlippedIndex = null;
    _secondFlippedIndex = null;
    _matchedPairs = 0;
    _errors = 0;
    _elapsedSeconds = 0;
    _lastScore = null;
    _error = null;
    notifyListeners();
    await startGame();
  }

  @override
  void dispose() {
    _stopwatch.stop();
    _displayTimer?.cancel();
    super.dispose();
  }
}
