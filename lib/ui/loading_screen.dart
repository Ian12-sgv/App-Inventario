import 'dart:ui';

import 'package:flutter/material.dart';

import 'app_theme.dart';

class LoadingScreen extends StatelessWidget {
  const LoadingScreen({
    super.key,
    this.message = 'Cargando...',
    this.compact = false,
  });

  final String message;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final panel = _LoadingPanel(message: message, compact: compact);

    return Semantics(
      label: message,
      liveRegion: true,
      child: ColoredBox(
        color: compact ? Colors.transparent : AppTheme.bg,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (!compact) const _LoadingBackdrop(),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(compact ? 20 : 28),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: compact ? 300 : 380),
                    child: panel,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BlockingLoadingOverlay extends StatelessWidget {
  const BlockingLoadingOverlay({super.key, this.message = 'Cargando...'});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: const ColoredBox(color: Color(0x7A162538)),
        ),
        Center(child: LoadingScreen(message: message, compact: true)),
      ],
    );
  }
}

class _LoadingPanel extends StatelessWidget {
  const _LoadingPanel({required this.message, required this.compact});

  final String message;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final logoSize = compact ? 86.0 : 104.0;
    final horizontalPadding = compact ? 20.0 : 28.0;
    final verticalPadding = compact ? 20.0 : 28.0;

    final panel = ClipRRect(
      borderRadius: BorderRadius.circular(compact ? 30 : 36),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: compact ? 14 : 20,
          sigmaY: compact ? 14 : 20,
        ),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: verticalPadding,
          ),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFDFEFF), Color(0xFFF6F9FE), Color(0xFFF1F6FC)],
            ),
            borderRadius: BorderRadius.circular(compact ? 30 : 36),
            border: Border.all(color: const Color(0xB8FFFFFF), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: AppTheme.navy.withValues(alpha: compact ? 0.18 : 0.12),
                blurRadius: compact ? 30 : 42,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _BrandChip(),
              SizedBox(height: compact ? 16 : 18),
              _LogoHalo(size: logoSize),
              SizedBox(height: compact ? 16 : 20),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.navy,
                  fontSize: compact ? 18 : 24,
                  fontWeight: FontWeight.w900,
                  height: 1.12,
                ),
              ),
              SizedBox(height: compact ? 8 : 10),
              Text(
                compact
                    ? 'Estamos dando los ultimos toques para mostrar tu panel.'
                    : 'Estamos preparando tu espacio y conectando la informacion necesaria para continuar.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: const Color(0xFF546173),
                  fontSize: compact ? 13 : 14,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: compact ? 16 : 20),
              _ProgressCard(compact: compact),
              if (!compact) ...[
                const SizedBox(height: 18),
                const Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _LoadingTag(
                      icon: Icons.verified_user_outlined,
                      label: 'Acceso seguro',
                    ),
                    _LoadingTag(
                      icon: Icons.sync_rounded,
                      label: 'Sincronizando datos',
                    ),
                    _LoadingTag(
                      icon: Icons.schedule_rounded,
                      label: 'Solo unos segundos',
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );

    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      tween: Tween(begin: 0.94, end: 1),
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 24),
            child: Transform.scale(scale: value, child: child),
          ),
        );
      },
      child: panel,
    );
  }
}

class _LoadingBackdrop extends StatelessWidget {
  const _LoadingBackdrop();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFF8FBFF), Color(0xFFEAF1F8), Color(0xFFF5F6F8)],
            ),
          ),
        ),
        Positioned(
          top: -80,
          left: -30,
          child: _BackdropGlow(
            size: 220,
            colors: [
              AppTheme.royalBlue.withValues(alpha: 0.18),
              AppTheme.royalBlue.withValues(alpha: 0.03),
            ],
          ),
        ),
        Positioned(
          right: -70,
          bottom: 40,
          child: _BackdropGlow(
            size: 260,
            colors: [
              const Color(0xFF9BC2F8).withValues(alpha: 0.20),
              Colors.white.withValues(alpha: 0.03),
            ],
          ),
        ),
        Positioned(
          left: 32,
          right: 32,
          top: 56,
          bottom: 56,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(36),
                border: Border.all(color: Colors.white.withValues(alpha: 0.45)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BackdropGlow extends StatelessWidget {
  const _BackdropGlow({required this.size, required this.colors});

  final double size;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: colors),
          ),
        ),
      ),
    );
  }
}

class _BrandChip extends StatelessWidget {
  const _BrandChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2FF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFD5E5FA)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome_rounded, size: 14, color: AppTheme.royalBlue),
          SizedBox(width: 8),
          Text(
            'By Rossy',
            style: TextStyle(
              color: AppTheme.navy,
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _LogoHalo extends StatelessWidget {
  const _LogoHalo({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEAF2FF), Color(0xFFFFFFFF)],
        ),
        border: Border.all(color: const Color(0xFFD1E0F4)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.royalBlue.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Stack(
          alignment: Alignment.center,
          children: [
            const SizedBox.expand(
              child: CircularProgressIndicator(
                strokeWidth: 3.2,
                color: AppTheme.royalBlue,
                backgroundColor: Color(0xFFD7E4F3),
              ),
            ),
            Container(
              width: size - 28,
              height: size - 28,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Image.asset(
                  'assets/branding/logo_by.png',
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 12 : 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFDCE6F2)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: const BoxDecoration(
                  color: AppTheme.green,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                compact
                    ? 'Sincronizando tu informacion'
                    : 'Preparando tu panel',
                style: TextStyle(
                  color: AppTheme.navy,
                  fontSize: compact ? 12.5 : 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: const LinearProgressIndicator(
              minHeight: 7,
              color: AppTheme.royalBlue,
              backgroundColor: Color(0xFFDCE6F5),
            ),
          ),
          if (!compact) ...[
            const SizedBox(height: 10),
            const Text(
              'Validando acceso, cargando datos y dejando todo listo para continuar.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF68778A),
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LoadingTag extends StatelessWidget {
  const _LoadingTag({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFDCE5F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppTheme.royalBlue),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.navy,
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
