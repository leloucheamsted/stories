import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:video_player/video_player.dart';
import 'package:image/image.dart' as img;

List<CameraDescription> cameras = [];

Future<void> main() async {
  // Ensure Flutter is initialized
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Get available cameras
    cameras = await availableCameras();
  } on CameraException catch (e) {
    debugPrint('Error initializing cameras: ${e.description}');
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Camera Stories',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const CameraScreen(),
    );
  }
}

// Enumération pour les types de grilles
enum GridType {
  none, // Pas de grille, photo plein écran
  horizontal, // Séparation horizontale (deux rangées)
  vertical, // Séparation verticale (deux colonnes)
  bottomRight, // Superposition de la caméra en mini cercle en bas à droite
}

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  CameraScreenState createState() => CameraScreenState();
}

class CameraScreenState extends State<CameraScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  bool _isCaptureInProgress = false;
  bool _isVideoMode = false; // Default to camera mode
  bool _isRecording = false; // Track if video is being recorded
  // Liste pour stocker les images capturées
  List<CapturedImage> _capturedImages = [];

  // Max video duration in seconds
  final int _maxVideoDuration = 45;
  // Current video recording duration
  int _currentVideoDuration = 0;
  Timer? _videoTimer;

  // Contrôleur d'animation pour le bouton de capture
  late AnimationController _animationController;

  // Type de grille sélectionné
  GridType _selectedGridType = GridType.horizontal;

  // Nombre de photos dans notre histoire (exactement 2)
  final int _maxStoryPhotos = 2;
  final PageController _pageController = PageController(viewportFraction: 0.3);
  int selectedIndex = 0;

  final List<String> icons = [
    'assets/story.svg',
    'assets/short.svg',
    'assets/challenge.svg',
  ];
  int _currentCameraIndex = 0; // Default to the first camera
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
    _pageController.addListener(() {
      setState(() {});
    });
    // Initialiser le contrôleur d'animation
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
  }

  double _calculateScale(int index) {
    double page = _pageController.page ?? selectedIndex.toDouble();
    double distance = (index - page).abs();
    return 1.3 - (distance * 0.3).clamp(0.5, 1.3);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_cameraController != null) {
      if (_cameraController!.value.isInitialized) {
        _cameraController!.dispose();
      }
      _cameraController = null;
    }
    _animationController.dispose();
    _videoTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // App state changed before the camera was initialized
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      _cameraController?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    if (cameras.isEmpty) {
      debugPrint('No cameras available');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No cameras found on device')),
      );
      return;
    }

    debugPrint('Available cameras: ${cameras.length}');
    for (var camera in cameras) {
      debugPrint('Camera: ${camera.name}, direction: ${camera.lensDirection}');
    }

    // Utiliser par défaut la caméra arrière
    CameraDescription? mainCamera;
    for (final camera in cameras) {
      if (camera.lensDirection == CameraLensDirection.back) {
        mainCamera = camera;
        break;
      }
    }

    // Si pas de caméra arrière, prendre la première disponible
    mainCamera ??= cameras.first;

    _cameraController = CameraController(
      mainCamera,
      ResolutionPreset.medium,
      imageFormatGroup: ImageFormatGroup.jpeg,
      enableAudio: _isVideoMode, // Enable audio only for video mode
    );

    try {
      await _cameraController!.initialize();
      await _cameraController!.lockCaptureOrientation();
      if (mounted) {  // Vérifier si le widget est toujours monté
        setState(() {
          _isCameraInitialized = true;
        });
        debugPrint('Camera initialized successfully');
      }
    } on CameraException catch (e) {
      debugPrint('Error initializing camera: ${e.description}');
    } catch (e) {
      debugPrint('Unexpected error initializing camera: $e');
    }
  }

  Future<void> _switchCamera() async {
    if (cameras.isEmpty) return;

    // If recording video, stop it first
    if (_isVideoMode && _cameraController?.value.isRecordingVideo == true) {
      await _stopVideoRecording();
    }

    // Dispose of the current controller before changing state
    final CameraController? oldController = _cameraController;
    _cameraController = null;

    // Update state to show loading indicator
    setState(() {
      _isCameraInitialized = false;
      _isRecording = false;
      // Toggle the camera index
      _currentCameraIndex = (_currentCameraIndex + 1) % cameras.length;
    });

    // Dispose of the old controller
    await oldController?.dispose();

    // Initialize the new camera
    _cameraController = CameraController(
      cameras[_currentCameraIndex],
      ResolutionPreset.medium,
      imageFormatGroup: ImageFormatGroup.jpeg,
      enableAudio: _isVideoMode, // Enable audio only in video mode
    );

    try {
      await _cameraController!.initialize();
      await _cameraController!.lockCaptureOrientation();
      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });
      }
    } on CameraException catch (e) {
      debugPrint('Error switching camera: ${e.description}');
    }
  }

  // Fonction pour faire défiler les types de grilles (y compris le mode sans grille)
  void _cycleGridType(GridType gridType) {
    // En mode vidéo, désactiver les grilles
    if (_isVideoMode) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Grid options are only available in photo mode'),
        ),
      );
      return;
    }

    // Ne pas changer de type de grille si des photos ont déjà été prises
    if (_capturedImages.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot change grid type after taking photos'),
        ),
      );
      return;
    }

    setState(() {
      _selectedGridType = gridType;
    });
  }

  Future<void> _startVideoRecording() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Camera is not ready yet')));
      return;
    }

    if (_cameraController!.value.isRecordingVideo) {
      return;
    }

    try {
      await _cameraController!.startVideoRecording();
      setState(() {
        _isCaptureInProgress = true;
        _isRecording = true;
        _currentVideoDuration = 0;
      });

      // Start a timer to track recording duration and auto-stop at max duration
      _videoTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() {
          _currentVideoDuration++;
        });

        // Auto-stop recording when max duration is reached
        if (_currentVideoDuration >= _maxVideoDuration) {
          _stopVideoRecording();
          timer.cancel();
        }
      });

      debugPrint('Started video recording');
    } on CameraException catch (e) {
      debugPrint('Error starting video recording: ${e.description}');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start recording: ${e.description}')),
      );
      setState(() {
        _isCaptureInProgress = false;
        _isRecording = false;
      });
    }
  }

  Future<void> _stopVideoRecording() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    if (!_cameraController!.value.isRecordingVideo) {
      return;
    }

    // Cancel the timer if it's running
    _videoTimer?.cancel();
    _videoTimer = null;

    try {
      final XFile video = await _cameraController!.stopVideoRecording();
      setState(() {
        _isCaptureInProgress = false;
        _isRecording = false;
      });

      // Copy the video to a more permanent location
      final directory = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final videoPath = path.join(directory.path, 'video_$timestamp.mp4');
      await File(video.path).copy(videoPath);

      debugPrint('Video recorded to: $videoPath');

      // Show video preview
      _showVideoPreview(videoPath);
    } on CameraException catch (e) {
      debugPrint('Error stopping video recording: ${e.description}');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to stop recording: ${e.description}')),
      );
      setState(() {
        _isCaptureInProgress = false;
        _isRecording = false;
      });
    }
  }

  void _showVideoPreview(String videoPath) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VideoPreviewScreen(videoPath: videoPath),
      ),
    );
  }

  Future<void> _captureImage() async {
    if (_isCaptureInProgress) return;
    if (!_isCameraInitialized || _cameraController == null || !_cameraController!.value.isInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Camera is not ready yet')),
      );
      return;
    }

    // Vérifiez le type de grid
    if (_selectedGridType == GridType.none && _capturedImages.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a grid type before capturing!')),
      );
      return;
    }
    
    // Vérifier si la limite d'images a été atteinte
    if (_capturedImages.length >= _maxStoryPhotos) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maximum number of story photos reached!')),
      );
      return;
    }

    setState(() {
      _isCaptureInProgress = true;
    });

    // Animer le bouton de capture
    _animationController.forward(from: 0.0);

    try {
      final directory = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      // Capture sécurisée: vérifier que la caméra est toujours disponible
      CameraController? controller = _cameraController;
      if (controller == null || !controller.value.isInitialized) {
        setState(() {
          _isCaptureInProgress = false;
        });
        return;
      }
      
      // Capturer l'image avec le controller actuel
      final xFile = await controller.takePicture();
      // Vérifier que le fichier existe avant de le copier
      if (xFile.path.isEmpty || !await File(xFile.path).exists()) {
        debugPrint('Camera returned empty or invalid file path: ${xFile.path}');
        setState(() {
          _isCaptureInProgress = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to capture image: invalid file')),
          );
        }
        return;
      }
      
      // Créer le chemin de destination
      final imagePath = path.join(directory.path, 'story_$timestamp.jpg');
      await File(xFile.path).copy(imagePath);

      // Vérifier que nous sommes toujours montés avant de mettre à jour l'état
      if (!mounted) {
        return;
      }
      
      // Ajouter l'image capturée à la liste
      setState(() {
        _capturedImages.add(
          CapturedImage(path: imagePath, gridType: _selectedGridType),
        );
        _isCaptureInProgress = false;

        // Si c'est la première photo et que nous avons une seconde à prendre
        if (_capturedImages.length == 1 && _maxStoryPhotos > 1) {
          // Garder le même type de grille pour toutes les photos
          // Cela évite les problèmes de changement de configuration au milieu de la capture
        }
      });

      // Si on a pris toutes les photos nécessaires, proposer d'afficher la prévisualisation
      if (_capturedImages.length == _maxStoryPhotos) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('All photos captured! Review your story?'),
            action: SnackBarAction(label: 'Preview', onPressed: _previewStory),
          ),
        );
      }
      // Si c'est la première capture, afficher un message pour informer l'utilisateur
      else if (_capturedImages.length == 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'First photo captured! Take one more for your story.',
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error capturing image: $e');
      setState(() {
        _isCaptureInProgress = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to capture image: $e')));
    }
  }

  // Construit la vue divisée avec caméra uniquement dans les zones vides
  Widget _buildSplitCameraView() {
    // Si nous n'avons pas encore d'images
    if (_capturedImages.isEmpty) {
      // En mode bottomRight ou none, afficher simplement la caméra en plein écran
      if (_selectedGridType == GridType.none ||
          _selectedGridType == GridType.bottomRight) {
        return _buildCameraPreview();
      }
    }

    // Trouver si des images existent pour les emplacements spécifiques
    String? topOrLeftImagePath;
    String? bottomOrRightImagePath;
    GridType? capturedGridType;

    // Parcourir les images capturées pour placer chacune au bon endroit
    for (int i = 0; i < _capturedImages.length; i++) {
      final image = _capturedImages[i];
      capturedGridType = image.gridType;

      if (i == 0) {
        topOrLeftImagePath = image.path;
      } else if (i == 1) {
        bottomOrRightImagePath = image.path;
      }
    }

    // Si une image a été prise en mode bottomRight, afficher l'image avec mini caméra
    if (_capturedImages.isNotEmpty &&
        capturedGridType == GridType.bottomRight) {
      return Stack(
        children: [
          // Image en plein écran
          Image.file(
            File(topOrLeftImagePath!),
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
          ),

          // Mini caméra en bas à droite
          Positioned(
            bottom: 150,
            right: 20,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: ClipOval(
                child:
                  bottomOrRightImagePath != null
                    ? Image.file(
                      File(bottomOrRightImagePath),
                      fit: BoxFit.cover,
                      width: double.infinity,
                    )
                    : _buildCameraPreview(),
              ),
            ),
          ),
        ],
      );
    }

    // Si une image a été prise en mode plein écran, l'afficher simplement
    if (_capturedImages.isNotEmpty && capturedGridType == GridType.none) {
      return Image.file(
        File(topOrLeftImagePath!),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
    }

    // Vérifier dans quelle disposition les placer
    // Si nous avons des images, nous utilisons leur type de grille, sinon la sélection actuelle
    final bool isHorizontalGrid =
        _capturedImages.isEmpty
            ? _selectedGridType == GridType.horizontal
            : capturedGridType == GridType.horizontal;

    if (!isHorizontalGrid) {
      // Grille horizontale (division haut/bas)
      return Column(
        children: [
          // Moitié supérieure
          Expanded(
            child: Stack(
              children: [
                topOrLeftImagePath != null
                    ? Image.file(
                      File(topOrLeftImagePath),
                      fit: BoxFit.cover,
                      width: double.infinity,
                    )
                    : _buildCameraPreview(),
              ],
            ),
          ),

          // Ligne de séparation
          Container(height: 1, color: Colors.white.withOpacity(0.7)),

          // Moitié inférieure
          Expanded(
            child: Stack(
              children: [
                bottomOrRightImagePath != null
                    ? Image.file(
                      File(bottomOrRightImagePath),
                      fit: BoxFit.cover,
                      width: double.infinity,
                    )
                    : _buildCameraPreview(),
                if (bottomOrRightImagePath == null && _capturedImages.isEmpty)
                  Container(color: Colors.black.withOpacity(0.8)),
              ],
            ),
          ),
        ],
      );
    } else {
      // Grille verticale (division gauche/droite)
      return Row(
        children: [
          // Moitié gauche
          Expanded(
            child:
                topOrLeftImagePath != null
                    ? Image.file(
                      File(topOrLeftImagePath),
                      fit: BoxFit.cover,
                      height: double.infinity,
                    )
                    : _buildCameraPreview(), // Caméra seulement si aucune image n'est prise
          ),

          // Ligne de séparation
          Container(width: 1, color: Colors.white.withOpacity(0.7)),

          // Moitié droite
          Expanded(
            child: Stack(
              children: [
                bottomOrRightImagePath != null
                    ? Image.file(
                      File(bottomOrRightImagePath),
                      fit: BoxFit.cover,
                      height: double.infinity,
                    )
                    : _buildCameraPreview(),
                if (bottomOrRightImagePath == null && _capturedImages.isEmpty)
                  Container(color: Colors.black.withOpacity(0.8)),
                // Caméra seulement si aucune image n'est prise
              ],
            ),
            // Caméra seulement si aucune image n'est prise
          ),
        ],
      );
    }
  }

  // Widget pour l'aperçu de la caméra
  Widget _buildCameraPreview() {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    // Safely access previewSize with null check
    final previewSize = _cameraController!.value.previewSize;
    if (previewSize == null) {
      return const Center(
        child: Text(
          'Camera preview size unavailable',
          style: TextStyle(color: Colors.white),
        ),
      );
    }

    return ClipRect(
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: previewSize.height,
            height: previewSize.width,
            child: CameraPreview(_cameraController!),
          ),
        ),
      ),
    );
  }

  // Fonction pour fusionner les images en une seule selon l'orientation
  Future<File?> _mergeImages() async {
    if (_capturedImages.length < 2) return null;

    try {
      // Decode les deux images
      final image1 = img.decodeImage(
        await File(_capturedImages[0].path).readAsBytes(),
      );
      final image2 = img.decodeImage(
        await File(_capturedImages[1].path).readAsBytes(),
      );

      if (image1 == null || image2 == null) return null;

      late img.Image merged;

      // Créer une image fusionnée selon le type de grille
      if (_capturedImages[0].gridType == GridType.horizontal) {
        // Fusionner horizontalement (une image au-dessus de l'autre)
        merged = img.Image(
          width: image1.width + image2.width,
          height: image1.height,
        );
        img.compositeImage(merged, image1, dstX: 0, dstY: 0);
        img.compositeImage(merged, image2, dstX: image1.width, dstY: 0);
      } else if (_capturedImages[0].gridType == GridType.vertical) {
        // Fusionner verticalement (une image à côté de l'autre)
        merged = img.Image(
          width: image1.width,
          height: image1.height + image2.height,
        );
        img.compositeImage(merged, image1, dstX: 0, dstY: 0);
        img.compositeImage(merged, image2, dstX: 0, dstY: image1.height);
      } else if (_capturedImages[0].gridType == GridType.bottomRight) {
        // Dessiner directement sur l'image principale sans utiliser d'intermédiaire
        
        // Copier l'image de fond
        merged = img.copyResize(
          image1,
          width: image1.width,
          height: image1.height,
        );
        
        // Redimensionner la seconde image pour l'insérer en cercle - taille doublée
        final circleSize = image1.width ~/ 3 * 2; // Doublé la taille du cercle
        final resizedImage2 = img.copyResize(
          image2,
          width: circleSize,
          height: circleSize,
        );
        
        // Position du cercle en bas à droite
        final posX = merged.width - circleSize - 20;
        final posY = merged.height - circleSize - 20;
        
        // Rayon du cercle
        final radius = circleSize / 2;
        
        // Centre du cercle relatif à la position
        final centerX = radius;
        final centerY = radius;
        
        // Dessiner directement sur l'image fusionnée en appliquant un masque circulaire
        for (int y = 0; y < circleSize; y++) {
          for (int x = 0; x < circleSize; x++) {
            // Position absolue dans l'image fusionnée
            final absX = posX + x;
            final absY = posY + y;
            
            // Vérifier si le pixel est dans les limites
            if (absX >= 0 && absX < merged.width && absY >= 0 && absY < merged.height) {
              // Distance au centre du cercle
              final dx = x - centerX;
              final dy = y - centerY;
              final distance = math.sqrt(dx * dx + dy * dy);
              
              // Dessiner bordure blanche
              if (distance <= radius && distance >= radius - 2) {
                // Bordure blanche
                merged.setPixel(absX, absY, img.ColorRgba8(255, 255, 255, 255));
              } 
              // Dessiner l'intérieur du cercle
              else if (distance < radius - 2) {
                // Copier le pixel de la seconde image
                merged.setPixel(absX, absY, resizedImage2.getPixel(x, y));
              }
              // Ne rien faire pour les pixels en dehors du cercle (garder l'image de fond)
            }
          }
        }
      } else {
        // Si GridType.none, simplement retourner la première image
        final directory = await getTemporaryDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final outputPath = "${directory.path}/final_${timestamp}.jpg";
        await File(_capturedImages[0].path).copy(outputPath);
        return File(outputPath);
      }

      // Sauvegarder l'image fusionnée - utiliser PNG pour préserver la transparence si nécessaire
      final Directory tempDir = await getTemporaryDirectory();
      final bool hasBorderCircle = _capturedImages[0].gridType == GridType.bottomRight;
      
      // Sauvegarder en PNG si on a un cercle (pour la transparence), sinon JPG
      if (hasBorderCircle) {
        final outputPath = "${tempDir.path}/merged_${DateTime.now().millisecondsSinceEpoch}.png";
        final file = File(outputPath);
        await file.writeAsBytes(img.encodePng(merged));
        return file;
      } else {
        final outputPath = "${tempDir.path}/merged_${DateTime.now().millisecondsSinceEpoch}.jpg";
        final file = File(outputPath);
        await file.writeAsBytes(img.encodeJpg(merged));
        return file;
      }
    } catch (e) {
      debugPrint('Error merging images: $e');
      return null;
    }
  }

  // Fonction pour prévisualiser la story complète
  Future<void> _previewStory() async {
    if (_capturedImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Take at least one photo first!')),
      );
      return;
    }

    // Si nous avons plusieurs images et que le type de grille n'est pas none,
    // fusionner les images en une seule
    if (_capturedImages.length >= 2 &&
        _capturedImages[0].gridType != GridType.none) {
      final mergedFile = await _mergeImages();

      if (mergedFile != null) {
        // Créer une nouvelle liste avec l'image fusionnée
        final mergedImage = CapturedImage(
          path: mergedFile.path,
          gridType: GridType.none,
        );

        // Afficher l'image fusionnée
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ImagePreviewScreen(image: mergedImage),
          ),
        );
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to merge images')));
      }
    } else if (_capturedImages.length == 1) {
      // Pour une seule image, l'afficher directement
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ImagePreviewScreen(image: _capturedImages[0]),
        ),
      );
    } else {
      // Comportement classique pour GridType.none avec plusieurs images
      Navigator.push(
        context,
        MaterialPageRoute(
          builder:
              (context) => StoryPreviewScreen(capturedImages: _capturedImages),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Section d'aperçu de la caméra avec les grilles remplies
          _buildSplitCameraView(),

          // Barre supérieure avec boutons
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Bouton retour
                      GestureDetector(
                        onTap: () {
                          if (_capturedImages.isNotEmpty) {
                            setState(() {
                              _capturedImages.clear();
                              _selectedGridType = GridType.none;
                            });
                          } else {
                            Navigator.pop(context);
                          }
                        },

                        child: SvgPicture.asset(
                          _capturedImages.isNotEmpty
                              ? 'assets/close.svg'
                              : 'assets/back.svg',
                          width: 18,
                          height: 18,
                          colorFilter: const ColorFilter.mode(
                            Colors.white,
                            BlendMode.srcIn,
                          ),
                        ),
                      ),

                      // Ajouter une musique
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            SvgPicture.asset(
                              'assets/music.svg',
                              width: 20,
                              height: 20,
                              colorFilter: const ColorFilter.mode(
                                Colors.white,
                                BlendMode.srcIn,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Ajouter une musique',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Bouton paramètres
                      SvgPicture.asset(
                        'assets/settings.svg',
                        width: 24,
                        height: 24,
                        colorFilter: const ColorFilter.mode(
                          Colors.white,
                          BlendMode.srcIn,
                        ),
                      ),
                    ],
                  ),

                  // Reste de la colonne pour ajouter d'autres éléments si nécessaire
                  const Spacer(),
                ],
              ),
            ),
          ),

          // Boutons latéraux gauche
          Positioned(
            left: 16,
            top: MediaQuery.of(context).size.height * 0.25,
            child: Column(
              children: [
                // Bouton texte - visible uniquement quand capture terminée
                if (_capturedImages.length >= _maxStoryPhotos)
                  Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    child: GestureDetector(
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Ajout de texte')),
                        );
                      },
                      child: SvgPicture.asset(
                        'assets/text.svg',
                        width: 28,
                        height: 28,
                        colorFilter: const ColorFilter.mode(
                          Colors.white,
                          BlendMode.srcIn,
                        ),
                      ),
                    ),
                  ),

                // Bouton toggle photo/video - visible seulement avant capture
                if (_capturedImages.isEmpty &&
                    _capturedImages.length < _maxStoryPhotos)
                  Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color:
                          _isVideoMode
                              ? Colors.red.withOpacity(0.3)
                              : Colors.transparent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _isVideoMode ? Colors.red : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: GestureDetector(
                      // switch video or camera mode
                      onTap: () async {
                        // If recording in progress, stop first
                        setState(() {
                          _selectedGridType = GridType.none;
                        });
                        
                        bool wasRecording = false;
                        if (_isVideoMode && _cameraController?.value.isRecordingVideo == true) {
                          wasRecording = true;
                          await _stopVideoRecording();
                        }

                        // First toggle the mode flag before disposing the camera
                        final bool newIsVideoMode = !_isVideoMode;
                        setState(() {
                          _isVideoMode = newIsVideoMode;
                          _isCameraInitialized = false; // Mark as not initialized
                        });

                        // Safely dispose old controller
                        if (_cameraController != null) {
                          final oldController = _cameraController;
                          _cameraController = null; // Remove reference before disposing
                          
                          try {
                            await oldController!.dispose();
                          } catch (e) {
                            debugPrint('Error disposing camera controller: $e');
                          }
                        }
                        
                        // Wait a moment before initializing new camera
                        await Future.delayed(Duration(milliseconds: 300));
                        
                        // Now initialize with new settings
                        await _initializeCamera();

                        if (_isVideoMode) {
                          debugPrint('Switched to video mode');
                        } else {
                          debugPrint('Switched to photo mode');
                        }
                      },
                      child: SvgPicture.asset(
                        _isVideoMode ? 'assets/video.svg' : 'assets/camera.svg',
                        width: 28,
                        height: 28,
                        colorFilter: ColorFilter.mode(
                          _isVideoMode ? Colors.red : Colors.white,
                          BlendMode.srcIn,
                        ),
                      ),
                    ),
                  ),
                // Bouton sticker - visible uniquement quand capture terminée
                if (_capturedImages.length >= _maxStoryPhotos)
                  Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    child: GestureDetector(
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Ajout de stickers')),
                        );
                      },
                      child: SvgPicture.asset(
                        'assets/sticker.svg',
                        width: 28,
                        height: 28,
                        colorFilter: const ColorFilter.mode(
                          Colors.white,
                          BlendMode.srcIn,
                        ),
                      ),
                    ),
                  ),
                // Bouton flash - visible uniquement pendant la capture
                if (_capturedImages.isEmpty &&
                    _capturedImages.length < _maxStoryPhotos)
                  GestureDetector(
                    onTap: () {
                      // passer a la camera avant si elle est arriere et inverse
                      if (_cameraController != null) {
                        _cameraController!.setFlashMode(
                          _cameraController!.value.flashMode == FlashMode.off
                              ? FlashMode.torch
                              : FlashMode.off,
                        );
                      }
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 20),
                      child: SvgPicture.asset(
                        'assets/flash.svg',
                        width: 28,
                        height: 28,
                        colorFilter: const ColorFilter.mode(
                          Colors.white,
                          BlendMode.srcIn,
                        ),
                      ),
                    ),
                  ),
                // Bouton de sélection de la grille
                // Bouton mode grille
                !_isVideoMode && _capturedImages.isEmpty
                    ? Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 2,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.65),
                        borderRadius: BorderRadius.circular(25),
                        border: Border.all(
                          color: Color(0XFFD9D9D9).withOpacity(0.5),
                          width: 4,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,

                        children: [
                          GestureDetector(
                            onTap: () {
                              if (_selectedGridType == GridType.horizontal) {
                                _cycleGridType(GridType.none);
                                return;
                              }
                              _cycleGridType(GridType.horizontal);
                            },
                            child: Container(
                              padding: const EdgeInsets.all(7),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color:
                                    _selectedGridType == GridType.horizontal
                                        ? Color(0XFFFFCD00)
                                        : Colors.transparent,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: SvgPicture.asset(
                                'assets/hori.svg',
                                width: 20,
                                height: 20,
                                colorFilter: const ColorFilter.mode(
                                  Colors.white,
                                  BlendMode.srcIn,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 8),
                          GestureDetector(
                            onTap: () {
                              if (_selectedGridType == GridType.vertical) {
                                _cycleGridType(GridType.none);
                                return;
                              }
                              _cycleGridType(GridType.vertical);
                            },
                            child: Container(
                              padding: const EdgeInsets.all(7),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color:
                                    _selectedGridType == GridType.vertical
                                        ? Color(0XFFFFCD00)
                                        : Colors.transparent,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: SvgPicture.asset(
                                'assets/verti.svg',
                                width: 20,
                                height: 20,
                                colorFilter: const ColorFilter.mode(
                                  Colors.white,
                                  BlendMode.srcIn,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          GestureDetector(
                            onTap: () {
                              if (_selectedGridType == GridType.bottomRight) {
                                _cycleGridType(GridType.none);
                                return;
                              }
                              _cycleGridType(GridType.bottomRight);
                            },
                            child: Container(
                              padding: const EdgeInsets.all(7),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color:
                                    _selectedGridType == GridType.bottomRight
                                        ? Color(0XFFFFCD00)
                                        : Colors.transparent,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: SvgPicture.asset(
                                'assets/bottomright.svg',
                                width: 20,
                                height: 20,
                                colorFilter: const ColorFilter.mode(
                                  Colors.white,
                                  BlendMode.srcIn,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                    : SizedBox.shrink(),
              ],
            ),
          ),

          // Contrôles inférieurs
          Positioned(
            left: 16,
            right: 16,
            bottom: 20,
            child: Column(
              children: [
                // Mode sélection
                (_selectedGridType != GridType.none &&
                            _capturedImages.length < _maxStoryPhotos) ||
                        (_selectedGridType == GridType.none &&
                            _capturedImages.isEmpty)
                    ? SizedBox(
                      height: 100,
                      child: PageView.builder(
                        controller: _pageController,
                        itemCount: icons.length,
                        scrollDirection: Axis.horizontal,
                        onPageChanged: (value) {
                          setState(() {
                            selectedIndex = value;
                          });
                        },
                        physics: BouncingScrollPhysics(),
                        itemBuilder: (context, index) {
                          double scale = _calculateScale(index);
                          return Center(
                            child: AnimatedContainer(
                              duration: Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                              width:
                                  selectedIndex == index
                                      ? 100 * scale
                                      : 70 *
                                          scale, // Augmenter la taille pour l'élément courant
                              height:
                                  selectedIndex == index
                                      ? 100 * scale
                                      : 70 * scale,
                              margin: EdgeInsets.symmetric(horizontal: 8),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.8),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color:
                                      index == selectedIndex
                                          ? Colors.white
                                          : Colors.white,
                                  width: 2,
                                ),
                                boxShadow:
                                    index == selectedIndex
                                        ? [
                                          BoxShadow(
                                            color: Colors.white,
                                            blurRadius: 5,
                                          ),
                                        ]
                                        : [],
                              ),
                              child: GestureDetector(
                                onTap: () {
                                  if (_isVideoMode) {
                                    if (_cameraController
                                            ?.value
                                            .isRecordingVideo ==
                                        true) {
                                      _stopVideoRecording();
                                    } else {
                                      _startVideoRecording();
                                    }
                                  } else {
                                    _captureImage();
                                  }
                                },
                                child:
                                    _isVideoMode &&
                                            _cameraController
                                                    ?.value
                                                    .isRecordingVideo ==
                                                true
                                        ? Stack(
                                          alignment: Alignment.center,
                                          children: [
                                            // Progress indicator
                                            index == 0
                                                ? SizedBox(
                                                  width: 70,
                                                  height: 70,
                                                  child: CustomPaint(
                                                    painter:
                                                        CircularProgressPainter(
                                                          progress:
                                                              _currentVideoDuration /
                                                              _maxVideoDuration,
                                                          color: Colors.red,
                                                        ),
                                                  ),
                                                )
                                                : SizedBox.shrink(),
                                            // Inner record button
                                            Container(
                                              width: 50,
                                              height: 50,
                                              decoration: BoxDecoration(
                                                color: Colors.red,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                          ],
                                        )
                                        : Stack(
                                          alignment: Alignment.center,
                                          children: [
                                            // Show progress indicator for photo capture
                                            if (!_isVideoMode &&
                                                _capturedImages.isNotEmpty &&
                                                index == 0)
                                              SizedBox(
                                                width: 70,
                                                height: 70,
                                                child: CustomPaint(
                                                  painter:
                                                      CircularProgressPainter(
                                                        progress:
                                                            _capturedImages
                                                                .length /
                                                            _maxStoryPhotos,
                                                        color: Colors.black,
                                                      ),
                                                ),
                                              ),
                                            // Icon
                                            SvgPicture.asset(
                                              icons[index],
                                              width: 50,
                                              height: 50,
                                              colorFilter:
                                                  _isVideoMode
                                                      ? ColorFilter.mode(
                                                        Colors.red.withOpacity(
                                                          0.8,
                                                        ),
                                                        BlendMode.srcIn,
                                                      )
                                                      : null,
                                            ),
                                          ],
                                        ),
                              ),
                            ),
                          );
                        },
                      ),
                    )
                    : SizedBox.shrink(),
                SizedBox(height: 20),
                // Boutons de contrôle
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Bouton galerie
                    _capturedImages.isEmpty
                        ? SvgPicture.asset(
                          'assets/gallery.svg',
                          width: 32,
                          height: 32,
                          colorFilter: const ColorFilter.mode(
                            Colors.white,
                            BlendMode.srcIn,
                          ),
                        )
                        : SizedBox.shrink(),
                    _capturedImages.length < _maxStoryPhotos
                        ? Text(
                          selectedIndex == 0
                              ? 'Story'
                              : selectedIndex == 1
                              ? 'Short'
                              : 'Challenge',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        )
                        : SizedBox.shrink(),
                    // Bouton de capture principal

                    //Button pour reverse la camera
                    _capturedImages.length < _maxStoryPhotos
                        ? GestureDetector(
                          onTap: _switchCamera,
                          child: SvgPicture.asset(
                            'assets/camera_reverse.svg',
                            width: 32,
                            height: 32,
                            colorFilter: const ColorFilter.mode(
                              Colors.white,
                              BlendMode.srcIn,
                            ),
                          ),
                        )
                        : SizedBox.shrink(),
                  ],
                ),
              ],
            ),
          ),

          // Indicateur au milieu pour le mode défi si nécessaire
        ],
      ),
    );
  }
}

// Classe pour stocker les informations sur une image capturée
class CapturedImage {
  final String path;
  final GridType gridType;

  CapturedImage({required this.path, required this.gridType});
}

// Peintre personnalisé pour dessiner les grilles
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

// Écran de prévisualisation de l'histoire complète
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

// Écran de prévisualisation de vidéo
class VideoPreviewScreen extends StatefulWidget {
  final String videoPath;

  const VideoPreviewScreen({super.key, required this.videoPath});

  @override
  State<VideoPreviewScreen> createState() => _VideoPreviewScreenState();
}

class _VideoPreviewScreenState extends State<VideoPreviewScreen> {
  late VideoPlayerController _videoPlayerController;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _initVideoPlayer();
  }

  Future<void> _initVideoPlayer() async {
    _videoPlayerController = VideoPlayerController.file(File(widget.videoPath));
    await _videoPlayerController.initialize();
    await _videoPlayerController.setLooping(true);

    // Auto-play when initialized
    await _videoPlayerController.play();

    setState(() {
      _isPlaying = true;
    });
  }

  @override
  void dispose() {
    _videoPlayerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Video
          Center(
            child:
                _videoPlayerController.value.isInitialized
                    ? AspectRatio(
                      aspectRatio: _videoPlayerController.value.aspectRatio,
                      child: VideoPlayer(_videoPlayerController),
                    )
                    : const CircularProgressIndicator(),
          ),

          // Controls
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Back button
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 30),
                  onPressed: () => Navigator.pop(context),
                ),

                // Play/Pause button
                IconButton(
                  icon: Icon(
                    _isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                    size: 40,
                  ),
                  onPressed: () {
                    setState(() {
                      if (_isPlaying) {
                        _videoPlayerController.pause();
                      } else {
                        _videoPlayerController.play();
                      }
                      _isPlaying = !_isPlaying;
                    });
                  },
                ),

                // Share button
                IconButton(
                  icon: const Icon(Icons.share, color: Colors.white, size: 30),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Sharing video...')),
                    );
                  },
                ),
              ],
            ),
          ),

          // Video progress
          Positioned(
            bottom: 80,
            left: 20,
            right: 20,
            child:
                _videoPlayerController.value.isInitialized
                    ? VideoProgressIndicator(
                      _videoPlayerController,
                      allowScrubbing: true,
                      colors: const VideoProgressColors(
                        playedColor: Colors.red,
                        bufferedColor: Colors.grey,
                        backgroundColor: Colors.white,
                      ),
                    )
                    : const SizedBox(),
          ),
        ],
      ),
    );
  }
}

// Widget pour afficher une image divisée selon le type de grille
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

// Créer un nouveau widget pour afficher l'image fusionnée
class ImagePreviewScreen extends StatefulWidget {
  final CapturedImage image;

  const ImagePreviewScreen({super.key, required this.image});

  @override
  _ImagePreviewScreenState createState() => _ImagePreviewScreenState();
}

class _ImagePreviewScreenState extends State<ImagePreviewScreen> {
  late String imagePath;

  @override
  void initState() {
    super.initState();
    imagePath = widget.image.path;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Image.file(
            File(imagePath),
            fit: BoxFit.contain,
            width: double.infinity,
            height: double.infinity,
          ),
        ],
      ),
    );
  }
}
