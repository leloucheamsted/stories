import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:camera_stories/Helpers/grid_painter.dart';
import 'package:camera_stories/Models/capture_image.model.dart';
import 'package:camera_stories/draggable_text.dart';
import 'package:camera_stories/video_preview_screen.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image/image.dart' as img;
import 'package:uuid/uuid.dart';
import 'dart:ui' as ui;
import 'package:flutter_image_compress/flutter_image_compress.dart';

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
  
  // Variables pour l'affichage direct de l'image fusionnée
  File? _mergedImageFile;
  bool _showMergedImage = false;

  // Max video duration in seconds
  final int _maxVideoDuration = 45;
  // Current video recording duration
  int _currentVideoDuration = 0;
  Timer? _videoTimer;

  // Contrôleur d'animation pour le bouton de capture
  late AnimationController _animationController;

  // Type de grille sélectionné
  GridType _selectedGridType = GridType.none;

  // Nombre de photos dans notre histoire (exactement 2)
  final int _maxStoryPhotos = 2;
  final PageController _pageController = PageController(viewportFraction: 0.3);
  int selectedIndex = 0;
List<EditableItem> items = [];
  EditableItem? selectedItem;

  GlobalKey previewContainer = GlobalKey();

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
      ResolutionPreset.max,
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

      // Si on a pris toutes les photos nécessaires, fusionner immédiatement les images
      if (_capturedImages.length == _maxStoryPhotos && _capturedImages[0].gridType != GridType.none) {
        _processMergedImage();
  
      }
      // Si c'est la première capture, afficher un message pour informer l'utilisateur
      else if (_capturedImages.length == 1) {
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
  void _addTextItem() {
    items.add(
      EditableItem(
        id: const Uuid().v4(),
        text: 'Texte',
        position: Offset(100, 100),
        color: Colors.white,
      ),
    );
    setState(() {});
  }
  Future<void> _saveToGallery() async {
    RenderRepaintBoundary boundary = previewContainer.currentContext!.findRenderObject() as RenderRepaintBoundary;
    ui.Image image = await boundary.toImage(pixelRatio: 3.0);
    ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    Uint8List pngBytes = byteData!.buffer.asUint8List();

   // final result = await ImageGallerySaver.saveImage(pngBytes);
   // print(result);
  }
  // Construit la vue divisée avec caméra uniquement dans les zones vides
  Widget _buildSplitCameraViewFinal() {
    // Si nous avons une image fusionnée, l'afficher en priorité
    if (_showMergedImage && _mergedImageFile != null) {
      return Stack(
        children: [
          // Image fusionnée en plein écran
          Image.file(
            _mergedImageFile!,
            fit: BoxFit.contain,
            width: double.infinity,
            height: double.infinity,
          ),
          
        ],
      );
    }
    
    // Si nous n'avons pas encore d'images
    if (_capturedImages.isEmpty) {
      // En mode bottomRight ou none, afficher simplement la caméra en plein écran
      if (_selectedGridType == GridType.none || _selectedGridType == GridType.bottomRight) {
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
    if (_capturedImages.isNotEmpty && capturedGridType == GridType.bottomRight) {
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
              child: bottomOrRightImagePath != null
                ? ClipOval(
                    child: Image.file(
                      File(bottomOrRightImagePath),
                      fit: BoxFit.cover,
                      width: 200,
                      height: 200,
                    ),
                  )
                : ClipOval(
                    child: _buildCameraPreview(),
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
    
    if (isHorizontalGrid) {
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
              ],
            ),
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
    final file1 = File(_capturedImages[0].path);
    final file2 = File(_capturedImages[1].path);

    final image1Bytes = await file1.readAsBytes();
    final image2Bytes = await file2.readAsBytes();

    final image1 = img.decodeImage(image1Bytes);
    final image2 = img.decodeImage(image2Bytes);

    if (image1 == null || image2 == null) return null;

    final gridType = _capturedImages[0].gridType;

    late img.Image merged;

    // Fonction de redimensionnement intelligent
    img.Image _resizeImage(img.Image image, int targetWidth, int targetHeight) {
      return img.copyResize(image, width: targetWidth, height: targetHeight);
    }

    // Fusion selon le type de grille
    if (gridType == GridType.vertical) {
      final width = image1.width;
      final height = image1.height + image2.height;

      merged = img.Image(width, height);
      img.copyInto(merged, image1, blend: false, dstX: 0, dstY: 0);
      img.copyInto(merged, image2, blend: false, dstX: 0, dstY: image1.height);

    } else if (gridType == GridType.horizontal) {
      final height = image1.height;
      final width = image1.width + image2.width;

      merged = img.Image(width, height);
      img.copyInto(merged, image1, blend: false, dstX: 0, dstY: 0);
      img.copyInto(merged, image2, blend: false, dstX: image1.width, dstY: 0);

    } else if (gridType == GridType.bottomRight) {
      merged = img.copyResize(image1, width: image1.width, height: image1.height);

      final circleSize = image1.width ~/ 2;
      final resizedImage2 = img.copyResizeCropSquare(image2, circleSize);

      final posX = merged.width - circleSize - 20;
      final posY = merged.height - circleSize - 20;

      for (int y = 0; y < circleSize; y++) {
        for (int x = 0; x < circleSize; x++) {
          final dx = x - circleSize / 2;
          final dy = y - circleSize / 2;
          final distance = math.sqrt(dx * dx + dy * dy);

          if (distance <= circleSize / 2) {
            final color = resizedImage2.getPixel(x, y);
            merged.setPixel(posX + x, posY + y, color);
          }
        }
      }

    } else {
      // Aucune fusion — retourne simplement la première image
      return file1;
    }

    // Compression et enregistrement de l'image fusionnée
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/merged_${DateTime.now().millisecondsSinceEpoch}.jpg';

    // Appliquer une compression
    final compressedBytes = await FlutterImageCompress.compressWithList(
      Uint8List.fromList(img.encodeJpg(merged)), // Conversion en JPG
      minWidth: 800, // Largeur minimale pour la compression
      minHeight: 600, // Hauteur minimale pour la compression
      quality: 85, // Taux de compression
    );

    final mergedFile = File(path);
    await mergedFile.writeAsBytes(compressedBytes);

    return mergedFile;

  } catch (e) {
    debugPrint('Fusion échouée : $e');
    return null;
  }
}
  // Fonction pour traiter et afficher l'image fusionnée directement
  Future<void> _processMergedImage() async {
    final mergedFile = await _mergeImages();
    if (mergedFile != null && mounted) {
      setState(() {
        _mergedImageFile = mergedFile;
        _showMergedImage = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Images merged! You can now share or edit.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to merge images. Please try again.')),
      );
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Section d'aperçu de la caméra avec les grilles remplies
       _buildSplitCameraViewFinal(),
       ...items.map((item) => EditableTextWidget(item: item)),
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
                              _showMergedImage = false;
                              _mergedImageFile = null;
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
                if (_capturedImages.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    child: GestureDetector(
                      onTap: () {
                      _addTextItem();
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
                if (_capturedImages.isNotEmpty)
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
                    _capturedImages.isEmpty 
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
                    _capturedImages.isEmpty 
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