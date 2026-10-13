import re

with open("lib/main.dart", "r", encoding="utf-8") as f:
    lines = f.readlines()

# 1. Add ML Kit Import
for i, line in enumerate(lines):
    if "import 'package:camera/camera.dart';" in line:
        if "google_mlkit_face_detection" not in "".join(lines):
            lines.insert(i+1, "import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';\n")
            lines.insert(i+2, "import 'package:flutter/foundation.dart'; // for WriteBuffer\n")
        break

content = "".join(lines)

# 2. Update Variables
old_vars = """  // Kamera & WebSocket
  CameraController? _cameraController;
  WebSocketChannel? _channel;
  bool _isProcessingFrame = false;
  String _currentServerIp = kDefaultServerIp;"""

new_vars = """  // Kamera & ML Kit On-Device
  CameraController? _cameraController;
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true,
      enableContours: true,
      performanceMode: FaceDetectorMode.fast,
    ),
  );
  bool _isProcessingFrame = false;"""

content = content.replace(old_vars, new_vars)

# 3. Replace _startMonitoring
start_idx = content.find("Future<void> _startMonitoring() async {")
end_idx = content.find("void _resumeTimer() {")

if start_idx != -1 and end_idx != -1:
    old_start_monitoring = content[start_idx:end_idx]
    
    new_start_monitoring = """Future<void> _startMonitoring() async {
    setState(() {
      _isMonitoring = true;
      _driverCondition = 'MEMUAT KAMERA...';
      _conditionDescription = 'Menyiapkan AI deteksi wajah On-Device.';
      _cameraMode = 'Memulai';
      _eyeDetected = false;
      _isAlertShowing = false;
    });

    final hasPermission = await _requestCameraPermission();
    if (!hasPermission) {
      if (mounted) {
        setState(() {
          _isMonitoring = false;
          _driverCondition = 'IZIN DITOLAK';
          _conditionDescription = 'Izin kamera dibutuhkan untuk monitoring.';
        });
      }
      return;
    }

    try {
      final cameras = await availableCameras();
      final frontCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.yuv420
            : ImageFormatGroup.bgra8888,
      );

      await _cameraController!.initialize();

      if (!mounted) return;

      setState(() {
        _cameraMode = 'AI Siaga Optimal';
        _driverCondition = 'MENUNGGU DETEKSI';
        _conditionDescription = 'Mencari wajah pengemudi...';
      });

      _resumeTimer();

      // Start processing frames with ML Kit
      _cameraController!.startImageStream((CameraImage image) async {
        if (_isProcessingFrame || !_isMonitoring) return;
        _isProcessingFrame = true;

        try {
          final WriteBuffer allBytes = WriteBuffer();
          for (final Plane plane in image.planes) {
            allBytes.putUint8List(plane.bytes);
          }
          final bytes = allBytes.done().buffer.asUint8List();

          final Size imageSize = Size(image.width.toDouble(), image.height.toDouble());
          
          final cameraRotation = InputImageRotationValue.fromRawValue(
              frontCamera.sensorOrientation) ?? InputImageRotation.rotation270deg;

          final format = InputImageFormatValue.fromRawValue(image.format.raw) ??
              (Platform.isAndroid ? InputImageFormat.nv21 : InputImageFormat.bgra8888);

          final planeData = image.planes.map(
            (Plane plane) {
              return InputImageMetadata(
                bytesPerRow: plane.bytesPerRow,
                size: Size(image.width.toDouble(), image.height.toDouble()),
                rotation: cameraRotation,
                format: format,
              );
            },
          ).toList();

          final inputImageMetadata = InputImageMetadata(
            size: imageSize,
            rotation: cameraRotation,
            format: format,
            bytesPerRow: planeData.first.bytesPerRow,
          );

          final inputImage = InputImage.fromBytes(
            bytes: bytes,
            metadata: inputImageMetadata,
          );

          final faces = await _faceDetector.processImage(inputImage);

          if (faces.isNotEmpty) {
            final face = faces.first;
            
            // EAR (Eye Aspect Ratio) proxy using probabilities
            double leftProb = face.leftEyeOpenProbability ?? 1.0;
            double rightProb = face.rightEyeOpenProbability ?? 1.0;
            double avgEyeOpen = (leftProb + rightProb) / 2.0;

            // MAR (Mouth Aspect Ratio) proxy using contours
            double mar = 0.0;
            final upperLip = face.contours[FaceContourType.upperLipTop]?.points;
            final lowerLip = face.contours[FaceContourType.lowerLipBottom]?.points;
            
            if (upperLip != null && lowerLip != null && upperLip.isNotEmpty && lowerLip.isNotEmpty) {
              // Ambil titik tengah bibir
              final upperMid = upperLip[upperLip.length ~/ 2];
              final lowerMid = lowerLip[lowerLip.length ~/ 2];
              // Jarak vertikal absolut
              mar = (lowerMid.y - upperMid.y).abs().toDouble();
            }

            if (mounted) {
              setState(() {
                _eyeDetected = true;
                _earIndex = avgEyeOpen;
                
                String status = 'AWAKE';
                
                if (avgEyeOpen < 0.25) {
                  _blinkFrequency++; // Simple blink approximation
                  status = 'SLEEP';
                } else if (avgEyeOpen < 0.6) {
                  status = 'DROWSY';
                } else if (mar > 35.0) { // Threshold for yawning
                  status = 'YAWN';
                }

                _driverCondition = status;
                
                if (_driverCondition == 'AWAKE') {
                  _earStatus = 'Aman';
                  _awarenessLevel = 0.99;
                  _fatigueScore = 5;
                  _fatigueLabel = 'Segar';
                  _conditionDescription = 'Pengemudi Fokus & Segar';
                } else if (_driverCondition == 'YAWN') {
                  _earStatus = 'Mengantuk';
                  _awarenessLevel = 0.70;
                  _fatigueScore = 40;
                  _fatigueLabel = 'Perlu Waspada';
                  _conditionDescription = 'Terdeteksi Menguap';
                } else if (_driverCondition == 'DROWSY') {
                  _earStatus = 'Waspada!';
                  _awarenessLevel = 0.40;
                  _fatigueScore = 70;
                  _fatigueLabel = 'Lelah';
                  _conditionDescription = 'Mata Sayu / Kelelahan';
                } else if (_driverCondition == 'SLEEP') {
                  _earStatus = 'BAHAYA!';
                  _awarenessLevel = 0.10;
                  _fatigueScore = 95;
                  _fatigueLabel = 'Kritis';
                  _conditionDescription = 'TERTIDUR! (Microsleep)';
                  _triggerMicrosleepAlert();
                }
              });
            }
          } else {
            if (mounted) {
              setState(() {
                _eyeDetected = false;
                _driverCondition = 'MENUNGGU DETEKSI';
                _conditionDescription = 'Wajah tidak terlihat oleh kamera.';
                _awarenessLevel = 0.0;
              });
            }
          }
        } catch (e) {
          debugPrint('ML Kit Error: $e');
        } finally {
          // Reduce frame rate to save CPU
          await Future.delayed(const Duration(milliseconds: 250));
          _isProcessingFrame = false;
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isMonitoring = false;
          _driverCondition = 'GAGAL MEMUAT';
          _conditionDescription = 'Error Kamera: $e';
        });
      }
    }
  }

  """
    content = content.replace(old_start_monitoring, new_start_monitoring)
    
# 4. Remove WebSocket close in _stopMonitoring
content = content.replace("_channel?.sink.close();", "// websocket removed")
content = content.replace("_channel = null;", "// websocket removed")
content = content.replace("_processingTimer?.cancel();", "// _processingTimer?.cancel();")


with open("lib/main.dart", "w", encoding="utf-8") as f:
    f.write(content)

print("Modified main.dart successfully.")
