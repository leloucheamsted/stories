// Écran de prévisualisation de vidéo
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

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

