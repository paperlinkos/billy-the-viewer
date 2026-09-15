// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:image/image.dart' as img;

void main() {
  final referenceFile = File('assets/campaigns/demo_ad.jpg');
  if (!referenceFile.existsSync()) {
    print('Error: Reference advertisement ${referenceFile.path} not found.');
    exit(1);
  }

  final outDir = Directory('assets/recognition_benchmark');
  if (!outDir.existsSync()) {
    outDir.createSync(recursive: true);
  }

  final refBytes = referenceFile.readAsBytesSync();
  final baseImage = img.decodeImage(refBytes)!;

  print('Loaded reference ad: ${baseImage.width}x${baseImage.height}');

  // 1. Distance (scale down and place in canvas)
  final distanceFar = img.Image(width: 800, height: 800);
  img.fill(distanceFar, color: img.ColorRgb8(180, 180, 180)); // Neutral room background
  final scaled = img.copyResize(baseImage, width: 320, height: 320);
  img.compositeImage(distanceFar, scaled, dstX: 240, dstY: 240);
  File('${outDir.path}/match_distance_far.jpg')
      .writeAsBytesSync(img.encodeJpg(distanceFar, quality: 85));
  print('Generated match_distance_far.jpg');

  // 2. Rotation (15 degrees)
  final rotated = img.copyRotate(baseImage, angle: 15);
  File('${outDir.path}/match_rotation_15deg.jpg')
      .writeAsBytesSync(img.encodeJpg(rotated, quality: 85));
  print('Generated match_rotation_15deg.jpg');

  // 3. Low Lighting (dim ambient)
  final lowLight = img.copyResize(baseImage, width: 640, height: 640);
  img.adjustColor(lowLight, brightness: 0.4, contrast: 0.85);
  File('${outDir.path}/match_low_light.jpg')
      .writeAsBytesSync(img.encodeJpg(lowLight, quality: 85));
  print('Generated match_low_light.jpg');

  // 4. Bright Glare (overexposed light flare)
  final brightGlare = img.copyResize(baseImage, width: 640, height: 640);
  img.adjustColor(brightGlare, brightness: 1.35, contrast: 0.9);
  // Add a bright radial glare spot
  for (int y = 0; y < 200; y++) {
    for (int x = 0; x < 200; x++) {
      final dist = sqrt(x * x + y * y);
      if (dist < 180) {
        final factor = (1 - dist / 180) * 0.5;
        final p = brightGlare.getPixel(x + 100, y + 100);
        brightGlare.setPixelRgb(
          x + 100,
          y + 100,
          min(255, (p.r + 255 * factor).toInt()),
          min(255, (p.g + 255 * factor).toInt()),
          min(255, (p.b + 255 * factor).toInt()),
        );
      }
    }
  }
  File('${outDir.path}/match_bright_glare.jpg')
      .writeAsBytesSync(img.encodeJpg(brightGlare, quality: 85));
  print('Generated match_bright_glare.jpg');

  // 5. Motion Blur
  final motionBlur = img.copyResize(baseImage, width: 640, height: 640);
  img.gaussianBlur(motionBlur, radius: 8);
  File('${outDir.path}/match_motion_blur.jpg')
      .writeAsBytesSync(img.encodeJpg(motionBlur, quality: 85));
  print('Generated match_motion_blur.jpg');

  // 6. Partial Visibility (partial crop & occlusion)
  final partial = img.Image(width: 640, height: 640);
  img.fill(partial, color: img.ColorRgb8(40, 40, 40));
  final croppedAd = img.copyCrop(baseImage, x: 0, y: 0, width: (baseImage.width * 0.65).toInt(), height: baseImage.height);
  final resizedCropped = img.copyResize(croppedAd, width: 400, height: 600);
  img.compositeImage(partial, resizedCropped, dstX: 20, dstY: 20);
  File('${outDir.path}/match_partial_occlusion.jpg')
      .writeAsBytesSync(img.encodeJpg(partial, quality: 85));
  print('Generated match_partial_occlusion.jpg');

  // 7. Screen Display (simulated laptop/phone screen frame with status bar/browser frame)
  final screenDisplay = img.Image(width: 800, height: 600);
  img.fill(screenDisplay, color: img.ColorRgb8(30, 30, 32)); // Dark laptop bezel
  // Inner screen area
  final innerAd = img.copyResize(baseImage, width: 680, height: 480);
  img.compositeImage(screenDisplay, innerAd, dstX: 60, dstY: 60);
  File('${outDir.path}/match_screen_display.jpg')
      .writeAsBytesSync(img.encodeJpg(screenDisplay, quality: 85));
  print('Generated match_screen_display.jpg');

  // 8. Printed Paper (matte texture / slight warm skew)
  final printedPaper = img.copyResize(baseImage, width: 640, height: 640);
  img.adjustColor(printedPaper, brightness: 0.95, gamma: 1.05);
  // Add subtle paper grain
  final random = Random(42);
  for (int y = 0; y < printedPaper.height; y += 2) {
    for (int x = 0; x < printedPaper.width; x += 2) {
      final noise = random.nextInt(15) - 7;
      final p = printedPaper.getPixel(x, y);
      printedPaper.setPixelRgb(
        x,
        y,
        (p.r + noise).clamp(0, 255).toInt(),
        (p.g + noise).clamp(0, 255).toInt(),
        (p.b + noise).clamp(0, 255).toInt(),
      );
    }
  }
  File('${outDir.path}/match_printed_paper.jpg')
      .writeAsBytesSync(img.encodeJpg(printedPaper, quality: 85));
  print('Generated match_printed_paper.jpg');

  // 9. Negative: Blank Wall (off-white stucco wall texture)
  final blankWall = img.Image(width: 640, height: 640);
  img.fill(blankWall, color: img.ColorRgb8(220, 218, 212));
  final wallRand = Random(123);
  for (int y = 0; y < 640; y++) {
    for (int x = 0; x < 640; x++) {
      final n = wallRand.nextInt(10) - 5;
      blankWall.setPixelRgb(x, y, 220 + n, 218 + n, 212 + n);
    }
  }
  File('${outDir.path}/nomatch_blank_wall.jpg')
      .writeAsBytesSync(img.encodeJpg(blankWall, quality: 85));
  print('Generated nomatch_blank_wall.jpg');

  // 10. Negative: Wood Desk (brown striped wooden surface)
  final woodDesk = img.Image(width: 640, height: 640);
  for (int y = 0; y < 640; y++) {
    final grain = (sin(y / 15.0) * 15).toInt();
    for (int x = 0; x < 640; x++) {
      woodDesk.setPixelRgb(x, y, 139 + grain, 90 + grain ~/ 2, 43 + grain ~/ 3);
    }
  }
  File('${outDir.path}/nomatch_wood_desk.jpg')
      .writeAsBytesSync(img.encodeJpg(woodDesk, quality: 85));
  print('Generated nomatch_wood_desk.jpg');

  // 11. Negative: Tile Floor (checkered indoor floor)
  final tileFloor = img.Image(width: 640, height: 640);
  for (int y = 0; y < 640; y++) {
    for (int x = 0; x < 640; x++) {
      final tileX = (x ~/ 80) % 2;
      final tileY = (y ~/ 80) % 2;
      final isWhite = (tileX ^ tileY) == 0;
      final baseC = isWhite ? 210 : 80;
      tileFloor.setPixelRgb(x, y, baseC, baseC, baseC);
    }
  }
  File('${outDir.path}/nomatch_tile_floor.jpg')
      .writeAsBytesSync(img.encodeJpg(tileFloor, quality: 85));
  print('Generated nomatch_tile_floor.jpg');

  // 12. Negative: Other Advertisement (unrelated colorful ad)
  final otherAd = img.Image(width: 640, height: 640);
  img.fill(otherAd, color: img.ColorRgb8(240, 80, 40)); // Vibrant orange
  // Add blue circle and bold elements
  img.fillCircle(otherAd, x: 320, y: 320, radius: 180, color: img.ColorRgb8(30, 140, 240));
  img.fillRect(otherAd, x1: 100, y1: 500, x2: 540, y2: 580, color: img.ColorRgb8(255, 230, 50));
  File('${outDir.path}/nomatch_other_ad.jpg')
      .writeAsBytesSync(img.encodeJpg(otherAd, quality: 85));
  print('Generated nomatch_other_ad.jpg');

  // 13. Manifest
  final manifest = {
    "reference": "assets/campaigns/demo_ad.jpg",
    "threshold": 0.65,
    "tests": [
      {
        "filename": "match_distance_far.jpg",
        "expected": "TRUE MATCH",
        "variation": "Distance variation (scaled 40% in room background)"
      },
      {
        "filename": "match_rotation_15deg.jpg",
        "expected": "TRUE MATCH",
        "variation": "Slight rotation (15 degrees)"
      },
      {
        "filename": "match_low_light.jpg",
        "expected": "TRUE MATCH",
        "variation": "Low lighting (dim ambient environment)"
      },
      {
        "filename": "match_bright_glare.jpg",
        "expected": "TRUE MATCH",
        "variation": "Overexposed bright lighting / glare flare"
      },
      {
        "filename": "match_motion_blur.jpg",
        "expected": "TRUE MATCH",
        "variation": "Motion blur / rapid phone movement"
      },
      {
        "filename": "match_partial_occlusion.jpg",
        "expected": "TRUE MATCH",
        "variation": "Partial visibility (65% crop with occlusion)"
      },
      {
        "filename": "match_screen_display.jpg",
        "expected": "TRUE MATCH",
        "variation": "Displayed on phone / laptop screen frame"
      },
      {
        "filename": "match_printed_paper.jpg",
        "expected": "TRUE MATCH",
        "variation": "Printed on matte paper with paper texture"
      },
      {
        "filename": "nomatch_blank_wall.jpg",
        "expected": "FALSE MATCH",
        "variation": "Unrelated plain stucco wall"
      },
      {
        "filename": "nomatch_wood_desk.jpg",
        "expected": "FALSE MATCH",
        "variation": "Unrelated wooden desk surface"
      },
      {
        "filename": "nomatch_tile_floor.jpg",
        "expected": "FALSE MATCH",
        "variation": "Unrelated checkered floor tiles"
      },
      {
        "filename": "nomatch_other_ad.jpg",
        "expected": "FALSE MATCH",
        "variation": "Unrelated advertisement creative (different branding)"
      }
    ]
  };

  File('${outDir.path}/benchmark_manifest.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(manifest),
  );
  print('Wrote benchmark_manifest.json with 12 benchmark test cases.');
}
