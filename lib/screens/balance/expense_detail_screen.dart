import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../ui/app_theme.dart';
import '../../ui/product_thumb.dart';
import '../../utils/receipt_printer.dart';
import 'receipt_download_sheet.dart';
import 'transaction_sheet.dart';

/// Detalle de un gasto:
/// - resumen principal
/// - listado de productos si la categoría viene de inventario
class ExpenseDetailScreen extends StatefulWidget {
  const ExpenseDetailScreen({
    super.key,
    required this.expense,
    required this.expenseId,
  });

  final Map<String, dynamic> expense;
  final String expenseId;

  @override
  State<ExpenseDetailScreen> createState() => _ExpenseDetailScreenState();
}

class _ExpenseDetailScreenState extends State<ExpenseDetailScreen> {
  bool _productsExpanded = false;

  Future<List<Map<String, dynamic>>>? _linesFuture;
  late Map<String, dynamic> _expense;
  late String _expenseId;

  @override
  void initState() {
    super.initState();
    _expense = Map<String, dynamic>.from(widget.expense);
    _expenseId = widget.expenseId;
  }

  static double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  String _money(double v) => '\$${v.toStringAsFixed(v % 1 == 0 ? 0 : 2)}';

  String _employeeName(AppState model, Map<String, dynamic> exp) {
    dynamic v =
        exp['employeeName'] ??
        exp['empleado'] ??
        exp['userName'] ??
        exp['createdByName'] ??
        exp['createdBy'] ??
        exp['user'];
    if (v is Map) {
      v = v['name'] ?? v['fullName'] ?? v['username'] ?? v['email'];
    }
    final s = (v ?? '').toString().trim();
    return s.isNotEmpty ? s : model.userDisplayName;
  }

  bool _looksInventoryExpense(Map<String, dynamic> expense) {
    final raw = (expense['categoryLabel'] ?? expense['category'] ?? '')
        .toString()
        .trim()
        .toUpperCase()
        .replaceAll('Á', 'A')
        .replaceAll('É', 'E')
        .replaceAll('Í', 'I')
        .replaceAll('Ó', 'O')
        .replaceAll('Ú', 'U')
        .replaceAll('Ñ', 'N')
        .replaceAll(RegExp(r'[^A-Z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return raw == 'COMPRA_PRODUCTOS_E_INSUMOS' ||
        raw == 'COMPRA_DE_PRODUCTOS_E_INSUMOS';
  }

  Map<String, dynamic> _resolveCurrentExpense(
    AppState model,
    String expenseId,
  ) {
    for (final txn in model.txnsForDay) {
      if ((txn.expenseId ?? '') != expenseId) continue;
      final expense = txn.expense;
      if (expense != null && expense.isNotEmpty) {
        return expense;
      }
    }
    return _expense;
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppState>();
    final exp = _resolveCurrentExpense(model, _expenseId);
    _expense = exp;

    final title = (exp['description'] ?? exp['concept'] ?? 'Gasto')
        .toString()
        .trim();
    final category = (exp['categoryLabel'] ?? exp['category'] ?? '')
        .toString()
        .trim();

    final totalUsd = _toDouble(
      exp['totalUsd'] ?? exp['amountUsd'] ?? exp['montoUsd'],
    );

    final related =
        model.txnsForDay
            .where((t) => (t.expenseId ?? '') == _expenseId)
            .toList()
          ..sort((a, b) => a.when.compareTo(b.when));

    final payments = related.where((t) {
      final k = (t.kind ?? '').toUpperCase();
      return k == 'GASTO' || k == 'ABONO';
    }).toList();

    final methodLabel = payments.length > 1
        ? 'Pagos múltiples'
        : (payments.isNotEmpty ? payments.first.paymentMethod : '—');

    final dtFmt = DateFormat('hh:mm a | dd MMM yyyy', 'es');
    final rawWhen = (exp['occurredAt'] ?? exp['occurred_at'] ?? '').toString();
    final parsedWhen = DateTime.tryParse(rawWhen);
    final when = parsedWhen == null
        ? (related.isNotEmpty ? related.first.when : DateTime.now())
        : (parsedWhen.isUtc ? parsedWhen.toLocal() : parsedWhen);

    final employee = _employeeName(model, exp);

    // Si este gasto viene asociado a un documento de inventario (ej: compra), mostramos sus líneas.
    final hasLinkedProducts =
        _looksInventoryExpense(exp) ||
        ((exp['inventoryDocId'] ?? exp['inventory_doc_id']) ?? '')
            .toString()
            .trim()
            .isNotEmpty ||
        ((exp['productId'] ?? exp['product_id']) ?? '')
            .toString()
            .trim()
            .isNotEmpty ||
        ((exp['product'] is Map ? exp['product']['id'] : null) ?? '')
            .toString()
            .trim()
            .isNotEmpty;
    if (_linesFuture == null && hasLinkedProducts) {
      _linesFuture = model.getExpensePurchaseLines(
        expense: exp,
        expenseId: _expenseId,
      );
    }

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
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE4E8EF), width: 1.2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Resumen del gasto',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    color: AppTheme.navy,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Transacción #${_expenseId.length <= 8 ? _expenseId : _expenseId.substring(0, 8)}',
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
                  title.isEmpty ? 'Gasto' : title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.navy,
                  ),
                ),
                const SizedBox(height: 14),
                const Divider(color: Color(0xFFE6EBF2), height: 1),
                const SizedBox(height: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Valor total',
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
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.navy,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Divider(color: Color(0xFFE6EBF2), height: 1),
                const SizedBox(height: 12),
                _SummaryInfoRow(
                  icon: Icons.calendar_month_outlined,
                  label: 'Fecha y hora',
                  value: dtFmt.format(when),
                ),
                _SummaryInfoRow(
                  icon: Icons.payments_outlined,
                  label: 'Método de pago',
                  value: methodLabel,
                ),
                _SummaryInfoRow(
                  icon: Icons.grid_view_rounded,
                  label: 'Categoría',
                  value: category.isEmpty ? '—' : category,
                ),
                _SummaryRefsRow(linesFuture: _linesFuture),
              ],
            ),
          ),

          const SizedBox(height: 12),
          if (_linesFuture != null)
            _ExpandableSection(
              title: 'Listado de productos',
              expanded: _productsExpanded,
              onChanged: (v) => setState(() => _productsExpanded = v),
              child: _ExpenseProductsBlock(linesFuture: _linesFuture),
            ),

          const SizedBox(height: 108),
        ],
      ),
      bottomNavigationBar: _BottomActions(
        actions: [
          _BottomAction(
            icon: Icons.print_outlined,
            label: 'Imprimir',
            onTap: () async {
              try {
                final lines =
                    await (_linesFuture ??
                        Future.value(const <Map<String, dynamic>>[]));
                await ReceiptPrinter.imprimirGasto(
                  expense: exp,
                  expenseId: _expenseId,
                  payments: payments,
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
                    await ReceiptPrinter.compartirGastoPdf(
                      expense: exp,
                      expenseId: _expenseId,
                      employeeName: employee,
                      payments: payments,
                      lines: lines,
                    );
                    break;
                  case ReceiptDownloadFormat.image:
                    await ReceiptPrinter.compartirGastoImagen(
                      expense: exp,
                      expenseId: _expenseId,
                      employeeName: employee,
                      payments: payments,
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
              final hasPayments = payments
                  .where((t) => (t.kind ?? '').toUpperCase() == 'ABONO')
                  .isNotEmpty;
              if (hasPayments) {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Editar gasto'),
                    content: const Text(
                      'Este gasto tiene abonos registrados.\n\nAl editar, se eliminará el gasto anterior y se creará uno nuevo con los cambios.\n\n¿Deseas continuar?',
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

              if (!context.mounted) return;

              try {
                final updatedExpenseId = await showEditarGastoSheet(
                  context,
                  expense: exp,
                  expenseId: _expenseId,
                );
                if ((updatedExpenseId ?? '').trim().isNotEmpty &&
                    context.mounted) {
                  final nextExpense = _resolveCurrentExpense(
                    model,
                    updatedExpenseId!.trim(),
                  );
                  setState(() {
                    _expenseId = updatedExpenseId.trim();
                    _expense = nextExpense;
                    _linesFuture = null;
                  });
                  _snack(context, 'Gasto actualizado');
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
                builder: (_) => AlertDialog(
                  title: const Text('Eliminar gasto'),
                  content: const Text(
                    '¿Seguro que deseas eliminar este gasto?',
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
                await model.eliminarGasto(_expenseId);
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

void _snack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE4E8EF), width: 1.2),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: () => onChanged(!expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: AppTheme.navy,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.black54,
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
              child: child,
            ),
        ],
      ),
    );
  }
}

class _SummaryRefsRow extends StatelessWidget {
  const _SummaryRefsRow({required this.linesFuture});

  final Future<List<Map<String, dynamic>>>? linesFuture;

  @override
  Widget build(BuildContext context) {
    if (linesFuture == null) return const SizedBox.shrink();

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: linesFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const _SummaryInfoRow(
            icon: Icons.inventory_2_outlined,
            label: 'Referencias totales',
            value: '...',
          );
        }
        final count = (snap.data ?? const []).length;
        return _SummaryInfoRow(
          icon: Icons.inventory_2_outlined,
          label: 'Referencias totales',
          value: count == 0 ? '—' : count.toString(),
        );
      },
    );
  }
}

class _SummaryInfoRow extends StatelessWidget {
  const _SummaryInfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: const Color(0xFF7E91A7)),
          const SizedBox(width: 14),
          SizedBox(
            width: 118,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.black54,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                color: AppTheme.navy,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpenseProductsBlock extends StatelessWidget {
  const _ExpenseProductsBlock({required this.linesFuture});
  final Future<List<Map<String, dynamic>>>? linesFuture;

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
            for (var i = 0; i < rows.length; i++) ...[
              _ExpenseLineTile(row: rows[i]),
              if (i != rows.length - 1) const SizedBox(height: 14),
            ],
          ],
        );
      },
    );
  }
}

class _ExpenseLineTile extends StatelessWidget {
  const _ExpenseLineTile({required this.row});
  final Map<String, dynamic> row;

  static double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
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
    final unitCost = _toDouble(row['unitCost']);
    final unitPrice = _toDouble(row['unitPriceUsd'] ?? row['unitPrice']);
    final unit = unitCost > 0 ? unitCost : unitPrice;
    final unitLabel = unitCost > 0 ? 'Costo U.' : 'Precio U.';
    final total = _toDouble(row['lineTotalUsd'] ?? row['totalUsd'] ?? 0);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProductThumb(
            imageUrl: imageUrl,
            size: 50,
            radius: 16,
            borderColor: const Color(0xFFE4E8EF),
            iconSize: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: AppTheme.navy,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
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
                '\u0024${total.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  color: AppTheme.navy,
                ),
              ),
              const SizedBox(height: 4),
              if (unit > 0)
                Text(
                  '$unitLabel \u0024${unit.toStringAsFixed(0)}',
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

class _BottomActions extends StatelessWidget {
  const _BottomActions({required this.actions});
  final List<_BottomAction> actions;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(
            top: BorderSide(color: const Color(0xFFE4E8EF), width: 1.2),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [for (final action in actions) Expanded(child: action)],
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
  final VoidCallback? onTap;
  final bool danger;
  final bool crown;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final color = danger ? AppTheme.red : AppTheme.navy;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 56,
                    height: 56,
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
                      right: -4,
                      top: -6,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: AppTheme.gold,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Icon(
                          Icons.workspace_premium_rounded,
                          size: 13,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 18,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: color,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
