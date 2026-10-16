import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_player/video_player.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // طلب الصلاحيات الشاملة
  await [
    Permission.camera, 
    Permission.microphone, 
    Permission.storage,
    Permission.photos
  ].request();
  
  try {
    cameras = await availableCameras();
  } catch (e) {
    debugPrint("Error initializing cameras: $e");
  }
  
  runApp(const LivePhotoApp());
}

class LivePhotoApp extends StatelessWidget {
  const LivePhotoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Live Photo App',
      theme: ThemeData.dark(),
      home: const CameraScreen(),
    );
  }
}

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  bool _isInitialized = false;
  bool _isCapturing = false;
  List<Map<String, String>> _mediaList = [];

  @override
  void initState() {
    super.initState();
    _initCamera();
    _loadExistingMedia();
  }

  Future<void> _initCamera() async {
    if (cameras.isEmpty) return;
    _controller = CameraController(cameras[0], ResolutionPreset.medium);
    await _controller!.initialize();
    if (!mounted) return;
    setState(() {
      _isInitialized = true;
    });
  }

  Future<void> _loadExistingMedia() async {
    final Directory extDir = await getApplicationDocumentsDirectory();
    final List<FileSystemEntity> files = extDir.listSync();
    
    Map<String, Map<String, String>> pairs = {};
    for (var file in files) {
      String path = file.path;
      if (path.endsWith('.jpg')) {
        String baseName = path.substring(0, path.length - 4);
        pairs[baseName] ??= {};
        pairs[baseName]!['img'] = path;
      } else if (path.endsWith('.mp4')) {
        String baseName = path.substring(0, path.length - 4);
        pairs[baseName] ??= {};
        pairs[baseName]!['vid'] = path;
      }
    }

    List<Map<String, String>> loadedList = [];
    pairs.forEach((key, value) {
      if (value['img'] != null && value['vid'] != null) {
        loadedList.add({'img': value['img']!, 'vid': value['vid']!});
      }
    });

    setState(() {
      _mediaList = loadedList.reversed.toList();
    });
  }

  // التقاط الـ Live Photo وحفظها تلقائياً في استوديو الهاتف
  Future<void> _captureLivePhoto() async {
    if (_controller == null || !_controller!.value.isInitialized || _isCapturing) return;

    setState(() {
      _isCapturing = true;
    });

    try {
      final Directory extDir = await getApplicationDocumentsDirectory();
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final String baseFilePath = '${extDir.path}/$timestamp';

      // 1. تسجيل الفيديو القصير (حركة Live)
      await _controller!.startVideoRecording();
      await Future.delayed(const Duration(seconds: 2));
      XFile videoFile = await _controller!.stopVideoRecording();
      String videoPath = '$baseFilePath.mp4';
      await videoFile.saveTo(videoPath);

      // 2. التقاط الصورة الثابتة
      XFile photoFile = await _controller!.takePicture();
      String imagePath = '$baseFilePath.jpg';
      await photoFile.saveTo(imagePath);

      // 3. حفظ الفيديو والصورة مباشرة في استوديو الهاتف العام (Gallery)
      if (await Gal.hasAccess()) {
        await Gal.putVideo(videoPath); // يحفظ الفيديو المتحرك في الاستوديو
        await Gal.putImage(imagePath); // يحفظ الصورة الثابتة في الاستوديو
      }

      setState(() {
        _mediaList.insert(0, {'img': imagePath, 'vid': videoPath});
        _isCapturing = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم التقاط وحفظ الـ Live Photo في الاستوديو بنجاح!')),
      );
    } catch (e) {
      debugPrint("Error capturing: $e");
      setState(() {
        _isCapturing = false;
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Photo الاحترافي'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CameraPreview(_controller!),
                if (_isCapturing)
                  Container(
                    color: Colors.black54,
                    child: const Center(
                      child: Text(
                        "جاري تسجيل اللقطة الحية...",
                        style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: FloatingActionButton.large(
              onPressed: _isCapturing ? null : _captureLivePhoto,
              backgroundColor: Colors.red,
              child: const Icon(Icons.camera, size: 40, color: Colors.white),
            ),
          ),

          const Text("معرض التطبيق (اضغط مطولاً للمعاينة أو شاركها):", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          Expanded(
            flex: 2,
            child: _mediaList.isEmpty
                ? const Center(child: Text("لا توجد لقطات بعد"))
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _mediaList.length,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: LivePhotoThumbnail(
                          imagePath: _mediaList[index]['img']!,
                          videoPath: _mediaList[index]['vid']!,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class LivePhotoThumbnail extends StatefulWidget {
  final String imagePath;
  final String videoPath;

  const LivePhotoThumbnail({super.key, required this.imagePath, required this.videoPath});

  @override
  State<LivePhotoThumbnail> createState() => _LivePhotoThumbnailState();
}

class _LivePhotoThumbnailState extends State<LivePhotoThumbnail> {
  VideoPlayerController? _videoController;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _videoController = VideoPlayerController.file(File(widget.videoPath))
      ..initialize().then((_) {
        _videoController!.setLooping(true);
        setState(() {});
      });
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  void _startPlaying() {
    if (_videoController != null && _videoController!.value.isInitialized) {
      _videoController!.play();
      setState(() {
        _isPlaying = true;
      });
    }
  }

  void _stopPlaying() {
    if (_videoController != null && _videoController!.value.isInitialized) {
      _videoController!.pause();
      _videoController!.seekTo(Duration.zero);
      setState(() {
        _isPlaying = false;
      });
    }
  }

  // دالة لمشاركة ملف الفيديو المتحرك مباشرة عبر واتساب أو غيره ليظهر كحركة للطرف الآخر
  void _shareLiveMotion() async {
    await Share.shareXFiles([XFile(widget.videoPath)], text: 'شاهد هذه اللقطة الحية!');
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: (_) => _startPlaying(),
      onLongPressEnd: (_) => _stopPlaying(),
      onTap: _shareLiveMotion, // الضغط العادي يفتح قائمة المشاركة لإرسالها كحركة للآخرين
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 100,
          height: 100,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _isPlaying && _videoController != null && _videoController!.value.isInitialized
                  ? VideoPlayer(_videoController!)
                  : Image.file(File(widget.imagePath), fit: BoxFit.cover),
              
              Positioned(
                bottom: 4,
                right: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  color: Colors.black54,
                  child: const Text("SHARE/LIVE", style: TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
