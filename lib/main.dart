// lib/main.dart
// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Geo-Fence with ML Face Auth',
      theme: ThemeData(primarySwatch: Colors.teal),
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// ------------------------ HOME PAGE ------------------------
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _latController = TextEditingController();
  final TextEditingController _lngController = TextEditingController();

  // Predefined target location
  final double _predefinedTargetLatitude = 18.466225;
  final double _predefinedTargetLongitude = 73.790503;

  double? _targetLatitude;
  double? _targetLongitude;
  double _distanceMeters = 0.0;
  bool _insideArea = false;
  bool _isAuthenticated = false;
  bool _isLoading = true;
  String _statusText = 'Initializing...';
  StreamSubscription<Position>? _positionStream;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // Set the predefined target coordinates
    _targetLatitude = _predefinedTargetLatitude;
    _targetLongitude = _predefinedTargetLongitude;

    // Fill the text fields with predefined coordinates
    _latController.text = _predefinedTargetLatitude.toString();
    _lngController.text = _predefinedTargetLongitude.toString();

    await _requestCameraPermission();

    final prefs = await SharedPreferences.getInstance();
    final registered = prefs.containsKey('registeredFacePath');

    if (!mounted) return;
    setState(() {
      _isAuthenticated = false;
      _isLoading = false;
      _statusText =
          registered ? 'Please authenticate with your face' : 'Register your face first';
    });
  }

  Future<void> _requestCameraPermission() async {
    var status = await Permission.camera.status;
    if (status.isDenied) await Permission.camera.request();
    if (status.isPermanentlyDenied) openAppSettings();
  }

  Future<void> _registerFace() async {
    final success = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => const FaceCapturePage(isRegistration: true),
      ),
    );

    if (success == true) {
      final prefs = await SharedPreferences.getInstance();
      final registered = prefs.containsKey('registeredFacePath');
      if (mounted && registered) {
        setState(() => _statusText = 'Face registered successfully!');
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Face registration failed! Try again.')),
        );
      }
    }
  }

  Future<void> _authenticateWithFace() async {
    final prefs = await SharedPreferences.getInstance();
    final registered = prefs.containsKey('registeredFacePath');

    if (!registered) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please register your face first!')),
      );
      return;
    }

    final success = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => const FaceCapturePage(isRegistration: false),
      ),
    );

    if (success == true) {
      if (!mounted) return;
      setState(() {
        _isAuthenticated = true;
        _statusText = 'Face matched! Starting location tracking...';
      });
      _startLocationTracking();
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Face authentication failed! Try again.')),
      );
    }
  }

  // ----------------- GEOLOCATION -----------------
  Future<void> _startLocationTracking() async {
    final bool ok = await _ensurePermissions();
    if (!ok) {
      setState(() {
        _statusText = 'Location permissions required';
      });
      return;
    }

    try {
      final Position current = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );
      _evaluateDistanceAndState(current.latitude, current.longitude);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Location error: ${e.toString()}')),
      );
    }
    _startPositionStream();
    setState(() {
      _statusText = 'Tracking location...';
    });
  }

  Future<bool> _ensurePermissions() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Location services disabled'),
          content: const Text('Please enable location services (GPS) and try again.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Permission denied'),
          content: const Text('Location permission was denied. Please allow it from settings.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return false;
    }
    if (permission == LocationPermission.deniedForever) {
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Permission permanently denied'),
          content: const Text('Location permission is permanently denied. Please enable it from app settings.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return false;
    }
    return true;
  }

  // Set the target latitude/longitude from the input fields
  Future<void> _setTargetAndStart() async {
    if (!_isAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please authenticate first')),
      );
      return;
    }

    final String latText = _latController.text.trim();
    final String lngText = _lngController.text.trim();
    if (latText.isEmpty || lngText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter both latitude and longitude')),
      );
      return;
    }

    double? lat = double.tryParse(latText);
    double? lng = double.tryParse(lngText);
    if (lat == null || lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid latitude or longitude format')),
      );
      return;
    }

    final bool ok = await _ensurePermissions();
    if (!ok) return;

    setState(() {
      _targetLatitude = lat;
      _targetLongitude = lng;
      _statusText = 'Target set: (${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)})';
    });
    _startLocationTracking();
  }

  void _startPositionStream() {
    _positionStream?.cancel();
    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 1,
    );
    _positionStream = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(
      (Position position) {
        _evaluateDistanceAndState(position.latitude, position.longitude);
      },
      onError: (error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Location error: ${error.toString()}')),
        );
      },
    );
  }

  // Calculate distance between current position and target, update UI state
  void _evaluateDistanceAndState(double currentLat, double currentLng) {
    if (_targetLatitude == null || _targetLongitude == null) return;
    double meters = Geolocator.distanceBetween(
      currentLat,
      currentLng,
      _targetLatitude!,
      _targetLongitude!,
    );
    bool inside = meters <= 100.0;
    setState(() {
      _distanceMeters = meters;
      _insideArea = inside;
      _statusText = inside ? 'You are inside the 100 m radius' : 'You are outside the 100 m radius';
    });
  }

  // Stop continuous location updates
  void _stopPositionStream() {
    _positionStream?.cancel();
    _positionStream = null;
    setState(() {
      _statusText = 'Location tracking stopped';
    });
  }

  // Format distance for display
  String _formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.toStringAsFixed(1)} m';
    } else {
      double km = meters / 1000.0;
      return '${km.toStringAsFixed(3)} km';
    }
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _latController.dispose();
    _lngController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Geo-Fence (100m) + Face Auth'),
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Initializing...'),
                ],
              ),
            )
          : !_isAuthenticated
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.face_retouching_natural,
                          size: 70, color: Colors.teal),
                      const SizedBox(height: 16),
                      Text(_statusText,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 18)),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.person_add_alt_1),
                        onPressed: _registerFace,
                        label: const Text('Register Face'),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.verified_user),
                        onPressed: _authenticateWithFace,
                        label: const Text('Authenticate Face'),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Set target location (latitude / longitude):'),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _latController,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true, signed: true),
                        decoration: const InputDecoration(
                          labelText: 'Latitude',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _lngController,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true, signed: true),
                        decoration: const InputDecoration(
                          labelText: 'Longitude',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          ElevatedButton(
                            onPressed: _setTargetAndStart,
                            child: const Text('Update Location'),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            onPressed: _stopPositionStream,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey,
                            ),
                            child: const Text('Stop Tracking'),
                          ),
                        ],
                      ),
                      const Divider(height: 30),
                      Text('Status: $_statusText'),
                      const SizedBox(height: 8),
                      Text('Distance: ${_formatDistance(_distanceMeters)}'),
                      const SizedBox(height: 8),
                      Card(
                        elevation: 4,
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _insideArea ? 'You are IN the area' : 'You are OUT of the area',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Icon(
                                _insideArea ? Icons.check_circle : Icons.location_off,
                                color: _insideArea ? Colors.green : Colors.red,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text('Notes:', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      const Text('- Predefined target location: 18.466225, 73.790503'),
                      const Text('- Best tested on a real device (GPS) for accurate results.'),
                      const Text('- In emulator, simulate location via Extended Controls or adb commands.'),
                    ],
                  ),
                ),
      floatingActionButton: _isAuthenticated
          ? FloatingActionButton(
              onPressed: () async {
                try {
                  if (!await _ensurePermissions()) return;
                  final pos = await Geolocator.getCurrentPosition(
                    desiredAccuracy: LocationAccuracy.best,
                  );
                  _latController.text = pos.latitude.toString();
                  _lngController.text = pos.longitude.toString();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Filled current location into fields')),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error getting location: ${e.toString()}')),
                  );
                }
              },
              child: const Icon(Icons.my_location),
              tooltip: 'Use current device location',
            )
          : null,
    );
  }
}

// ------------------------ FACE CAPTURE PAGE ------------------------
class FaceCapturePage extends StatefulWidget {
  final bool isRegistration;
  const FaceCapturePage({super.key, required this.isRegistration});

  @override
  State<FaceCapturePage> createState() => _FaceCapturePageState();
}

class _FaceCapturePageState extends State<FaceCapturePage> {
  CameraController? _controller;
  bool _busy = false;
  bool _faceDetected = false;
  bool _isGoodPosition = false;

  final FaceDetector _detector = FaceDetector(
    options: FaceDetectorOptions(
      enableContours: true,
      enableClassification: false,
      enableLandmarks: true,
      performanceMode: FaceDetectorMode.accurate,
    ),
  );

  Timer? _faceDetectionTimer;
  Face? _currentFace;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    if (cameras.isEmpty) return;
    _controller = CameraController(
      cameras.firstWhere(
          (cam) => cam.lensDirection == CameraLensDirection.front,
          orElse: () => cameras.first),
      ResolutionPreset.medium,
    );
    await _controller!.initialize();
    if (mounted) setState(() {});
    _startFaceDetection();
  }

  void _startFaceDetection() {
    _faceDetectionTimer?.cancel();
    _faceDetectionTimer = Timer.periodic(const Duration(milliseconds: 900), (timer) {
      if (_controller != null && _controller!.value.isInitialized && !_busy) {
        _detectFaceInPreview();
      }
    });
  }

  Future<void> _detectFaceInPreview() async {
    try {
      if (_controller == null || !_controller!.value.isInitialized) return;

      // Take a quick picture and run face detector on it
      final image = await _controller!.takePicture();
      final inputImage = InputImage.fromFilePath(image.path);
      final faces = await _detector.processImage(inputImage);

      // Delete the temporary image file
      try {
        await File(image.path).delete();
      } catch (_) {}

      if (mounted) {
        setState(() {
          _faceDetected = faces.isNotEmpty;
          _currentFace = faces.isNotEmpty ? faces.first : null;
          _isGoodPosition = _faceDetected ? _isFaceAcceptable(_currentFace!) : false;
        });
      }
    } catch (e) {
      debugPrint('Face detection error: $e');
    }
  }

  bool _isFaceAcceptable(Face face) {
    // Acceptable ranges — more lenient
    final yaw = face.headEulerAngleY?.abs() ?? 0;
    final pitch = face.headEulerAngleX?.abs() ?? 0;
    final roll = face.headEulerAngleZ?.abs() ?? 0;

    // Accept wider range of head positions but not extreme
    return yaw < 50 && pitch < 50 && roll < 50;
  }

  Future<void> _captureAndProcess() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (!_faceDetected || _currentFace == null) {
      _showMsg('No face detected! Please position your face in the circle.');
      return;
    }

    if (mounted) setState(() => _busy = true);

    try {
      final picture = await _controller!.takePicture();
      final inputImage = InputImage.fromFilePath(picture.path);
      final faces = await _detector.processImage(inputImage);

      if (faces.isEmpty) {
        _showMsg('Face lost during capture! Please try again.');
        setState(() => _busy = false);
        return;
      }

      final face = faces.first;

      if (!_isFaceGoodEnough(face)) {
        _showMsg('Please ensure your face is clearly visible in the circle.');
        setState(() => _busy = false);
        return;
      }

      final prefs = await SharedPreferences.getInstance();

      if (widget.isRegistration) {
        // Save persistent copy of the captured image (camera temp path may be cleaned)
        final savedPath = await _saveImageToAppDir(picture.path);

        // Extract embedding vector
        final vector = await _extractFaceEmbedding(savedPath, face);

        if (vector.isEmpty) {
          _showMsg('Failed to process face. Try in better light.');
          setState(() => _busy = false);
          return;
        }

        // Store vector and path
        await prefs.setString('registeredFacePath', savedPath);
        await prefs.setString('face_vector', vector.join(','));

        _showMsg('Face registered successfully!');
        if (mounted) {
          setState(() => _busy = false);
          Navigator.pop(context, true);
        }
      } else {
        final regPath = prefs.getString('registeredFacePath');
        final storedVecStr = prefs.getString('face_vector');

        if (regPath == null || storedVecStr == null) {
          _showMsg('No face registered yet!');
          if (mounted) {
            setState(() => _busy = false);
            Navigator.pop(context, false);
          }
          return;
        }

        // Extract vector of current capture
        final currentVector = await _extractFaceEmbedding(picture.path, face);

        // Parse stored vector
        final storedVector = storedVecStr.split(',').map((e) => double.tryParse(e) ?? 0.0).toList();

        final similarity = _cosineSimilarity(storedVector, currentVector);
        debugPrint('Face similarity: $similarity');

        // Threshold: tune as needed. 0.86 is strict but robust.
        final matched = similarity >= 0.86;

        _showMsg(matched ? 'Face matched ✅' : 'Not matched ❌');

        // delete temporary capture file
        try {
          await File(picture.path).delete();
        } catch (_) {}

        if (mounted) {
          setState(() => _busy = false);
          Navigator.pop(context, matched);
        }
      }
    } catch (e) {
      _showMsg('Error: $e');
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String> _saveImageToAppDir(String srcPath) async {
    try {
      final bytes = await File(srcPath).readAsBytes();
      final dir = await getApplicationDocumentsDirectory();
      final targetPath = '${dir.path}/registered_face.jpg';
      final f = File(targetPath);
      await f.writeAsBytes(bytes, flush: true);
      return targetPath;
    } catch (e) {
      debugPrint('Save image error: $e');
      return srcPath; // fallback to original path
    }
  }

  bool _isFaceGoodEnough(Face face) {
    // Basic checks: size and landmarks
    if (face.boundingBox.width < 80 || face.boundingBox.height < 80) {
      debugPrint('Face too small: ${face.boundingBox.width}x${face.boundingBox.height}');
      return false;
    }

    final leftEye = face.landmarks[FaceLandmarkType.leftEye];
    final rightEye = face.landmarks[FaceLandmarkType.rightEye];
    final noseBase = face.landmarks[FaceLandmarkType.noseBase];

    if (leftEye == null || rightEye == null || noseBase == null) {
      debugPrint('Missing basic landmarks');
      return false;
    }

    return true;
  }

  /// Extract a normalized grayscale embedding vector from the face image.
  /// Steps:
  /// 1. load the image
  /// 2. compute an expanded crop around face bounding box (with padding)
  /// 3. if eyes available, align by rotating crop to make eye line horizontal
  /// 4. resize to fixed size (112x112) and grayscale -> normalized vector [0..1]
  Future<List<double>> _extractFaceEmbedding(String imagePath, Face face) async {
    try {
      final bytes = await File(imagePath).readAsBytes();
      img.Image? image = img.decodeImage(bytes);
      if (image == null) return [];

      // bounding box from MLKit is in image coordinates
      final rect = face.boundingBox;

      // Add padding to bounding box (use ints safely)
      final padW = (rect.width * 0.4).toInt();
      final padH = (rect.height * 0.6).toInt();

      int left = math.max(0, rect.left.toInt() - padW);
      int top = math.max(0, rect.top.toInt() - padH);
      int right = math.min(image.width, rect.right.toInt() + padW);
      int bottom = math.min(image.height, rect.bottom.toInt() + padH);

      int width = math.max(1, right - left);
      int height = math.max(1, bottom - top);

      // Use named arguments for copyCrop
      img.Image crop = img.copyCrop(image, x: left, y: top, width: width, height: height);

      // Align by eyes if available
      final leftEye = face.landmarks[FaceLandmarkType.leftEye];
      final rightEye = face.landmarks[FaceLandmarkType.rightEye];
      if (leftEye != null && rightEye != null) {
        // Convert landmark coordinates relative to the crop
        final eyeLX = leftEye.position.x - left;
        final eyeLY = leftEye.position.y - top;
        final eyeRX = rightEye.position.x - left;
        final eyeRY = rightEye.position.y - top;

        final dy = eyeRY - eyeLY;
        final dx = eyeRX - eyeLX;
        final angleRad = math.atan2(dy, dx);
        final angleDeg = angleRad * 180 / math.pi;

        // rotate by negative angle to make eyes horizontal
        // Use named parameter 'angle' to match image package >=4.x
        final rotated = img.copyRotate(crop, angle: -angleDeg);
        crop = rotated;
      }

      // Resize to fixed size (named params ok)
      final targetSize = 112;
      final resized = img.copyResize(crop, width: targetSize, height: targetSize);

      // Convert to grayscale
      final gray = img.grayscale(resized);

      // Get bytes of grayscale image
      final pixels = gray.getBytes(); // intensity bytes

      // Normalize to 0..1
      final vector = pixels.map((p) => (p & 0xFF) / 255.0).toList();

      // L2 normalize the vector (helps cosine similarity)
      final norm = math.sqrt(vector.fold(0.0, (prev, e) => prev + e * e));
      if (norm > 1e-6) {
        for (int i = 0; i < vector.length; i++) {
          vector[i] = vector[i] / norm;
        }
      }

      return vector;
    } catch (e) {
      debugPrint('Embedding extraction error: $e');
      return [];
    }
  }

  double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.isEmpty || b.isEmpty) return 0.0;
    final len = math.min(a.length, b.length);
    double dot = 0, magA = 0, magB = 0;
    for (int i = 0; i < len; i++) {
      dot += a[i] * b[i];
      magA += a[i] * a[i];
      magB += b[i] * b[i];
    }
    if (magA <= 0 || magB <= 0) return 0.0;
    return dot / (math.sqrt(magA) * math.sqrt(magB));
  }

  void _showMsg(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    _faceDetectionTimer?.cancel();
    _controller?.dispose();
    _detector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isRegistration ? 'Register Face' : 'Authenticate Face'),
      ),
      body: _controller == null || !_controller!.value.isInitialized
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                CameraPreview(_controller!),

                // Face detection overlay
                _buildFaceDetectionOverlay(),

                // Guidance
                _buildGuidanceOverlay(),

                if (_busy)
                  Container(
                    color: Colors.black54,
                    child: const Center(child: CircularProgressIndicator(color: Colors.white)),
                  ),
              ],
            ),
      floatingActionButton: _faceDetected
          ? FloatingActionButton.extended(
              onPressed: _busy ? null : _captureAndProcess,
              icon: Icon(_faceDetected ? Icons.face : Icons.camera, color: Colors.white),
              label: Text(widget.isRegistration ? 'Register Face' : 'Verify Face'),
              backgroundColor: _faceDetected ? Colors.green : Colors.teal,
            )
          : null,
    );
  }

  Widget _buildFaceDetectionOverlay() {
    return Center(
      child: Container(
        width: 250,
        height: 250,
        decoration: BoxDecoration(
          border: Border.all(
            color: _faceDetected ? Colors.green : Colors.white60,
            width: 3,
          ),
          borderRadius: BorderRadius.circular(125),
        ),
        child: _faceDetected
            ? Icon(
                Icons.face,
                size: 50,
                color: Colors.green,
              )
            : Icon(
                Icons.face_retouching_natural,
                size: 50,
                color: Colors.white60,
              ),
      ),
    );
  }

  Widget _buildGuidanceOverlay() {
    return Positioned(
      bottom: 100,
      left: 20,
      right: 20,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              _faceDetected
                  ? '✓ Face detected! Ready to ${widget.isRegistration ? 'register' : 'verify'}'
                  : 'Position your face in the circle',
              style: TextStyle(
                color: _faceDetected ? Colors.green : Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Make sure your face is clearly visible',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
