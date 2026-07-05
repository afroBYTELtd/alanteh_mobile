import 'package:flutter/material.dart';

abstract final class AsmColors {
  static const Color brandGreen = Color(0xFF275C2E);
  static const Color brandBlack = Color(0xFF000000);
  static const Color brandWhite = Color(0xFFFFFFFF);

  static const Color green = brandGreen;
  static const Color solarYellow = Color(0xFFFFC928);

  static const Color passengerScaffold = Color(0xFFFAFBF8);
  static const Color driverScaffold = brandBlack;
  static const Color driverPanelMuted = Color(0xFF111A14);
  static const Color driverTextSecondary = Color(0xFFD6DED8);
  static const Color driverWarningSurface = Color(0xFFFFD968);
}

abstract final class AsmSpacing {
  static const double space4 = 4;
  static const double space8 = 8;
  static const double space12 = 12;
  static const double space16 = 16;
  static const double space20 = 20;
  static const double space24 = 24;
  static const double space32 = 32;
}

abstract final class AsmRadii {
  static const double radius6 = 6;
  static const double radius8 = 8;
}

abstract final class AsmThemes {
  static ThemeData get passenger {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: AsmColors.brandGreen,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: AsmColors.passengerScaffold,
      useMaterial3: true,
    );
  }

  static ThemeData get driver {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: AsmColors.brandGreen,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: AsmColors.driverScaffold,
      useMaterial3: true,
    );
  }
}

class AsmDemoPlaceholder extends StatelessWidget {
  const AsmDemoPlaceholder({
    required this.icon,
    required this.title,
    required this.message,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AsmSpacing.space24),
          child: Semantics(
            container: true,
            label: 'Local demo. $title. $message',
            child: ExcludeSemantics(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(AsmRadii.radius8),
                    ),
                    child: Icon(
                      icon,
                      color: colors.onPrimaryContainer,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: AsmSpacing.space20),
                  const AsmLocalDemoBadge(
                    padding: EdgeInsets.symmetric(
                      horizontal: AsmSpacing.space12,
                      vertical: AsmSpacing.space8,
                    ),
                    textStyle: TextStyle(fontSize: 11),
                  ),
                  const SizedBox(height: AsmSpacing.space16),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AsmSpacing.space8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Text(
                      message,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: colors.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AsmLocalDemoBadge extends StatelessWidget {
  const AsmLocalDemoBadge({
    this.text = 'LOCAL DEMO',
    this.backgroundColor,
    this.foregroundColor,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AsmSpacing.space8,
      vertical: AsmSpacing.space8,
    ),
    this.semanticLabel,
    this.textStyle,
    super.key,
  });

  final String text;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final EdgeInsetsGeometry padding;
  final String? semanticLabel;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final effectiveForeground = foregroundColor ?? colors.onPrimaryContainer;
    final effectiveStyle = const TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w800,
    ).merge(textStyle).copyWith(color: effectiveForeground);

    return Semantics(
      container: true,
      label: semanticLabel ?? text,
      child: ExcludeSemantics(
        child: Container(
          padding: padding,
          constraints: const BoxConstraints(maxWidth: 180),
          decoration: BoxDecoration(
            color: backgroundColor ?? colors.primaryContainer,
            borderRadius: BorderRadius.circular(AsmRadii.radius6),
          ),
          child: Text(text, textAlign: TextAlign.center, style: effectiveStyle),
        ),
      ),
    );
  }
}

class AsmAppBrandMark extends StatelessWidget {
  const AsmAppBrandMark({
    this.icon = Icons.wb_sunny_outlined,
    this.size = 40,
    this.backgroundColor,
    this.iconColor = Colors.white,
    this.borderRadius = AsmRadii.radius8,
    super.key,
  });

  final IconData icon;
  final double size;
  final Color? backgroundColor;
  final Color iconColor;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor ?? colors.primary,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Icon(icon, color: iconColor),
    );
  }
}

class AsmScreenHeader extends StatelessWidget {
  const AsmScreenHeader({
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.titleStyle,
    this.subtitleStyle,
    this.titleMaxLines = 2,
    this.subtitleMaxLines = 2,
    this.spacing = AsmSpacing.space12,
    this.compact = false,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final TextStyle? titleStyle;
  final TextStyle? subtitleStyle;
  final int? titleMaxLines;
  final int? subtitleMaxLines;
  final double spacing;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final effectiveTitleStyle =
        titleStyle ??
        textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800);
    final effectiveSubtitleStyle =
        subtitleStyle ??
        textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant);

    final textContent = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: titleMaxLines,
          overflow: TextOverflow.ellipsis,
          style: effectiveTitleStyle,
        ),
        if (subtitle != null) ...[
          SizedBox(height: compact ? 0 : AsmSpacing.space4),
          Text(
            subtitle!,
            maxLines: subtitleMaxLines,
            overflow: TextOverflow.ellipsis,
            style: effectiveSubtitleStyle,
          ),
        ],
      ],
    );

    return Row(
      children: [
        if (leading != null) ...[leading!, SizedBox(width: spacing)],
        Expanded(child: textContent),
        if (trailing != null) ...[SizedBox(width: spacing), trailing!],
      ],
    );
  }
}

class AsmSectionLabel extends StatelessWidget {
  const AsmSectionLabel({
    required this.text,
    this.helperText,
    this.icon,
    this.compact = false,
    this.spacing = AsmSpacing.space8,
    this.textSpacing = AsmSpacing.space4,
    this.iconColor,
    this.textStyle,
    this.helperStyle,
    this.textMaxLines = 2,
    this.helperMaxLines = 2,
    this.textAlign = TextAlign.start,
    this.crossAxisAlignment = CrossAxisAlignment.start,
    super.key,
  });

  final String text;
  final String? helperText;
  final IconData? icon;
  final bool compact;
  final double spacing;
  final double textSpacing;
  final Color? iconColor;
  final TextStyle? textStyle;
  final TextStyle? helperStyle;
  final int? textMaxLines;
  final int? helperMaxLines;
  final TextAlign textAlign;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final effectiveTextStyle =
        textStyle ??
        textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700);
    final effectiveHelperStyle =
        helperStyle ??
        textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant);
    final hasHelper = helperText != null && helperText!.isNotEmpty;
    final textContent = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: crossAxisAlignment,
      children: [
        Text(
          text,
          maxLines: textMaxLines,
          overflow: TextOverflow.ellipsis,
          textAlign: textAlign,
          style: effectiveTextStyle,
        ),
        if (hasHelper) ...[
          SizedBox(height: compact ? 0 : textSpacing),
          Text(
            helperText!,
            maxLines: helperMaxLines,
            overflow: TextOverflow.ellipsis,
            textAlign: textAlign,
            style: effectiveHelperStyle,
          ),
        ],
      ],
    );

    if (icon == null) {
      return textContent;
    }

    return Row(
      mainAxisSize: MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: iconColor ?? colors.primary),
        SizedBox(width: spacing),
        Flexible(child: textContent),
      ],
    );
  }
}

class AsmScreenSurface extends StatelessWidget {
  const AsmScreenSurface({
    required this.child,
    this.padding = const EdgeInsets.all(AsmSpacing.space16),
    this.scrollable = false,
    this.safeArea = true,
    this.expandToViewport = false,
    this.backgroundColor,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool scrollable;
  final bool safeArea;
  final bool expandToViewport;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    Widget content = scrollable
        ? _ScrollableScreenSurface(
            padding: padding,
            expandToViewport: expandToViewport,
            child: child,
          )
        : Padding(padding: padding, child: child);

    if (safeArea) {
      content = SafeArea(child: content);
    }

    if (backgroundColor != null) {
      content = ColoredBox(color: backgroundColor!, child: content);
    }

    return content;
  }
}

class _ScrollableScreenSurface extends StatelessWidget {
  const _ScrollableScreenSurface({
    required this.child,
    required this.padding,
    required this.expandToViewport,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool expandToViewport;

  @override
  Widget build(BuildContext context) {
    final paddedChild = Padding(padding: padding, child: child);

    if (!expandToViewport) {
      return SingleChildScrollView(child: paddedChild);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(child: paddedChild),
          ),
        );
      },
    );
  }
}

class AsmRouteInputTile extends StatelessWidget {
  const AsmRouteInputTile({
    required this.markerColor,
    required this.placeholder,
    required this.onTap,
    this.description,
    this.enabled = true,
    this.trailingIcon = Icons.chevron_right,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AsmSpacing.space16,
      vertical: AsmSpacing.space12,
    ),
    this.minHeight = 62,
    this.backgroundColor,
    this.placeholderStyle,
    this.selectedStyle,
    Key? key,
  }) : _tileKey = key,
       super(key: null);

  final Color markerColor;
  final String placeholder;
  final String? description;
  final VoidCallback? onTap;
  final bool enabled;
  final IconData? trailingIcon;
  final EdgeInsetsGeometry padding;
  final double minHeight;
  final Color? backgroundColor;
  final TextStyle? placeholderStyle;
  final TextStyle? selectedStyle;
  final Key? _tileKey;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final value = description?.trim();
    final hasValue = value != null && value.isNotEmpty;
    final effectiveOnTap = enabled ? onTap : null;
    final text = hasValue ? value : placeholder;
    final textStyle = hasValue
        ? selectedStyle ??
              TextStyle(
                color: colors.onSurface,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              )
        : placeholderStyle ??
              TextStyle(
                color: colors.onSurfaceVariant,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              );

    return Semantics(
      button: true,
      enabled: enabled,
      label: hasValue ? '$placeholder, $value' : placeholder,
      child: Material(
        color: backgroundColor ?? colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AsmRadii.radius8),
        child: InkWell(
          key: _tileKey,
          onTap: effectiveOnTap,
          borderRadius: BorderRadius.circular(AsmRadii.radius8),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Padding(
              padding: padding,
              child: Row(
                children: [
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: markerColor,
                      shape: hasValue ? BoxShape.circle : BoxShape.rectangle,
                      borderRadius: hasValue
                          ? null
                          : BorderRadius.circular(AsmRadii.radius6),
                    ),
                  ),
                  const SizedBox(width: AsmSpacing.space12),
                  Expanded(
                    child: Text(
                      text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textStyle,
                    ),
                  ),
                  if (trailingIcon != null) ...[
                    const SizedBox(width: AsmSpacing.space8),
                    Icon(trailingIcon),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AsmRouteActionRow extends StatelessWidget {
  const AsmRouteActionRow({
    required this.onSwapPressed,
    this.onClearPressed,
    this.swapEnabled = true,
    this.clearEnabled = true,
    this.showClearAction = false,
    this.swapLabel = 'Swap pickup and destination',
    this.clearLabel = 'Clear route',
    this.swapIcon = Icons.swap_vert,
    this.clearIcon = Icons.clear,
    this.alignment = MainAxisAlignment.end,
    this.spacing = AsmSpacing.space8,
    this.swapKey,
    this.clearKey,
    super.key,
  });

  final VoidCallback? onSwapPressed;
  final VoidCallback? onClearPressed;
  final bool swapEnabled;
  final bool clearEnabled;
  final bool showClearAction;
  final String swapLabel;
  final String clearLabel;
  final IconData swapIcon;
  final IconData clearIcon;
  final MainAxisAlignment alignment;
  final double spacing;
  final Key? swapKey;
  final Key? clearKey;

  @override
  Widget build(BuildContext context) {
    final effectiveSwapEnabled = swapEnabled && onSwapPressed != null;
    final effectiveClearEnabled = clearEnabled && onClearPressed != null;

    return Row(
      mainAxisAlignment: alignment,
      children: [
        Semantics(
          button: true,
          enabled: effectiveSwapEnabled,
          label: swapLabel,
          child: IconButton.outlined(
            key: swapKey,
            tooltip: swapLabel,
            onPressed: effectiveSwapEnabled ? onSwapPressed : null,
            icon: Icon(swapIcon),
          ),
        ),
        if (showClearAction) ...[
          SizedBox(width: spacing),
          TextButton.icon(
            key: clearKey,
            onPressed: effectiveClearEnabled ? onClearPressed : null,
            icon: Icon(clearIcon),
            label: Text(clearLabel),
          ),
        ],
      ],
    );
  }
}

class AsmRoutePlannerPanel extends StatelessWidget {
  const AsmRoutePlannerPanel({
    required this.pickupInputTile,
    required this.destinationInputTile,
    required this.actionRow,
    this.validationNotice,
    this.actionArea,
    this.padding = const EdgeInsets.all(AsmSpacing.space12),
    this.tileSpacing = AsmSpacing.space8,
    this.validationSpacing = AsmSpacing.space8,
    this.actionAreaSpacing = AsmSpacing.space12,
    this.backgroundColor,
    this.borderColor,
    super.key,
  });

  final Widget pickupInputTile;
  final Widget destinationInputTile;
  final Widget actionRow;
  final Widget? validationNotice;
  final Widget? actionArea;
  final EdgeInsetsGeometry padding;
  final double tileSpacing;
  final double validationSpacing;
  final double actionAreaSpacing;
  final Color? backgroundColor;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor ?? colors.surface,
        borderRadius: BorderRadius.circular(AsmRadii.radius8),
        border: Border.all(color: borderColor ?? colors.outlineVariant),
      ),
      child: Column(
        children: [
          pickupInputTile,
          SizedBox(height: tileSpacing),
          destinationInputTile,
          SizedBox(height: tileSpacing),
          actionRow,
          if (validationNotice != null) ...[
            SizedBox(height: validationSpacing),
            validationNotice!,
          ],
          if (actionArea != null) ...[
            SizedBox(height: actionAreaSpacing),
            actionArea!,
          ],
        ],
      ),
    );
  }
}

enum AsmRouteValidationSeverity { error, warning, info }

class AsmRouteValidationNotice extends StatelessWidget {
  const AsmRouteValidationNotice({
    required this.message,
    this.visible = true,
    this.icon,
    this.severity = AsmRouteValidationSeverity.error,
    this.color,
    this.textStyle,
    this.padding = EdgeInsets.zero,
    this.maxLines,
    super.key,
  });

  final String message;
  final bool visible;
  final IconData? icon;
  final AsmRouteValidationSeverity severity;
  final Color? color;
  final TextStyle? textStyle;
  final EdgeInsetsGeometry padding;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    if (!visible) {
      return const SizedBox.shrink();
    }

    final colors = Theme.of(context).colorScheme;
    final effectiveColor =
        color ??
        switch (severity) {
          AsmRouteValidationSeverity.error => colors.error,
          AsmRouteValidationSeverity.warning => colors.tertiary,
          AsmRouteValidationSeverity.info => colors.primary,
        };
    final effectiveTextStyle = TextStyle(
      color: effectiveColor,
      fontWeight: FontWeight.w600,
    ).merge(textStyle);

    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, color: effectiveColor, size: 18),
            const SizedBox(width: AsmSpacing.space8),
          ],
          Expanded(
            child: Text(
              message,
              maxLines: maxLines,
              overflow: maxLines == null ? null : TextOverflow.ellipsis,
              style: effectiveTextStyle,
            ),
          ),
        ],
      ),
    );
  }
}

enum AsmActionButtonVariant { filled, outlined, text }

class AsmPrimaryActionButton extends StatelessWidget {
  const AsmPrimaryActionButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.enabled = true,
    this.variant = AsmActionButtonVariant.filled,
    this.fullWidth = true,
    this.backgroundColor,
    this.foregroundColor,
    this.minimumHeight = 52,
    Key? key,
  }) : _buttonKey = key,
       super(key: null);

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool enabled;
  final AsmActionButtonVariant variant;
  final bool fullWidth;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final double minimumHeight;
  final Key? _buttonKey;

  @override
  Widget build(BuildContext context) {
    final effectiveOnPressed = enabled ? onPressed : null;
    final labelText = Text(
      label,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
    );
    final child = Row(
      mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon),
          const SizedBox(width: AsmSpacing.space8),
        ],
        if (fullWidth) Flexible(child: labelText) else labelText,
      ],
    );

    final button = switch (variant) {
      AsmActionButtonVariant.filled => FilledButton(
        key: _buttonKey,
        onPressed: effectiveOnPressed,
        style: FilledButton.styleFrom(
          minimumSize: Size.fromHeight(minimumHeight),
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
        ),
        child: child,
      ),
      AsmActionButtonVariant.outlined => OutlinedButton(
        key: _buttonKey,
        onPressed: effectiveOnPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: Size.fromHeight(minimumHeight),
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
        ),
        child: child,
      ),
      AsmActionButtonVariant.text => TextButton(
        key: _buttonKey,
        onPressed: effectiveOnPressed,
        style: TextButton.styleFrom(
          minimumSize: Size.fromHeight(minimumHeight),
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
        ),
        child: child,
      ),
    };

    if (!fullWidth) {
      return button;
    }

    return SizedBox(width: double.infinity, child: button);
  }
}

class AsmEmptyStatePanel extends StatelessWidget {
  const AsmEmptyStatePanel({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.compact = false,
    this.fullWidth = true,
    this.minHeight,
    this.padding = const EdgeInsets.all(AsmSpacing.space20),
    this.backgroundColor,
    this.borderColor,
    this.iconColor,
    this.iconSize,
    this.titleStyle,
    this.messageStyle,
    this.titleMaxLines = 3,
    this.messageMaxLines = 4,
    this.borderRadius = AsmRadii.radius8,
    this.iconSpacing = AsmSpacing.space12,
    this.textSpacing = AsmSpacing.space4,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  final bool compact;
  final bool fullWidth;
  final double? minHeight;
  final EdgeInsetsGeometry padding;
  final Color? backgroundColor;
  final Color? borderColor;
  final Color? iconColor;
  final double? iconSize;
  final TextStyle? titleStyle;
  final TextStyle? messageStyle;
  final int? titleMaxLines;
  final int? messageMaxLines;
  final double borderRadius;
  final double iconSpacing;
  final double textSpacing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final effectiveTitleStyle =
        titleStyle ??
        textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700);
    final effectiveMessageStyle =
        messageStyle ??
        textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant);
    final effectiveIcon = Icon(
      icon,
      color: iconColor ?? colors.primary,
      size: iconSize ?? (compact ? 24 : 42),
    );
    final textContent = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: compact
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        if (title.isNotEmpty)
          Text(
            title,
            textAlign: compact ? TextAlign.start : TextAlign.center,
            maxLines: titleMaxLines,
            overflow: TextOverflow.ellipsis,
            style: effectiveTitleStyle,
          ),
        if (title.isNotEmpty && message.isNotEmpty)
          SizedBox(height: textSpacing),
        if (message.isNotEmpty)
          Text(
            message,
            textAlign: compact ? TextAlign.start : TextAlign.center,
            maxLines: messageMaxLines,
            overflow: TextOverflow.ellipsis,
            style: effectiveMessageStyle,
          ),
        if (action != null) ...[
          const SizedBox(height: AsmSpacing.space16),
          action!,
        ],
      ],
    );

    final content = compact
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              effectiveIcon,
              SizedBox(width: iconSpacing),
              Expanded(child: textContent),
            ],
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              effectiveIcon,
              SizedBox(height: iconSpacing),
              textContent,
            ],
          );

    final panel = Container(
      constraints: BoxConstraints(minHeight: minHeight ?? 0),
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor ?? colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: borderColor ?? colors.outlineVariant),
      ),
      child: compact ? content : Center(child: content),
    );

    if (!fullWidth) {
      return panel;
    }

    return SizedBox(width: double.infinity, child: panel);
  }
}

class AsmLocalMapPreviewSurface extends StatelessWidget {
  const AsmLocalMapPreviewSurface({
    required this.title,
    this.message,
    this.icon = Icons.map_outlined,
    this.minHeight = 190,
    this.padding = const EdgeInsets.all(AsmSpacing.space20),
    this.backgroundColor,
    this.borderColor,
    this.iconColor,
    this.iconSize = 42,
    this.titleStyle,
    this.messageStyle,
    this.titleMaxLines = 3,
    this.messageMaxLines = 4,
    super.key,
  });

  final String title;
  final String? message;
  final IconData icon;
  final double minHeight;
  final EdgeInsetsGeometry padding;
  final Color? backgroundColor;
  final Color? borderColor;
  final Color? iconColor;
  final double iconSize;
  final TextStyle? titleStyle;
  final TextStyle? messageStyle;
  final int? titleMaxLines;
  final int? messageMaxLines;

  @override
  Widget build(BuildContext context) {
    final effectiveMessage = message ?? '';

    return AsmEmptyStatePanel(
      icon: icon,
      title: title,
      message: effectiveMessage,
      minHeight: minHeight,
      padding: padding,
      backgroundColor: backgroundColor,
      borderColor: borderColor,
      iconColor: iconColor,
      iconSize: iconSize,
      titleStyle: titleStyle ?? const TextStyle(fontWeight: FontWeight.w700),
      messageStyle: messageStyle,
      titleMaxLines: titleMaxLines,
      messageMaxLines: messageMaxLines,
    );
  }
}

class AsmRideDetailRow extends StatelessWidget {
  const AsmRideDetailRow({
    required this.label,
    required this.value,
    this.icon,
    this.iconColor,
    this.contained = false,
    this.selectableValue = false,
    this.backgroundColor,
    this.borderColor,
    this.labelStyle,
    this.valueStyle,
    super.key,
  });

  final String label;
  final String value;
  final IconData? icon;
  final Color? iconColor;
  final bool contained;
  final bool selectableValue;
  final Color? backgroundColor;
  final Color? borderColor;
  final TextStyle? labelStyle;
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final effectiveLabelStyle =
        labelStyle ??
        textTheme.labelLarge?.copyWith(color: colors.onSurfaceVariant);
    final effectiveValueStyle =
        valueStyle ??
        textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700);

    final textContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: effectiveLabelStyle),
        const SizedBox(height: AsmSpacing.space4),
        selectableValue
            ? SelectableText(value, style: effectiveValueStyle)
            : Text(value, style: effectiveValueStyle),
      ],
    );

    final content = icon == null
        ? textContent
        : Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icon, color: iconColor ?? colors.primary),
              const SizedBox(width: AsmSpacing.space12),
              Expanded(child: textContent),
            ],
          );

    if (!contained) {
      return Padding(
        padding: const EdgeInsets.only(bottom: AsmSpacing.space16),
        child: content,
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AsmSpacing.space16),
      decoration: BoxDecoration(
        color: backgroundColor ?? colors.surfaceContainerHighest,
        border: Border.all(color: borderColor ?? colors.outlineVariant),
        borderRadius: BorderRadius.circular(AsmRadii.radius8),
      ),
      child: content,
    );
  }
}

class AsmPilotNoticeBanner extends StatelessWidget {
  const AsmPilotNoticeBanner({
    required this.message,
    this.icon = Icons.info_outline,
    this.backgroundColor = const Color(0xFFE9F0EA),
    this.iconColor = AsmColors.green,
    this.textStyle = const TextStyle(fontWeight: FontWeight.w600),
    this.padding = const EdgeInsets.all(AsmSpacing.space12),
    this.spacing = AsmSpacing.space12,
    this.borderRadius = AsmRadii.radius8,
    super.key,
  });

  final String message;
  final IconData icon;
  final Color? backgroundColor;
  final Color? iconColor;
  final TextStyle? textStyle;
  final EdgeInsetsGeometry padding;
  final double spacing;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor),
          SizedBox(width: spacing),
          Expanded(child: Text(message, maxLines: null, style: textStyle)),
        ],
      ),
    );
  }
}

class AsmBottomNavigationDestination {
  const AsmBottomNavigationDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final Widget icon;
  final Widget selectedIcon;
  final String label;
}

class AsmBottomNavigationBar extends StatelessWidget {
  const AsmBottomNavigationBar({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
    super.key,
  });

  final int selectedIndex;
  final ValueChanged<int>? onDestinationSelected;
  final List<AsmBottomNavigationDestination> destinations;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: onDestinationSelected,
      destinations: destinations
          .map(
            (destination) => NavigationDestination(
              icon: destination.icon,
              selectedIcon: destination.selectedIcon,
              label: destination.label,
            ),
          )
          .toList(growable: false),
    );
  }
}

class AsmLocalInfoPanel extends StatelessWidget {
  const AsmLocalInfoPanel({
    required this.message,
    this.icon = Icons.info_outline,
    this.iconColor,
    this.backgroundColor,
    this.borderColor,
    this.textStyle,
    super.key,
  });

  final String message;
  final IconData icon;
  final Color? iconColor;
  final Color? backgroundColor;
  final Color? borderColor;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final effectiveTextStyle =
        textStyle ??
        TextStyle(
          color: colors.onPrimaryContainer,
          fontWeight: FontWeight.w800,
        );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AsmSpacing.space16),
      decoration: BoxDecoration(
        color: backgroundColor ?? colors.primaryContainer,
        border: borderColor == null ? null : Border.all(color: borderColor!),
        borderRadius: BorderRadius.circular(AsmRadii.radius8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor ?? colors.onPrimaryContainer),
          const SizedBox(width: AsmSpacing.space12),
          Expanded(child: Text(message, style: effectiveTextStyle)),
        ],
      ),
    );
  }
}
