import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/txn.dart';
import '../../state/app_state.dart';
import '../../ui/app_theme.dart';
import '../../ui/product_thumb.dart';
import '../../utils/receipt_printer.dart';
import 'receipt_download_sheet.dart';
import 'transaction_sheet.dart';

/// Detalle completo de una venta:
/// - total
/// - lista de pagos (cuentas divididas)
/// - listado de productos (por inventoryDocId)
class SaleDetailScreen extends StatefulWidget {
  const SaleDetailScreen({super.key, required this.sale, required this.saleId});

  final Map<String, dynamic> sale;
  final String saleId;

  @override
  State<SaleDetailScreen> createState() => _SaleDetailScreenState();
}

class _SaleDetailScreenState extends State<SaleDetailScreen> {
  bool _paymentsExpanded = true;
  bool _productsExpanded = false;

  Future<List<Map<String, dynamic>>>? _linesFuture;

  static double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  String _money(double v) => '\$${v.toStringAsFixed(v % 1 == 0 ? 0 : 2)}';

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppState>();
    final sale = widget.sale;

    dynamic ev =
        sale['employeeName'] ??
        sale['empleado'] ??
        sale['userName'] ??
        sale['createdByName'] ??
        sale['createdBy'] ??
        sale['user'];
    if (ev is Map) {
      ev = ev['name'] ?? ev['fullName'] ?? ev['username'] ?? ev['email'];
    }
    final employee = (ev ?? '').toString().trim().isNotEmpty
        ? ev.toString().trim()
        : model.userDisplayName;

    _linesFuture ??= _buildLinesFuture(context, sale);

    final totalUsd = _toDouble(sale['totalUsd']);
    final cogsUsd = _toDouble(sale['cogsUsd']);
    final profit = totalUsd - cogsUsd;

    final payments =
        model.txnsForDay
            .where(
              (t) =>
                  (t.kind ?? '').toUpperCase() == 'VENTA' &&
                  (t.saleId ?? '') == widget.saleId,
            )
            .toList()
          ..sort((a, b) => a.when.compareTo(b.when));

    final methodLabel = payments.length > 1
        ? 'Cuentas divididas'
        : (payments.isNotEmpty ? payments.first.paymentMethod : '—');
    final dtFmt = DateFormat('hh:mm a | dd MMM yyyy', 'es');

    final title = (sale['description'] ?? sale['concept'] ?? 'Venta')
        .toString()
        .trim();
    final rawWhen = (sale['occurredAt'] ?? sale['occurred_at'] ?? '')
        .toString();
    final parsedWhen = DateTime.tryParse(rawWhen);
    final when = parsedWhen == null
        ? (payments.isNotEmpty ? payments.first.when : DateTime.now())
        : (parsedWhen.isUtc ? parsedWhen.toLocal() : parsedWhen);

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bannerBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Volver',
        ),
        title: const Text(
          'Detalle de la venta',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFFE6EBF2), width: 1.2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Resumen de la venta',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    color: AppTheme.navy,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Transacción • ${widget.saleId.length <= 8 ? widget.saleId : widget.saleId.substring(0, 8)}',
                  style: const TextStyle(
                    color: Colors.black54,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                const Divider(color: Color(0xFFE6EBF2), height: 1),
                const SizedBox(height: 14),
                const Text(
                  'Concepto',
                  style: TextStyle(
                    color: Colors.black54,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  title.isEmpty ? 'Venta' : title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    color: AppTheme.navy,
                  ),
                ),
                const SizedBox(height: 14),
                const Divider(color: Color(0xFFE6EBF2), height: 1),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Pago',
                            style: TextStyle(
                              color: Colors.black54,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _money(totalUsd),
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 28,
                              color: AppTheme.navy,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.green.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'Pagada',
                        style: TextStyle(
                          color: AppTheme.green,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Divider(color: Color(0xFFE6EBF2), height: 1),
                const SizedBox(height: 12),
                _kvRow(
                  'Total venta',
                  _money(totalUsd),
                  valueColor: AppTheme.green,
                ),
                _kvRow('Fecha y hora', dtFmt.format(when)),
                _kvRow('Método de pago', methodLabel),
                if (employee.trim().isNotEmpty && employee.trim() != '—')
                  _kvRow('Empleado', employee),
                _RefsCountRow(linesFuture: _linesFuture),
                _kvRow('Ganancia', _money(profit), valueColor: AppTheme.green),
              ],
            ),
          ),
          const SizedBox(height: 12),

          _ExpandableSection(
            title: 'Lista de pagos',
            expanded: _paymentsExpanded,
            onChanged: (v) => setState(() => _paymentsExpanded = v),
            child: payments.isEmpty
                ? const Text(
                    'No hay pagos para mostrar.',
                    style: TextStyle(
                      color: Colors.black54,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                : Column(
                    children: [
                      for (final p in payments) ...[
                        _PaymentRow(p: p),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ),
          ),
          const SizedBox(height: 12),

          _ExpandableSection(
            title: 'Listado de productos',
            expanded: _productsExpanded,
            onChanged: (v) => setState(() => _productsExpanded = v),
            child: _ProductsBlock(sale: sale, linesFuture: _linesFuture),
          ),

          const SizedBox(height: 90),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(
              top: BorderSide(color: Color(0xFFE6EBF2), width: 1.2),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _BottomAction(
                icon: Icons.receipt_long,
                label: 'Comprobante',
                crown: true,
                onTap: () async {
                  try {
                    final format = await showReceiptDownloadSheet(context);
                    if (format == null || !context.mounted) return;
                    final lines =
                        await (_linesFuture ??
                            Future.value(const <Map<String, dynamic>>[]));
                    switch (format) {
                      case ReceiptDownloadFormat.pdf:
                        await ReceiptPrinter.compartirVentaCompletaPdf(
                          sale: sale,
                          saleId: widget.saleId,
                          payments: payments,
                          lines: lines,
                          employeeName: employee,
                        );
                        break;
                      case ReceiptDownloadFormat.image:
                        await ReceiptPrinter.compartirVentaCompletaImagen(
                          sale: sale,
                          saleId: widget.saleId,
                          payments: payments,
                          lines: lines,
                          employeeName: employee,
                        );
                        break;
                    }
                  } catch (_) {
                    if (!context.mounted) return;
                    _snack(context, 'No se pudo generar el comprobante');
                  }
                },
              ),
              _BottomAction(
                icon: Icons.edit,
                label: 'Editar',
                onTap: context.watch<AppState>().canEditarVenta
                    ? () async {
                        try {
                          final saved = await showEditarVentaSheet(
                            context,
                            sale: sale,
                            saleId: widget.saleId,
                          );
                          if (saved == true && context.mounted) {
                            _snack(context, 'Venta actualizada');
                            Navigator.pop(context);
                          }
                        } catch (_) {
                          if (!context.mounted) return;
                          _snack(context, 'No se pudo abrir la edición');
                        }
                      }
                    : null,
              ),
              _BottomAction(
                icon: Icons.delete,
                label: 'Eliminar',
                danger: true,
                onTap: context.watch<AppState>().canEliminarVenta
                    ? () async {
                        final state = context.read<AppState>();
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (_) {
                            return AlertDialog(
                              title: const Text('Eliminar venta'),
                              content: const Text(
                                '¿Seguro que deseas eliminar esta venta?\n\nSi es una venta de inventario, el stock será devuelto automáticamente.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('Cancelar'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('Eliminar'),
                                ),
                              ],
                            );
                          },
                        );
                        if (ok != true) return;

                        try {
                          await state.eliminarVenta(widget.saleId);
                          if (!context.mounted) return;
                          _snack(context, 'Venta eliminada');
                          Navigator.pop(context);
                        } catch (_) {
                          if (!context.mounted) return;
                          _snack(context, 'No se pudo eliminar la venta');
                        }
                      }
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<List<Map<String, dynamic>>>? _buildLinesFuture(
    BuildContext context,
    Map<String, dynamic> sale,
  ) {
    final docId = (sale['inventoryDocId'] ?? sale['inventory_doc_id'])
        ?.toString();
    if (docId == null || docId.trim().isEmpty) return null;
    return context.read<AppState>().getEnrichedInventoryDocLines(docId.trim());
  }
}

class _RefsCountRow extends StatelessWidget {
  const _RefsCountRow({required this.linesFuture});

  final Future<List<Map<String, dynamic>>>? linesFuture;

  @override
  Widget build(BuildContext context) {
    if (linesFuture == null) {
      return _kvRow('Referencias totales', '—');
    }
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: linesFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _kvRow('Referencias totales', '...');
        }
        final count = (snap.data ?? const []).length;
        return _kvRow(
          'Referencias totales',
          count == 0 ? '—' : count.toString(),
        );
      },
    );
  }
}

class _ProductsBlock extends StatelessWidget {
  const _ProductsBlock({required this.sale, required this.linesFuture});
  final Map<String, dynamic> sale;
  final Future<List<Map<String, dynamic>>>? linesFuture;

  static double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  static String _money(double v) =>
      '\$${v.toStringAsFixed(v % 1 == 0 ? 0 : 2)}';

  @override
  Widget build(BuildContext context) {
    if (linesFuture == null) {
      return const Text(
        'No hay productos para mostrar.',
        style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w700),
      );
    }

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: linesFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final rows = snap.data ?? const [];
        final saleTotal = _toDouble(
          sale['totalUsd'] ?? sale['total_usd'] ?? sale['total'],
        );
        if (rows.isEmpty) {
          return const Text(
            'No hay productos para mostrar.',
            style: TextStyle(
              color: Colors.black54,
              fontWeight: FontWeight.w700,
            ),
          );
        }
        return Column(
          children: [
            for (final r in rows) ...[
              _LineTile(
                row: r,
                fallbackTxnTotalUsd: rows.length == 1 ? saleTotal : 0,
              ),
              const SizedBox(height: 10),
            ],
            if (saleTotal > 0)
              Container(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 2),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Total transacción',
                        style: TextStyle(
                          color: Colors.black54,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      _money(saleTotal),
                      style: const TextStyle(
                        color: AppTheme.navy,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _LineTile extends StatelessWidget {
  const _LineTile({required this.row, this.fallbackTxnTotalUsd = 0});
  final Map<String, dynamic> row;
  final double fallbackTxnTotalUsd;

  static double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  static double _unitSalePrice(
    Map<String, dynamic> row,
    Map<String, dynamic> product,
    double qty,
    double fallbackTxnTotalUsd,
  ) {
    final explicit = _toDouble(
      row['unitPriceUsd'] ??
          row['unitPrice'] ??
          row['priceRetailUsd'] ??
          row['priceRetail'] ??
          row['saleUnitPriceUsd'] ??
          row['salePriceUsd'] ??
          row['salePrice'] ??
          product['priceRetailUsd'] ??
          product['priceRetail'] ??
          product['salePriceUsd'] ??
          product['salePrice'] ??
          product['price'],
    );
    if (explicit > 0) return explicit;
    if (fallbackTxnTotalUsd > 0 && qty > 0) return fallbackTxnTotalUsd / qty;
    return 0;
  }

  static double _explicitSaleTotal(Map<String, dynamic> row) {
    return _toDouble(
      row['totalUsd'] ??
          row['saleTotalUsd'] ??
          row['saleLineTotalUsd'] ??
          row['subtotalUsd'] ??
          row['amountUsd'],
    );
  }

  static double _lineSaleTotal(
    Map<String, dynamic> row,
    double qty,
    double unitSalePrice,
    double fallbackTxnTotalUsd,
  ) {
    final explicitSaleTotal = _explicitSaleTotal(row);
    if (explicitSaleTotal > 0) return explicitSaleTotal;
    if (unitSalePrice > 0 && qty > 0) return qty * unitSalePrice;
    if (fallbackTxnTotalUsd > 0) return fallbackTxnTotalUsd;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final model = context.read<AppState>();
    final p = (row['product'] is Map)
        ? (row['product'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final name =
        (p['description'] ?? p['reference'] ?? p['barcode'] ?? 'Producto')
            .toString();
    final imageUrl = resolveProductLineImageUrl(row: row, state: model);
    final qty = _toDouble(row['qty']);
    final unit = _unitSalePrice(row, p, qty, fallbackTxnTotalUsd);
    final total = _lineSaleTotal(row, qty, unit, fallbackTxnTotalUsd);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6EBF2), width: 1.2),
      ),
      child: Row(
        children: [
          ProductThumb(
            imageUrl: imageUrl,
            size: 46,
            radius: 14,
            borderColor: const Color(0xFFE6EBF2),
            iconSize: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: AppTheme.navy,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${qty.toStringAsFixed(qty % 1 == 0 ? 0 : 2)} und',
                  style: const TextStyle(
                    color: Colors.black54,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '\$${total.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  color: AppTheme.navy,
                ),
              ),
              const SizedBox(height: 4),
              if (unit > 0)
                Text(
                  'Precio U. \$${unit.toStringAsFixed(0)}',
                  style: const TextStyle(
                    color: Colors.black54,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({required this.p});
  final Txn p;

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('d MMMM yyyy', 'es');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6EBF2), width: 1.2),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Fecha del abono',
                  style: TextStyle(
                    color: Colors.black54,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  dateFmt.format(p.when),
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: AppTheme.navy,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                'Valor del abono',
                style: TextStyle(
                  color: Colors.black54,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '\$${p.amount.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: AppTheme.navy,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ExpandableSection extends StatelessWidget {
  const _ExpandableSection({
    required this.title,
    required this.expanded,
    required this.onChanged,
    required this.child,
  });
  final String title;
  final bool expanded;
  final ValueChanged<bool> onChanged;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE6EBF2), width: 1.2),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: expanded,
          onExpansionChanged: onChanged,
          title: Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              color: AppTheme.navy,
            ),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
          children: [child],
        ),
      ),
    );
  }
}

Widget _kvRow(String k, String v, {Color? valueColor}) {
  return Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Row(
      children: [
        Expanded(
          child: Text(
            k,
            style: const TextStyle(
              color: Colors.black54,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            v,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: valueColor ?? AppTheme.navy,
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
        ),
      ],
    ),
  );
}

void _snack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

class _BottomAction extends StatelessWidget {
  const _BottomAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
    this.crown = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool danger;
  final bool crown;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final color = danger ? AppTheme.red : AppTheme.navy;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: danger
                            ? AppTheme.red.withValues(alpha: 0.35)
                            : const Color(0xFFE6EBF2),
                        width: 1.2,
                      ),
                    ),
                    child: Icon(icon, color: color, size: 26),
                  ),
                  if (crown)
                    Positioned(
                      top: -2,
                      right: -2,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Color(0xFF1E77D3),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.emoji_events,
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
