import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Reports its child's height after each layout that changes it.
class MeasuredHeight extends SingleChildRenderObjectWidget {
  const MeasuredHeight({
    required this.onHeight,
    required super.child,
    super.key,
  });

  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderMeasuredHeight(onHeight);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderMeasuredHeight renderObject,
  ) {
    renderObject.onHeight = onHeight;
  }
}

class RenderMeasuredHeight extends RenderProxyBox {
  RenderMeasuredHeight(this.onHeight);

  ValueChanged<double> onHeight;
  double? _reported;

  @override
  void performLayout() {
    super.performLayout();
    final height = size.height;
    if (height != _reported) {
      _reported = height;
      WidgetsBinding.instance.addPostFrameCallback((_) => onHeight(height));
    }
  }
}
