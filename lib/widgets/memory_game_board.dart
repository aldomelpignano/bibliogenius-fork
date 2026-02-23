import 'package:flutter/material.dart';

import '../models/memory_game.dart';
import 'memory_card_widget.dart';

/// Responsive grid board for the memory game.
///
/// Adapts column count based on card count and screen size.
/// Cards maintain a book cover aspect ratio (~2:3).
class MemoryGameBoard extends StatelessWidget {
  final List<MemoryCard> cards;
  final ValueChanged<int> onCardTap;

  const MemoryGameBoard({
    super.key,
    required this.cards,
    required this.onCardTap,
  });

  /// Determine column count based on total cards and available width.
  int _columnCount(double availableWidth) {
    final totalCards = cards.length;

    // Match the grid dimensions from the Rust difficulty config
    if (totalCards <= 6) return 3; // Easy: 3x2
    if (totalCards <= 12) return 3; // Medium: 3x4
    if (totalCards <= 16) return 4; // Hard: 4x4
    if (totalCards <= 20) return 5; // Expert: 5x4
    return 5; // Master: 5x6

    // On very small screens, reduce columns
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _columnCount(constraints.maxWidth);
        final spacing = 8.0;
        final cardWidth =
            (constraints.maxWidth - spacing * (columns + 1)) / columns;
        final cardHeight = cardWidth * 1.4; // ~2:3 book cover ratio

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.all(spacing),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            childAspectRatio: cardWidth / cardHeight,
          ),
          itemCount: cards.length,
          itemBuilder: (context, index) {
            return MemoryCardWidget(
              card: cards[index],
              onTap: () => onCardTap(index),
            );
          },
        );
      },
    );
  }
}
