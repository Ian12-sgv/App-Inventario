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
    final card = Container(
      width: compact ? 210 : 240,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 18 : 22,
        vertical: compact ? 18 : 22,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x16000000),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'assets/branding/logo_by.png',
            width: compact ? 74 : 96,
            height: compact ? 74 : 96,
            fit: BoxFit.contain,
          ),
          SizedBox(height: compact ? 12 : 16),
          Text(
            'By Rossy',
            style: TextStyle(
              color: AppTheme.navy,
              fontSize: compact ? 18 : 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.black54,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: compact ? 14 : 16),
          const SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(
              strokeWidth: 2.8,
              color: AppTheme.royalBlue,
            ),
          ),
        ],
      ),
    );

    return ColoredBox(
      color: AppTheme.bg,
      child: Center(
        child: Padding(padding: const EdgeInsets.all(24), child: card),
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
      children: [
        const ModalBarrier(dismissible: false, color: Color(0x660C1B2A)),
        Center(child: LoadingScreen(message: message, compact: true)),
      ],
    );
  }
}
