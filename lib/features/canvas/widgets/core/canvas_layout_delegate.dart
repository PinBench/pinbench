import 'package:flutter/widgets.dart';

import 'package:collection/collection.dart';
import 'package:pinbench_parts/models/component_instance.dart';

class InfiniteCanvasNodesDelegate(final List<ComponentInstance> nodes)
    extends MultiChildLayoutDelegate {
  @override
  void performLayout(Size size) {
    for (final widget in nodes) {
      layoutChild(widget, BoxConstraints.tight(widget.currentSize));
      positionChild(widget, widget.position);
    }
  }

  @override
  bool shouldRelayout(InfiniteCanvasNodesDelegate oldDelegate) =>
      !const ListEquality<ComponentInstance>().equals(nodes, oldDelegate.nodes);
}
