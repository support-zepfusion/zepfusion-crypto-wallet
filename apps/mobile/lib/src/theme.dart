import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Cofinex dark navy and teal. No third-party wallet branding.
class CofinexColors {
  static const navy = Color(0xFF07111F);
  static const navyRaised = Color(0xFF0E1A2B);
  static const card = Color(0xFF132338);
  static const cardHigh = Color(0xFF1B3048);
  static const line = Color(0xFF2A405C);
  static const teal = Color(0xFF2EE6C7);
  static const tealDeep = Color(0xFF14C8B0);
  static const ink = Color(0xFF04221C);
  static const text = Color(0xFFF4F7FB);
  static const muted = Color(0xFF93A4B8);
  static const danger = Color(0xFFFF6B8A);
  static const warning = Color(0xFFFFC46B);
}

ThemeData cofinexTheme() {
  const scheme = ColorScheme.dark(
    brightness: Brightness.dark,
    surface: CofinexColors.navy,
    primary: CofinexColors.teal,
    onPrimary: CofinexColors.ink,
    secondary: CofinexColors.tealDeep,
    onSecondary: CofinexColors.ink,
    error: CofinexColors.danger,
    onError: CofinexColors.text,
    onSurface: CofinexColors.text,
    surfaceContainerHighest: CofinexColors.card,
    outline: CofinexColors.line,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: Brightness.dark,
  );
  return base.copyWith(
    scaffoldBackgroundColor: CofinexColors.navy,
    splashColor: CofinexColors.teal.withValues(alpha: 0.12),
    highlightColor: CofinexColors.teal.withValues(alpha: 0.06),
    appBarTheme: const AppBarTheme(
      backgroundColor: CofinexColors.navy,
      foregroundColor: CofinexColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
    ),
    cardTheme: CardThemeData(
      color: CofinexColors.card,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: CofinexColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: CofinexColors.navyRaised,
      modalBackgroundColor: CofinexColors.navyRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: CofinexColors.cardHigh,
      contentTextStyle: const TextStyle(color: CofinexColors.text),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: CofinexColors.card,
      labelStyle: const TextStyle(color: CofinexColors.muted),
      hintStyle: const TextStyle(color: CofinexColors.muted),
      helperStyle: const TextStyle(color: CofinexColors.muted),
      errorStyle: const TextStyle(color: CofinexColors.danger),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: CofinexColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: CofinexColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: CofinexColors.teal, width: 1.4),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: CofinexColors.teal,
        foregroundColor: CofinexColors.ink,
        disabledBackgroundColor: CofinexColors.cardHigh,
        disabledForegroundColor: CofinexColors.muted,
        minimumSize: const Size(64, 54),
        textStyle: const TextStyle(
          fontFamily: 'Roboto',
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: CofinexColors.teal,
        textStyle: const TextStyle(
          fontFamily: 'Roboto',
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    dividerColor: CofinexColors.line,
    textTheme: base.textTheme.apply(
      bodyColor: CofinexColors.text,
      displayColor: CofinexColors.text,
    ),
  );
}

class CofinexMark extends StatelessWidget {
  const CofinexMark({super.key, this.size = 96});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Cofinex',
      child: CustomPaint(size: Size.square(size), painter: const _HexPainter()),
    );
  }
}

class _HexPainter extends CustomPainter {
  const _HexPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final outer = size.width / 2;
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addPolygon(_hex(center, outer), true)
      ..addPolygon(_hex(center, outer * 0.58), true);
    canvas.drawPath(
      path,
      Paint()
        ..color = CofinexColors.teal.withValues(alpha: 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
    );
    canvas.drawPath(
      path,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF7AF6E4), CofinexColors.tealDeep],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

List<Offset> _hex(Offset center, double radius) {
  return List<Offset>.generate(6, (index) {
    final angle = (math.pi / 180) * (60 * index - 90);
    return Offset(
      center.dx + radius * math.cos(angle),
      center.dy + radius * math.sin(angle),
    );
  });
}

void cofinexHaptic() {
  try {
    HapticFeedback.selectionClick();
  } catch (_) {
    // Desktop tests and some emulators have no vibrator.
  }
}

void showCofinexMessage(
  BuildContext context,
  String message, {
  bool error = false,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) {
    return;
  }
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: error ? const Color(0xFF3A1824) : CofinexColors.cardHigh,
    ),
  );
}

Route<T> cofinexRoute<T>(Widget child) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 240),
    reverseTransitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (context, animation, secondary) => child,
    transitionsBuilder: (context, animation, secondary, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.05, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Keeps phone layouts readable on a tablet-width window.
class CofinexFrame extends StatelessWidget {
  const CofinexFrame({super.key, required this.child, this.maxWidth = 520});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

class CofinexButton extends StatelessWidget {
  const CofinexButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: busy || onPressed == null
          ? null
          : () {
              cofinexHaptic();
              onPressed!();
            },
      child: busy
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            )
          : Text(label),
    );
  }
}

class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    required this.height,
    this.width = double.infinity,
  });

  final double height;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: CofinexColors.cardHigh,
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }
}

class InlineError extends StatelessWidget {
  const InlineError({super.key, required this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final message = this.message;
    if (message == null || message.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(
        message,
        key: const Key('inline-error'),
        style: const TextStyle(color: CofinexColors.danger, height: 1.35),
      ),
    );
  }
}
