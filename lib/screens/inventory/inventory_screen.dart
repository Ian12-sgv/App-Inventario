import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/product.dart';
import '../../state/app_state.dart';
import '../../ui/account_header.dart';
import '../../ui/app_theme.dart';
import '../../utils/inventory_exporter.dart';
import 'product_sheets.dart';

const double _lowStockThreshold = 3;

enum _SortField { stock, name, createdAt, price }

class _SortSpec {
  final _SortField field;
  final bool asc;
  const _SortSpec(this.field, this.asc);

  @override
  bool operator ==(Object other) =>
      other is _SortSpec && other.field == field && other.asc == asc;

  @override
  int get hashCode => Object.hash(field, asc);
}

class _InventoryFilters {
  final String line;
  final String subLine;
  final String category;
  final String subCategory;

  const _InventoryFilters({
    this.line = 'Todas',
    this.subLine = 'Todas',
    this.category = 'Todas',
    this.subCategory = 'Todas',
  });

  bool get hasActive =>
      line != 'Todas' ||
      subLine != 'Todas' ||
      category != 'Todas' ||
      subCategory != 'Todas';

  _InventoryFilters copyWith({
    String? line,
    String? subLine,
    String? category,
    String? subCategory,
  }) {
    return _InventoryFilters(
      line: line ?? this.line,
      subLine: subLine ?? this.subLine,
      category: category ?? this.category,
      subCategory: subCategory ?? this.subCategory,
    );
  }
}

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  _InventoryFilters _filters = const _InventoryFilters();
  _SortSpec? _sort;

  bool _showSearch = false;
  final _searchCtl = TextEditingController();
  final _searchFocus = FocusNode();

  @override
  void dispose() {
    _searchCtl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  List<Product> _applySort(List<Product> input) {
    final spec = _sort;
    final list = List<Product>.of(input);
    if (spec == null) return list;

    int cmpNum(num a, num b) => a.compareTo(b);
    int cmpStr(String a, String b) =>
        a.toLowerCase().compareTo(b.toLowerCase());

    int cmp(Product a, Product b) {
      switch (spec.field) {
        case _SortField.stock:
          return cmpNum(a.stock, b.stock);
        case _SortField.name:
          return cmpStr(a.name, b.name);
        case _SortField.price:
          return cmpNum(a.priceRetailUsd, b.priceRetailUsd);
        case _SortField.createdAt:
          return cmpStr(a.id, b.id);
      }
    }

    list.sort((a, b) {
      final r = cmp(a, b);
      return spec.asc ? r : -r;
    });

    return list;
  }

  List<Product> _filteredByHierarchy(
    List<Product> products,
    _InventoryFilters filters,
  ) {
    return products.where((p) {
      if (filters.line != 'Todas' && p.line != filters.line) return false;
      if (filters.subLine != 'Todas' && p.subLine != filters.subLine) {
        return false;
      }
      if (filters.category != 'Todas' && p.category != filters.category) {
        return false;
      }
      if (filters.subCategory != 'Todas' &&
          p.subCategory != filters.subCategory) {
        return false;
      }
      return true;
    }).toList();
  }

  Future<void> _openSortSheet() async {
    final result = await showModalBottomSheet<_SortResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => _InventorySortSheet(current: _sort),
    );

    if (!mounted || result == null) return;
    setState(() => _sort = result.spec);
  }

  Future<void> _openFiltersSheet(List<Product> products) async {
    final result = await showModalBottomSheet<_InventoryFilters>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) =>
          _InventoryFiltersSheet(products: products, current: _filters),
    );

    if (!mounted || result == null) return;
    setState(() => _filters = result);
  }

  Future<void> _openExportSheet(AppState model, List<Product> products) async {
    if (products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay productos para exportar')),
      );
      return;
    }

    final shareOrigin = _shareOriginFor(context);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => _InventoryExportSheet(
        productCount: products.length,
        onPdf: () async {
          Navigator.pop(sheetContext);
          await _exportPdf(model, products);
        },
        onExcel: () async {
          Navigator.pop(sheetContext);
          await _exportExcel(model, products, shareOrigin: shareOrigin);
        },
      ),
    );
  }

  Rect? _shareOriginFor(BuildContext context) {
    final box = context.findRenderObject();
    if (box is RenderBox) {
      return box.localToGlobal(Offset.zero) & box.size;
    }
    return null;
  }

  Future<void> _exportPdf(AppState model, List<Product> products) async {
    try {
      await InventoryExporter.sharePdfReport(
        products: products,
        generatedBy: model.userDisplayName,
        warehouseName: model.warehouseName,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo exportar el PDF: $e')));
    }
  }

  Future<void> _exportExcel(
    AppState model,
    List<Product> products, {
    Rect? shareOrigin,
  }) async {
    try {
      await InventoryExporter.shareExcelReport(
        products: products,
        generatedBy: model.userDisplayName,
        warehouseName: model.warehouseName,
        sharePositionOrigin: shareOrigin,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo exportar Excel: $e')));
    }
  }

  void _toggleSearch() {
    setState(() => _showSearch = !_showSearch);
    if (_showSearch) {
      Future.delayed(const Duration(milliseconds: 120), () {
        if (!mounted) return;
        _searchFocus.requestFocus();
      });
    } else {
      _searchCtl.clear();
      _searchFocus.unfocus();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final clampedTextScaler = mq.textScaler.clamp(
      minScaleFactor: 0.95,
      maxScaleFactor: 1.05,
    );

    return MediaQuery(
      data: mq.copyWith(textScaler: clampedTextScaler),
      child: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final model = context.watch<AppState>();
    final products = model.products;

    final byHierarchy = _filteredByHierarchy(products, _filters);

    final q = _searchCtl.text.trim().toLowerCase();
    final filtered = q.isEmpty
        ? byHierarchy
        : byHierarchy.where((p) {
            final haystack = [
              p.name,
              p.barcode,
              p.line,
              p.subLine,
              p.category,
              p.subCategory,
              p.legacyCategory ?? '',
            ].join(' | ').toLowerCase();
            return haystack.contains(q);
          }).toList();

    final display = _applySort(filtered);

    final totalRefs = products.length;
    final totalCost = products.fold<double>(
      0,
      (a, p) => a + (p.costUsd * p.stock),
    );

    final activeFilterLabels = <String>[
      if (_filters.line != 'Todas') _filters.line,
      if (_filters.subLine != 'Todas') _filters.subLine,
      if (_filters.category != 'Todas') _filters.category,
      if (_filters.subCategory != 'Todas') _filters.subCategory,
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF2F3F5),
      appBar: AccountHeader(
        contextLabel: 'Inventario',
        onSearch: _toggleSearch,
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: Column(
          children: [
            Row(
              children: [
                _SquareAction(
                  size: 46,
                  icon: Icons.download_rounded,
                  filled: false,
                  tooltip: 'Acción',
                  onTap: () => _openExportSheet(model, display),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: FilledButton.icon(
                      onPressed: () async => showPurchaseSheet(context),
                      icon: const Icon(
                        Icons.shopping_basket_outlined,
                        size: 20,
                      ),
                      label: const Text('Registrar compras'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.navy,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(22),
                        ),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _SummaryCardCompact(totalRefs: totalRefs, totalCost: totalCost),
            const SizedBox(height: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              child: !_showSearch
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: SizedBox(
                        height: 44,
                        child: TextField(
                          controller: _searchCtl,
                          focusNode: _searchFocus,
                          onChanged: (_) => setState(() {}),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.navy,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Buscar producto',
                            hintStyle: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF8A96A8),
                            ),
                            prefixIcon: const Icon(
                              Icons.search_rounded,
                              size: 22,
                            ),
                            suffixIcon: _searchCtl.text.trim().isEmpty
                                ? null
                                : IconButton(
                                    onPressed: () {
                                      _searchCtl.clear();
                                      setState(() {});
                                    },
                                    icon: const Icon(
                                      Icons.close_rounded,
                                      size: 20,
                                    ),
                                    tooltip: 'Limpiar',
                                  ),
                            isDense: true,
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(
                                color: Color(0xFFD6DCE4),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(
                                color: AppTheme.royalBlue,
                                width: 1.4,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
            SizedBox(
              height: 46,
              child: Row(
                children: [
                  _SquareAction(
                    size: 46,
                    icon: Icons.sort_rounded,
                    filled: true,
                    tooltip: 'Ordenar',
                    onTap: _openSortSheet,
                  ),
                  const SizedBox(width: 8),
                  _SquareAction(
                    size: 46,
                    icon: Icons.filter_alt_outlined,
                    filled: false,
                    tooltip: 'Filtros',
                    onTap: () => _openFiltersSheet(products),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _ScopeChip(
                            label: 'Todas',
                            selected: !_filters.hasActive,
                          ),
                          for (final label in activeFilterLabels) ...[
                            const SizedBox(width: 8),
                            _ScopeChip(label: label, selected: true),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (_filters.hasActive) ...[
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () =>
                          setState(() => _filters = const _InventoryFilters()),
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.navy,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      child: const Text(
                        'Limpiar',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${display.length} producto(s)',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF667085),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: display.isEmpty
                  ? const Center(
                      child: Text(
                        'No hay productos para esos filtros.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 12),
                      itemCount: display.length,
                      separatorBuilder: (context, separatorIndex) =>
                          const SizedBox(height: 15),
                      itemBuilder: (context, i) => _ProductTileCompact(
                        p: display[i],
                        onTap: () => showProductSheet(context, display[i]),
                      ),
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        color: const Color(0xFFF2F3F5),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SizedBox(
              height: 54,
              width: double.infinity,
              child: FilledButton(
                onPressed: model.canCrearInventario
                    ? () => showCreateProductSheet(context)
                    : null,
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
                  backgroundColor: AppTheme.navy,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
                child: const Text('Crear producto'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InventoryExportSheet extends StatelessWidget {
  const _InventoryExportSheet({
    required this.productCount,
    required this.onPdf,
    required this.onExcel,
  });

  final int productCount;
  final Future<void> Function() onPdf;
  final Future<void> Function() onExcel;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Descargar inventario',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.navy,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFFF2F4F7),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Exporta $productCount producto(s) del inventario actual. Se respetan los filtros y la busqueda activa.',
              style: const TextStyle(
                color: Colors.black54,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            _InventoryExportOption(
              icon: Icons.picture_as_pdf_rounded,
              accent: AppTheme.red,
              title: 'PDF',
              subtitle:
                  'Reporte visual con resumen y detalle del inventario por jerarquia.',
              onTap: onPdf,
            ),
            const SizedBox(height: 12),
            _InventoryExportOption(
              icon: Icons.table_chart_rounded,
              accent: AppTheme.green,
              title: 'Excel',
              subtitle:
                  'Hoja compatible con Excel para revisar, editar o compartir.',
              onTap: onExcel,
            ),
          ],
        ),
      ),
    );
  }
}

class _InventoryExportOption extends StatelessWidget {
  const _InventoryExportOption({
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
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onTap(),
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFD8E0E8)),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: accent, size: 24),
              ),
              const SizedBox(width: 12),
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
                        fontWeight: FontWeight.w700,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppTheme.navy,
                size: 26,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SquareAction extends StatelessWidget {
  const _SquareAction({
    required this.size,
    required this.icon,
    required this.filled,
    required this.tooltip,
    required this.onTap,
  });

  final double size;
  final IconData icon;
  final bool filled;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = filled ? AppTheme.navy : Colors.white;
    final fg = filled ? Colors.white : AppTheme.navy;
    final borderColor = filled ? AppTheme.navy : const Color(0xFFD5DDE7);

    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor, width: 1.3),
            ),
            child: Icon(icon, color: fg, size: 22),
          ),
        ),
      ),
    );
  }
}

class _ScopeChip extends StatelessWidget {
  const _ScopeChip({required this.label, required this.selected});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: selected ? AppTheme.royalBlue : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected ? AppTheme.royalBlue : const Color(0xFFC9D3DE),
          width: 1.4,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? Colors.white : AppTheme.navy,
          fontWeight: FontWeight.w800,
          fontSize: 14,
        ),
      ),
    );
  }
}

class _SummaryCardCompact extends StatelessWidget {
  const _SummaryCardCompact({required this.totalRefs, required this.totalCost});

  final int totalRefs;
  final double totalCost;

  @override
  Widget build(BuildContext context) {
    Widget row(String left, String right, {bool bigRight = false}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                left,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.navy,
                ),
              ),
            ),
            Text(
              right,
              style: TextStyle(
                fontSize: bigRight ? 22 : 17,
                fontWeight: FontWeight.w900,
                color: AppTheme.navy,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDBE3EC), width: 1.1),
      ),
      child: Column(
        children: [
          row('Total de referencias', '$totalRefs'),
          const SizedBox(height: 6),
          row(
            'Costo total',
            '\$${totalCost.toStringAsFixed(0)}',
            bigRight: true,
          ),
        ],
      ),
    );
  }
}

class _ProductTileCompact extends StatelessWidget {
  const _ProductTileCompact({required this.p, required this.onTap});

  final Product p;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hierarchy = [
      if (p.line.trim().isNotEmpty) p.line.trim(),
      if (p.subLine.trim().isNotEmpty) p.subLine.trim(),
      if (p.category.trim().isNotEmpty) p.category.trim(),
      if (p.subCategory.trim().isNotEmpty) p.subCategory.trim(),
    ].join(' • ');

    final isLowStock = p.stock < _lowStockThreshold;
    final stockBg = isLowStock
        ? const Color(0xFFFEE4E2)
        : const Color(0xFFDFF7EC);
    final stockFg = isLowStock ? AppTheme.red : const Color(0xFF0F5E3B);
    final stockLabel = isLowStock
        ? 'Stock bajo: ${p.stock.toStringAsFixed(0)}'
        : '${p.stock.toStringAsFixed(0)} disponibles';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFC9D3DE), width: 1.5),
          ),
          child: Row(
            children: [
              _ProductThumb(imageUrl: p.imageUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.navy,
                      ),
                    ),
                    if (hierarchy.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        hierarchy,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF7A869A),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: stockBg,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        stockLabel,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: stockFg,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '\$${p.priceRetailUsd.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.navy,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductThumb extends StatelessWidget {
  const _ProductThumb({required this.imageUrl});

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final resolved = context.read<AppState>().resolveApiUrl(imageUrl);
    return Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        color: AppTheme.bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD6DCE4), width: 1.1),
      ),
      clipBehavior: Clip.antiAlias,
      child: (resolved ?? '').trim().isEmpty
          ? Icon(Icons.inventory_2_outlined, color: AppTheme.navy, size: 26)
          : Image.network(
              resolved!,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Icon(
                Icons.inventory_2_outlined,
                color: AppTheme.navy,
                size: 26,
              ),
            ),
    );
  }
}

class _SortResult {
  final _SortSpec? spec;
  const _SortResult(this.spec);
}

class _InventorySortSheet extends StatefulWidget {
  const _InventorySortSheet({required this.current});
  final _SortSpec? current;

  @override
  State<_InventorySortSheet> createState() => _InventorySortSheetState();
}

class _InventorySortSheetState extends State<_InventorySortSheet> {
  _SortSpec? _temp;

  @override
  void initState() {
    super.initState();
    _temp = widget.current;
  }

  Widget _sectionTitle(String t) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 10),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        t,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
      ),
    ),
  );

  Widget _twoBtns({
    required String left,
    required _SortSpec leftSpec,
    required String right,
    required _SortSpec rightSpec,
  }) {
    Widget btn(String label, _SortSpec spec) {
      final selected = _temp == spec;
      return Expanded(
        child: OutlinedButton(
          onPressed: () => setState(() => _temp = spec),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12),
            side: BorderSide(
              color: selected ? AppTheme.navy : const Color(0xFFD6DCE4),
            ),
            backgroundColor: selected ? AppTheme.bg : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              color: AppTheme.navy,
              fontSize: 14,
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        btn(left, leftSpec),
        const SizedBox(width: 12),
        btn(right, rightSpec),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ordenar inventario',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Solo puedes aplicar un orden a la vez',
                          style: TextStyle(
                            color: Colors.black54,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    style: IconButton.styleFrom(
                      backgroundColor: AppTheme.bg,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ],
              ),
              _sectionTitle('Por stock'),
              _twoBtns(
                left: 'Menos stock',
                leftSpec: const _SortSpec(_SortField.stock, true),
                right: 'Más stock',
                rightSpec: const _SortSpec(_SortField.stock, false),
              ),
              _sectionTitle('Por nombre'),
              _twoBtns(
                left: 'Nombre A-Z',
                leftSpec: const _SortSpec(_SortField.name, true),
                right: 'Nombre Z-A',
                rightSpec: const _SortSpec(_SortField.name, false),
              ),
              _sectionTitle('Por fecha de creación'),
              _twoBtns(
                left: 'Más antiguo',
                leftSpec: const _SortSpec(_SortField.createdAt, true),
                right: 'Más reciente',
                rightSpec: const _SortSpec(_SortField.createdAt, false),
              ),
              _sectionTitle('Por precio'),
              _twoBtns(
                left: 'Más bajo',
                leftSpec: const _SortSpec(_SortField.price, true),
                right: 'Más alto',
                rightSpec: const _SortSpec(_SortField.price, false),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, _SortResult(_temp)),
                  child: const Text('Aplicar'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () =>
                      Navigator.pop(context, const _SortResult(null)),
                  child: const Text('Limpiar orden'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InventoryFiltersSheet extends StatefulWidget {
  const _InventoryFiltersSheet({required this.products, required this.current});

  final List<Product> products;
  final _InventoryFilters current;

  @override
  State<_InventoryFiltersSheet> createState() => _InventoryFiltersSheetState();
}

class _InventoryFiltersSheetState extends State<_InventoryFiltersSheet> {
  late _InventoryFilters _temp;

  @override
  void initState() {
    super.initState();
    _temp = widget.current;
  }

  List<String> _valuesFrom(
    List<Product> products,
    String Function(Product) pick,
  ) {
    final set = <String>{};
    for (final p in products) {
      final value = pick(p).trim();
      if (value.isNotEmpty) set.add(value);
    }
    final items = set.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return items;
  }

  List<Product> _applyStep({String? line, String? subLine, String? category}) {
    return widget.products.where((p) {
      if (line != null && line != 'Todas' && p.line != line) return false;
      if (subLine != null && subLine != 'Todas' && p.subLine != subLine) {
        return false;
      }
      if (category != null && category != 'Todas' && p.category != category) {
        return false;
      }
      return true;
    }).toList();
  }

  Widget _dropdown({
    required String label,
    required String value,
    required List<String> options,
    required ValueChanged<String?> onChanged,
  }) {
    final items = ['Todas', ...options];
    final safeValue = items.contains(value) ? value : 'Todas';
    return DropdownButtonFormField<String>(
      initialValue: safeValue,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      ),
      items: items
          .map(
            (item) => DropdownMenuItem<String>(value: item, child: Text(item)),
          )
          .toList(),
      onChanged: onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final lineOptions = _valuesFrom(widget.products, (p) => p.line);
    final subLineBase = _applyStep(line: _temp.line);
    final subLineOptions = _valuesFrom(subLineBase, (p) => p.subLine);
    final categoryBase = _applyStep(line: _temp.line, subLine: _temp.subLine);
    final categoryOptions = _valuesFrom(categoryBase, (p) => p.category);
    final subCategoryBase = _applyStep(
      line: _temp.line,
      subLine: _temp.subLine,
      category: _temp.category,
    );
    final subCategoryOptions = _valuesFrom(
      subCategoryBase,
      (p) => p.subCategory,
    );
    final missingHierarchyData = lineOptions.isEmpty && subLineOptions.isEmpty;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Filtrar inventario',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'La jerarquía sigue este orden: línea, sub línea, categoría y sub categoría.',
                        style: TextStyle(
                          color: Colors.black54,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (missingHierarchyData) ...[
                        SizedBox(height: 8),
                        Text(
                          'No hay líneas ni sub líneas disponibles en el inventario cargado.',
                          style: TextStyle(
                            color: AppTheme.red,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  style: IconButton.styleFrom(
                    backgroundColor: AppTheme.bg,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _dropdown(
              label: 'Línea',
              value: _temp.line,
              options: lineOptions,
              onChanged: (v) => setState(() {
                _temp = _temp.copyWith(
                  line: v ?? 'Todas',
                  subLine: 'Todas',
                  category: 'Todas',
                  subCategory: 'Todas',
                );
              }),
            ),
            const SizedBox(height: 12),
            _dropdown(
              label: 'Sub línea',
              value: _temp.subLine,
              options: subLineOptions,
              onChanged: (v) => setState(() {
                _temp = _temp.copyWith(
                  subLine: v ?? 'Todas',
                  category: 'Todas',
                  subCategory: 'Todas',
                );
              }),
            ),
            const SizedBox(height: 12),
            _dropdown(
              label: 'Categoría',
              value: _temp.category,
              options: categoryOptions,
              onChanged: (v) => setState(() {
                _temp = _temp.copyWith(
                  category: v ?? 'Todas',
                  subCategory: 'Todas',
                );
              }),
            ),
            const SizedBox(height: 12),
            _dropdown(
              label: 'Sub categoría',
              value: _temp.subCategory,
              options: subCategoryOptions,
              onChanged: (v) => setState(() {
                _temp = _temp.copyWith(subCategory: v ?? 'Todas');
              }),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, _temp),
                child: const Text('Aplicar filtros'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () =>
                    Navigator.pop(context, const _InventoryFilters()),
                child: const Text('Limpiar filtros'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
