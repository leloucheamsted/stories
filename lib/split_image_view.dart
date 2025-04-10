// Widget pour afficher une image divisée selon le type de grille
import 'dart:io';

import 'package:camera_stories/main.dart';
import 'package:flutter/material.dart';

class SplitImageView extends StatelessWidget {
  final String imagePath;
  final GridType gridType;

  const SplitImageView({
    super.key,
    required this.imagePath,
    required this.gridType,
  });

  @override
  Widget build(BuildContext context) {
    if (gridType == GridType.horizontal) {
      // Affichage horizontal (deux colonnes)
      return Row(
        children: [
          // Moitié gauche
          Expanded(
            child: ClipRect(
              child: Transform.scale(
                scale: 1.0,
                alignment: Alignment.centerRight,
                child: Image.file(File(imagePath), fit: BoxFit.cover),
              ),
            ),
          ),
          // Ligne centrale
          Container(width: 1, color: Colors.white),
          // Moitié droite
          Expanded(
            child: ClipRect(
              child: Transform.scale(
                scale: 1.0,
                alignment: Alignment.centerLeft,
                child: Image.file(File(imagePath), fit: BoxFit.cover),
              ),
            ),
          ),
        ],
      );
    } else {
      // Affichage vertical (deux rangées)
      return Column(
        children: [
          // Moitié supérieure
          Expanded(
            child: ClipRect(
              child: Transform.scale(
                scale: 1.0,
                alignment: Alignment.bottomCenter,
                child: Image.file(File(imagePath), fit: BoxFit.cover),
              ),
            ),
          ),
          // Ligne centrale
          Container(height: 1, color: Colors.white),
          // Moitié inférieure
          Expanded(
            child: ClipRect(
              child: Transform.scale(
                scale: 1.0,
                alignment: Alignment.topCenter,
                child: Image.file(File(imagePath), fit: BoxFit.cover),
              ),
            ),
          ),
        ],
      );
    }
  }
}
