// lib/models/variant.dart
class Variant {
  final int id;
  final int productId;

  /// NUEVO: Solo estos 2 campos son la variante.
  final String size;  // talla
  final String color; // color

  /// Separador para guardar size/color dentro de la columna "name" (schema viejo).
  /// Ej: "M||Azul"
  static const String _sep = '||';

  const Variant({
    required this.id,
    required this.productId,
    required this.size,
    required this.color,
  });

  /// Para mostrar en UI: "Talla M • Azul"
  String get label {
    final s = size.trim();
    final c = color.trim();
    if (s.isEmpty && c.isEmpty) return 'Variante';
    if (s.isEmpty) return c;
    if (c.isEmpty) return 'Talla $s';
    return 'Talla $s • $c';
  }

  /// Codifica size/color dentro de "name" (para DB legacy).
  String toLegacyName() => '${size.trim()}$_sep${color.trim()}';

  static Map<String, String> _parseLegacyName(String raw) {
    final txt = raw.trim();
    if (txt.isEmpty) return {'size': '', 'color': ''};

    // Caso ideal: "M||Azul"
    if (txt.contains(_sep)) {
      final parts = txt.split(_sep);
      final s = parts.isNotEmpty ? parts[0].trim() : '';
      final c = parts.length > 1 ? parts[1].trim() : '';
      return {'size': s, 'color': c};
    }

    // Soporte suave a formatos antiguos tipo "Talla M - Azul" o "M / Azul"
    final fallback = txt
        .replaceAll('Talla', '')
        .replaceAll('talla', '')
        .replaceAll('Color', '')
        .replaceAll('color', '')
        .replaceAll(':', '')
        .trim();

    // Intenta separar por "•", "-", "/", "|"
    final seps = ['•', '-', '/', '|'];
    for (final sp in seps) {
      if (fallback.contains(sp)) {
        final parts = fallback.split(sp).map((e) => e.trim()).toList();
        final s = parts.isNotEmpty ? parts[0] : '';
        final c = parts.length > 1 ? parts[1] : '';
        return {'size': s, 'color': c};
      }
    }

    // Si no se puede, lo tomamos como "size" y dejamos color vacío.
    return {'size': fallback, 'color': ''};
  }

  factory Variant.fromMap(Map<String, Object?> m) {
    final id = (m['id'] as int?) ?? 0;

    // Soporta productId o product_id (por si tu schema usa snake_case)
    final productId =
        (m['productId'] as int?) ?? (m['product_id'] as int?) ?? 0;

    // Si existen columnas nuevas (size/color), prioridad a eso:
    final rawSize = (m['size'] as String?)?.trim();
    final rawColor = (m['color'] as String?)?.trim();

    String size = rawSize ?? '';
    String color = rawColor ?? '';

    // Si no existen, parsea desde "name" (schema viejo)
    if (size.isEmpty && color.isEmpty) {
      final name = (m['name'] as String?) ?? '';
      final parsed = _parseLegacyName(name);
      size = parsed['size'] ?? '';
      color = parsed['color'] ?? '';
    }

    return Variant(
      id: id,
      productId: productId,
      size: size,
      color: color,
    );
  }

  Variant copyWith({
    int? id,
    int? productId,
    String? size,
    String? color,
  }) {
    return Variant(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      size: size ?? this.size,
      color: color ?? this.color,
    );
  }

  // ---------------------------------------------------------------------------
  // MAPAS PARA DB
  //
  // IMPORTANTE:
  // - Si tu tabla variants es vieja (name, price, cost, stock), usa los métodos legacy.
  // - Si tu tabla variants nueva tiene columnas size/color, usa toDbNewSchemaMap.
  // ---------------------------------------------------------------------------

  /// Para schema viejo: columns típicas: productId, name, price, cost, stock, createdAt
  /// Nosotros ponemos price/cost/stock en 0 para no usarlos.
  Map<String, Object?> toDbLegacyInsertMap({
    required int productId,
    int? createdAt,
  }) {
    return {
      'productId': productId,
      'name': toLegacyName(),
      'price': 0.0,
      'cost': 0.0,
      'stock': 0,
      if (createdAt != null) 'createdAt': createdAt,
    };
  }

  /// Para update en schema viejo (no incluye productId normalmente)
  Map<String, Object?> toDbLegacyUpdateMap() {
    return {
      'name': toLegacyName(),
      'price': 0.0,
      'cost': 0.0,
      'stock': 0,
    };
  }

  /// Para schema nuevo: columns: productId, size, color, createdAt (opcional)
  Map<String, Object?> toDbNewSchemaMap({
    required int productId,
    int? createdAt,
  }) {
    return {
      'productId': productId,
      'size': size.trim(),
      'color': color.trim(),
      if (createdAt != null) 'createdAt': createdAt,
    };
  }
}
