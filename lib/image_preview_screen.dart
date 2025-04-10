import 'dart:io';

import 'package:flutter/material.dart';

import 'Models/capture_image.model.dart';

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
