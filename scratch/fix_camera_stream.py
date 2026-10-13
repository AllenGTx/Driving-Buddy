import re

with open("lib/main.dart", "r", encoding="utf-8") as f:
    content = f.read()

old_block = """      _cameraController!.startImageStream((CameraImage image) async {
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

          // Menggunakan cara resmi dari dokumentasi ML Kit google_mlkit_commons
          final cameraRotation = InputImageRotationValue.fromRawValue(
              frontCamera.sensorOrientation) ?? InputImageRotation.rotation270deg;

          final inputImage = InputImage.fromBytes(
            bytes: plane.bytes,
            metadata: InputImageMetadata(
              size: Size(image.width.toDouble(), image.height.toDouble()),
              rotation: cameraRotation, // used only in Android
              format: format, // used only in iOS
              bytesPerRow: plane.bytesPerRow, // used only in iOS
            ),
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
      });"""

new_block = """      // Menggunakan Timer dan takePicture() untuk menghindari bug buffer Kamera Vivo (NullPointerException di ML Kit)
      _processingTimer = Timer.periodic(const Duration(milliseconds: 400), (_) async {
        if (!_isProcessingFrame && _isMonitoring &&
            _cameraController != null &&
            (_cameraController?.value.isInitialized ?? false)) {
          _isProcessingFrame = true;
          String? tempPath;
          try {
            final XFile photo = await _cameraController!.takePicture();
            tempPath = photo.path;
            
            final inputImage = InputImage.fromFilePath(tempPath);
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
            _isProcessingFrame = false;
            if (tempPath != null) {
              try { await File(tempPath).delete(); } catch (_) {}
            }
          }
        }
      });"""

if old_block in content:
    content = content.replace(old_block, new_block)
    # Add _processingTimer back to MonitorScreenState variables
    if "Timer? _processingTimer;" not in content:
        content = content.replace("  Timer? _drivingTimer;\n", "  Timer? _drivingTimer;\n  Timer? _processingTimer;\n")
    # Add _processingTimer?.cancel() back to _stopMonitoring
    if "// _processingTimer?.cancel();" in content:
        content = content.replace("// _processingTimer?.cancel();", "_processingTimer?.cancel();")
    
    with open("lib/main.dart", "w", encoding="utf-8") as f:
        f.write(content)
    print("Success")
else:
    print("Block not found!")
