import 'package:flutter/material.dart';
import 'package:billy_the_viewer/app/theme.dart';

/// Editorial primary button adhering to Billy's minimal black + white + line identity.
/// Features clean interactive states, zero excessive border radius, crisp typography.
class BillyButton extends StatefulWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isOutlined;
  final double? width;
  final double height;

  const BillyButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isOutlined = false,
    this.width,
    this.height = 58.0,
  });

  @override
  State<BillyButton> createState() => _BillyButtonState();
}

class _BillyButtonState extends State<BillyButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final bool isEnabled = widget.onPressed != null;

    final Color bgColor = widget.isOutlined
        ? (_isPressed ? BillyTheme.grayExtraLight : BillyTheme.white)
        : (_isPressed ? BillyTheme.grayDark : BillyTheme.black);

    final Color textColor = widget.isOutlined
        ? BillyTheme.black
        : BillyTheme.white;

    final Color borderColor = isEnabled ? BillyTheme.black : BillyTheme.grayLight;

    return Semantics(
      button: true,
      enabled: isEnabled,
      label: widget.text,
      child: GestureDetector(
        onTapDown: isEnabled ? (_) => setState(() => _isPressed = true) : null,
        onTapUp: isEnabled ? (_) => setState(() => _isPressed = false) : null,
        onTapCancel: isEnabled ? () => setState(() => _isPressed = false) : null,
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          width: widget.width ?? double.infinity,
          height: widget.height,
          decoration: BoxDecoration(
            color: isEnabled ? bgColor : BillyTheme.grayLight,
            border: Border.all(
              color: borderColor,
              width: BillyTheme.borderWidthMedium,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            widget.text,
            style: BillyTheme.buttonText.copyWith(
              color: isEnabled ? textColor : BillyTheme.grayMedium,
            ),
          ),
        ),
      ),
    );
  }
}
