import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// Represents the status of the camera initialization and permission lifecycle.
enum CameraStateStatus {
  initial,
  checkingPermission,
  permissionDenied,
  permissionPermanentlyDenied,
  initializing,
  ready,
  error,
}

/// Service dedicated strictly to device camera initialization, lifecycle,
/// permission checks, and frame streaming.
///
/// Designed to be decoupled from any computer vision or matching logic.
class CameraService {
  CameraController? _controller;
  CameraStateStatus _status = CameraStateStatus.initial;
  String? _errorMessage;
  bool _isStreamingImages = false;

  CameraController? get controller => _controller;
  CameraStateStatus get status => _status;
  String? get errorMessage => _errorMessage;
  bool get isReady =>
      _status == CameraStateStatus.ready &&
      _controller != null &&
      _controller!.value.isInitialized;
  bool get isStreamingImages => _isStreamingImages;

  /// Initializes the camera, checking permissions first.
  Future<CameraStateStatus> initialize() async {
    _status = CameraStateStatus.checkingPermission;
    _errorMessage = null;

    try {
      // 1. Check and request camera permission
      final permissionStatus = await Permission.camera.request();

      if (permissionStatus.isPermanentlyDenied) {
        _status = CameraStateStatus.permissionPermanentlyDenied;
        _errorMessage = 'Camera permission is permanently denied. Please enable it in Settings.';
        return _status;
      }

      if (!permissionStatus.isGranted && !permissionStatus.isLimited) {
        _status = CameraStateStatus.permissionDenied;
        _errorMessage = 'Camera permission was denied.';
        return _status;
      }

      // 2. Discover available cameras
      _status = CameraStateStatus.initializing;
      final cameras = await availableCameras();

      if (cameras.isEmpty) {
        _status = CameraStateStatus.error;
        _errorMessage = 'No available camera found on this device.';
        return _status;
      }

      // 3. Find primary rear camera (or fallback to first camera available)
      final rearCamera = cameras.firstWhere(
        (cam) => cam.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      // Dispose existing controller if present before creating a new one
      await dispose();

      // On iOS use bgra8888; on Android use yuv420
      final imageFormat = Platform.isIOS ? ImageFormatGroup.bgra8888 : ImageFormatGroup.yuv420;

      _controller = CameraController(
        rearCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: imageFormat,
      );

      await _controller!.initialize();
      _status = CameraStateStatus.ready;
      return _status;
    } on CameraException catch (e) {
      debugPrint('CameraException: ${e.code}, ${e.description}');
      _status = CameraStateStatus.error;
      _errorMessage = e.description ?? 'Camera initialization failed (${e.code}).';
      return _status;
    } catch (e) {
      debugPrint('General camera error: $e');
      _status = CameraStateStatus.error;
      _errorMessage = 'Failed to initialize camera: $e';
      return _status;
    }
  }

  /// Starts listening to the live camera image stream.
  Future<void> startImageStream(Function(CameraImage image) onAvailable) async {
    if (_controller != null && _controller!.value.isInitialized && !_isStreamingImages) {
      try {
        await _controller!.startImageStream(onAvailable);
        _isStreamingImages = true;
      } catch (e) {
        debugPrint('Error starting camera image stream: $e');
      }
    }
  }

  /// Stops listening to the live camera image stream.
  Future<void> stopImageStream() async {
    if (_controller != null && _controller!.value.isInitialized && _isStreamingImages) {
      try {
        await _controller!.stopImageStream();
      } catch (e) {
        debugPrint('Error stopping camera image stream: $e');
      } finally {
        _isStreamingImages = false;
      }
    }
  }

  /// Opens the system app settings to allow the user to enable permissions.
  Future<bool> openSettings() async {
    return await openAppSettings();
  }

  /// Disposes camera resources cleanly.
  Future<void> dispose() async {
    try {
      if (_isStreamingImages) {
        await stopImageStream();
      }
      await _controller?.dispose();
    } catch (e) {
      debugPrint('Error disposing CameraController: $e');
    } finally {
      _controller = null;
      _status = CameraStateStatus.initial;
      _errorMessage = null;
      _isStreamingImages = false;
    }
  }
}
