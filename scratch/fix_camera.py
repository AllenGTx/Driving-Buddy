import re

with open("lib/main.dart", "r", encoding="utf-8") as f:
    content = f.read()

old_block = """      _cameraController = CameraController(
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

          final faces = await _faceDetector.processImage(inputImage);"""


new_block = """      _cameraController = CameraController(
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

          final faces = await _faceDetector.processImage(inputImage);"""


if old_block in content:
    content = content.replace(old_block, new_block)
    with open("lib/main.dart", "w", encoding="utf-8") as f:
        f.write(content)
    print("Success")
else:
    print("Block not found!")
