import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'package:file_selector/file_selector.dart';
import 'package:pinbench_ui/strings.dart';

import '../controller/canvas_controller.dart';
import '../widgets/painters/wire_painter.dart';

class CanvasExporter {
  static Future<bool> exportToPng(CanvasController controller) async {
    final nodes = controller.nodes;
    final wires = controller.wires;

    if (nodes.isEmpty && wires.isEmpty) return false;

    // 1. Calculate bounding box of all elements
    Rect? bounds;
    for (final node in nodes) {
      if (bounds == null) {
        bounds = node.rect;
      } else {
        bounds = bounds.expandToInclude(node.rect);
      }
    }

    for (final wire in wires) {
      final startPos = controller.wiringManager.getPortPosition(wire.start);
      final endPos = controller.wiringManager.getPortPosition(wire.end);
      final points = [?startPos, ...wire.bendPoints, ?endPos];
      for (final p in points) {
        final r = Rect.fromCircle(center: p, radius: 10);
        if (bounds == null) {
          bounds = r;
        } else {
          bounds = bounds.expandToInclude(r);
        }
      }
    }

    if (bounds == null) return false;

    // Add padding
    bounds = bounds.inflate(50);

    const exportScale = 4.0; // 4x resolution for high-quality export

    // 2. Setup PictureRecorder
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Apply high-res scale to the entire canvas
    canvas.scale(exportScale, exportScale);

    // 3. Paint Background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, bounds.width, bounds.height),
      Paint()..color = const Color(0xFF1E1E1E), // Dark theme background
    );

    // Translate to bounds origin
    canvas.translate(-bounds.left, -bounds.top);

    // 4. Paint Wires
    final wirePainter = WirePainter(nodes: nodes, wires: wires);
    // Ignore bounds size, wire painter paints to absolute coordinates
    wirePainter.paint(canvas, const Size(10000, 10000));

    // 5. Paint Nodes
    for (final node in nodes) {
      canvas.save();

      final left = node.pivotOffset.dx - node.baseSize.width / 2;
      final top = node.pivotOffset.dy;

      canvas.translate(node.position.dx + left, node.position.dy + top);

      // Rotate around top center
      final rotateCenter = Offset(node.baseSize.width / 2, 0);
      canvas.translate(rotateCenter.dx, rotateCenter.dy);
      canvas.rotate(node.rotationAngle);
      canvas.translate(-rotateCenter.dx, -rotateCenter.dy);

      // Scale (flip) around center
      final scaleCenter = Offset(node.baseSize.width / 2, node.baseSize.height / 2);
      canvas.translate(scaleCenter.dx, scaleCenter.dy);
      canvas.scale(node.flipHorizontal ? -1.0 : 1.0, node.flipVertical ? -1.0 : 1.0);
      canvas.translate(-scaleCenter.dx, -scaleCenter.dy);

      final painter = node.part.getPainter(properties: node.properties);
      if (painter != null) {
        painter.paintComponent(canvas, node.baseSize);
      }

      canvas.restore();
    }

    // 6. Finalize image
    final picture = recorder.endRecording();
    final imageWidth = (bounds.width * exportScale).toInt();
    final imageHeight = (bounds.height * exportScale).toInt();
    final image = await picture.toImage(imageWidth, imageHeight);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return false;
    final pngBytes = byteData.buffer.asUint8List();

    // 7. Prompt User to Save
    const fileName = 'circuit_export.png';
    final result = await getSaveLocation(
      suggestedName: fileName,
      acceptedTypeGroups: [
        const XTypeGroup(label: AppStrings.pngFileTypeGroupLabel, extensions: ['png']),
      ],
    );

    if (result != null) {
      try {
        final xFile = XFile.fromData(pngBytes, mimeType: 'image/png', name: fileName);
        await xFile.saveTo(result.path);
        return true;
      } catch (e) {
        return false;
      }
    }
    return false;
  }
}
