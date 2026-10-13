import re

with open("lib/main.dart", "r", encoding="utf-8") as f:
    content = f.read()

# 1. Update FaceDetectorOptions
old_options = """    options: FaceDetectorOptions(
      enableClassification: true,
      enableContours: true,
      performanceMode: FaceDetectorMode.fast,
    ),"""

new_options = """    options: FaceDetectorOptions(
      enableClassification: true,
      enableLandmarks: true,
      enableContours: false, // CRITICAL FIX: Cannot use contours + classification in fast mode
      performanceMode: FaceDetectorMode.fast,
    ),"""
content = content.replace(old_options, new_options)


# 2. Rewrite _startMonitoring completely
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
        ResolutionPreset.low, // Keep it low for performance
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21 // REQUIRED FOR ML KIT ANDROID!
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
          final format = InputImageFormatValue.fromRawValue(image.format.raw);
          if (format == null ||
              (Platform.isAndroid && format != InputImageFormat.nv21) ||
              (Platform.isIOS && format != InputImageFormat.bgra8888)) {
            return;
          }

          if (image.planes.isEmpty) return;
          final plane = image.planes.first;

          final cameraRotation = InputImageRotationValue.fromRawValue(
              frontCamera.sensorOrientation) ?? InputImageRotation.rotation270deg;

          final inputImage = InputImage.fromBytes(
            bytes: plane.bytes,
            metadata: InputImageMetadata(
              size: Size(image.width.toDouble(), image.height.toDouble()),
              rotation: cameraRotation,
              format: format,
              bytesPerRow: plane.bytesPerRow,
            ),
          );

          final faces = await _faceDetector.processImage(inputImage);

          if (faces.isNotEmpty) {
            final face = faces.first;
            
            // EAR (Eye Aspect Ratio) proxy using probabilities
            double leftProb = face.leftEyeOpenProbability ?? 1.0;
            double rightProb = face.rightEyeOpenProbability ?? 1.0;
            double avgEyeOpen = (leftProb + rightProb) / 2.0;

            // MAR (Mouth Aspect Ratio) proxy using landmarks
            double mar = 0.0;
            final bottomMouth = face.landmarks[FaceLandmarkType.bottomMouth]?.position;
            final leftMouth = face.landmarks[FaceLandmarkType.leftMouth]?.position;
            final rightMouth = face.landmarks[FaceLandmarkType.rightMouth]?.position;

            if (bottomMouth != null && leftMouth != null && rightMouth != null) {
              final a = (rightMouth.y - leftMouth.y).toDouble();
              final b = (leftMouth.x - rightMouth.x).toDouble();
              final c = (rightMouth.x * leftMouth.y - rightMouth.y * leftMouth.x).toDouble();
              
              final mouthWidth = sqrt(a*a + b*b);
              if (mouthWidth > 0) {
                final dist = (a * bottomMouth.x + b * bottomMouth.y + c).abs() / mouthWidth;
                mar = dist / mouthWidth; // Ratio of jaw drop to mouth width
              }
            }

            if (mounted) {
              setState(() {
                _eyeDetected = true;
                _earIndex = avgEyeOpen;
                
                String status = 'AWAKE';
                
                if (avgEyeOpen < 0.25) {
                  _blinkFrequency++;
                  status = 'SLEEP';
                } else if (avgEyeOpen < 0.6) {
                  status = 'DROWSY';
                } else if (mar > 0.4) { // Threshold for yawning using MAR ratio
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
          // Reduce frame rate to save CPU (proses 4 frame per detik)
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

with open("lib/main.dart", "w", encoding="utf-8") as f:
    f.write(content)
print("Fix applied.")
