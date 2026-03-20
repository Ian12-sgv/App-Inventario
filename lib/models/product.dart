class Product {
  final String id;
  final String barcode;
  final String reference;
  final String name; // UI: nombre/descripcion

  // Nueva jerarquía comercial
  final String line; // Línea = género
  final String subLine; // Sub línea = tipo de prenda / modelo
  final String
  category; // Categoría = talla (con respaldo legacy si viene vacío)
  final String subCategory; // Sub categoría = color
  final String? legacyCategory; // Campo antiguo del backend, solo respaldo
  final String? imageUrl;

  final double priceRetailUsd;
  final double priceWholesaleUsd;
  final double costUsd;
  final double stock; // stock en bodega seleccionada

  const Product({
    required this.id,
    required this.barcode,
    required this.reference,
    required this.name,
    required this.line,
    required this.subLine,
    required this.category,
    required this.subCategory,
    required this.priceRetailUsd,
    required this.priceWholesaleUsd,
    required this.costUsd,
    required this.stock,
    this.legacyCategory,
    this.imageUrl,
  });

  Product copyWith({
    double? stock,
    String? imageUrl,
    bool clearImage = false,
  }) => Product(
    id: id,
    barcode: barcode,
    reference: reference,
    name: name,
    line: line,
    subLine: subLine,
    category: category,
    subCategory: subCategory,
    priceRetailUsd: priceRetailUsd,
    priceWholesaleUsd: priceWholesaleUsd,
    costUsd: costUsd,
    stock: stock ?? this.stock,
    legacyCategory: legacyCategory,
    imageUrl: clearImage ? null : (imageUrl ?? this.imageUrl),
  );

  bool get hasImage => (imageUrl ?? '').trim().isNotEmpty;

  static double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  static String _clean(dynamic v) => (v ?? '').toString().trim();

  static String _firstNonEmpty(Map<String, dynamic> source, List<String> keys) {
    for (final key in keys) {
      final value = _clean(source[key]);
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  factory Product.fromApi(Map<String, dynamic> m, {double stock = 0}) {
    final desc = _firstNonEmpty(m, ['description', 'name', 'nombre']);
    final reference = _firstNonEmpty(m, ['reference', 'referencia']);
    final barcode = _firstNonEmpty(m, [
      'barcode',
      'codigoBarras',
      'codigo_barra',
    ]);
    final line = _firstNonEmpty(m, ['line', 'linea', 'línea']);
    final subLine = _firstNonEmpty(m, [
      'subLine',
      'sub_line',
      'subline',
      'sublinea',
      'sub_linea',
      'subLínea',
    ]);
    final legacyCategory = _firstNonEmpty(m, ['category', 'categoria']);
    final size = _firstNonEmpty(m, ['size', 'talla']);
    final displayCategory = size.isNotEmpty
        ? size
        : (legacyCategory.isNotEmpty ? legacyCategory : 'Sin categoría');
    final subCategory = _firstNonEmpty(m, [
      'color',
      'subCategory',
      'sub_category',
      'subcategoria',
      'sub_categoria',
    ]);

    final name = desc.isNotEmpty
        ? desc
        : (reference.isNotEmpty
              ? reference
              : (barcode.isNotEmpty ? barcode : 'Producto'));

    final imageUrl = _firstNonEmpty(m, ['imageUrl', 'image_url', 'image']);

    return Product(
      id: _clean(m['id']),
      barcode: barcode,
      reference: reference,
      name: name,
      line: line,
      subLine: subLine,
      category: displayCategory,
      subCategory: subCategory,
      priceRetailUsd: _toDouble(m['priceRetail']),
      priceWholesaleUsd: _toDouble(m['priceWholesale']),
      costUsd: _toDouble(m['cost']),
      stock: stock,
      legacyCategory: legacyCategory.isEmpty ? null : legacyCategory,
      imageUrl: imageUrl.isEmpty ? null : imageUrl,
    );
  }
}
