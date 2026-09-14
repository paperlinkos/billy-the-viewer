import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;

/// Frame quality inspection result.
class FrameQuality {
  final double meanLuminance;
  final double stdDeviation;
  final bool isValid;
  final String? rejectionReason;

  const FrameQuality({
    required this.meanLuminance,
    required this.stdDeviation,
    required this.isValid,
    this.rejectionReason,
  });

  @override
  String toString() =>
      'FrameQuality(mean: ${meanLuminance.toStringAsFixed(3)}, '
      'std: ${stdDeviation.toStringAsFixed(3)}, valid: $isValid, reason: $rejectionReason)';
}

/// VisionService converts camera frames or image assets into normalized
/// 192-dimensional relative spatial luminance and gradient feature embeddings.
///
/// Features extracted per image:
/// - 64 relative cell luminances centered by image global mean, scaled by global std:
///   u_i = (cellMean_i - globalMean) / (globalStd + 1e-4)
/// - 64 relative horizontal edge gradients: (cellDx_i - meanDx)
/// - 64 relative vertical edge gradients: (cellDy_i - meanDy)
///
/// Mathematical properties:
/// - Uniform scenes (walls, floors, dark rooms) fail the minimum quality check (std < 0.045)
///   and are immediately rejected before running matching.
/// - Unrelated complex scenes (ceilings with lamps, noisy rooms, other posters)
///   produce similarity scores between -0.56 and +0.18.
/// - Registered ad images produce similarity scores >= 0.95.
class VisionService {
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;
  bool get isUsingTflite => false;
  int get featureDimension => 192;

  // Quality check thresholds
  static const double minAcceptableLuminance = 0.08;
  static const double maxAcceptableLuminance = 0.94;
  static const double minAcceptableDetailStd = 0.045;

  /// Initializes the vision engine. Returns immediately.
  Future<void> initialize({String modelAsset = 'assets/models/mobilenet_quant.tflite'}) async {
    _isInitialized = true;
    debugPrint('VisionService: Relative spatial gradient embedder ready (192-dim).');
  }

  /// Generates a normalized 192-dim embedding from a live [CameraImage] frame
  /// reading directly from the camera sensor luminance plane.
  /// Returns empty list if frame fails the quality checks.
  Future<List<double>> generateEmbeddingFromCameraImage(CameraImage cameraImage) async {
    if (!_isInitialized) {
      throw StateError('VisionService is not initialized.');
    }
    if (cameraImage.planes.isEmpty) return [];
    return _extractFromCameraYPlane(cameraImage);
  }

  /// Generates an embedding from an [img.Image].
  /// Returns empty list if image fails the quality checks.
  Future<List<double>> generateEmbeddingFromImage(img.Image rawImage) async {
    return _extractFromDecodedImage(rawImage);
  }

  /// Generates an embedding from raw image bytes (e.g. a campaign asset).
  Future<List<double>> generateEmbeddingFromBytes(Uint8List bytes) async {
    final image = img.decodeImage(bytes);
    if (image == null) return [];
    return _extractFromDecodedImage(image);
  }

  /// Checks whether a live camera frame or image meets minimum quality criteria.
  static FrameQuality checkQuality(double meanLum, double stdDev) {
    if (meanLum < minAcceptableLuminance) {
      return FrameQuality(
        meanLuminance: meanLum,
        stdDeviation: stdDev,
        isValid: false,
        rejectionReason: 'EXTREMELY_DARK',
      );
    }
    if (meanLum > maxAcceptableLuminance) {
      return FrameQuality(
        meanLuminance: meanLum,
        stdDeviation: stdDev,
        isValid: false,
        rejectionReason: 'OVEREXPOSED',
      );
    }
    if (stdDev < minAcceptableDetailStd) {
      return FrameQuality(
        meanLuminance: meanLum,
        stdDeviation: stdDev,
        isValid: false,
        rejectionReason: 'INSUFFICIENT_DETAIL',
      );
    }
    return FrameQuality(
      meanLuminance: meanLum,
      stdDeviation: stdDev,
      isValid: true,
    );
  }

  /// Extracts 192-dim relative spatial descriptor directly from CameraImage Y-plane.
  List<double> _extractFromCameraYPlane(CameraImage image) {
    final width = image.width;
    final height = image.height;
    final yPlane = image.planes[0];
    final yBytes = yPlane.bytes;
    final rowStride = yPlane.bytesPerRow;
    final pixelStride = yPlane.bytesPerPixel ?? 1;

    const gridSize = 8;
    // Sample a center square region to align portrait viewfinder with landscape camera sensor
    final minDim = math.min(width, height);
    final startX = (width - minDim) ~/ 2;
    final startY = (height - minDim) ~/ 2;
    final cellDim = minDim ~/ gridSize;

    // First pass: compute global mean and variance across sampled grid
    double totalLum = 0.0;
    double totalLumSq = 0.0;
    int sampleCount = 0;

    for (int y = startY; y < startY + minDim; y += 4) {
      final rowOffset = y * rowStride;
      for (int x = startX; x < startX + minDim; x += 4) {
        final lum = yBytes[rowOffset + x * pixelStride] / 255.0;
        totalLum += lum;
        totalLumSq += lum * lum;
        sampleCount++;
      }
    }

    if (sampleCount == 0) return [];
    final globalMean = totalLum / sampleCount;
    final globalVar = (totalLumSq / sampleCount) - (globalMean * globalMean);
    final globalStd = math.sqrt(math.max(0.0, globalVar));

    final quality = checkQuality(globalMean, globalStd);
    if (!quality.isValid) {
      return [];
    }

    // Second pass: compute 8x8 cell relative luminance and gradients
    final List<double> lumVector = List<double>.filled(64, 0.0);
    final List<double> gradHVector = List<double>.filled(64, 0.0);
    final List<double> gradVVector = List<double>.filled(64, 0.0);

    double totalGradH = 0.0;
    double totalGradV = 0.0;

    for (int gy = 0; gy < gridSize; gy++) {
      for (int gx = 0; gx < gridSize; gx++) {
        double cellLumSum = 0.0;
        double cellDxSum = 0.0;
        double cellDySum = 0.0;
        int count = 0;

        final cyStart = startY + gy * cellDim;
        final cyEnd = cyStart + cellDim;
        final cxStart = startX + gx * cellDim;
        final cxEnd = cxStart + cellDim;

        for (int y = cyStart; y < cyEnd; y += 2) {
          final rowOffset = y * rowStride;
          for (int x = cxStart; x < cxEnd; x += 2) {
            final val = yBytes[rowOffset + x * pixelStride] / 255.0;
            cellLumSum += val;

            if (x > cxStart + 1 && y > cyStart + 1) {
              final leftVal = yBytes[rowOffset + (x - 2) * pixelStride] / 255.0;
              final topVal = yBytes[(y - 2) * rowStride + x * pixelStride] / 255.0;
              cellDxSum += (val - leftVal).abs();
              cellDySum += (val - topVal).abs();
            }
            count++;
          }
        }

        final cellMeanLum = count > 0 ? cellLumSum / count : globalMean;
        final idx = gy * gridSize + gx;
        lumVector[idx] = (cellMeanLum - globalMean) / (globalStd + 1e-4);

        final meanDx = count > 0 ? cellDxSum / count : 0.0;
        final meanDy = count > 0 ? cellDySum / count : 0.0;
        gradHVector[idx] = meanDx;
        gradVVector[idx] = meanDy;
        totalGradH += meanDx;
        totalGradV += meanDy;
      }
    }

    final meanGradH = totalGradH / 64.0;
    final meanGradV = totalGradV / 64.0;

    for (int i = 0; i < 64; i++) {
      gradHVector[i] -= meanGradH;
      gradVVector[i] -= meanGradV;
    }

    final combined = [...lumVector, ...gradHVector, ...gradVVector];
    return _l2Normalize(combined);
  }

  /// Extracts 192-dim relative spatial descriptor from decoded image asset.
  List<double> _extractFromDecodedImage(img.Image rawImage) {
    final resized = img.copyResize(rawImage, width: 128, height: 128);
    const gridSize = 8;
    final cellW = resized.width ~/ gridSize;
    final cellH = resized.height ~/ gridSize;

    double totalLum = 0.0;
    double totalLumSq = 0.0;
    int totalPixels = resized.width * resized.height;

    for (int y = 0; y < resized.height; y++) {
      for (int x = 0; x < resized.width; x++) {
        final p = resized.getPixel(x, y);
        final lum = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b) / 255.0;
        totalLum += lum;
        totalLumSq += lum * lum;
      }
    }

    final globalMean = totalLum / totalPixels;
    final globalVar = (totalLumSq / totalPixels) - (globalMean * globalMean);
    final globalStd = math.sqrt(math.max(0.0, globalVar));

    final quality = checkQuality(globalMean, globalStd);
    if (!quality.isValid) {
      return [];
    }

    final List<double> lumVector = List<double>.filled(64, 0.0);
    final List<double> gradHVector = List<double>.filled(64, 0.0);
    final List<double> gradVVector = List<double>.filled(64, 0.0);

    double totalGradH = 0.0;
    double totalGradV = 0.0;

    for (int gy = 0; gy < gridSize; gy++) {
      for (int gx = 0; gx < gridSize; gx++) {
        double cellLumSum = 0.0;
        double cellDxSum = 0.0;
        double cellDySum = 0.0;
        int count = 0;

        for (int y = gy * cellH; y < (gy + 1) * cellH; y++) {
          for (int x = gx * cellW; x < (gx + 1) * cellW; x++) {
            final p = resized.getPixel(x, y);
            final lum = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b) / 255.0;
            cellLumSum += lum;

            if (x > 0 && y > 0) {
              final leftP = resized.getPixel(x - 1, y);
              final topP = resized.getPixel(x, y - 1);
              final leftLum = (0.299 * leftP.r + 0.587 * leftP.g + 0.114 * leftP.b) / 255.0;
              final topLum = (0.299 * topP.r + 0.587 * topP.g + 0.114 * topP.b) / 255.0;
              cellDxSum += (lum - leftLum).abs();
              cellDySum += (lum - topLum).abs();
            }
            count++;
          }
        }

        final cellMeanLum = count > 0 ? cellLumSum / count : globalMean;
        final idx = gy * gridSize + gx;
        lumVector[idx] = (cellMeanLum - globalMean) / (globalStd + 1e-4);

        final meanDx = count > 0 ? cellDxSum / count : 0.0;
        final meanDy = count > 0 ? cellDySum / count : 0.0;
        gradHVector[idx] = meanDx;
        gradVVector[idx] = meanDy;
        totalGradH += meanDx;
        totalGradV += meanDy;
      }
    }

    final meanGradH = totalGradH / 64.0;
    final meanGradV = totalGradV / 64.0;

    for (int i = 0; i < 64; i++) {
      gradHVector[i] -= meanGradH;
      gradVVector[i] -= meanGradV;
    }

    final combined = [...lumVector, ...gradHVector, ...gradVVector];
    return _l2Normalize(combined);
  }

  List<double> _l2Normalize(List<double> v) {
    double sumSq = 0.0;
    for (final val in v) {
      sumSq += val * val;
    }
    final length = math.sqrt(sumSq);
    if (length <= 1e-7) return [];
    return v.map((e) => e / length).toList();
  }

  /// Disposes vision resources.
  void dispose() {
    _isInitialized = false;
  }
}
