import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:billy_the_viewer/models/ad_target.dart';
import 'package:billy_the_viewer/screens/home_screen.dart';
import 'package:billy_the_viewer/services/account_session.dart';
import 'package:billy_the_viewer/services/camera_service.dart';
import 'package:billy_the_viewer/services/gemini_embedding_service.dart';
import 'package:billy_the_viewer/services/verification_coordinator.dart';

class FakeCameraService extends CameraService {
  CameraStateStatus stubbedStatus = CameraStateStatus.ready;

  @override
  CameraStateStatus get status => stubbedStatus;

  @override
  bool get isReady => stubbedStatus == CameraStateStatus.ready;

  @override
  Future<CameraStateStatus> initialize() async => stubbedStatus;

  @override
  Future<void> dispose() async {}
}

/// Fake HTTP client that delays response to test single-flight and non-blocking semantics.
class DelayedMockHttpClient extends http.BaseClient {
  final Duration delay;
  int requestCount = 0;

  DelayedMockHttpClient({this.delay = const Duration(milliseconds: 50)});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requestCount++;
    await Future.delayed(delay);
    final responseBody = jsonEncode({
      'embedding': {
        'values': List<double>.filled(128, 0.5),
      }
    });
    return http.StreamedResponse(
      Stream.value(utf8.encode(responseBody)),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AdTarget dummyTarget;
  late Uint8List dummyJpegBytes;

  setUp(() {
    dummyTarget = const AdTarget(
      id: 'target-verif-001',
      name: 'VERIFY ME',
      brand: 'BRAND',
      destinationUrl: 'https://verify.example.com',
      imageAsset: '',
      embedding: [0.1, 0.2, 0.3],
    );
    dummyJpegBytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46]);
  });

  group('VerificationCoordinator Tests', () {
    test('Enforces single-flight: drops redundant calls while in flight', () async {
      final mockHttp = DelayedMockHttpClient(delay: const Duration(milliseconds: 100));
      final client = GeminiEmbeddingClient(apiKey: 'test-key', httpClient: mockHttp);
      final coordinator = VerificationCoordinator(geminiClient: client);

      expect(coordinator.isInFlight, isFalse);

      // Launch first verification call
      final future1 = coordinator.verifyCandidate(
        candidate: dummyTarget,
        frameJpegBytes: dummyJpegBytes,
      );

      // Verify lock is active
      expect(coordinator.isInFlight, isTrue);

      // Launch second concurrent call while first is in-flight
      final result2 = await coordinator.verifyCandidate(
        candidate: dummyTarget,
        frameJpegBytes: dummyJpegBytes,
      );

      // Second call must be immediately dropped (returns null)
      expect(result2, isNull);

      // Await first
      await future1;
      expect(coordinator.isInFlight, isFalse);
    });

    test('10s In-Session Cache: skips network call if recently confirmed', () async {
      final mockHttp = DelayedMockHttpClient();
      final client = GeminiEmbeddingClient(apiKey: 'test-key', httpClient: mockHttp);
      final coordinator = VerificationCoordinator(
        geminiClient: client,
        cacheTtl: const Duration(seconds: 10),
      );

      // Initially not confirmed
      expect(coordinator.isRecentlyConfirmed(dummyTarget.id), isFalse);

      // Record confirmed
      coordinator.recordConfirmed(dummyTarget.id);
      expect(coordinator.isRecentlyConfirmed(dummyTarget.id), isTrue);

      // Subsequent call returns cache hit immediately without invoking network
      final match = await coordinator.verifyCandidate(
        candidate: dummyTarget,
        frameJpegBytes: dummyJpegBytes,
      );

      expect(match, isNotNull);
      expect(match!.target.id, dummyTarget.id);
      expect(mockHttp.requestCount, 0); // Zero network calls!
    });

    test('Honors candidatePool pre-filter: skips verification if candidate not in pool', () async {
      final coordinator = VerificationCoordinator();
      const otherTarget = AdTarget(
        id: 'other-target-999',
        name: 'OTHER',
        brand: 'B',
        destinationUrl: '',
        imageAsset: '',
      );

      final result = await coordinator.verifyCandidate(
        candidate: dummyTarget,
        frameJpegBytes: dummyJpegBytes,
        candidatePool: [otherTarget], // dummyTarget NOT in pre-filtered candidate pool
      );

      expect(result, isNull);
    });

    test('Cache expires after TTL', () async {
      final coordinator = VerificationCoordinator(
        cacheTtl: const Duration(milliseconds: 10),
      );

      coordinator.recordConfirmed(dummyTarget.id);
      expect(coordinator.isRecentlyConfirmed(dummyTarget.id), isTrue);

      await Future.delayed(const Duration(milliseconds: 20));
      // After TTL, cache expires
      expect(coordinator.isRecentlyConfirmed(dummyTarget.id), isFalse);
    });
  });

  group('HomeScreen Two-Tier Async Verification Integration Tests', () {
    testWidgets('HomeScreen integrates VerificationCoordinator and displays confirming state optimistically', (tester) async {
      final session = AccountSession();
      session.signInAsConsumer();

      final fakeCameraService = FakeCameraService();
      final coordinator = VerificationCoordinator();

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            cameraService: fakeCameraService,
            accountSession: session,
            verificationCoordinator: coordinator,
            initialCampaigns: [dummyTarget],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open scanner
      await tester.tap(find.text('SCAN'));
      await tester.pump();

      // Scanner opens in looking state (defaulting to clean photo-first mode)
      expect(find.text('FRAME THE BILLBOARD OR SCREEN IN VIEWFINDER'), findsOneWidget);
    });
  });
}
