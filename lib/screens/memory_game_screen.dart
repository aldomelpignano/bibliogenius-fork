import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/memory_game_provider.dart';
import '../services/translation_service.dart';
import '../widgets/memory_game_board.dart';

/// Memory Game screen with three phases:
/// 1. Setup — pick difficulty
/// 2. Playing — flip cards, find pairs
/// 3. Complete — view score, play again
class MemoryGameScreen extends StatefulWidget {
  const MemoryGameScreen({super.key});

  @override
  State<MemoryGameScreen> createState() => _MemoryGameScreenState();
}

class _MemoryGameScreenState extends State<MemoryGameScreen> {
  late MemoryGameProvider _provider;

  @override
  void initState() {
    super.initState();
    _provider = context.read<MemoryGameProvider>();
    _provider.loadDifficulties();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          TranslationService.translate(context, 'memory_game_title'),
        ),
      ),
      body: Consumer<MemoryGameProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.error != null) {
            return _buildError(provider);
          }

          switch (provider.phase) {
            case GamePhase.setup:
              return _buildSetup(provider);
            case GamePhase.playing:
            case GamePhase.matchCheck:
              return _buildPlaying(provider);
            case GamePhase.complete:
              return _buildComplete(provider);
          }
        },
      ),
    );
  }

  Widget _buildError(MemoryGameProvider provider) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 48, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            provider.error!,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[600]),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => provider.loadDifficulties(),
            child: Text(
              TranslationService.translate(context, 'button_retry'),
            ),
          ),
        ],
      ),
    );
  }

  // ============ Setup Phase ============

  Widget _buildSetup(MemoryGameProvider provider) {
    final difficulties = provider.availableDifficulties;

    if (difficulties.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.photo_library_outlined,
                  size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                TranslationService.translate(
                    context, 'memory_game_not_enough_books'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            TranslationService.translate(
                context, 'memory_game_choose_difficulty'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 24),
          ...difficulties.map((d) => _buildDifficultyTile(provider, d)),
          const Spacer(),
          FilledButton.icon(
            onPressed:
                provider.selectedDifficulty != null ? provider.startGame : null,
            icon: const Icon(Icons.play_arrow),
            label: Text(
              TranslationService.translate(context, 'memory_game_play'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDifficultyTile(MemoryGameProvider provider, String difficulty) {
    final isSelected = provider.selectedDifficulty == difficulty;
    final info = _difficultyInfo(difficulty);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        selected: isSelected,
        selectedTileColor:
            Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
        leading: Icon(info.icon, color: info.color),
        title: Text(
          TranslationService.translate(
              context, 'memory_game_$difficulty'),
        ),
        subtitle: Text(info.subtitle),
        onTap: () => provider.selectDifficulty(difficulty),
      ),
    );
  }

  // ============ Playing Phase ============

  Widget _buildPlaying(MemoryGameProvider provider) {
    return SafeArea(
      child: Column(
        children: [
          // Stats bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStat(
                  Icons.timer_outlined,
                  provider.formattedTime,
                  TranslationService.translate(context, 'memory_game_time'),
                ),
                _buildStat(
                  Icons.check_circle_outline,
                  '${provider.matchedPairs}/${provider.totalPairs}',
                  TranslationService.translate(context, 'memory_game_pairs'),
                ),
                _buildStat(
                  Icons.close,
                  '${provider.errors}',
                  TranslationService.translate(context, 'memory_game_errors'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Game board
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: MemoryGameBoard(
                  cards: provider.cards,
                  onCardTap: provider.flipCard,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStat(IconData icon, String value, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: Colors.grey[600]),
            const SizedBox(width: 4),
            Text(value, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey[500],
              ),
        ),
      ],
    );
  }

  // ============ Complete Phase ============

  Widget _buildComplete(MemoryGameProvider provider) {
    final score = provider.lastScore;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.emoji_events,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              TranslationService.translate(
                  context, 'memory_game_congratulations'),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 24),
            if (score != null) ...[
              _buildScoreRow(
                TranslationService.translate(context, 'memory_game_score'),
                score.formattedScore,
              ),
              _buildScoreRow(
                TranslationService.translate(context, 'memory_game_time'),
                score.formattedTime,
              ),
              _buildScoreRow(
                TranslationService.translate(context, 'memory_game_errors'),
                '${score.errors}',
              ),
              _buildScoreRow(
                TranslationService.translate(
                    context, 'memory_game_difficulty_label'),
                TranslationService.translate(
                    context, 'memory_game_${score.difficulty}'),
              ),
            ],
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: provider.playAgain,
              icon: const Icon(Icons.replay),
              label: Text(
                TranslationService.translate(
                    context, 'memory_game_play_again'),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: provider.resetToSetup,
              icon: const Icon(Icons.arrow_back),
              label: Text(
                TranslationService.translate(
                    context, 'memory_game_change_difficulty'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScoreRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('$label : ',
              style: TextStyle(color: Colors.grey[600])),
          Text(value,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // ============ Helpers ============

  _DifficultyInfo _difficultyInfo(String difficulty) {
    switch (difficulty) {
      case 'easy':
        return _DifficultyInfo(
            Icons.sentiment_satisfied, Colors.green, '3 pairs - 3x2');
      case 'medium':
        return _DifficultyInfo(
            Icons.sentiment_neutral, Colors.blue, '6 pairs - 3x4');
      case 'hard':
        return _DifficultyInfo(
            Icons.sentiment_dissatisfied, Colors.orange, '8 pairs - 4x4');
      case 'expert':
        return _DifficultyInfo(
            Icons.psychology, Colors.red, '10 pairs - 5x4');
      case 'master':
        return _DifficultyInfo(
            Icons.local_fire_department, Colors.purple, '15 pairs - 5x6');
      default:
        return _DifficultyInfo(Icons.help_outline, Colors.grey, difficulty);
    }
  }
}

class _DifficultyInfo {
  final IconData icon;
  final Color color;
  final String subtitle;

  const _DifficultyInfo(this.icon, this.color, this.subtitle);
}
