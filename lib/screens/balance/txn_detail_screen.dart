import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/txn.dart';
import '../../state/app_state.dart';
import '../../ui/app_theme.dart';
import '../../ui/product_thumb.dart';
import '../../utils/receipt_printer.dart';
import 'receipt_download_sheet.dart';
import 'sale_detail_screen.dart';
import 'expense_detail_screen.dart';
import 'transaction_sheet.dart';

/// Detalle al tocar una transacción en Balance.
///
/// - Para VENTA: muestra el detalle del pago (si es pago parcial) + botón "Ver detalle de la venta".
/// - Para GASTO/ABONO/DEUDA: muestra el detalle completo del gasto (una sola pantalla).
class TxnDetailScreen extends StatelessWidget {
  const TxnDetailScreen({super.key, required this.txn});

  final Txn txn;

  static double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final kind = (txn.kind ?? '').toUpperCase();

    if (kind == 'VENTA' && txn.sale != null && (txn.saleId ?? '').isNotEmpty) {
      return _SalePaymentDetail(txn: txn);
    }

    // GASTO / ABONO / DEUDA: abrir el detalle completo directamente.
    final model = context.watch<AppState>();
    final exp = txn.expense ?? const <String, dynamic>{};
    final expenseId = (txn.expenseId ?? exp['id']?.toString() ?? '')
        .toString()
        .trim();

    if (expenseId.isNotEmpty) {
      Map<String, dynamic> best = exp;
      if (best.isEmpty) {
        for (final t in model.txnsForDay) {
          if ((t.expenseId ?? '') == expenseId) {
            final e = t.expense;
            if (e != null && e.isNotEmpty) {
              best = e;
              break;
            }
          }
        }
      }
      return ExpenseDetailScreen(expense: best, expenseId: expenseId);
    }

    // Si por algún motivo no hay expenseId, mantenemos un fallback simple.
    return _ExpenseTxnDetail(txn: txn);
  }
}

class _SalePaymentDetail extends StatefulWidget {
  const _SalePaymentDetail({required this.txn});
  final Txn txn;

  @override
  State<_SalePaymentDetail> createState() => _SalePaymentDetailState();
}

class _SalePaymentDetailState extends State<_SalePaymentDetail> {
  bool _productsExpanded = false;
  Future<List<Map<String, dynamic>>>? _linesFuture;

  String _employeeName(AppState model, Map<String, dynamic> sale) {
    dynamic v =
        sale['employeeName'] ??
        sale['empleado'] ??
        sale['userName'] ??
        sale['createdByName'] ??
        sale['createdBy'] ??
        sale['user'];
    if (v is Map) {
      v = v['name'] ?? v['fullName'] ?? v['username'] ?? v['email'];
    }
    final s = (v ?? '').toString().trim();
    return s.isNotEmpty ? s : model.userDisplayName;
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppState>();
    final sale = widget.txn.sale ?? const <String, dynamic>{};
    final saleId = widget.txn.saleId ?? '';
    _linesFuture ??= _buildLinesFuture(context, sale);
    final totalUsd = TxnDetailScreen._toDouble(sale['totalUsd']);
    final cogsUsd = TxnDetailScreen._toDouble(sale['cogsUsd']);
    final profit = (totalUsd - cogsUsd);

    final related =
        model.txnsForDay
            .where(
              (t) =>
                  (t.kind ?? '').toUpperCase() == 'VENTA' &&
                  (t.saleId ?? '') == saleId,
            )
            .toList()
          ..sort((a, b) => a.when.compareTo(b.when));

    final isPartial =
        related.length > 1 ||
        (totalUsd > 0 && (widget.txn.amount + 0.000001) < totalUsd);

    final occurredAt = widget.txn.when;
    final dtFmt = DateFormat('hh:mm a | dd MMM yyyy', 'es');

    final baseTitle =
        (sale['description'] ?? sale['concept'] ?? widget.txn.note ?? 'Venta')
            .toString()
            .trim();
    final title = isPartial
        ? 'Pago parcial (${baseTitle.isEmpty ? 'Venta' : baseTitle})'
        : baseTitle;

    final employee = _employeeName(model, sale);

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
          _SummaryCard(
            headerTitle: 'Resumen de la venta',
            headerSubtitle: _compactTxnId(widget.txn.id),
            conceptLabel: title.isEmpty ? 'Venta' : title,
            amountLabel: isPartial ? 'Pago' : 'Valor total',
            amountUsd: widget.txn.amount,
            badgeText: 'Pagada',
            badgeColor: AppTheme.green,
            rows: [
              _kv('Fecha y hora', dtFmt.format(occurredAt)),
              _kv('Método de pago', widget.txn.paymentMethod),
              if (employee.trim().isNotEmpty && employee.trim() != '—')
                _kv('Empleado', employee),
              if (isPartial)
                _kv(
                  'Total venta',
                  _money(totalUsd),
                  valueColor: AppTheme.green,
                ),
              _kv('Ganancia', _money(profit), valueColor: AppTheme.green),
            ],
          ),
          const SizedBox(height: 12),

          if (isPartial)
            _PrimaryLinkCard(
              text: 'Ver detalle de la venta',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        SaleDetailScreen(sale: sale, saleId: saleId),
                  ),
                );
              },
            ),

          if (!isPartial)
            _ExpandableSection(
              title: 'Listado de productos',
              expanded: _productsExpanded,
              onChanged: (v) => setState(() => _productsExpanded = v),
              child: _SaleProductsBlock(sale: sale),
            ),

          const SizedBox(height: 90),
        ],
      ),
      bottomNavigationBar: _BottomActions(
        actions: [
          _BottomAction(
            icon: Icons.print,
            label: 'Imprimir',
            onTap: () async {
              try {
                final lines =
                    await (_linesFuture ??
                        Future.value(const <Map<String, dynamic>>[]));
                await ReceiptPrinter.imprimirPagoVenta(
                  txn: widget.txn,
                  sale: sale,
                  employeeName: employee,
                  lines: lines,
                );
              } catch (_) {
                if (!context.mounted) return;
                _snack(context, 'No se pudo imprimir el comprobante');
              }
            },
          ),
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
                    await ReceiptPrinter.compartirPagoVentaPdf(
                      txn: widget.txn,
                      sale: sale,
                      employeeName: employee,
                      lines: lines,
                    );
                    break;
                  case ReceiptDownloadFormat.image:
                    await ReceiptPrinter.compartirPagoVentaImagen(
                      txn: widget.txn,
                      sale: sale,
                      employeeName: employee,
                      lines: lines,
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
            onTap: () async {
              if (isPartial) {
                // Para pagos parciales, se edita desde la venta completa.
                if (!context.mounted) return;
                _snack(
                  context,
                  'Para editar, abre el detalle completo de la venta.',
                );
                return;
              }
              try {
                final saved = await showEditarVentaSheet(
                  context,
                  sale: sale,
                  saleId: saleId,
                );
                if (saved == true && context.mounted) {
                  _snack(context, 'Venta actualizada');
                  Navigator.pop(context);
                }
              } catch (_) {
                if (!context.mounted) return;
                _snack(context, 'No se pudo abrir la edición');
              }
            },
          ),
          _BottomAction(
            icon: Icons.delete,
            label: 'Eliminar',
            danger: true,
            onTap: () async {
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
                        onPressed: () => Navigator.pop(context, false),
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
                if (!context.mounted) return;
                final state = context.read<AppState>();
                await state.eliminarVenta(saleId);
                if (!context.mounted) return;
                _snack(context, 'Venta eliminada');
                Navigator.pop(context);
              } catch (_) {
                if (!context.mounted) return;
                _snack(context, 'No se pudo eliminar la venta');
              }
            },
          ),
        ],
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

class _ExpenseTxnDetail extends StatelessWidget {
  const _ExpenseTxnDetail({required this.txn});
  final Txn txn;

  String _resolvePaymentCode(AppState model, String label) {
    final raw = label.trim();
    if (raw.isEmpty) return 'CASH';
    final up = raw.toUpperCase();
    for (final m in model.paymentMethods) {
      if (m.code.toUpperCase() == up) return m.code;
      if (m.name.toUpperCase() == up) return m.code;
    }
    // Best-effort: convertir a estilo CODE
    final guess = up.replaceAll(RegExp(r'\s+'), '_');
    return guess.isEmpty ? 'CASH' : guess;
  }

  List<Map<String, dynamic>> _prefillPayments(
    AppState model,
    String expenseId,
    bool isDebt,
  ) {
    final related = model.txnsForDay
        .where((t) => (t.expenseId ?? '') == expenseId)
        .toList();
    related.sort((a, b) => a.when.compareTo(b.when));

    final wantedKind = isDebt ? 'ABONO' : 'GASTO';
    final rows = related
        .where((t) => (t.kind ?? '').toUpperCase() == wantedKind)
        .toList();
    if (rows.isEmpty &&
        txn.paymentMethod.trim().isNotEmpty &&
        txn.paymentMethod != '—') {
      // Fallback: usar el pago actual.
      return [
        {
          'paymentMethodCode': _resolvePaymentCode(model, txn.paymentMethod),
          'amountUsd': txn.amount,
          'concept': 'Gasto',
          'receiptNote': '',
        },
      ];
    }

    return rows
        .map(
          (t) => {
            'paymentMethodCode': _resolvePaymentCode(model, t.paymentMethod),
            'amountUsd': t.amount,
            'concept': 'Gasto',
            'receiptNote': '',
          },
        )
        .toList();
  }

  static double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppState>();
    final exp = txn.expense ?? const <String, dynamic>{};
    final kind = (txn.kind ?? '').toUpperCase();
    final dtFmt = DateFormat('hh:mm a | dd MMM yyyy', 'es');
    final occurredAt = txn.when;

    final statusLabel = (exp['statusLabel'] ?? exp['status'] ?? '').toString();
    final categoryLabel = (exp['categoryLabel'] ?? exp['category'] ?? '')
        .toString();
    final title = (exp['description'] ?? exp['concept'] ?? txn.note ?? 'Gasto')
        .toString();

    final totalUsd = _toDouble(exp['totalUsd'] ?? exp['amountUsd']);
    final outstandingUsd = _toDouble(exp['outstandingUsd']);

    final badgeText =
        kind == 'DEUDA' || statusLabel.toUpperCase().contains('DEUDA')
        ? 'Deuda'
        : 'Pagado';
    final badgeColor = badgeText == 'Deuda' ? AppTheme.red : AppTheme.green;

    final expenseId = (txn.expenseId ?? exp['id']?.toString() ?? '')
        .toString()
        .trim();
    final isDebt = badgeText == 'Deuda';
    final hasPayments =
        (outstandingUsd > 0 &&
            totalUsd > 0 &&
            (totalUsd - outstandingUsd) > 0.01) ||
        kind == 'ABONO';

    dynamic ev =
        exp['employeeName'] ??
        exp['empleado'] ??
        exp['userName'] ??
        exp['createdByName'] ??
        exp['createdBy'] ??
        exp['user'];
    if (ev is Map) {
      ev = ev['name'] ?? ev['fullName'] ?? ev['username'] ?? ev['email'];
    }
    final employee = (ev ?? '').toString().trim().isNotEmpty
        ? ev.toString().trim()
        : model.userDisplayName;

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
          'Detalle del gasto',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _SummaryCard(
            headerTitle: 'Resumen del gasto',
            headerSubtitle: _compactTxnId(txn.id),
            conceptLabel: title,
            amountLabel: kind == 'ABONO' ? 'Abono' : 'Valor',
            amountUsd: txn.amount,
            badgeText: badgeText,
            badgeColor: badgeColor,
            rows: [
              if (categoryLabel.trim().isNotEmpty)
                _kv('Categoría', categoryLabel),
              _kv('Fecha y hora', dtFmt.format(occurredAt)),
              if (txn.paymentMethod.trim().isNotEmpty &&
                  txn.paymentMethod != '—')
                _kv('Método de pago', txn.paymentMethod),
              if (employee.trim().isNotEmpty && employee.trim() != '—')
                _kv('Empleado', employee),
              if (totalUsd > 0 && kind == 'ABONO')
                _kv(
                  'Total del gasto',
                  _money(totalUsd),
                  valueColor: AppTheme.navy,
                ),
              if (outstandingUsd > 0)
                _kv(
                  'Pendiente',
                  _money(outstandingUsd),
                  valueColor: AppTheme.red,
                ),
            ],
          ),
          // Importante: no mostramos un segundo detalle aquí.
          // Al tocar el gasto desde el listado se abre directamente la pantalla de detalle completo.
          const SizedBox(height: 90),
        ],
      ),
      bottomNavigationBar: _BottomActions(
        actions: [
          _BottomAction(
            icon: Icons.receipt_long,
            label: 'Comprobante',
            crown: true,
            onTap: () async {
              if (expenseId.isEmpty) {
                _snack(context, 'No se pudo generar el comprobante');
                return;
              }
              try {
                final format = await showReceiptDownloadSheet(context);
                if (format == null || !context.mounted) return;
                final lines = await model.getExpensePurchaseLines(
                  expense: exp,
                  expenseId: expenseId,
                );
                switch (format) {
                  case ReceiptDownloadFormat.pdf:
                    await ReceiptPrinter.compartirGastoPdf(
                      expense: exp,
                      expenseId: expenseId,
                      payments: model.txnsForDay
                          .where((t) => (t.expenseId ?? '') == expenseId)
                          .toList(),
                      employeeName: employee,
                      lines: lines,
                    );
                    break;
                  case ReceiptDownloadFormat.image:
                    await ReceiptPrinter.compartirGastoImagen(
                      expense: exp,
                      expenseId: expenseId,
                      payments: model.txnsForDay
                          .where((t) => (t.expenseId ?? '') == expenseId)
                          .toList(),
                      employeeName: employee,
                      lines: lines,
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
            onTap: () async {
              if (expenseId.isEmpty) {
                _snack(context, 'No se pudo editar: gasto sin id');
                return;
              }

              // Advertencia si hay abonos/pagos: editar recrea el gasto.
              if (hasPayments) {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Editar gasto'),
                    content: const Text(
                      'Este gasto tiene pagos/abonos registrados.\n\nAl editar, se eliminará el gasto anterior y se creará uno nuevo con los cambios.\n\n¿Deseas continuar?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancelar'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Continuar'),
                      ),
                    ],
                  ),
                );
                if (ok != true) return;
              }

              try {
                if (!context.mounted) return;
                final updatedExpenseId = await showEditarGastoSheet(
                  context,
                  expense: exp,
                  expenseId: expenseId,
                  prefillPayments: _prefillPayments(model, expenseId, isDebt),
                );
                if ((updatedExpenseId ?? '').trim().isNotEmpty &&
                    context.mounted) {
                  _snack(context, 'Gasto actualizado');
                  Navigator.pop(context);
                }
              } catch (_) {
                if (!context.mounted) return;
                _snack(context, 'No se pudo abrir la edición');
              }
            },
          ),
          _BottomAction(
            icon: Icons.delete,
            label: 'Eliminar',
            danger: true,
            onTap: () async {
              if (expenseId.isEmpty) {
                _snack(context, 'No se pudo eliminar: gasto sin id');
                return;
              }

              final ok = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Eliminar gasto'),
                  content: const Text(
                    '¿Seguro que deseas eliminar este gasto?\n\nSe eliminarán también sus pagos/abonos asociados.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancelar'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Eliminar'),
                    ),
                  ],
                ),
              );
              if (ok != true) return;

              try {
                if (!context.mounted) return;
                final state = context.read<AppState>();
                await state.eliminarGasto(expenseId);
                if (!context.mounted) return;
                _snack(context, 'Gasto eliminado');
                Navigator.pop(context);
              } catch (_) {
                if (!context.mounted) return;
                _snack(context, 'No se pudo eliminar el gasto');
              }
            },
          ),
        ],
      ),
    );
  }
}

class _SaleProductsBlock extends StatelessWidget {
  const _SaleProductsBlock({required this.sale});
  final Map<String, dynamic> sale;

  static double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  static String _money(double v) =>
      '\$${v.toStringAsFixed(v % 1 == 0 ? 0 : 2)}';

  @override
  Widget build(BuildContext context) {
    final docId = (sale['inventoryDocId'] ?? sale['inventory_doc_id'])
        ?.toString();
    if (docId == null || docId.trim().isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 6),
        child: Text(
          'No hay productos para mostrar.',
          style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w700),
        ),
      );
    }

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: context.read<AppState>().getInventoryDocLines(docId.trim()),
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
          return const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'No hay productos para mostrar.',
              style: TextStyle(
                color: Colors.black54,
                fontWeight: FontWeight.w700,
              ),
            ),
          );
        }

        return Column(
          children: [
            for (final r in rows) ...[
              _ProductLineTile(
                row: r,
                fallbackTxnTotalUsd: rows.length == 1 ? saleTotal : 0,
              ),
              const SizedBox(height: 10),
            ],
            if (saleTotal > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 2, 12, 0),
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

class _ProductLineTile extends StatelessWidget {
  const _ProductLineTile({required this.row, this.fallbackTxnTotalUsd = 0});
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
                _money(total),
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  color: AppTheme.navy,
                ),
              ),
              const SizedBox(height: 4),
              if (unit > 0)
                Text(
                  'Precio U. ${_money(unit)}',
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

class _PrimaryLinkCard extends StatelessWidget {
  const _PrimaryLinkCard({required this.text, required this.onTap});
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE6EBF2), width: 1.2),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: AppTheme.gold,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right, color: AppTheme.gold),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.headerTitle,
    required this.headerSubtitle,
    required this.conceptLabel,
    required this.amountLabel,
    required this.amountUsd,
    required this.badgeText,
    required this.badgeColor,
    required this.rows,
  });

  final String headerTitle;
  final String headerSubtitle;
  final String conceptLabel;
  final String amountLabel;
  final double amountUsd;
  final String badgeText;
  final Color badgeColor;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE6EBF2), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            headerTitle,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 18,
              color: AppTheme.navy,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            headerSubtitle,
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
            conceptLabel,
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
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      amountLabel,
                      style: const TextStyle(
                        color: Colors.black54,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _money(amountUsd),
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
                  color: badgeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(
                    color: badgeColor,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(color: Color(0xFFE6EBF2), height: 1),
          const SizedBox(height: 12),
          ...rows,
        ],
      ),
    );
  }
}

Widget _kv(String k, String v, {Color? valueColor}) {
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

String _money(double v) => '\$${v.toStringAsFixed(v % 1 == 0 ? 0 : 2)}';

String _compactTxnId(String id) {
  final s = id.trim();
  if (s.isEmpty) return 'Transacción';
  // Para que se vea tipo "Transacción #9" si es numérico, o recorta uuid.
  final onlyDigits = RegExp(r'^\d+$');
  if (onlyDigits.hasMatch(s)) return 'Transacción #$s';
  return 'Transacción • ${s.length <= 8 ? s : s.substring(0, 8)}';
}

void _snack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

class _BottomActions extends StatelessWidget {
  const _BottomActions({required this.actions});
  final List<_BottomAction> actions;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE6EBF2), width: 1.2)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: actions,
        ),
      ),
    );
  }
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
  final VoidCallback onTap;
  final bool danger;
  final bool crown;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppTheme.red : AppTheme.navy;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
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
    );
  }
}
