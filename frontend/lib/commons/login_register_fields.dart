import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:notif/commons/auth_palette.dart';

class Logo extends StatelessWidget {
  final String title;
  final Color? textColor;

  const Logo({super.key, required this.title, this.textColor});

  @override
  Widget build(BuildContext context) {
    final bool isSmallScreen = MediaQuery.of(context).size.width < 600;
    final colorScheme = Theme.of(context).colorScheme;
    final baseStyle = isSmallScreen
        ? Theme.of(context).textTheme.headlineSmall
        : Theme.of(context).textTheme.headlineMedium;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FlutterLogo(size: isSmallScreen ? 100 : 200),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            title,
            textAlign: TextAlign.center,
            style:
                baseStyle?.copyWith(color: textColor ?? colorScheme.onSurface),
          ),
        )
      ],
    );
  }
}

class PageBackground extends StatelessWidget {
  final Widget child;

  const PageBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: CustomPaint(
        painter: const _PosterBackgroundPainter(),
        child: child,
      ),
    );
  }
}

class _PosterBackgroundPainter extends CustomPainter {
  const _PosterBackgroundPainter();

  static const List<_BackgroundOp> _operations = [
    _LinearGradientOp(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: AuthPalette.baseGradientColors,
      stops: AuthPalette.baseGradientStops,
    ),
    _CircularGradientOp(
      centerYFactor: 0,
      diameterFactor: 0.78,
      colors: AuthPalette.bloomColors,
      stops: AuthPalette.bloomStops,
    ),
    _LinearGradientOp(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: AuthPalette.transitionColors,
      stops: AuthPalette.transitionStops,
    ),
    _GrainOp(
      spacing: 2.6,
      limitYFactor: 1,
      noiseThreshold: 0.09,
      opacityScale: 0.34,
      minRadius: 0.26,
      maxRadiusDelta: 0.38,
      fromColor: AuthPalette.grainFrom,
      toColor: AuthPalette.grainTo,
      colorLerpScale: 0.68,
      fadeCenter: Alignment(0, -1),
      fadeRadius: 2.85,
    ),
    _HalftoneOp(
      spacing: 11.5,
      startYFactor: 0.44,
      baseRadius: 1.35,
      radiusGrowth: 6.6,
      opacityBase: 0.14,
      opacityGrowth: 0.24,
      topColor: AuthPalette.halftoneTop,
      bottomColor: AuthPalette.halftoneBottom,
      colorLerpScale: 0.66,
      convexCurveDepthFactor: 0.16,
      landscapeCurveBoost: 1.15,
      curveExponent: 1.7,
      landscapeExponentPull: 0.35,
    ),
    _LinearGradientOp(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: AuthPalette.floorFadeColors,
      stops: AuthPalette.floorFadeStops,
    ),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    for (final operation in _operations) {
      operation.paint(canvas, size);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}

abstract class _BackgroundOp {
  const _BackgroundOp();

  void paint(Canvas canvas, Size size);
}

enum _BackgroundShape { rect, oval }

class _RelativeRect {
  final double leftFactor;
  final double topFactor;
  final double widthFactor;
  final double heightFactor;

  const _RelativeRect({
    required this.leftFactor,
    required this.topFactor,
    required this.widthFactor,
    required this.heightFactor,
  });

  const _RelativeRect.full()
      : leftFactor = 0,
        topFactor = 0,
        widthFactor = 1,
        heightFactor = 1;

  Rect resolve(Size size) {
    return Rect.fromLTWH(
      size.width * leftFactor,
      size.height * topFactor,
      size.width * widthFactor,
      size.height * heightFactor,
    );
  }
}

class _LinearGradientOp extends _BackgroundOp {
  final Alignment begin;
  final Alignment end;
  final List<Color> colors;
  final List<double>? stops;
  final _RelativeRect rect;
  final _BackgroundShape shape;

  const _LinearGradientOp({
    required this.begin,
    required this.end,
    required this.colors,
    this.stops,
    this.rect = const _RelativeRect.full(),
    this.shape = _BackgroundShape.rect,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final targetRect = rect.resolve(size);
    final paint = Paint()
      ..shader = LinearGradient(
        begin: begin,
        end: end,
        colors: colors,
        stops: stops,
      ).createShader(targetRect);

    _drawShape(canvas, targetRect, paint, shape);
  }
}

class _CircularGradientOp extends _BackgroundOp {
  final double centerYFactor;
  final double diameterFactor;
  final List<Color> colors;
  final List<double>? stops;

  const _CircularGradientOp({
    required this.centerYFactor,
    required this.diameterFactor,
    required this.colors,
    this.stops,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.width * diameterFactor / 2;
    final center = Offset(size.width / 2, size.height * centerYFactor);
    final paint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 1,
        colors: colors,
        stops: stops,
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawRect(Offset.zero & size, paint);
  }
}

class _GrainOp extends _BackgroundOp {
  final double spacing;
  final double limitYFactor;
  final double noiseThreshold;
  final double opacityScale;
  final double minRadius;
  final double maxRadiusDelta;
  final Color fromColor;
  final Color toColor;
  final double colorLerpScale;
  final Alignment fadeCenter;
  final double fadeRadius;

  const _GrainOp({
    required this.spacing,
    required this.limitYFactor,
    required this.noiseThreshold,
    required this.opacityScale,
    required this.minRadius,
    required this.maxRadiusDelta,
    required this.fromColor,
    required this.toColor,
    required this.colorLerpScale,
    required this.fadeCenter,
    required this.fadeRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final limitY = size.height * limitYFactor;
    final cx = (fadeCenter.x + 1) / 2 * size.width;
    final cy = (fadeCenter.y + 1) / 2 * size.height;
    final halfW = size.width * 0.5;
    final halfH = size.height * 0.5;
    var rowIndex = 0;

    for (double y = 0; y < limitY; y += spacing) {
      final offsetX = rowIndex.isEven ? 0.0 : spacing / 2;

      for (double x = -spacing; x < size.width + spacing; x += spacing) {
        final dotX = x + offsetX;
        final nx = (dotX - cx) / halfW;
        final ny = (y - cy) / halfH;
        final dist = sqrt(nx * nx + ny * ny);
        final radialFade = (1.0 - dist / fadeRadius).clamp(0.0, 1.0);

        if (radialFade <= 0) continue;

        final noise = _hashNoise(
          ((x + spacing) / spacing).floor(),
          (y / spacing).floor(),
        );
        if (noise < noiseThreshold) continue;

        paint.color = Color.lerp(
              fromColor,
              toColor,
              noise * colorLerpScale,
            )!
            .withOpacity((noise - noiseThreshold) * opacityScale * radialFade);

        canvas.drawCircle(
          Offset(dotX, y),
          minRadius + noise * maxRadiusDelta,
          paint,
        );
      }

      rowIndex++;
    }
  }
}

class _HalftoneOp extends _BackgroundOp {
  final double spacing;
  final double startYFactor;
  final double baseRadius;
  final double radiusGrowth;
  final double opacityBase;
  final double opacityGrowth;
  final Color topColor;
  final Color bottomColor;
  final double colorLerpScale;
  final double convexCurveDepthFactor;
  final double landscapeCurveBoost;
  final double curveExponent;
  final double landscapeExponentPull;

  const _HalftoneOp({
    required this.spacing,
    required this.startYFactor,
    required this.baseRadius,
    required this.radiusGrowth,
    required this.opacityBase,
    required this.opacityGrowth,
    required this.topColor,
    required this.bottomColor,
    required this.colorLerpScale,
    this.convexCurveDepthFactor = 0,
    this.landscapeCurveBoost = 0,
    this.curveExponent = 2,
    this.landscapeExponentPull = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final startY = size.height * startYFactor;
    final aspectRatio = size.width / size.height;
    final landscapeFactor = (aspectRatio - 1).clamp(0.0, 1.8);
    final curveDepth = size.height *
        convexCurveDepthFactor *
        (1 + landscapeFactor * landscapeCurveBoost);
    final exponent =
        (curveExponent - landscapeFactor * landscapeExponentPull).clamp(0.7, 4.0);
    var rowIndex = 0;

    for (double y = startY; y < size.height + spacing; y += spacing) {
      final normalized = ((y - startY) / (size.height - startY)).clamp(0.0, 1.0);
      final contrastFactor = 1 - normalized;
      final xOffset = rowIndex.isEven ? 0.0 : spacing / 2;
      final radius = baseRadius + normalized * radiusGrowth;

      paint.color = Color.lerp(
            bottomColor,
            topColor,
            contrastFactor * colorLerpScale,
          )!
          .withOpacity(opacityBase + contrastFactor * opacityGrowth);

      for (double x = -spacing; x < size.width + spacing; x += spacing) {
        final currentX = x + xOffset;
        final centerDistance =
            ((currentX - (size.width / 2)).abs() / (size.width / 2))
                .clamp(0.0, 1.0);
        final edgeLift = 1 - pow(centerDistance, exponent).toDouble();
        final localStartY =
            startY + curveDepth * edgeLift;
        if (y < localStartY) {
          continue;
        }

        canvas.drawCircle(Offset(currentX, y), radius, paint);
      }

      rowIndex++;
    }
  }
}

class GlassHelpButton extends StatelessWidget {
  final VoidCallback onPressed;
  final String tooltip;
  final Widget child;

  const GlassHelpButton({
    super.key,
    required this.onPressed,
    required this.tooltip,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(4);

    return Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: AuthPalette.fabShadow,
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            decoration: BoxDecoration(
              color: AuthPalette.fabGlass,
              borderRadius: radius,
              border: Border.all(color: AuthPalette.panelBorder),
            ),
            child: FloatingActionButton(
              onPressed: onPressed,
              tooltip: tooltip,
              backgroundColor: Colors.transparent,
              foregroundColor: AuthPalette.fabIcon,
              elevation: 0,
              highlightElevation: 0,
              hoverElevation: 0,
              focusElevation: 0,
              splashColor: Colors.white.withOpacity(0.12),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

void _drawShape(
  Canvas canvas,
  Rect rect,
  Paint paint,
  _BackgroundShape shape,
) {
  if (shape == _BackgroundShape.oval) {
    canvas.drawOval(rect, paint);
    return;
  }

  canvas.drawRect(rect, paint);
}

double _hashNoise(int x, int y) {
  int value = x * 374761393 + y * 668265263;
  value = (value ^ (value >> 13)) * 1274126177;
  value ^= value >> 16;
  return (value & 0x7fffffff) / 0x7fffffff;
}

class AuthPanel extends StatelessWidget {
  final Widget child;

  const AuthPanel({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(4);
    return Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: AuthPalette.panelShadow,
            blurRadius: 36,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            decoration: BoxDecoration(
              color: AuthPalette.panel.withOpacity(0.42),
              borderRadius: radius,
              border: Border.all(color: AuthPalette.panelBorder),
            ),
            padding: const EdgeInsets.all(24),
            child: child,
          ),
        ),
      ),
    );
  }
}

class UsernameTextField extends StatefulWidget {
  final String labelText;
  final String hintText;
  final TextEditingController textController;

  const UsernameTextField({
    super.key,
    required this.labelText,
    required this.hintText,
    required this.textController,
  });

  @override
  State<UsernameTextField> createState() => _UsernameTextFieldState();
}

class _UsernameTextFieldState extends State<UsernameTextField> {
  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: widget.key,
      controller: widget.textController,
      decoration: InputDecoration(
        labelText: widget.labelText,
        hintText: widget.hintText,
        prefixIcon: const Icon(Icons.account_box_outlined),
      ),
    );
  }
}

class EmailTextField extends StatefulWidget {
  final String labelText;
  final String hintText;
  final String? Function(String?)? validator;
  final TextEditingController textController;

  const EmailTextField(
      {super.key,
      required this.labelText,
      required this.hintText,
      this.validator,
      required this.textController});

  @override
  State<EmailTextField> createState() => _EmailTextFieldState();
}

class _EmailTextFieldState extends State<EmailTextField> {
  late String? Function(String?) validator;

  _EmailTextFieldState();

  @override
  void initState() {
    super.initState();
    validator = widget.validator ?? defaultValidator;
  }

  String? defaultValidator(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter an email address';
    } else if (!RegExp(r"^[a-zA-Z0-9.]+@[a-zA-Z0-9]+\.[a-zA-Z]+")
        .hasMatch(value)) {
      return 'Please enter a valid email address';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      validator: validator,
      controller: widget.textController,
      decoration: InputDecoration(
        labelText: widget.labelText,
        hintText: widget.hintText,
        prefixIcon: const Icon(Icons.email_outlined),
      ),
    );
  }
}

class PasswordTextField extends StatefulWidget {
  final String labelText;
  final String hintText;
  final String? Function(String?)? validator;
  final TextEditingController textController;

  const PasswordTextField(
      {super.key,
      required this.labelText,
      required this.hintText,
      this.validator,
      required this.textController});

  @override
  State<PasswordTextField> createState() => _PasswordTextFieldState();
}

class _PasswordTextFieldState extends State<PasswordTextField> {
  bool _isPasswordVisible = false;
  late String? Function(String?) validator;

  _PasswordTextFieldState();

  @override
  void initState() {
    super.initState();
    validator = widget.validator ?? EntropyValidator().validate;
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.textController,
      validator: validator,
      obscureText: !_isPasswordVisible,
      decoration: InputDecoration(
          labelText: widget.labelText,
          hintText: widget.hintText,
          prefixIcon: const Icon(Icons.lock_outline_rounded),
          suffixIcon: IconButton(
            icon: Icon(
                _isPasswordVisible ? Icons.visibility_off : Icons.visibility),
            onPressed: () {
              setState(() {
                _isPasswordVisible = !_isPasswordVisible;
              });
            },
          )),
    );
  }
}

class CustomButton extends StatelessWidget {
  final String buttonText;
  final Function onPressed;
  final Color? buttonColor;

  const CustomButton(
      {super.key,
      required this.buttonText,
      required this.onPressed,
      this.buttonColor});

  @override
  Widget build(BuildContext context) {
    final backgroundColor = buttonColor ?? AuthPalette.primaryButtonBase;
    final isPrimary = buttonColor == null;
    final foregroundColor = isPrimary
        ? AuthPalette.buttonForeground
        : AuthPalette.secondaryButtonForeground;

    final radius = BorderRadius.circular(4);

    return SizedBox(
      width: double.infinity,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: AuthPalette.buttonShadow,
              blurRadius: 10,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: radius,
                border: Border.all(color: AuthPalette.buttonBorder),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onPressed as void Function(),
                  child: Padding(
                    padding: const EdgeInsets.all(10.0),
                    child: Center(
                      child: Text(
                        buttonText,
                        style: TextStyle(
                          color: foregroundColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class EntropyValidator {
  static const double timeInSeconds =
      100 * 365 * 24 * 60 * 60; // 100 years in seconds
  static const double attemptsPerSecond =
      1e9; // Estimated attempts per second for a consumer CPU
  static final double minEntropy = log(timeInSeconds * attemptsPerSecond) / ln2;

  String? validate(String? password) {
    if (password == null || password.isEmpty) {
      return "Password cannot be empty";
    }

    double passwordEntropy = calculatePasswordEntropy(password);
    if (passwordEntropy < minEntropy) {
      return getHelpText(passwordEntropy: passwordEntropy);
    }

    return null;
  }

  String getHelpText({double? passwordEntropy}) {
    // ignore: prefer_interpolation_to_compose_strings
    return "Use more and different characters. \"S0m3 password!\"";
  }

  double calculatePasswordEntropy(String password) {
    bool hasDigit = password.contains(RegExp(r'\d'));
    bool hasLower = password.contains(RegExp(r'[a-z]'));
    bool hasUpper = password.contains(RegExp(r'[A-Z]'));
    bool hasPunct = password.contains(RegExp(r'[!@#\$%^&*(),.?":{}|<>]'));
    bool hasOther = password.contains(RegExp(r'[^\w\s]'));

    List<bool> categories = [hasDigit, hasLower, hasUpper, hasPunct, hasOther];
    List<int> lengths = [10, 26, 26, 32, 40];
    int charSet = 0;

    for (var i = 0; i < categories.length; i++) {
      if (categories[i]) {
        charSet += lengths[i];
      }
    }

    double passwordEntropy = log(charSet) / ln2 * password.length;

    return passwordEntropy;
  }
}
