// Écran de prévisualisation de l'histoire complète
import 'package:camera_stories/Models/capture_image.model.dart';
import 'package:camera_stories/split_image_view.dart';
import 'package:flutter/material.dart';

class StoryPreviewScreen extends StatefulWidget {
  final List<CapturedImage> capturedImages;

  const StoryPreviewScreen({super.key, required this.capturedImages});

  @override
  State<StoryPreviewScreen> createState() => _StoryPreviewScreenState();
}

class _StoryPreviewScreenState extends State<StoryPreviewScreen>
    with SingleTickerProviderStateMixin {
  late PageController _pageController;
  late AnimationController _progressController;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5), // Durée d'affichage de chaque photo
    )..addListener(() {
      if (_progressController.status == AnimationStatus.completed) {
        _nextStory();
      }
    });

    _progressController.forward();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  void _nextStory() {
    if (_currentIndex < widget.capturedImages.length - 1) {
      setState(() {
        _currentIndex++;
        _pageController.animateToPage(
          _currentIndex,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      });
      _progressController.forward(from: 0.0);
    } else {
      Navigator.pop(context); // Retourner à l'écran de la caméra
    }
  }

  void _previousStory() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
        _pageController.animateToPage(
          _currentIndex,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      });
      _progressController.forward(from: 0.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTapUp: (details) {
          final screenWidth = MediaQuery.of(context).size.width;
          if (details.globalPosition.dx < screenWidth / 3) {
            _previousStory();
          } else {
            _nextStory();
          }
        },
        child: Stack(
          children: [
            // Barres de progression en haut de l'écran
            Positioned(
              top: 50,
              left: 10,
              right: 10,
              child: Row(
                children: List.generate(
                  widget.capturedImages.length,
                  (index) => Expanded(
                    child: Container(
                      height: 2,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      child: LinearProgressIndicator(
                        value:
                            index < _currentIndex
                                ? 1.0
                                : index == _currentIndex
                                ? _progressController.value
                                : 0.0,
                        backgroundColor: Colors.grey.withOpacity(0.5),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Carrousel des images capturées
            PageView.builder(
              controller: _pageController,
              physics:
                  const NeverScrollableScrollPhysics(), // Désactiver le défilement par glissement
              itemCount: widget.capturedImages.length,
              onPageChanged: (index) {
                setState(() {
                  _currentIndex = index;
                });
                _progressController.forward(from: 0.0);
              },
              itemBuilder: (context, index) {
                final image = widget.capturedImages[index];

                return SplitImageView(
                  imagePath: image.path,
                  gridType: image.gridType,
                );
              },
            ),

            // Bouton de fermeture en haut à droite
            Positioned(
              top: 40,
              right: 10,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(context),
              ),
            ),

            // Bouton pour partager la story
            Positioned(
              bottom: 20,
              left: 0,
              right: 0,
              child: Center(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.share),
                  label: const Text('Share Story'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Sharing story...')),
                    );
                    // Ici, vous implémenteriez le partage réel
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

