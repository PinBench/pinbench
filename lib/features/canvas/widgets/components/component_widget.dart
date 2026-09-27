import 'package:flutter/widgets.dart';

import 'package:flutter_svg/flutter_svg.dart';
import 'package:pinbench_parts/part_registry.dart';
import 'package:pinbench_parts/models/breadboard_state.dart';
import 'package:pinbench_parts/painters/breadboard_painter/breadboard_painter.dart';
import 'package:pinbench_parts/painting/dsl_component_painter.dart';
import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench_ui/theme/theme.dart';

class ComponentWidget extends StatelessWidget {
  final PartModel part;
  final Offset? hoveredLocalPosition;
  final BreadboardHoverState? breadboardHover;
  final Map<String, dynamic>? properties;
  final bool isOutline;
  final Size? customSize;

  const ComponentWidget({
    super.key,
    required this.part,
    this.hoveredLocalPosition,
    this.breadboardHover,
    this.properties,
    this.isOutline = false,
    this.customSize,
  });

  // Cache default property maps by definition ID to avoid Map rebuilds.
  static final _defaultPropsCache = <String, Map<String, dynamic>>{};
  static final _svgThemeCache = <String?, SvgTheme>{};
  static final _colorCache = <String, Color?>{};

  Map<String, dynamic> _buildMergedProps(String definitionId) {
    final def = PartRegistry.getPart(definitionId)!;
    return _defaultPropsCache.putIfAbsent(
      definitionId,
      () => Map<String, dynamic>.from(def.properties.map((k, v) => MapEntry(k, v.defaultValue))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final actualSize = customSize ?? part.size;

    if (part.definitionId != null) {
      final def = PartRegistry.getPart(part.definitionId!);
      if (def != null) {
        if (def.visual.shapes.isNotEmpty) {
          return CustomPaint(
            size: actualSize,
            painter: DSLComponentPainter(
              definition: def,
              properties: properties,
              isOutline: isOutline,
            ),
          );
        } else if (def.visual.svgPath != null) {
          // Evaluate dynamic variables in the SVG path (e.g., assets/led_\${isOn}.svg)
          var finalSvgPath = def.visual.svgPath!;
          final mergedProps = Map<String, dynamic>.from(_buildMergedProps(def.id));
          if (properties != null) {
            mergedProps.addAll(properties!);
          }

          if (isOutline && mergedProps.containsKey('isOn')) {
            mergedProps[ComponentProps.isOn] = false;
          }

          for (final key in mergedProps.keys) {
            finalSvgPath = finalSvgPath.replaceAll('\${$key}', mergedProps[key].toString());
          }

          Color? filterColor;
          final colorKey = properties?[ComponentProps.color]?.toString();
          if (colorKey != null) {
            filterColor = _colorCache.putIfAbsent(
              '${colorKey}_${finalSvgPath.contains('false')}',
              () => _getColorFromString(colorKey, dark: finalSvgPath.contains('false')),
            );
          }

          final theme = colorKey != null
              ? _svgThemeCache.putIfAbsent(colorKey, () => SvgTheme(currentColor: filterColor!))
              : const SvgTheme();

          final Widget svgWidget = SizedBox(
            width: actualSize.width,
            height: actualSize.height,
            child: OverflowBox(
              maxWidth: double.infinity,
              maxHeight: double.infinity,
              child: Transform.scale(
                scaleX: actualSize.width / part.size.width,
                scaleY: actualSize.height / part.size.height,
                child: SvgPicture.asset(finalSvgPath, theme: theme),
              ),
            ),
          );

          return svgWidget;
        }
      }
    }

    final painter = part.getPainter(isOutline: isOutline, properties: properties);

    if (painter == null) {
      return SizedBox(width: actualSize.width, height: actualSize.height);
    }

    if (painter is BreadboardPainter) {
      return CustomPaint(
        size: actualSize,
        painter: BreadboardPainter(config: painter.config, hoverState: breadboardHover),
      );
    }

    return CustomPaint(size: actualSize, painter: painter);
  }

  Color? _getColorFromString(String? colorString, {bool dark = false}) {
    if (colorString == null) return null;
    switch (colorString.toLowerCase()) {
      case 'green':
        return dark ? const Color(0xFF006600) : AppPalette.green;
      case 'blue':
        return dark ? const Color(0xFF000099) : AppPalette.blue;
      case 'yellow':
        return dark ? const Color(0xFF999900) : AppPalette.yellow;
      case 'cyan':
        return dark ? const Color(0xFF009999) : AppPalette.cyan;
      case 'pink':
        return dark ? const Color(0xFF99004D) : AppPalette.pink;
      case 'orange':
        return dark ? const Color(0xFF994C00) : AppPalette.orange;
      case 'red':
        return dark ? const Color(0xFF990000) : AppPalette.red;
      default:
        return null;
    }
  }
}
