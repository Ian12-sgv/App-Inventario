import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'app_theme.dart';

String? _stringCandidate(dynamic value) {
  if (value == null) return null;
  if (value is Map) {
    for (final key in const ['imageUrl', 'image_url', 'url', 'path', 'src']) {
      final nested = _stringCandidate(value[key]);
      if (nested != null) return nested;
    }
    return null;
  }
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

String? resolveProductLineImageUrl({
  required Map<String, dynamic> row,
  required AppState state,
}) {
  final product = (row['product'] is Map)
      ? (row['product'] as Map).cast<String, dynamic>()
      : const <String, dynamic>{};

  for (final candidate in [
    product['imageUrl'],
    product['image_url'],
    product['image'],
    row['imageUrl'],
    row['image_url'],
    row['image'],
  ]) {
    final imageUrl = _stringCandidate(candidate);
    if (imageUrl != null) return imageUrl;
  }

  final productId =
      _stringCandidate(row['productId']) ??
      _stringCandidate(row['product_id']) ??
      _stringCandidate(product['id']);
  if (productId == null) return null;

  for (final item in state.products) {
    if (item.id == productId) {
      return item.imageUrl;
    }
  }
  return null;
}

String? resolveExpenseProductImageUrl({
  required Map<String, dynamic> expense,
  required AppState state,
}) {
  final product = (expense['product'] is Map)
      ? (expense['product'] as Map).cast<String, dynamic>()
      : const <String, dynamic>{};

  for (final candidate in [
    product['imageUrl'],
    product['image_url'],
    product['image'],
    expense['imageUrl'],
    expense['image_url'],
    expense['image'],
  ]) {
    final imageUrl = _stringCandidate(candidate);
    if (imageUrl != null) return imageUrl;
  }

  final productId =
      _stringCandidate(expense['productId']) ??
      _stringCandidate(expense['product_id']) ??
      _stringCandidate(product['id']);
  if (productId == null) return null;

  for (final item in state.products) {
    if (item.id == productId) {
      return item.imageUrl;
    }
  }
  return null;
}

class ProductThumb extends StatelessWidget {
  const ProductThumb({
    super.key,
    required this.imageUrl,
    this.size = 72,
    this.radius = 16,
    this.borderColor = const Color(0xFFD6DCE4),
    this.iconSize,
  });

  final String? imageUrl;
  final double size;
  final double radius;
  final Color borderColor;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    final resolved = context.read<AppState>().resolveApiUrl(imageUrl);
    final placeholder = Icon(
      Icons.inventory_2_outlined,
      color: AppTheme.navy,
      size: iconSize ?? (size * 0.4),
    );

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppTheme.bg,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor, width: 1.2),
      ),
      clipBehavior: Clip.antiAlias,
      child: (resolved ?? '').trim().isEmpty
          ? placeholder
          : Image.network(
              resolved!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => placeholder,
            ),
    );
  }
}
