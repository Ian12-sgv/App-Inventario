// ignore_for_file: unused_element_parameter

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/product.dart';
import '../../state/app_state.dart';
import '../../ui/app_theme.dart';
import '../../ui/input_formatters.dart';
import 'expense_flow.dart';
import 'free_sale_flow.dart';
import 'product_sale_flow.dart';

String _humanizeDioError(Object e) {
  if (e is DioException) {
    final data = e.response?.data;
    if (data is Map) {
      final message = data['message'];
      if (message is List) {
        final joined = message
            .map((x) => x.toString())
            .where((x) => x.trim().isNotEmpty)
            .join(' | ');
        if (joined.trim().isNotEmpty) return joined;
      }
      if (message != null && message.toString().trim().isNotEmpty) {
        return message.toString();
      }
      final err = data['error'];
      if (err != null && err.toString().trim().isNotEmpty) {
        return err.toString();
      }
    }
    return e.message ?? 'Error de red';
  }
  final msg = e.toString();
  if (msg.startsWith('Bad state: ')) return msg.substring('Bad state: '.length);
  return msg;
}

const double _lowStockThreshold = 3;
const String _inventoryExpenseCategoryCode = 'COMPRA_PRODUCTOS_E_INSUMOS';
const Set<String> _inventoryExpenseCategoryAliases = {
  _inventoryExpenseCategoryCode,
  'COMPRA_DE_PRODUCTOS_E_INSUMOS',
};

bool _isLowStock(double stock) => stock < _lowStockThreshold;

String _normalizeExpenseCategoryKey(String? raw) {
  var value = (raw ?? '').trim().toUpperCase();
  if (value.isEmpty) return '';
  const replacements = {
    'Á': 'A',
    'É': 'E',
    'Í': 'I',
    'Ó': 'O',
    'Ú': 'U',
    'Ñ': 'N',
  };
  replacements.forEach((from, to) {
    value = value.replaceAll(from, to);
  });
  value = value.replaceAll(RegExp(r'[^A-Z0-9]+'), '_');
  value = value.replaceAll(RegExp(r'_+'), '_');
  value = value.replaceAll(RegExp(r'^_|_$'), '');
  return value;
}

bool _isInventoryExpenseCategory(String? category) {
  return _inventoryExpenseCategoryAliases.contains(
    _normalizeExpenseCategoryKey(category),
  );
}

String _expenseCategoryPayloadValue(String? category) {
  final raw = (category ?? '').trim();
  if (raw.isEmpty) return raw;
  return _isInventoryExpenseCategory(raw) ? _inventoryExpenseCategoryCode : raw;
}

Future<void> showNuevaVentaSheet(BuildContext context) async {
  final tipo = await showModalBottomSheet<_TipoVenta>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => const _VentaTypePickerSheet(),
  );
  if (tipo == null || !context.mounted) return;
  if (tipo == _TipoVenta.inventario) {
    await showProductSaleFlow(context);
    return;
  }
  await showFreeSaleFlow(context);
}

Future<bool?> showEditarVentaSheet(
  BuildContext context, {
  required Map<String, dynamic> sale,
  required String saleId,
}) async {
  final state = context.read<AppState>();
  if (_isInventorySale(sale)) {
    var lineRows = _extractInventorySaleRows(sale);
    if (lineRows.isEmpty) {
      final docId = (sale['inventoryDocId'] ?? sale['inventory_doc_id'])
          ?.toString()
          .trim();
      if (docId != null && docId.isNotEmpty) {
        try {
          lineRows = await state.getInventoryDocLines(docId);
        } catch (_) {}
      }
    }
    if (!context.mounted) return null;
    return showEditProductSaleFlow(
      context,
      sale: sale,
      saleId: saleId,
      lineRows: lineRows,
    );
  }

  final prefillPayments = _prefillSalePayments(state, saleId, sale);
  if (!context.mounted) return null;
  return await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => _VentaSheet(
      isEdit: true,
      existingSale: sale,
      saleId: saleId,
      prefillPayments: prefillPayments,
      initialType: _TipoVenta.libre,
      showTypeSelector: false,
    ),
  );
}

bool _isInventorySale(Map<String, dynamic> sale) {
  final rawType =
      sale['saleType'] ?? sale['sale_type'] ?? sale['type'] ?? sale['kind'];
  final saleType = (rawType ?? '').toString().trim().toUpperCase();
  if (saleType.contains('LIBRE')) return false;
  if (saleType.contains('INVENT')) return true;

  final docId = (sale['inventoryDocId'] ?? sale['inventory_doc_id'])
      ?.toString()
      .trim();
  if ((docId ?? '').isNotEmpty) return true;

  final rows = _extractInventorySaleRows(sale);
  return rows.isNotEmpty;
}

List<Map<String, dynamic>> _extractInventorySaleRows(
  Map<String, dynamic> sale,
) {
  for (final key in const ['items', 'lines', 'products']) {
    final raw = sale[key];
    if (raw is! List) continue;
    final rows = raw.whereType<Map>().map((row) {
      return row.cast<String, dynamic>();
    }).toList();
    if (rows.isNotEmpty) return rows;
  }
  return const [];
}

bool _saleLooksDebt(Map<String, dynamic> sale) {
  final status = (sale['status'] ?? '').toString().trim().toUpperCase();
  final statusLabel = (sale['statusLabel'] ?? '')
      .toString()
      .trim()
      .toUpperCase();
  return status.contains('DEBT') ||
      status.contains('DEUDA') ||
      statusLabel.contains('DEBT') ||
      statusLabel.contains('DEUDA');
}

String _resolveSalePaymentCode(AppState model, String label) {
  final raw = label.trim();
  if (raw.isEmpty) return 'CASH';
  final up = raw.toUpperCase();
  for (final method in model.paymentMethods) {
    if (method.code.toUpperCase() == up) return method.code;
    if (method.name.toUpperCase() == up) return method.code;
  }
  final guess = up.replaceAll(RegExp(r'\s+'), '_');
  return guess.isEmpty ? 'CASH' : guess;
}

List<Map<String, dynamic>> _prefillSalePayments(
  AppState model,
  String saleId,
  Map<String, dynamic> sale,
) {
  final related =
      model.txnsForDay.where((txn) => (txn.saleId ?? '') == saleId).toList()
        ..sort((a, b) => a.when.compareTo(b.when));
  final isDebt = _saleLooksDebt(sale);
  final wantedKind = isDebt ? 'ABONO' : 'VENTA';
  final rows = related
      .where((txn) => (txn.kind ?? '').toUpperCase() == wantedKind)
      .toList();
  if (rows.isEmpty && isDebt) return const [];
  final source = rows.isNotEmpty ? rows : related;

  return source
      .map(
        (txn) => {
          'paymentMethodCode': _resolveSalePaymentCode(
            model,
            txn.paymentMethod,
          ),
          'amountUsd': txn.amount,
          'concept': (sale['description'] ?? sale['concept'] ?? 'Venta')
              .toString()
              .trim(),
          'receiptNote': (sale['receiptNote'] ?? '').toString(),
        },
      )
      .toList();
}

Future<void> showNuevoGastoSheet(BuildContext context) async {
  await showExpenseFlow(context);
}

String _resolveExpensePaymentCode(AppState model, String label) {
  final raw = label.trim();
  if (raw.isEmpty) return 'CASH';
  final up = raw.toUpperCase();
  for (final method in model.paymentMethods) {
    if (method.code.toUpperCase() == up) return method.code;
    if (method.name.toUpperCase() == up) return method.code;
  }
  final guess = up.replaceAll(RegExp(r'\s+'), '_');
  return guess.isEmpty ? 'CASH' : guess;
}

bool _expenseLooksDebt(Map<String, dynamic> expense) {
  final status = (expense['status'] ?? '').toString().trim().toUpperCase();
  final statusLabel = (expense['statusLabel'] ?? '')
      .toString()
      .trim()
      .toUpperCase();
  return status.contains('DEBT') ||
      status.contains('DEUDA') ||
      statusLabel.contains('DEBT') ||
      statusLabel.contains('DEUDA');
}

List<Map<String, dynamic>> _prefillExpensePayments(
  AppState model,
  String expenseId,
  Map<String, dynamic> expense,
) {
  final related =
      model.txnsForDay
          .where((txn) => (txn.expenseId ?? '') == expenseId)
          .toList()
        ..sort((a, b) => a.when.compareTo(b.when));
  final isDebt = _expenseLooksDebt(expense);
  final wantedKind = isDebt ? 'ABONO' : 'GASTO';
  final rows = related
      .where((txn) => (txn.kind ?? '').toUpperCase() == wantedKind)
      .toList();
  if (rows.isEmpty && isDebt) return const [];
  final source = rows.isNotEmpty ? rows : related;
  if (source.isNotEmpty) {
    return source
        .map(
          (txn) => {
            'paymentMethodCode': _resolveExpensePaymentCode(
              model,
              txn.paymentMethod,
            ),
            'amountUsd': txn.amount,
            'concept': (expense['description'] ?? expense['concept'] ?? 'Gasto')
                .toString()
                .trim(),
            'receiptNote': (expense['receiptNote'] ?? '').toString(),
          },
        )
        .toList();
  }

  final method =
      (expense['paymentMethodCode'] ??
              expense['paymentMethodName'] ??
              expense['paymentMethod'] ??
              expense['metodoPago'] ??
              '')
          .toString()
          .trim();
  if (method.isEmpty || isDebt) return const [];
  return [
    {
      'paymentMethodCode': _resolveExpensePaymentCode(model, method),
      'amountUsd':
          (expense['totalUsd'] ??
              expense['amountUsd'] ??
              expense['montoUsd']) ??
          0,
      'concept': (expense['description'] ?? expense['concept'] ?? 'Gasto')
          .toString()
          .trim(),
      'receiptNote': (expense['receiptNote'] ?? '').toString(),
    },
  ];
}

Future<String?> showEditarGastoSheet(
  BuildContext context, {
  required Map<String, dynamic> expense,
  required String expenseId,
  List<Map<String, dynamic>>? prefillPayments,
}) async {
  final state = context.read<AppState>();
  final payments =
      prefillPayments ?? _prefillExpensePayments(state, expenseId, expense);
  final lineRows = await state.getExpensePurchaseLines(
    expense: expense,
    expenseId: expenseId,
  );
  if (!context.mounted) return null;
  return showEditExpenseFlow(
    context,
    expense: expense,
    expenseId: expenseId,
    prefillPayments: payments,
    lineRows: lineRows,
  );
}

class _SheetScrollContainer extends StatelessWidget {
  const _SheetScrollContainer({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.9;

    return SafeArea(
      top: false,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: bottomInset),
        child: SizedBox(
          height: maxHeight,
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: child,
          ),
        ),
      ),
    );
  }
}

enum _TipoVenta { inventario, libre }

class _VentaTypePickerSheet extends StatelessWidget {
  const _VentaTypePickerSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Nueva venta',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.navy,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Selecciona el tipo de venta que quieres hacer.',
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.35,
                          color: Color(0xFF667085),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 40,
                  height: 40,
                  child: IconButton(
                    onPressed: () => Navigator.pop(context),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF6F8093),
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.close_rounded, size: 20),
                    tooltip: 'Cerrar',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            _VentaTypeOptionCard(
              title: 'Venta de productos',
              subtitle:
                  'Registra una venta seleccionando los productos de tu inventario.',
              icon: Icons.shopping_basket_rounded,
              iconBackgroundColor: const Color(0xFFF7E6A6),
              iconColor: const Color(0xFF9C6B09),
              onTap: () => Navigator.pop(context, _TipoVenta.inventario),
            ),
            const SizedBox(height: 14),
            _VentaTypeOptionCard(
              title: 'Venta libre',
              subtitle:
                  'Registra un ingreso sin seleccionar productos de tu inventario.',
              icon: Icons.payments_rounded,
              iconBackgroundColor: const Color(0xFFDDE3EA),
              iconColor: const Color(0xFF1F9D55),
              onTap: () => Navigator.pop(context, _TipoVenta.libre),
            ),
          ],
        ),
      ),
    );
  }
}

class _VentaTypeOptionCard extends StatelessWidget {
  const _VentaTypeOptionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconBackgroundColor,
    required this.iconColor,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconBackgroundColor;
  final Color iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFE6EBF2)),
          ),
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 78,
                height: 78,
                decoration: BoxDecoration(
                  color: iconBackgroundColor,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(icon, size: 36, color: iconColor),
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
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.35,
                        color: Color(0xFF667085),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF8091A7),
                size: 34,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SaleLine {
  final String productId;
  final String name;
  final double stock;
  double qty;
  double unitPriceUsd;

  _SaleLine({
    required this.productId,
    required this.name,
    required this.stock,
    required this.qty,
    required this.unitPriceUsd,
  });

  double get subtotal => qty * unitPriceUsd;
}

class _PaymentRow {
  String methodCode;
  double amountUsd;
  String concept;
  String receiptNote;

  _PaymentRow({
    required this.methodCode,
    required this.amountUsd,
    required this.concept,
    required this.receiptNote,
  });
}

class _VentaSheet extends StatefulWidget {
  const _VentaSheet({
    this.isEdit = false,
    this.existingSale,
    this.saleId,
    this.prefillPayments,
    this.initialType = _TipoVenta.inventario,
    this.showTypeSelector = true,
  });

  final bool isEdit;
  final Map<String, dynamic>? existingSale;
  final String? saleId;
  final List<Map<String, dynamic>>? prefillPayments;
  final _TipoVenta initialType;
  final bool showTypeSelector;

  @override
  State<_VentaSheet> createState() => _VentaSheetState();
}

class _VentaSheetState extends State<_VentaSheet> {
  _TipoVenta _tipo = _TipoVenta.inventario;
  DateTime? _occurredAt;
  bool _allowEmptyPayments = false;

  final _totalLibreCtl = TextEditingController();
  final _discountPctCtl = TextEditingController();
  final _discountUsdCtl = TextEditingController();

  final _notaCtl = TextEditingController();
  final _notaComprobanteCtl = TextEditingController();

  final List<_SaleLine> _lines = [];
  final List<_PaymentRow> _payments = [];

  static double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  @override
  void initState() {
    super.initState();
    _tipo = widget.initialType;

    final p = widget.prefillPayments;
    if (p != null && p.isNotEmpty) {
      _payments.clear();
      for (final row in p) {
        _payments.add(
          _PaymentRow(
            methodCode:
                (row['paymentMethodCode'] ?? row['methodCode'] ?? 'CASH')
                    .toString(),
            amountUsd: _toDouble(row['amountUsd'] ?? row['amount'] ?? 0),
            concept: (row['concept'] ?? 'Venta').toString(),
            receiptNote: (row['receiptNote'] ?? '').toString(),
          ),
        );
      }
    }

    final rawType =
        widget.existingSale?['saleType'] ??
        widget.existingSale?['sale_type'] ??
        widget.existingSale?['type'];
    final saleType = (rawType ?? '').toString().trim().toUpperCase();
    if (saleType.contains('LIBRE')) {
      _tipo = _TipoVenta.libre;
    } else if (saleType.contains('INVENT')) {
      _tipo = _TipoVenta.inventario;
    }
    final raw =
        widget.existingSale?['occurredAt'] ??
        widget.existingSale?['occurred_at'];
    if (raw is DateTime) {
      _occurredAt = raw.isUtc ? raw.toLocal() : raw;
    } else {
      final parsed = raw == null ? null : DateTime.tryParse(raw.toString());
      _occurredAt = parsed == null
          ? DateTime.now()
          : (parsed.isUtc ? parsed.toLocal() : parsed);
    }

    final sale = widget.existingSale;
    if (widget.isEdit && sale != null) {
      final total = _toDouble(
        sale['totalUsd'] ?? sale['total_usd'] ?? sale['total'],
      );
      if (_tipo == _TipoVenta.libre && total > 0) {
        _totalLibreCtl.text = total.toStringAsFixed(total % 1 == 0 ? 0 : 2);
      }

      final discountPct = _toDouble(
        sale['discountPercent'] ?? sale['discount_percent'],
      );
      final discountUsd = _toDouble(
        sale['discountUsd'] ?? sale['discount_usd'],
      );
      if (discountPct > 0) {
        _discountPctCtl.text = discountPct.toStringAsFixed(
          discountPct % 1 == 0 ? 0 : 2,
        );
      } else if (discountUsd > 0) {
        _discountUsdCtl.text = discountUsd.toStringAsFixed(
          discountUsd % 1 == 0 ? 0 : 2,
        );
      }

      _notaCtl.text = (sale['description'] ?? sale['concept'] ?? '')
          .toString()
          .trim();
      _notaComprobanteCtl.text = (sale['receiptNote'] ?? '').toString().trim();

      _allowEmptyPayments = _saleLooksDebt(sale);
    }
  }

  @override
  void dispose() {
    _totalLibreCtl.dispose();
    _discountPctCtl.dispose();
    _discountUsdCtl.dispose();
    _notaCtl.dispose();
    _notaComprobanteCtl.dispose();
    super.dispose();
  }

  double _num(TextEditingController c) =>
      double.tryParse(c.text.replaceAll(',', '.').trim()) ?? 0;

  String get _sheetTitle {
    if (widget.isEdit) return 'Editar venta';
    if (widget.showTypeSelector) return 'Nueva venta';
    return _tipo == _TipoVenta.inventario
        ? 'Venta de productos'
        : 'Venta libre';
  }

  double get _subtotal {
    if (_tipo == _TipoVenta.libre) return _num(_totalLibreCtl);
    return _lines.fold(0.0, (a, l) => a + l.subtotal);
  }

  double get _discountUsd {
    final pct = _num(_discountPctCtl);
    final usd = _num(_discountUsdCtl);
    if (pct > 0) return (_subtotal * pct / 100).clamp(0, _subtotal);
    if (usd > 0) return usd.clamp(0, _subtotal);
    return 0;
  }

  double get _total => (_subtotal - _discountUsd).clamp(0, double.infinity);

  double get _paymentsSum => _payments.fold(0.0, (a, p) => a + p.amountUsd);

  bool _almostEq(double a, double b) => (a - b).abs() <= 0.01;

  void _ensureDefaultPayment(AppState state) {
    if (_payments.isNotEmpty) return;
    if (_allowEmptyPayments) return;
    final first = state.paymentMethods.isNotEmpty
        ? state.paymentMethods.first
        : null;
    _payments.add(
      _PaymentRow(
        methodCode: first?.code ?? 'CASH',
        amountUsd: 0,
        concept: 'Venta',
        receiptNote: '',
      ),
    );
  }

  Future<void> _pickProducts() async {
    final state = context.read<AppState>();
    final selected = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => _ProductPicker(
        products: state.products,
        selectedIds: _lines.map((e) => e.productId).toSet(),
      ),
    );

    if (selected == null) return;

    final byId = {for (final p in state.products) p.id: p};
    for (final id in selected) {
      final p = byId[id];
      if (p == null) continue;
      if (_lines.any((l) => l.productId == id)) continue;
      _lines.add(
        _SaleLine(
          productId: p.id,
          name: p.name,
          stock: p.stock,
          qty: 1,
          unitPriceUsd: p.priceRetailUsd,
        ),
      );
    }

    setState(() {});
  }

  Future<void> _submit() async {
    final state = context.read<AppState>();

    if (_tipo == _TipoVenta.inventario && _lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona al menos un producto.')),
      );
      return;
    }

    if (_tipo == _TipoVenta.inventario &&
        (state.warehouseId ?? '').trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No hay bodega seleccionada. Actualiza inventario o inicia sesión nuevamente.',
          ),
        ),
      );
      return;
    }

    if (_subtotal <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El valor de la venta debe ser mayor a 0.'),
        ),
      );
      return;
    }

    if (_payments.isEmpty && !_allowEmptyPayments) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agrega al menos un método de pago.')),
      );
      return;
    }

    if (_payments.isNotEmpty && !_almostEq(_paymentsSum, _total)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'La suma de pagos (\$${_paymentsSum.toStringAsFixed(2)}) no coincide con el total (\$${_total.toStringAsFixed(2)}).',
          ),
        ),
      );
      return;
    }

    if (_tipo == _TipoVenta.inventario) {
      for (final l in _lines) {
        if (l.qty <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cantidad inválida en un producto.')),
          );
          return;
        }
        if (l.qty > l.stock) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Stock insuficiente para "${l.name}". Disponibles: ${l.stock.toStringAsFixed(0)}.',
              ),
            ),
          );
          return;
        }
      }
    }

    final discountPct = _num(_discountPctCtl);
    final discountUsd = _num(_discountUsdCtl);

    final paymentsPayload = _payments
        .where((p) => p.amountUsd > 0)
        .map(
          (p) => {
            'paymentMethodCode': p.methodCode,
            'amountUsd': p.amountUsd,
            'concept': p.concept,
            'receiptNote': p.receiptNote,
          },
        )
        .toList();

    try {
      final occurredAtIso = (_occurredAt ?? DateTime.now())
          .toUtc()
          .toIso8601String();
      if (widget.isEdit && (widget.saleId ?? '').trim().isEmpty) {
        throw StateError('No se pudo editar: saleId vacío');
      }

      if (_tipo == _TipoVenta.libre) {
        if (widget.isEdit) {
          final payload = {
            'saleType': 'LIBRE',
            'totalUsd': _subtotal,
            if (discountPct > 0) 'discountPercent': discountPct,
            if (discountPct <= 0 && discountUsd > 0) 'discountUsd': discountUsd,
            'description': _notaCtl.text.trim(),
            'receiptNote': _notaComprobanteCtl.text.trim(),
            'occurredAt': occurredAtIso,
            'payments': paymentsPayload,
          };
          await state.editarVentaRecrear(
            saleId: widget.saleId!.trim(),
            payload: payload,
          );
        } else {
          await state.crearVentaLibre(
            totalUsd: _subtotal,
            discountPercent: discountPct > 0 ? discountPct : null,
            discountUsd: discountPct > 0
                ? null
                : (discountUsd > 0 ? discountUsd : null),
            note: _notaCtl.text.trim(),
            receiptNote: _notaComprobanteCtl.text.trim(),
            payments: paymentsPayload,
            occurredAt: _occurredAt,
          );
        }
      } else {
        final itemsPayload = _lines
            .map(
              (l) => {
                'productId': l.productId,
                'qty': l.qty,
                'unitPriceUsd': l.unitPriceUsd,
              },
            )
            .toList();

        if (widget.isEdit) {
          final wid = (state.warehouseId ?? '').trim();
          final payload = {
            'saleType': 'INVENTARIO',
            'warehouseId': wid,
            'items': itemsPayload,
            if (discountPct > 0) 'discountPercent': discountPct,
            if (discountPct <= 0 && discountUsd > 0) 'discountUsd': discountUsd,
            'description': _notaCtl.text.trim(),
            'receiptNote': _notaComprobanteCtl.text.trim(),
            'occurredAt': occurredAtIso,
            'payments': paymentsPayload,
          };
          await state.editarVentaRecrear(
            saleId: widget.saleId!.trim(),
            payload: payload,
          );
        } else {
          await state.crearVentaInventario(
            items: itemsPayload,
            discountPercent: discountPct > 0 ? discountPct : null,
            discountUsd: discountPct > 0
                ? null
                : (discountUsd > 0 ? discountUsd : null),
            note: _notaCtl.text.trim(),
            receiptNote: _notaComprobanteCtl.text.trim(),
            payments: paymentsPayload,
            occurredAt: _occurredAt,
          );
        }
      }

      if (mounted) Navigator.pop(context, widget.isEdit ? true : null);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No se pudo registrar la venta: ${_humanizeDioError(e)}',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    _ensureDefaultPayment(state);

    final methods = state.paymentMethods.isNotEmpty
        ? state.paymentMethods
        : const [
            PaymentMethod(
              code: 'CASH',
              name: 'Efectivo',
              isActive: true,
              sortOrder: 0,
            ),
          ];

    return _SheetScrollContainer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppTheme.bg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE6EBF2)),
                ),
                child: const Icon(Icons.trending_up, color: AppTheme.green),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _sheetTitle,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.navy,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (widget.showTypeSelector) ...[
            SegmentedButton<_TipoVenta>(
              segments: const [
                ButtonSegment(
                  value: _TipoVenta.inventario,
                  label: Text('Venta de inventario'),
                ),
                ButtonSegment(
                  value: _TipoVenta.libre,
                  label: Text('Venta libre'),
                ),
              ],
              selected: {_tipo},
              onSelectionChanged: (s) => setState(() => _tipo = s.first),
            ),
            const SizedBox(height: 12),
          ],

          if (_tipo == _TipoVenta.inventario) ...[
            SizedBox(
              height: 44,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppTheme.navy),
                onPressed: state.busy ? null : _pickProducts,
                icon: const Icon(Icons.add_shopping_cart_outlined, size: 20),
                label: const Text(
                  'Seleccionar productos',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
            const SizedBox(height: 10),
            if (_lines.isEmpty)
              const Text(
                'Aún no has seleccionado productos.',
                style: TextStyle(
                  color: Colors.black54,
                  fontWeight: FontWeight.w700,
                ),
              ),
            if (_lines.isNotEmpty)
              ..._lines.map(
                (l) => _LineCard(
                  key: ValueKey(l.productId),
                  line: l,
                  onRemove: () => setState(
                    () => _lines.removeWhere((x) => x.productId == l.productId),
                  ),
                  onChanged: () => setState(() {}),
                ),
              ),
            const SizedBox(height: 8),
          ] else ...[
            TextField(
              controller: _totalLibreCtl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: AppInputFormatters.decimal(maxDecimals: 2),
              decoration: const InputDecoration(
                labelText: 'Valor de la venta (USD)',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
          ],

          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _discountPctCtl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: AppInputFormatters.decimal(maxDecimals: 2),
                  decoration: const InputDecoration(
                    labelText: 'Descuento %',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) {
                    if (_discountPctCtl.text.trim().isNotEmpty) {
                      _discountUsdCtl.clear();
                    }
                    setState(() {});
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _discountUsdCtl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: AppInputFormatters.decimal(maxDecimals: 2),
                  decoration: const InputDecoration(
                    labelText: 'Descuento USD',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) {
                    if (_discountUsdCtl.text.trim().isNotEmpty) {
                      _discountPctCtl.clear();
                    }
                    setState(() {});
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          TextField(
            controller: _notaComprobanteCtl,
            decoration: const InputDecoration(
              labelText: 'Nota del comprobante (opcional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _notaCtl,
            decoration: const InputDecoration(
              labelText: 'Concepto / Nota (opcional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),

          _TotalsBar(
            subtotal: _subtotal,
            discount: _discountUsd,
            total: _total,
          ),
          const SizedBox(height: 12),

          const Text(
            'Pagos',
            style: TextStyle(fontWeight: FontWeight.w900, color: AppTheme.navy),
          ),
          const SizedBox(height: 8),
          ..._payments.asMap().entries.map((entry) {
            final i = entry.key;
            final p = entry.value;
            return _PaymentCard(
              key: ObjectKey(p),
              index: i,
              methods: methods,
              row: p,
              onRemove: _payments.length <= 1
                  ? null
                  : () => setState(() => _payments.removeAt(i)),
              onChanged: () => setState(() {}),
            );
          }),
          const SizedBox(height: 8),
          SizedBox(
            height: 44,
            child: OutlinedButton.icon(
              onPressed: () {
                final first = methods.first;
                setState(() {
                  _payments.add(
                    _PaymentRow(
                      methodCode: first.code,
                      amountUsd: 0,
                      concept: 'Venta',
                      receiptNote: '',
                    ),
                  );
                });
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text(
                'Agregar otro pago',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 54,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppTheme.green),
              onPressed: state.busy ? null : _submit,
              child: state.busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.6,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      '${widget.isEdit ? 'Guardar cambios' : 'Confirmar venta'} (\$${_total.toStringAsFixed(2)})',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _EstadoGasto { pagado, deuda }

class _GastoSheet extends StatefulWidget {
  const _GastoSheet({
    this.isEdit = false,
    this.existingExpense,
    this.expenseId,
    this.prefillPayments,
  });

  final bool isEdit;
  final Map<String, dynamic>? existingExpense;
  final String? expenseId;
  final List<Map<String, dynamic>>? prefillPayments;

  @override
  State<_GastoSheet> createState() => _GastoSheetState();
}

class _GastoSheetState extends State<_GastoSheet> {
  _EstadoGasto _estado = _EstadoGasto.pagado;
  DateTime _date = DateTime.now();
  DateTime? _occurredAt;

  String? _category;
  String? _selectedProductId;
  String? _selectedProductName;
  String? _selectedProductBarcode;
  String? _selectedProductReference;

  final _amountCtl = TextEditingController();
  final _descCtl = TextEditingController();
  final _receiptCtl = TextEditingController();

  final List<_PaymentRow> _payments = [];

  static double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  DateTime _toDate(dynamic v) {
    if (v == null) return DateTime.now();
    if (v is DateTime) return v.isUtc ? v.toLocal() : v;
    final dt = DateTime.tryParse(v.toString());
    if (dt == null) return DateTime.now();
    return dt.isUtc ? dt.toLocal() : dt;
  }

  @override
  void initState() {
    super.initState();

    // Prefill payments (si vienen), antes de pintar.
    final p = widget.prefillPayments;
    if (p != null && p.isNotEmpty) {
      _payments.clear();
      for (final row in p) {
        _payments.add(
          _PaymentRow(
            methodCode:
                (row['paymentMethodCode'] ?? row['methodCode'] ?? 'CASH')
                    .toString(),
            amountUsd: _toDouble(row['amountUsd'] ?? row['amount'] ?? 0),
            concept: (row['concept'] ?? 'Gasto').toString(),
            receiptNote: (row['receiptNote'] ?? '').toString(),
          ),
        );
      }
    }

    if (widget.isEdit && widget.existingExpense != null) {
      final exp = widget.existingExpense!;

      final status = (exp['status'] ?? '').toString().toUpperCase();
      final statusLabel = (exp['statusLabel'] ?? '').toString().toUpperCase();
      final isDebt = status.contains('DEBT') || statusLabel.contains('DEUDA');
      _estado = isDebt ? _EstadoGasto.deuda : _EstadoGasto.pagado;

      final when = _toDate(exp['occurredAt']);
      _occurredAt = when;
      _date = DateTime(when.year, when.month, when.day);

      final cat = (exp['categoryLabel'] ?? exp['category'] ?? '')
          .toString()
          .trim();
      if (cat.isNotEmpty) _category = cat;

      final product = (exp['product'] is Map)
          ? (exp['product'] as Map).cast<String, dynamic>()
          : const <String, dynamic>{};
      final productId = (exp['productId'] ?? exp['product_id'] ?? product['id'])
          ?.toString()
          .trim();
      if (productId != null && productId.isNotEmpty) {
        _selectedProductId = productId;
      }
      final productName =
          (product['description'] ?? product['reference'] ?? product['barcode'])
              ?.toString()
              .trim();
      if (productName != null && productName.isNotEmpty) {
        _selectedProductName = productName;
      }
      final productBarcode = product['barcode']?.toString().trim();
      if (productBarcode != null && productBarcode.isNotEmpty) {
        _selectedProductBarcode = productBarcode;
      }
      final productReference = product['reference']?.toString().trim();
      if (productReference != null && productReference.isNotEmpty) {
        _selectedProductReference = productReference;
      }

      final amt = _toDouble(exp['totalUsd'] ?? exp['amountUsd']);
      if (amt > 0) _amountCtl.text = amt.toStringAsFixed(2);

      final desc = (exp['description'] ?? exp['concept'] ?? '')
          .toString()
          .trim();
      _descCtl.text = desc;

      final receipt = (exp['receiptNote'] ?? '').toString().trim();
      _receiptCtl.text = receipt;
    }
  }

  @override
  void dispose() {
    _amountCtl.dispose();
    _descCtl.dispose();
    _receiptCtl.dispose();
    super.dispose();
  }

  double _num(TextEditingController c) =>
      double.tryParse(c.text.replaceAll(',', '.').trim()) ?? 0;

  double get _amount => _num(_amountCtl);
  double get _paymentsSum => _payments.fold(0.0, (a, p) => a + p.amountUsd);
  bool get _showProductSelector => _isInventoryExpenseCategory(_category);

  bool _almostEq(double a, double b) => (a - b).abs() <= 0.01;

  void _ensureDefaultPayment(AppState state) {
    if (_payments.isNotEmpty) return;
    final first = state.paymentMethods.isNotEmpty
        ? state.paymentMethods.first
        : null;
    _payments.add(
      _PaymentRow(
        methodCode: first?.code ?? 'CASH',
        amountUsd: 0,
        concept: 'Gasto',
        receiptNote: '',
      ),
    );
  }

  void _clearSelectedProduct() {
    _selectedProductId = null;
    _selectedProductName = null;
    _selectedProductBarcode = null;
    _selectedProductReference = null;
  }

  void _setSelectedProduct(Product product) {
    _selectedProductId = product.id;
    _selectedProductName = product.name;
    _selectedProductBarcode = product.barcode.trim().isEmpty
        ? null
        : product.barcode.trim();
    _selectedProductReference = product.reference.trim().isEmpty
        ? null
        : product.reference.trim();
  }

  Product? _selectedProductFrom(AppState state) {
    final id = (_selectedProductId ?? '').trim();
    if (id.isEmpty) return null;
    for (final product in state.products) {
      if (product.id == id) return product;
    }
    return null;
  }

  Future<void> _pickProduct() async {
    final state = context.read<AppState>();
    final selected = await showModalBottomSheet<Product?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => _ExpenseProductPicker(
        products: state.products,
        selectedProductId: _selectedProductId,
      ),
    );
    if (!mounted || selected == null) return;
    setState(() {
      _setSelectedProduct(selected);
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: _date,
      locale: const Locale('es'),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    final state = context.read<AppState>();

    if (_amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El valor debe ser mayor a 0.')),
      );
      return;
    }

    final cat =
        _category ??
        (state.expenseCategories.isNotEmpty
            ? state.expenseCategories.first
            : 'Otros');
    final categoryPayload = _expenseCategoryPayloadValue(cat);
    final productId = _showProductSelector
        ? ((_selectedProductId ?? '').trim().isEmpty
              ? null
              : _selectedProductId!.trim())
        : null;

    final paymentsPayload = _payments
        .where((p) => p.amountUsd > 0)
        .map(
          (p) => {
            'paymentMethodCode': p.methodCode,
            'amountUsd': p.amountUsd,
            'concept': p.concept,
            'receiptNote': p.receiptNote,
          },
        )
        .toList();

    if (_estado == _EstadoGasto.pagado) {
      if (paymentsPayload.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Agrega al menos un pago.')),
        );
        return;
      }
      if (!_almostEq(_paymentsSum, _amount)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'La suma de pagos (\$${_paymentsSum.toStringAsFixed(2)}) no coincide con el total (\$${_amount.toStringAsFixed(2)}).',
            ),
          ),
        );
        return;
      }
    }

    try {
      final baseTime = _occurredAt ?? DateTime.now();
      final occurredAt = DateTime(
        _date.year,
        _date.month,
        _date.day,
        baseTime.hour,
        baseTime.minute,
        baseTime.second,
      );

      if (widget.isEdit) {
        final id = (widget.expenseId ?? '').trim();
        if (id.isEmpty) throw StateError('No se pudo editar: expenseId vacío');

        final payload = <String, dynamic>{
          'status': _estado == _EstadoGasto.pagado ? 'PAGADO' : 'DEUDA',
          'category': categoryPayload,
          'amountUsd': _amount,
          'description': _descCtl.text.trim(),
          'receiptNote': _receiptCtl.text.trim(),
          'occurredAt': occurredAt.toUtc().toIso8601String(),
          if (_estado == _EstadoGasto.pagado) 'payments': paymentsPayload,
          if (_estado == _EstadoGasto.deuda && paymentsPayload.isNotEmpty)
            'payments': paymentsPayload,
        };
        if (productId != null) {
          payload['productId'] = productId;
        }
        await state.editarGastoRecrear(expenseId: id, payload: payload);
        if (mounted) Navigator.pop(context, true);
      } else {
        await state.crearGasto(
          status: _estado == _EstadoGasto.pagado ? 'PAGADO' : 'DEUDA',
          category: categoryPayload,
          amountUsd: _amount,
          description: _descCtl.text.trim(),
          receiptNote: _receiptCtl.text.trim(),
          productId: productId,
          occurredAt: occurredAt,
          payments: _estado == _EstadoGasto.pagado
              ? paymentsPayload
              : (paymentsPayload.isEmpty ? null : paymentsPayload),
        );
        if (mounted) Navigator.pop(context);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No se pudo registrar el gasto: ${_humanizeDioError(e)}',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    _ensureDefaultPayment(state);

    final methods = state.paymentMethods.isNotEmpty
        ? state.paymentMethods
        : const [
            PaymentMethod(
              code: 'CASH',
              name: 'Efectivo',
              isActive: true,
              sortOrder: 0,
            ),
          ];

    final baseCats = state.expenseCategories.isNotEmpty
        ? state.expenseCategories
        : const [
            'Servicio público',
            'Compra de productos e insumos',
            'Arriendo',
            'Nómina',
            'Gasto administrativo',
            'Mercadeo y publicidad',
            'Transporte',
            'Domicilio y logística',
            'Mantenimiento y reparaciones',
            'Muebles, equipos o maquinaria',
            'Otros',
          ];

    final cats = List<String>.of(baseCats);
    if ((_category ?? '').trim().isNotEmpty && !cats.contains(_category)) {
      cats.insert(0, _category!);
    }
    if (_category == null || !cats.contains(_category)) {
      _category = cats.first;
    }

    final selectedProduct = _selectedProductFrom(state);
    final selectedProductName = selectedProduct?.name ?? _selectedProductName;
    final selectedProductBarcode =
        selectedProduct != null && selectedProduct.barcode.trim().isNotEmpty
        ? selectedProduct.barcode.trim()
        : _selectedProductBarcode;
    final selectedProductReference =
        selectedProduct != null && selectedProduct.reference.trim().isNotEmpty
        ? selectedProduct.reference.trim()
        : _selectedProductReference;

    return _SheetScrollContainer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppTheme.bg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE6EBF2)),
                ),
                child: const Icon(Icons.trending_down, color: AppTheme.red),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.isEdit ? 'Editar gasto' : 'Nuevo gasto',
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
              ),
            ],
          ),
          const SizedBox(height: 12),

          SegmentedButton<_EstadoGasto>(
            segments: const [
              ButtonSegment(value: _EstadoGasto.pagado, label: Text('Pagado')),
              ButtonSegment(value: _EstadoGasto.deuda, label: Text('Deuda')),
            ],
            selected: {_estado},
            onSelectionChanged: (s) => setState(() => _estado = s.first),
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _category,
                  isExpanded: true,
                  items: cats
                      .map(
                        (c) => DropdownMenuItem(
                          value: c,
                          child: Text(c, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() {
                    _category = v;
                    if (!_showProductSelector) {
                      _clearSelectedProduct();
                    }
                  }),
                  decoration: const InputDecoration(
                    labelText: 'Categoría',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 56,
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '${_date.day.toString().padLeft(2, '0')}/${_date.month.toString().padLeft(2, '0')}/${_date.year}',
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_showProductSelector) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: state.products.isEmpty ? null : _pickProduct,
              icon: const Icon(Icons.inventory_2_outlined),
              label: Text(
                ((_selectedProductId ?? '').trim().isEmpty)
                    ? 'Seleccionar producto (opcional)'
                    : 'Cambiar producto',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            if (state.products.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'No hay productos disponibles en inventario.',
                  style: TextStyle(
                    color: Colors.black54,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            if ((selectedProductName ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE6EBF2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: AppTheme.green),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            selectedProductName!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              color: AppTheme.navy,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            [
                              if ((selectedProductBarcode ?? '')
                                  .trim()
                                  .isNotEmpty)
                                'Código: ${selectedProductBarcode!.trim()}',
                              if ((selectedProductReference ?? '')
                                  .trim()
                                  .isNotEmpty)
                                'Ref: ${selectedProductReference!.trim()}',
                            ].join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.black54,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => setState(_clearSelectedProduct),
                      tooltip: 'Quitar producto',
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
            ],
          ],
          const SizedBox(height: 10),

          TextField(
            controller: _amountCtl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: AppInputFormatters.decimal(maxDecimals: 2),
            decoration: const InputDecoration(
              labelText: 'Valor (USD)',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _descCtl,
            decoration: const InputDecoration(
              labelText: 'Descripción / Concepto (opcional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _receiptCtl,
            decoration: const InputDecoration(
              labelText: 'Nota del comprobante (opcional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),

          if (_estado == _EstadoGasto.pagado ||
              (_estado == _EstadoGasto.deuda && _payments.isNotEmpty)) ...[
            const Text(
              'Pagos',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: AppTheme.navy,
              ),
            ),
            const SizedBox(height: 8),
            ..._payments.asMap().entries.map((entry) {
              final i = entry.key;
              final p = entry.value;
              return _PaymentCard(
                key: ObjectKey(p),
                index: i,
                methods: methods,
                row: p,
                onRemove: _payments.length <= 1
                    ? null
                    : () => setState(() => _payments.removeAt(i)),
                onChanged: () => setState(() {}),
              );
            }),
            const SizedBox(height: 8),
            SizedBox(
              height: 44,
              child: OutlinedButton.icon(
                onPressed: () {
                  final first = methods.first;
                  setState(() {
                    _payments.add(
                      _PaymentRow(
                        methodCode: first.code,
                        amountUsd: 0,
                        concept: 'Gasto',
                        receiptNote: '',
                      ),
                    );
                  });
                },
                icon: const Icon(Icons.add_rounded),
                label: const Text(
                  'Agregar otro pago',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ],

          const SizedBox(height: 14),
          SizedBox(
            height: 54,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppTheme.red),
              onPressed: state.busy ? null : _submit,
              child: state.busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.6,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      '${widget.isEdit ? 'Guardar cambios' : 'Confirmar gasto'} (\$${_amount.toStringAsFixed(2)})',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalsBar extends StatelessWidget {
  const _TotalsBar({
    required this.subtotal,
    required this.discount,
    required this.total,
  });

  final double subtotal;
  final double discount;
  final double total;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6EBF2)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Subtotal: \$${subtotal.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  'Descuento: \$${discount.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
          Text(
            'Total: \$${total.toStringAsFixed(2)}',
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 16,
              color: AppTheme.navy,
            ),
          ),
        ],
      ),
    );
  }
}

class _LineCard extends StatefulWidget {
  const _LineCard({
    super.key,
    required this.line,
    required this.onRemove,
    required this.onChanged,
  });

  final _SaleLine line;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  @override
  State<_LineCard> createState() => _LineCardState();
}

class _LineCardState extends State<_LineCard> {
  late final TextEditingController _qtyCtl;
  late final TextEditingController _priceCtl;

  @override
  void initState() {
    super.initState();
    _qtyCtl = TextEditingController(text: widget.line.qty.toStringAsFixed(0));
    _priceCtl = TextEditingController(
      text: widget.line.unitPriceUsd.toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _qtyCtl.dispose();
    _priceCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final line = widget.line;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6EBF2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  line.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: AppTheme.navy,
                  ),
                ),
              ),
              IconButton(
                onPressed: widget.onRemove,
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Quitar',
              ),
            ],
          ),
          Text(
            'Disponibles: ${line.stock.toStringAsFixed(0)}',
            style: TextStyle(
              color: _isLowStock(line.stock) ? AppTheme.red : Colors.black54,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _qtyCtl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: AppInputFormatters.decimal(maxDecimals: 3),
                  decoration: const InputDecoration(
                    labelText: 'Cantidad',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) {
                    final n = double.tryParse(v.replaceAll(',', '.')) ?? 0;
                    line.qty = n;
                    widget.onChanged();
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _priceCtl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: AppInputFormatters.decimal(maxDecimals: 2),
                  decoration: const InputDecoration(
                    labelText: 'Precio unitario (USD)',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) {
                    final n = double.tryParse(v.replaceAll(',', '.')) ?? 0;
                    line.unitPriceUsd = n;
                    widget.onChanged();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PaymentCard extends StatefulWidget {
  const _PaymentCard({
    super.key,
    required this.index,
    required this.methods,
    required this.row,
    required this.onChanged,
    this.onRemove,
  });

  final int index;
  final List<PaymentMethod> methods;
  final _PaymentRow row;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  @override
  State<_PaymentCard> createState() => _PaymentCardState();
}

class _PaymentCardState extends State<_PaymentCard> {
  late final TextEditingController _amountCtl;
  late final TextEditingController _conceptCtl;
  late final TextEditingController _receiptCtl;

  @override
  void initState() {
    super.initState();
    _amountCtl = TextEditingController(
      text: widget.row.amountUsd == 0
          ? ''
          : widget.row.amountUsd.toStringAsFixed(2),
    );
    _conceptCtl = TextEditingController(text: widget.row.concept);
    _receiptCtl = TextEditingController(text: widget.row.receiptNote);
  }

  @override
  void dispose() {
    _amountCtl.dispose();
    _conceptCtl.dispose();
    _receiptCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.row;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6EBF2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Pago ${widget.index + 1}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: AppTheme.navy,
                  ),
                ),
              ),
              if (widget.onRemove != null)
                IconButton(
                  onPressed: widget.onRemove,
                  icon: const Icon(Icons.close),
                  tooltip: 'Quitar',
                ),
            ],
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: row.methodCode,
            isExpanded: true,
            items: widget.methods
                .where((m) => m.isActive)
                .map(
                  (m) => DropdownMenuItem(value: m.code, child: Text(m.name)),
                )
                .toList(),
            onChanged: (v) {
              row.methodCode = v ?? row.methodCode;
              widget.onChanged();
            },
            decoration: const InputDecoration(
              labelText: 'Tipo de pago',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _amountCtl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: AppInputFormatters.decimal(maxDecimals: 2),
            decoration: const InputDecoration(
              labelText: 'Monto (USD)',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) {
              row.amountUsd = double.tryParse(v.replaceAll(',', '.')) ?? 0;
              widget.onChanged();
            },
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _conceptCtl,
            decoration: const InputDecoration(
              labelText: 'Concepto de pago',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) {
              row.concept = v;
              widget.onChanged();
            },
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _receiptCtl,
            decoration: const InputDecoration(
              labelText: 'Nota del comprobante',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) {
              row.receiptNote = v;
              widget.onChanged();
            },
          ),
        ],
      ),
    );
  }
}

class _ProductPicker extends StatefulWidget {
  const _ProductPicker({required this.products, required this.selectedIds});

  final List<Product> products;
  final Set<String> selectedIds;

  @override
  State<_ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends State<_ProductPicker> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final q = _search.text.trim().toLowerCase();

    final list = q.isEmpty
        ? widget.products
        : widget.products
              .where(
                (p) =>
                    p.name.toLowerCase().contains(q) ||
                    p.barcode.toLowerCase().contains(q),
              )
              .toList();

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Seleccionar productos',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: AppTheme.navy,
                    fontSize: 18,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _search,
            decoration: const InputDecoration(
              labelText: 'Buscar…',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: list.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final p = list[i];
                final checked = widget.selectedIds.contains(p.id);
                return CheckboxListTile(
                  value: checked,
                  onChanged: (v) {
                    setState(() {
                      if (v == true) {
                        widget.selectedIds.add(p.id);
                      } else {
                        widget.selectedIds.remove(p.id);
                      }
                    });
                  },
                  title: Text(
                    p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    'Stock: ${p.stock.toStringAsFixed(0)} · \$${p.priceRetailUsd.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: _isLowStock(p.stock)
                          ? AppTheme.red
                          : Colors.black54,
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 52,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppTheme.navy),
              onPressed: () =>
                  Navigator.pop(context, widget.selectedIds.toList()),
              child: const Text(
                'Listo',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpenseProductPicker extends StatefulWidget {
  const _ExpenseProductPicker({
    required this.products,
    required this.selectedProductId,
  });

  final List<Product> products;
  final String? selectedProductId;

  @override
  State<_ExpenseProductPicker> createState() => _ExpenseProductPickerState();
}

class _ExpenseProductPickerState extends State<_ExpenseProductPicker> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(Product product, String query) {
    if (query.isEmpty) return true;
    final haystack = [
      product.name,
      product.barcode,
      product.reference,
    ].map((e) => e.toLowerCase()).join(' ');
    return haystack.contains(query);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final query = _search.text.trim().toLowerCase();
    final list = widget.products.where((p) => _matches(p, query)).toList();

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Seleccionar producto',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: AppTheme.navy,
                    fontSize: 18,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _search,
            decoration: const InputDecoration(
              labelText: 'Buscar por descripción, código o referencia',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: list.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final product = list[i];
                final selected =
                    product.id == (widget.selectedProductId ?? '').trim();
                return ListTile(
                  onTap: () => Navigator.pop(context, product),
                  leading: Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: selected ? AppTheme.navy : Colors.black38,
                  ),
                  title: Text(
                    product.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    [
                      if (product.barcode.trim().isNotEmpty)
                        'Código: ${product.barcode.trim()}',
                      if (product.reference.trim().isNotEmpty)
                        'Ref: ${product.reference.trim()}',
                    ].join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
