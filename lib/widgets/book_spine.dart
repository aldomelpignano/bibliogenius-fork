import 'package:flutter/material.dart';
import 'dart:math';
import '../models/book.dart';

/// A book spine widget that renders a colored vertical strip with the title.
///
/// Can be constructed from either a full [Book] object or minimal data
/// (title + optional author + color seed). The color is deterministic
/// based on the seed value.
class BookSpine extends StatelessWidget {
  final String title;
  final String? subtitle;
  final int colorSeed;
  final double height;
  final double width;
  final double opacity;

  /// Creates a spine from a full [Book] object.
  BookSpine.fromBook({
    super.key,
    required Book book,
    this.height = 150,
    this.width = 40,
  })  : title = book.title,
        subtitle = book.publisher,
        colorSeed = book.id ?? 0,
        opacity = book.owned ? 1.0 : 0.5;

  /// Creates a spine from minimal data (title + optional author/subtitle).
  /// [colorSeed] is used to generate a deterministic color (e.g. ISBN hashCode).
  const BookSpine({
    super.key,
    required this.title,
    this.subtitle,
    required this.colorSeed,
    this.height = 150,
    this.width = 40,
    this.opacity = 1.0,
  });

  Color _getColor() {
    final random = Random(colorSeed);
    return Color.fromARGB(
      255,
      random.nextInt(200), // Darker colors look more like books
      random.nextInt(200),
      random.nextInt(200),
    );
  }

  @override
  Widget build(BuildContext context) {
    final baseColor = _getColor();

    return Semantics(
      label: subtitle != null ? '$title, $subtitle' : title,
      child: Opacity(
        opacity: opacity,
        child: Container(
          height: height,
          width: width,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: baseColor,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(4),
              topRight: Radius.circular(4),
              bottomLeft: Radius.circular(2),
              bottomRight: Radius.circular(2),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                offset: const Offset(1, 1),
                blurRadius: 2,
              ),
            ],
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                baseColor.withValues(alpha: 0.8),
                baseColor,
                baseColor.withValues(alpha: 0.9),
              ],
              stops: const [0.0, 0.2, 0.9],
            ),
          ),
          child: Center(
            child: RotatedBox(
              quarterTurns: 3, // Rotate 270 degrees (bottom to top)
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(width: 4),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
