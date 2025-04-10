// Peintre personnalisé pour dessiner les grilles
import 'dart:math' as math;

import 'package:camera_stories/main.dart';
import 'package:flutter/material.dart';

class GridPainter extends CustomPainter {
  final GridType gridType;

  GridPainter({required this.gridType});

  @override
  void paint(Canvas canvas, Size size) {
    // Si mode sans grille, ne rien dessiner
    if (gridType == GridType.none) {
      return;
    }

    final paint =
        Paint()
          ..color = Colors.white.withOpacity(0.7)
          ..strokeWidth = 1.0
          ..style = PaintingStyle.stroke;

    if (gridType == GridType.horizontal) {
      // Grille horizontale - 1 ligne au milieu
      final y = size.height / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    } else if (gridType == GridType.vertical) {
      // Grille verticale - 1 colonne au milieu
      final x = size.width / 2;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}

// Peintre personnalisé pour dessiner la progression circulaire comme Instagram
class CircularProgressPainter extends CustomPainter {
  final double progress; // 0.0 à 1.0
  final Color color;

  CircularProgressPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = color
          ..strokeWidth = 3.0
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Dessiner l'arc de progression
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2, // Commencer en haut
      progress *
          2 *
          math.pi, // Angle basé sur la progression (tour complet = 2*pi)
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CircularProgressPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}
