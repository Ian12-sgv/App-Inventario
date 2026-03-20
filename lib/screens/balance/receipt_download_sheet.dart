import 'package:flutter/material.dart';

import '../../ui/app_theme.dart';

enum ReceiptDownloadFormat { pdf, image }

Future<ReceiptDownloadFormat?> showReceiptDownloadSheet(
  BuildContext context, {
  String title = 'Descargar comprobante',
}) {
  return showModalBottomSheet<ReceiptDownloadFormat>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (sheetContext) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.navy,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(sheetContext),
                  icon: const Icon(Icons.close),
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFFF2F4F7),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Elige el formato en el que quieres descargar o compartir el comprobante.',
              style: TextStyle(
                color: Colors.black54,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            _ReceiptFormatOption(
              icon: Icons.picture_as_pdf_rounded,
              accent: AppTheme.red,
              title: 'PDF',
              subtitle: 'Comprobante en PDF con el diseño completo.',
              onTap: () =>
                  Navigator.pop(sheetContext, ReceiptDownloadFormat.pdf),
            ),
            const SizedBox(height: 12),
            _ReceiptFormatOption(
              icon: Icons.image_rounded,
              accent: AppTheme.green,
              title: 'Imagen',
              subtitle: 'Comprobante exportado como imagen para compartir.',
              onTap: () =>
                  Navigator.pop(sheetContext, ReceiptDownloadFormat.image),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ReceiptFormatOption extends StatelessWidget {
  const _ReceiptFormatOption({
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE4EAF2), width: 1.2),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: accent, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.navy,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.25,
                        color: Colors.black54,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppTheme.navy,
                size: 28,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
