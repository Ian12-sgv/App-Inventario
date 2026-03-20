import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/product.dart';
import '../../state/app_state.dart';
import '../../ui/app_theme.dart';
import '../../ui/input_formatters.dart';
import '../inventory/product_sheets.dart';

const double _saleLowStockThreshold = 3;
const Color _saleFlowHeaderColor = AppTheme.bannerBlue;
const Color _saleFlowBackground = Color(0xFFF3F4F6);
const Color _saleFlowBorderColor = Color(0xFFD5DDE7);
const Color _saleFlowMutedText = Color(0xFF667085);

Future<void> showProductSaleFlow(BuildContext context) async {
  await Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const ProductSaleFlowScreen()));
}

Future<bool?> showEditProductSaleFlow(
  BuildContext context, {
  required Map<String, dynamic> sale,
  required String saleId,
  List<Map<String, dynamic>> lineRows = const [],
}) async {
  return Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => ProductSaleFlowScreen(
        isEdit: true,
        existingSale: sale,
        saleId: saleId,
        initialLineRows: lineRows,
      ),
    ),
  );
}

double _saleFlowToDouble(dynamic value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}

String _saleFlowText(dynamic value) => (value ?? '').toString().trim();

String _saleFlowNormalizeKey(String value) {
  return value
      .trim()
      .toUpperCase()
      .replaceAll(RegExp(r'[^A-Z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
}

InputDecoration _saleInputDecoration({
  String? hintText,
  String? labelText,
  String? prefixText,
}) {
  return InputDecoration(
    hintText: hintText,
    labelText: labelText,
    prefixText: prefixText,
    isDense: true,
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: _saleFlowBorderColor),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: _saleFlowBorderColor),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: _saleFlowHeaderColor, width: 1.4),
    ),
  );
}

enum _ProductSaleStep { catalog, confirm, payment }

enum _ProductSaleStatus { paid, debt }

class _ProductSaleLine {
  _ProductSaleLine({
    required this.product,
    required this.qty,
    required this.unitPriceUsd,
  });

  Product product;
  int qty;
  double unitPriceUsd;

  double get subtotal => qty * unitPriceUsd;
}

class _ProductSalePaymentSlot {
  _ProductSalePaymentSlot({required this.methodCode});

  String methodCode;
}

class ProductSaleFlowScreen extends StatefulWidget {
  const ProductSaleFlowScreen({
    super.key,
    this.isEdit = false,
    this.existingSale,
    this.saleId,
    this.initialLineRows = const [],
  });

  final bool isEdit;
  final Map<String, dynamic>? existingSale;
  final String? saleId;
  final List<Map<String, dynamic>> initialLineRows;

  @override
  State<ProductSaleFlowScreen> createState() => _ProductSaleFlowScreenState();
}

class _ProductSaleFlowScreenState extends State<ProductSaleFlowScreen> {
  final _searchCtl = TextEditingController();
  final _discountPctCtl = TextEditingController();
  final _discountUsdCtl = TextEditingController();
  final _conceptCtl = TextEditingController();
  final _receiptCtl = TextEditingController();

  final Map<String, _ProductSaleLine> _linesById = {};
  final Map<String, int> _initialQtyByProductId = {};
  final List<_ProductSalePaymentSlot> _paymentSlots = [];

  _ProductSaleStep _step = _ProductSaleStep.catalog;
  _ProductSaleStatus _status = _ProductSaleStatus.paid;
  DateTime _saleDate = DateTime.now();
  bool _showSearch = false;
  bool _lowStockOnly = false;
  bool _selectedOnly = false;
  bool _sortByStock = false;
  bool _moreOptionsExpanded = true;
  bool _paymentDetailExpanded = false;
  int _paymentCount = 1;
  bool _submitting = false;
  String _initialSignature = '';

  @override
  void initState() {
    super.initState();
    if (widget.isEdit) {
      _prefillEditState();
    }
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    _discountPctCtl.dispose();
    _discountUsdCtl.dispose();
    _conceptCtl.dispose();
    _receiptCtl.dispose();
    super.dispose();
  }

  List<_ProductSaleLine> get _lines => _linesById.values.toList();

  int get _selectedLineCount => _lines.length;

  double get _subtotal =>
      _lines.fold<double>(0, (sum, line) => sum + line.subtotal);

  double get _discountUsd {
    final pct = _parseNum(_discountPctCtl.text);
    final usd = _parseNum(_discountUsdCtl.text);
    if (pct > 0) return (_subtotal * pct / 100).clamp(0, _subtotal);
    if (usd > 0) return usd.clamp(0, _subtotal);
    return 0;
  }

  double get _total => (_subtotal - _discountUsd).clamp(0, double.infinity);

  double _parseNum(String raw) =>
      double.tryParse(raw.replaceAll(',', '.').trim()) ?? 0;

  String get _saleId => (widget.saleId ?? '').trim();

  bool get _canPopRoute => widget.isEdit
      ? _step == _ProductSaleStep.payment
      : _step == _ProductSaleStep.catalog;

  bool get _isDirty => _buildEditSignature() != _initialSignature;

  int _maxQtyFor(Product product) {
    final reserved = widget.isEdit
        ? (_initialQtyByProductId[product.id] ?? 0)
        : 0;
    return math.max(0, product.stock.floor() + reserved);
  }

  int _selectedQtyFor(Product product) => _linesById[product.id]?.qty ?? 0;

  int _remainingQtyFor(Product product) =>
      math.max(0, _maxQtyFor(product) - _selectedQtyFor(product));

  bool _isLowStockQty(int qty) => qty < _saleLowStockThreshold;

  DateTime _parseSaleDate(dynamic raw) {
    if (raw is DateTime) {
      return raw.isUtc ? raw.toLocal() : raw;
    }
    final parsed = raw == null ? null : DateTime.tryParse(raw.toString());
    if (parsed == null) return DateTime.now();
    return parsed.isUtc ? parsed.toLocal() : parsed;
  }

  String _defaultConceptFromLines(List<_ProductSaleLine> lines) {
    if (lines.isEmpty) return 'Venta';
    if (lines.length == 1) {
      final line = lines.first;
      return '${line.qty} ${line.product.name}'.trim();
    }
    final totalQty = lines.fold<int>(0, (sum, line) => sum + line.qty);
    return '$totalQty productos';
  }

  String _resolveMethodCode(
    List<PaymentMethod> methods,
    String label, {
    String fallback = 'CASH',
  }) {
    final raw = label.trim();
    if (raw.isEmpty) return fallback;
    final wanted = _saleFlowNormalizeKey(raw);
    for (final method in methods) {
      if (_saleFlowNormalizeKey(method.code) == wanted) return method.code;
      if (_saleFlowNormalizeKey(method.name) == wanted) return method.code;
    }
    return fallback;
  }

  bool _isDebtSale(Map<String, dynamic> sale) {
    final status = _saleFlowText(sale['status']);
    final statusLabel = _saleFlowText(sale['statusLabel']);
    final normalized = _saleFlowNormalizeKey('$status $statusLabel');
    return normalized.contains('DEUDA') || normalized.contains('DEBT');
  }

  Product? _productFromLineRow(Map<String, dynamic> row, AppState state) {
    final productMap = (row['product'] is Map)
        ? (row['product'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};
    final productId = _saleFlowText(
      row['productId'] ?? row['product_id'] ?? productMap['id'],
    );
    if (productId.isEmpty) return null;

    for (final product in state.products) {
      if (product.id == productId) {
        return product;
      }
    }

    final stock = _saleFlowToDouble(
      row['stock'] ??
          row['availableQty'] ??
          row['available_qty'] ??
          productMap['stock'] ??
          productMap['availableQty'],
    );
    final merged = <String, dynamic>{
      ...productMap,
      'id': productId,
      'description':
          productMap['description'] ??
          productMap['name'] ??
          row['description'] ??
          row['name'] ??
          row['reference'] ??
          row['barcode'],
      'reference': productMap['reference'] ?? row['reference'],
      'barcode': productMap['barcode'] ?? row['barcode'],
      'line': productMap['line'] ?? row['line'] ?? row['linea'],
      'subLine':
          productMap['subLine'] ??
          productMap['sub_line'] ??
          row['subLine'] ??
          row['sub_line'] ??
          row['sublinea'],
      'category': productMap['category'] ?? row['category'] ?? row['categoria'],
      'subCategory':
          productMap['subCategory'] ??
          productMap['sub_category'] ??
          row['subCategory'] ??
          row['sub_category'] ??
          row['subcategoria'],
      'imageUrl':
          productMap['imageUrl'] ??
          productMap['image_url'] ??
          row['imageUrl'] ??
          row['image_url'] ??
          row['image'],
      'priceRetail':
          row['unitPriceUsd'] ??
          row['unitPrice'] ??
          row['priceRetailUsd'] ??
          row['priceRetail'] ??
          productMap['priceRetail'] ??
          productMap['priceRetailUsd'] ??
          productMap['salePriceUsd'] ??
          productMap['salePrice'],
      'priceWholesale':
          productMap['priceWholesale'] ?? productMap['priceWholesaleUsd'],
      'cost': productMap['cost'] ?? productMap['costUsd'],
    };
    return Product.fromApi(merged, stock: stock);
  }

  _ProductSaleLine? _lineFromRow(Map<String, dynamic> row, AppState state) {
    final product = _productFromLineRow(row, state);
    if (product == null) return null;
    final qty = _saleFlowToDouble(row['qty']);
    final explicitUnit = _saleFlowToDouble(
      row['unitPriceUsd'] ??
          row['unitPrice'] ??
          row['priceRetailUsd'] ??
          row['priceRetail'] ??
          row['saleUnitPriceUsd'] ??
          row['salePriceUsd'] ??
          row['salePrice'],
    );
    final explicitTotal = _saleFlowToDouble(
      row['totalUsd'] ??
          row['saleTotalUsd'] ??
          row['saleLineTotalUsd'] ??
          row['subtotalUsd'] ??
          row['amountUsd'],
    );
    final derivedUnit = explicitUnit > 0
        ? explicitUnit
        : (qty > 0 && explicitTotal > 0 ? explicitTotal / qty : 0.0);
    return _ProductSaleLine(
      product: product,
      qty: math.max(1, qty.round()),
      unitPriceUsd: derivedUnit > 0
          ? derivedUnit
          : (product.priceRetailUsd > 0 ? product.priceRetailUsd : 0.0),
    );
  }

  List<Map<String, dynamic>> _paymentRowsForSale(
    AppState state,
    List<PaymentMethod> methods,
  ) {
    final sale = widget.existingSale;
    if (sale == null || _saleId.isEmpty) return const [];
    final related =
        state.txnsForDay.where((txn) => (txn.saleId ?? '') == _saleId).toList()
          ..sort((a, b) => a.when.compareTo(b.when));
    final isDebt = _isDebtSale(sale);
    final wantedKind = isDebt ? 'ABONO' : 'VENTA';
    final rows = related
        .where((txn) => (txn.kind ?? '').toUpperCase() == wantedKind)
        .toList();
    if (rows.isEmpty && isDebt) return const [];
    final source = rows.isNotEmpty ? rows : related;
    if (source.isNotEmpty) {
      return source
          .map(
            (txn) => {
              'paymentMethodCode': _resolveMethodCode(
                methods,
                txn.paymentMethod,
                fallback: methods.first.code,
              ),
              'amountUsd': txn.amount,
            },
          )
          .toList();
    }

    final saleMethod = _saleFlowText(
      sale['paymentMethodCode'] ??
          sale['paymentMethodName'] ??
          sale['paymentMethod'] ??
          sale['metodoPago'],
    );
    if (saleMethod.isEmpty || isDebt) return const [];
    return [
      {
        'paymentMethodCode': _resolveMethodCode(
          methods,
          saleMethod,
          fallback: methods.first.code,
        ),
        'amountUsd': _saleFlowToDouble(
          sale['totalUsd'] ?? sale['total_usd'] ?? sale['total'],
        ),
      },
    ];
  }

  String _buildEditSignature() {
    final linesKey = _lines.toList()
      ..sort((a, b) => a.product.id.compareTo(b.product.id));
    final paymentKey = _status == _ProductSaleStatus.debt
        ? ''
        : _paymentSlots.map((slot) => slot.methodCode).join('|');
    final dateKey = _saleDate.toIso8601String();
    final lineKey = linesKey
        .map(
          (line) =>
              '${line.product.id}:${line.qty}:${line.unitPriceUsd.toStringAsFixed(2)}',
        )
        .join('|');
    return [
      _status.name,
      dateKey,
      _discountPctCtl.text.trim(),
      _discountUsdCtl.text.trim(),
      _conceptCtl.text.trim(),
      _receiptCtl.text.trim(),
      _paymentCount.toString(),
      paymentKey,
      lineKey,
    ].join('||');
  }

  void _prefillEditState() {
    final sale = widget.existingSale;
    if (sale == null) {
      _step = _ProductSaleStep.payment;
      _initialSignature = _buildEditSignature();
      return;
    }
    final state = context.read<AppState>();
    final methods = _activeMethods(state);

    _step = _ProductSaleStep.payment;
    _saleDate = _parseSaleDate(sale['occurredAt'] ?? sale['occurred_at']);

    final discountPct = _saleFlowToDouble(
      sale['discountPercent'] ?? sale['discount_percent'],
    );
    final discountUsd = _saleFlowToDouble(
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

    _conceptCtl.text = _saleFlowText(sale['description'] ?? sale['concept']);
    _receiptCtl.text = _saleFlowText(sale['receiptNote']);

    _linesById.clear();
    _initialQtyByProductId.clear();
    for (final row in widget.initialLineRows) {
      final line = _lineFromRow(row, state);
      if (line == null) continue;
      _linesById[line.product.id] = line;
      _initialQtyByProductId[line.product.id] = line.qty;
    }
    if (_conceptCtl.text.trim().isEmpty && _lines.isNotEmpty) {
      _conceptCtl.text = _defaultConceptFromLines(_lines);
    }

    final paymentRows = _paymentRowsForSale(state, methods);
    _paymentSlots.clear();
    if (paymentRows.isNotEmpty) {
      _status = _ProductSaleStatus.paid;
      _paymentCount = paymentRows.length;
      for (final row in paymentRows) {
        _paymentSlots.add(
          _ProductSalePaymentSlot(
            methodCode: _saleFlowText(row['paymentMethodCode']).isEmpty
                ? methods.first.code
                : _saleFlowText(row['paymentMethodCode']),
          ),
        );
      }
    } else {
      _status = _isDebtSale(sale)
          ? _ProductSaleStatus.debt
          : _ProductSaleStatus.paid;
      _paymentCount = 1;
      _ensurePaymentSlots(methods);
    }
    _initialSignature = _buildEditSignature();
  }

  List<double> _splitAmounts(double total, int count) {
    if (count <= 0) return const [];
    final roundedTotal = double.parse(total.toStringAsFixed(2));
    final cents = (roundedTotal * 100).round();
    final base = cents ~/ count;
    final remainder = cents % count;
    return List<double>.generate(count, (index) {
      final value = base + (index == count - 1 ? remainder : 0);
      return value / 100;
    });
  }

  String _humanizeError(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map) {
        final message = data['message'];
        if (message is List) {
          final joined = message
              .map((x) => x.toString())
              .where((x) => x.trim().isNotEmpty)
              .join(' | ');
          if (joined.trim().isNotEmpty) {
            return joined;
          }
        }
        if (message != null && message.toString().trim().isNotEmpty) {
          return message.toString();
        }
        final error = data['error'];
        if (error != null && error.toString().trim().isNotEmpty) {
          return error.toString();
        }
      }
      return e.message ?? 'Error de red';
    }
    final msg = e.toString();
    if (msg.startsWith('Bad state: ')) {
      return msg.substring('Bad state: '.length);
    }
    return msg;
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _handleBack() {
    FocusScope.of(context).unfocus();
    switch (_step) {
      case _ProductSaleStep.catalog:
        if (widget.isEdit) {
          setState(() => _step = _ProductSaleStep.payment);
        } else {
          Navigator.of(context).pop();
        }
        break;
      case _ProductSaleStep.confirm:
        setState(() => _step = _ProductSaleStep.catalog);
        break;
      case _ProductSaleStep.payment:
        if (widget.isEdit) {
          Navigator.of(context).pop();
        } else {
          setState(() => _step = _ProductSaleStep.confirm);
        }
        break;
    }
  }

  void _incrementProduct(Product product) {
    final maxQty = _maxQtyFor(product);
    if (maxQty <= 0) return;
    final current = _selectedQtyFor(product);
    if (current >= maxQty) return;
    setState(() {
      final line = _linesById.putIfAbsent(
        product.id,
        () => _ProductSaleLine(
          product: product,
          qty: 0,
          unitPriceUsd: product.priceRetailUsd,
        ),
      );
      line.product = product;
      line.qty += 1;
    });
  }

  void _decrementProduct(Product product) {
    final current = _selectedQtyFor(product);
    if (current <= 0) return;
    setState(() {
      final line = _linesById[product.id];
      if (line == null) return;
      line.qty -= 1;
      if (line.qty <= 0) {
        _linesById.remove(product.id);
      }
    });
  }

  void _removeLine(_ProductSaleLine line) {
    setState(() {
      _linesById.remove(line.product.id);
      if (_linesById.isEmpty && _step != _ProductSaleStep.catalog) {
        _step = _ProductSaleStep.catalog;
      }
    });
  }

  void _updateLineQty(_ProductSaleLine line, int qty) {
    final maxQty = _maxQtyFor(line.product);
    final nextQty = qty.clamp(1, maxQty);
    setState(() {
      line.qty = nextQty;
    });
  }

  void _updateLinePrice(_ProductSaleLine line, double price) {
    setState(() {
      line.unitPriceUsd = price;
    });
  }

  Future<void> _openCreateProduct() async {
    await showCreateProductSheet(context);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: _saleDate,
      locale: const Locale('es'),
    );
    if (picked == null) return;
    setState(() {
      _saleDate = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _saleDate.hour,
        _saleDate.minute,
        _saleDate.second,
        _saleDate.millisecond,
        _saleDate.microsecond,
      );
    });
  }

  List<PaymentMethod> _activeMethods(AppState state) {
    final methods = state.paymentMethods.where((m) => m.isActive).toList();
    if (methods.isNotEmpty) return methods;
    return const [
      PaymentMethod(
        code: 'CASH',
        name: 'Efectivo',
        isActive: true,
        sortOrder: 0,
      ),
    ];
  }

  void _ensurePaymentSlots(List<PaymentMethod> methods) {
    final fallbackCode = methods.first.code;
    while (_paymentSlots.length < _paymentCount) {
      _paymentSlots.add(_ProductSalePaymentSlot(methodCode: fallbackCode));
    }
    while (_paymentSlots.length > _paymentCount) {
      _paymentSlots.removeLast();
    }
    for (final slot in _paymentSlots) {
      if (!methods.any((method) => method.code == slot.methodCode)) {
        slot.methodCode = fallbackCode;
      }
    }
  }

  void _setPaymentCount(int count, List<PaymentMethod> methods) {
    setState(() {
      _paymentCount = count;
      _ensurePaymentSlots(methods);
    });
  }

  void _applyMethodToAll(String methodCode) {
    setState(() {
      for (final slot in _paymentSlots) {
        slot.methodCode = methodCode;
      }
    });
  }

  void _goToConfirm() {
    if (_lines.isEmpty) {
      _showSnack('Selecciona al menos un producto.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _step = _ProductSaleStep.confirm);
  }

  void _goToPayment(List<PaymentMethod> methods) {
    if (_lines.isEmpty) {
      _showSnack('Selecciona al menos un producto.');
      return;
    }
    for (final line in _lines) {
      if (line.qty <= 0) {
        _showSnack('La cantidad debe ser mayor a 0.');
        return;
      }
      if (line.unitPriceUsd <= 0) {
        _showSnack('El precio unitario debe ser mayor a 0.');
        return;
      }
    }
    _ensurePaymentSlots(methods);
    FocusScope.of(context).unfocus();
    setState(() {
      _step = _ProductSaleStep.payment;
      if (_conceptCtl.text.trim().isEmpty) {
        _conceptCtl.text = _defaultConceptFromLines(_lines);
      }
    });
  }

  Future<void> _submit(AppState state, List<PaymentMethod> methods) async {
    if (_submitting) return;
    if (_lines.isEmpty) {
      _showSnack('Selecciona al menos un producto.');
      return;
    }
    if (_total <= 0) {
      _showSnack('El valor de la venta debe ser mayor a 0.');
      return;
    }
    final warehouseId = (state.warehouseId ?? '').trim();
    if (warehouseId.isEmpty) {
      _showSnack(
        'No hay bodega seleccionada. Actualiza inventario o inicia sesión nuevamente.',
      );
      return;
    }

    final discountPct = _parseNum(_discountPctCtl.text);
    final discountUsd = _parseNum(_discountUsdCtl.text);
    final paymentAmounts = _splitAmounts(_total, _paymentCount);
    final concept = _conceptCtl.text.trim().isEmpty
        ? 'Venta'
        : _conceptCtl.text.trim();
    final receiptNote = _receiptCtl.text.trim();
    final paymentsPayload = _status == _ProductSaleStatus.debt
        ? <Map<String, dynamic>>[]
        : List<Map<String, dynamic>>.generate(_paymentSlots.length, (index) {
            final slot = _paymentSlots[index];
            return {
              'paymentMethodCode': slot.methodCode,
              'amountUsd': paymentAmounts[index],
              'concept': concept,
              'receiptNote': receiptNote,
            };
          });

    setState(() => _submitting = true);
    try {
      final itemsPayload = _lines
          .map(
            (line) => {
              'productId': line.product.id,
              'qty': line.qty,
              'unitPriceUsd': line.unitPriceUsd,
            },
          )
          .toList();
      if (widget.isEdit) {
        if (_saleId.isEmpty) {
          throw StateError('No se pudo editar: saleId vacío');
        }
        await state.editarVentaRecrear(
          saleId: _saleId,
          payload: {
            'saleType': 'INVENTARIO',
            'warehouseId': (state.warehouseId ?? '').trim(),
            'items': itemsPayload,
            if (discountPct > 0) 'discountPercent': discountPct,
            if (discountPct <= 0 && discountUsd > 0) 'discountUsd': discountUsd,
            'description': _conceptCtl.text.trim(),
            'receiptNote': receiptNote,
            'occurredAt': _saleDate.toUtc().toIso8601String(),
            'payments': paymentsPayload,
          },
        );
      } else {
        await state.crearVentaInventario(
          items: itemsPayload,
          discountPercent: discountPct > 0 ? discountPct : null,
          discountUsd: discountPct > 0
              ? null
              : (discountUsd > 0 ? discountUsd : null),
          note: _conceptCtl.text.trim(),
          receiptNote: receiptNote,
          occurredAt: _saleDate,
          payments: paymentsPayload,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(widget.isEdit ? true : null);
    } catch (e) {
      if (!mounted) return;
      _showSnack(
        widget.isEdit
            ? 'No se pudo editar la venta: ${_humanizeError(e)}'
            : 'No se pudo registrar la venta: ${_humanizeError(e)}',
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  List<Product> _visibleProducts(List<Product> products) {
    final merged = <String, Product>{
      for (final product in products) product.id: product,
    };
    for (final line in _lines) {
      merged.putIfAbsent(line.product.id, () => line.product);
    }
    final query = _searchCtl.text.trim().toLowerCase();
    final filtered = merged.values.where((product) {
      if (_selectedOnly && !_linesById.containsKey(product.id)) {
        return false;
      }
      if (_lowStockOnly && !_isLowStockQty(_remainingQtyFor(product))) {
        return false;
      }
      if (query.isEmpty) return true;
      final haystack = [
        product.name,
        product.barcode,
        product.reference,
        product.line,
        product.subLine,
        product.category,
        product.subCategory,
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();

    filtered.sort((a, b) {
      final aSelected = _selectedQtyFor(a) > 0;
      final bSelected = _selectedQtyFor(b) > 0;
      if (aSelected != bSelected) {
        return aSelected ? -1 : 1;
      }
      if (_sortByStock) {
        return b.stock.compareTo(a.stock);
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return filtered;
  }

  Widget _buildCatalogStep(BuildContext context, AppState state) {
    final products = _visibleProducts(state.products);
    final canAdd = _lines.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      children: [
        OutlinedButton.icon(
          onPressed: _openCreateProduct,
          style: OutlinedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: AppTheme.navy,
            side: const BorderSide(color: AppTheme.navy, width: 1.8),
            minimumSize: const Size.fromHeight(70),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
          icon: const Icon(Icons.add_circle_outline_rounded, size: 30),
          label: const Text('Nuevo producto'),
        ),
        if (_showSearch) ...[
          const SizedBox(height: 14),
          TextField(
            controller: _searchCtl,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Buscar productos',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searchCtl.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _searchCtl.clear();
                        setState(() {});
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: const BorderSide(color: _saleFlowBorderColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: const BorderSide(color: _saleFlowBorderColor),
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            _CatalogActionButton(
              icon: Icons.sort_rounded,
              filled: _sortByStock,
              tooltip: _sortByStock
                  ? 'Ordenando por stock'
                  : 'Ordenar por stock',
              onTap: () => setState(() => _sortByStock = !_sortByStock),
            ),
            const SizedBox(width: 12),
            _CatalogActionButton(
              icon: Icons.edit_outlined,
              filled: _selectedOnly,
              tooltip: _selectedOnly
                  ? 'Mostrando solo seleccionados'
                  : 'Mostrar solo seleccionados',
              onTap: () => setState(() => _selectedOnly = !_selectedOnly),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _CatalogScopeChip(
                      label: 'Todas',
                      selected: !_lowStockOnly,
                      selectedColor: _saleFlowHeaderColor,
                      selectedTextColor: Colors.white,
                      onTap: () => setState(() => _lowStockOnly = false),
                    ),
                    const SizedBox(width: 10),
                    _CatalogScopeChip(
                      label: 'Stock bajo',
                      selected: _lowStockOnly,
                      selectedColor: _saleFlowHeaderColor,
                      selectedTextColor: Colors.white,
                      leading: const Icon(
                        Icons.workspace_premium_rounded,
                        size: 18,
                        color: Colors.white,
                      ),
                      onTap: () => setState(() => _lowStockOnly = true),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (products.isEmpty)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _saleFlowBorderColor),
            ),
            child: const Text(
              'No hay productos para mostrar con esos filtros.',
              style: TextStyle(
                color: _saleFlowMutedText,
                fontWeight: FontWeight.w700,
              ),
            ),
          )
        else
          ...products.map(
            (product) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _CatalogProductCard(
                product: product,
                selectedQty: _selectedQtyFor(product),
                remainingQty: _remainingQtyFor(product),
                onMinus: () => _decrementProduct(product),
                onPlus: () => _incrementProduct(product),
              ),
            ),
          ),
        if (!canAdd) const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildConfirmStep(BuildContext context) {
    final infoText = widget.isEdit
        ? 'Al guardar la venta se actualizarán las unidades seleccionadas de tu inventario.'
        : 'Al crear la venta se descontarán las unidades seleccionadas de tu inventario.';
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFDCEBFB),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF1A78D7), width: 1.6),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.info_outline_rounded,
                color: Color(0xFF1A78D7),
                size: 26,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  infoText,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.3,
                    color: AppTheme.navy,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        ..._lines.map(
          (line) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _ConfirmProductCard(
              line: line,
              maxQty: _maxQtyFor(line.product),
              onRemove: () => _removeLine(line),
              onQtyChanged: (qty) => _updateLineQty(line, qty),
              onPriceChanged: (price) => _updateLinePrice(line, price),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentStep(BuildContext context, AppState state) {
    final methods = _activeMethods(state);
    _ensurePaymentSlots(methods);
    final paymentAmounts = _splitAmounts(_total, _paymentSlots.length);
    final dateLabel = DateFormat('d MMMM', 'es').format(_saleDate);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      children: [
        _SaleStatusToggle(
          value: _status,
          onChanged: (value) => setState(() => _status = value),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: const TextStyle(
                    fontSize: 16,
                    color: AppTheme.navy,
                    fontWeight: FontWeight.w700,
                  ),
                  children: [
                    const TextSpan(text: 'Fecha de la venta : '),
                    TextSpan(
                      text: dateLabel,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
            ),
            TextButton(
              onPressed: _pickDate,
              child: const Text(
                'Editar',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_status == _ProductSaleStatus.paid) ...[
          const Text(
            'Selecciona el número de pagos y su método *',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppTheme.navy,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 52,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: 8,
              separatorBuilder: (context, index) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final count = index + 1;
                final selected = count == _paymentCount;
                return _PaymentCountChip(
                  label: '$count',
                  selected: selected,
                  onTap: () => _setPaymentCount(count, methods),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _paymentCount == 1
                ? 'Método de pago'
                : 'Método por defecto para los $_paymentCount pagos',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppTheme.navy,
            ),
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final spacing = 8.0;
              final width = ((constraints.maxWidth - (spacing * 2)) / 3).clamp(
                82.0,
                168.0,
              );
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: methods.map((method) {
                  final selected =
                      _paymentSlots.isNotEmpty &&
                      _paymentSlots.every(
                        (slot) => slot.methodCode == method.code,
                      );
                  return SizedBox(
                    width: width,
                    child: _PaymentMethodTile(
                      method: method,
                      selected: selected,
                      onTap: () => _applyMethodToAll(method.code),
                    ),
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: 12),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _saleFlowBorderColor),
            ),
            child: const Text(
              'La venta se registrará sin pagos para manejarla como deuda.',
              style: TextStyle(
                fontSize: 13,
                color: _saleFlowMutedText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],
        const Text(
          'Descuento',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppTheme.navy,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _discountPctCtl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: AppInputFormatters.decimal(maxDecimals: 2),
                decoration: _saleInputDecoration(hintText: '0%'),
                onChanged: (_) {
                  if (_discountPctCtl.text.trim().isNotEmpty) {
                    _discountUsdCtl.clear();
                  }
                  setState(() {});
                },
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                '=',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.navy,
                ),
              ),
            ),
            Expanded(
              child: TextField(
                controller: _discountUsdCtl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: AppInputFormatters.decimal(maxDecimals: 2),
                decoration: _saleInputDecoration(hintText: '\$ 0'),
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
        const SizedBox(height: 14),
        const Text(
          'Cliente',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppTheme.navy,
          ),
        ),
        const SizedBox(height: 8),
        _PlaceholderPickerField(
          label: 'Selecciona un cliente',
          onTap: () => _showSnack('Clientes: próximamente'),
        ),
        if (widget.isEdit) ...[
          const SizedBox(height: 14),
          _SelectedProductsCard(
            count: _selectedLineCount,
            onTap: () => setState(() => _step = _ProductSaleStep.catalog),
          ),
        ],
        const SizedBox(height: 14),
        _ExpandableSectionCard(
          title: 'Más opciones',
          expanded: _moreOptionsExpanded,
          onTap: () =>
              setState(() => _moreOptionsExpanded = !_moreOptionsExpanded),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 6),
              const Text(
                'Concepto',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.navy,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _conceptCtl,
                decoration: _saleInputDecoration(
                  hintText: 'Dale un nombre a tu venta',
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Nota en el comprobante',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.navy,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _receiptCtl,
                minLines: 2,
                maxLines: 3,
                decoration: _saleInputDecoration(hintText: 'Agregar nota...'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _ExpandableSectionCard(
          title: 'Detalle del pago',
          expanded: _paymentDetailExpanded,
          onTap: () =>
              setState(() => _paymentDetailExpanded = !_paymentDetailExpanded),
          child: _status == _ProductSaleStatus.debt
              ? const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'No hay pagos configurados para esta venta.',
                    style: TextStyle(
                      color: _saleFlowMutedText,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              : Column(
                  children: List<Widget>.generate(_paymentSlots.length, (
                    index,
                  ) {
                    final slot = _paymentSlots[index];
                    return Padding(
                      padding: EdgeInsets.only(
                        top: index == 0 ? 8 : 12,
                        bottom: index == _paymentSlots.length - 1 ? 0 : 0,
                      ),
                      child: _PaymentDetailRow(
                        index: index,
                        amount: paymentAmounts[index],
                        methods: methods,
                        methodCode: slot.methodCode,
                        onChanged: (value) {
                          setState(() => slot.methodCode = value);
                        },
                      ),
                    );
                  }),
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final methods = _activeMethods(state);
    _ensurePaymentSlots(methods);

    final title = switch (_step) {
      _ProductSaleStep.catalog => 'Seleccionar productos',
      _ProductSaleStep.confirm => 'Confirma precios y cantidades',
      _ProductSaleStep.payment =>
        widget.isEdit ? 'Editar venta' : 'Nueva venta',
    };

    return PopScope<void>(
      canPop: _canPopRoute,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _handleBack();
        }
      },
      child: Scaffold(
        backgroundColor: _saleFlowBackground,
        appBar: AppBar(
          backgroundColor: _saleFlowHeaderColor,
          foregroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          systemOverlayStyle: AppTheme.bannerOverlay,
          leading: IconButton(
            onPressed: _handleBack,
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: 'Volver',
          ),
          title: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 22,
            ),
          ),
          actions: _step == _ProductSaleStep.catalog
              ? [
                  IconButton(
                    onPressed: () => setState(() => _showSearch = !_showSearch),
                    icon: const Icon(Icons.search_rounded),
                    tooltip: 'Buscar',
                  ),
                  IconButton(
                    onPressed: () =>
                        _showSnack('Escáner de código: próximamente'),
                    icon: const Icon(Icons.qr_code_scanner_rounded),
                    tooltip: 'Escanear',
                  ),
                ]
              : null,
        ),
        body: SafeArea(
          top: false,
          child: switch (_step) {
            _ProductSaleStep.catalog => _buildCatalogStep(context, state),
            _ProductSaleStep.confirm => _buildConfirmStep(context),
            _ProductSaleStep.payment => _buildPaymentStep(context, state),
          },
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: _SaleBottomButton(
              count: _selectedLineCount,
              amountUsd: _step == _ProductSaleStep.payment ? _total : _subtotal,
              label: switch (_step) {
                _ProductSaleStep.catalog => 'Añadir productos',
                _ProductSaleStep.confirm => 'Confirmar',
                _ProductSaleStep.payment =>
                  widget.isEdit ? 'Guardar' : 'Crear venta',
              },
              enabled: switch (_step) {
                _ProductSaleStep.catalog => _lines.isNotEmpty,
                _ProductSaleStep.confirm => _lines.isNotEmpty,
                _ProductSaleStep.payment =>
                  !_submitting &&
                      _lines.isNotEmpty &&
                      (!widget.isEdit || _isDirty),
              },
              loading: _submitting,
              onTap: () {
                switch (_step) {
                  case _ProductSaleStep.catalog:
                    _goToConfirm();
                    break;
                  case _ProductSaleStep.confirm:
                    _goToPayment(methods);
                    break;
                  case _ProductSaleStep.payment:
                    _submit(state, methods);
                    break;
                }
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _CatalogActionButton extends StatelessWidget {
  const _CatalogActionButton({
    required this.icon,
    required this.filled,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final bool filled;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final background = filled ? AppTheme.navy : Colors.white;
    final foreground = filled ? Colors.white : AppTheme.navy;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: filled ? AppTheme.navy : _saleFlowBorderColor,
                width: 1.4,
              ),
            ),
            child: Icon(icon, color: foreground, size: 24),
          ),
        ),
      ),
    );
  }
}

class _CatalogScopeChip extends StatelessWidget {
  const _CatalogScopeChip({
    required this.label,
    required this.selected,
    required this.selectedColor,
    required this.selectedTextColor,
    required this.onTap,
    this.leading,
  });

  final String label;
  final bool selected;
  final Color selectedColor;
  final Color selectedTextColor;
  final VoidCallback onTap;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? selectedColor : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? selectedColor : _saleFlowBorderColor,
              width: 1.4,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 8)],
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: selected ? selectedTextColor : AppTheme.navy,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CatalogProductCard extends StatelessWidget {
  const _CatalogProductCard({
    required this.product,
    required this.selectedQty,
    required this.remainingQty,
    required this.onMinus,
    required this.onPlus,
  });

  final Product product;
  final int selectedQty;
  final int remainingQty;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    final selected = selectedQty > 0;
    final low = remainingQty == 0 || remainingQty < _saleLowStockThreshold;
    final stockBg = remainingQty == 0
        ? const Color(0xFFFDE8E7)
        : (low ? const Color(0xFFFDE8E7) : const Color(0xFFDDF6EA));
    final stockFg = remainingQty == 0
        ? AppTheme.red
        : (low ? AppTheme.red : const Color(0xFF0F7B4F));
    final stockLabel = remainingQty == 0
        ? 'No disponible'
        : '$remainingQty disponibles';

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected ? AppTheme.green : _saleFlowBorderColor,
          width: selected ? 2.0 : 1.3,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SaleProductThumb(product: product, size: 76),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.navy,
                        ),
                      ),
                    ),
                    if (low)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFDE8E7),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Icon(
                          Icons.info_outline_rounded,
                          color: AppTheme.red,
                          size: 14,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: stockBg,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    stockLabel,
                    style: TextStyle(
                      fontSize: 12,
                      color: stockFg,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '\$${product.priceRetailUsd.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.navy,
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: _StepperPill(
                    value: '$selectedQty',
                    onMinus: selectedQty > 0 ? onMinus : null,
                    onPlus: remainingQty > 0 ? onPlus : null,
                    compact: true,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfirmProductCard extends StatefulWidget {
  const _ConfirmProductCard({
    required this.line,
    required this.maxQty,
    required this.onRemove,
    required this.onQtyChanged,
    required this.onPriceChanged,
  });

  final _ProductSaleLine line;
  final int maxQty;
  final VoidCallback onRemove;
  final ValueChanged<int> onQtyChanged;
  final ValueChanged<double> onPriceChanged;

  @override
  State<_ConfirmProductCard> createState() => _ConfirmProductCardState();
}

class _ConfirmProductCardState extends State<_ConfirmProductCard> {
  late final TextEditingController _priceCtl;

  @override
  void initState() {
    super.initState();
    _priceCtl = TextEditingController(
      text: widget.line.unitPriceUsd.toStringAsFixed(2),
    );
  }

  @override
  void didUpdateWidget(covariant _ConfirmProductCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.line.unitPriceUsd.toStringAsFixed(2);
    if (_priceCtl.text != next) {
      _priceCtl.text = next;
    }
  }

  @override
  void dispose() {
    _priceCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final line = widget.line;
    final maxQty = math.max(1, widget.maxQty);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _saleFlowBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _SaleProductThumb(product: line.product, size: 40),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  line.product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.navy,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              OutlinedButton(
                onPressed: widget.onRemove,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.red,
                  side: const BorderSide(color: AppTheme.red, width: 1.6),
                  padding: const EdgeInsets.all(8),
                  minimumSize: const Size(42, 42),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Icon(Icons.delete_outline_rounded, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Cantidad *',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.navy,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _StepperPill(
                      value: '${line.qty}',
                      onMinus: line.qty > 1
                          ? () => widget.onQtyChanged(line.qty - 1)
                          : null,
                      onPlus: line.qty < maxQty
                          ? () => widget.onQtyChanged(line.qty + 1)
                          : null,
                      compact: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Precio unitario *',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.navy,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _priceCtl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: AppInputFormatters.decimal(
                        maxDecimals: 2,
                      ),
                      decoration: _saleInputDecoration(prefixText: '\$ '),
                      onChanged: (value) => widget.onPriceChanged(
                        double.tryParse(value.replaceAll(',', '.')) ?? 0,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Precio por 1 unidad: \$${line.unitPriceUsd.toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 13,
              color: AppTheme.navy,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Divider(color: Colors.black.withValues(alpha: 0.10)),
        ],
      ),
    );
  }
}

class _SaleStatusToggle extends StatelessWidget {
  const _SaleStatusToggle({required this.value, required this.onChanged});

  final _ProductSaleStatus value;
  final ValueChanged<_ProductSaleStatus> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget tab(String label, _ProductSaleStatus status) {
      final selected = value == status;
      return Expanded(
        child: GestureDetector(
          onTap: () => onChanged(status),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected ? AppTheme.green : Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : AppTheme.navy,
                fontWeight: FontWeight.w900,
                fontSize: 15,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _saleFlowBorderColor),
      ),
      child: Row(
        children: [
          tab('Pagado', _ProductSaleStatus.paid),
          const SizedBox(width: 4),
          tab('Deuda', _ProductSaleStatus.debt),
        ],
      ),
    );
  }
}

class _PaymentCountChip extends StatelessWidget {
  const _PaymentCountChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: selected ? _saleFlowHeaderColor : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? _saleFlowHeaderColor : _saleFlowBorderColor,
              width: 1.4,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: selected ? Colors.white : AppTheme.navy,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PaymentMethodTile extends StatelessWidget {
  const _PaymentMethodTile({
    required this.method,
    required this.selected,
    required this.onTap,
  });

  final PaymentMethod method;
  final bool selected;
  final VoidCallback onTap;

  IconData _iconForMethod() {
    final key = '${method.code} ${method.name}'.toUpperCase();
    if (key.contains('CASH') || key.contains('EFECTIVO')) {
      return Icons.payments_outlined;
    }
    if (key.contains('CARD') || key.contains('TARJETA')) {
      return Icons.credit_card_outlined;
    }
    if (key.contains('TRANSFER')) {
      return Icons.account_balance_outlined;
    }
    if (key.contains('PAGO MOVIL') ||
        key.contains('PAGO_M') ||
        key.contains('MOVIL')) {
      return Icons.chat_bubble_outline_rounded;
    }
    if (key.contains('ZELLE')) {
      return Icons.flash_on_outlined;
    }
    if (key.contains('BINANCE')) {
      return Icons.currency_bitcoin_outlined;
    }
    return Icons.account_balance_wallet_outlined;
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? _saleFlowHeaderColor : _saleFlowBorderColor,
              width: selected ? 1.8 : 1.4,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _iconForMethod(),
                size: 24,
                color: selected ? _saleFlowHeaderColor : AppTheme.navy,
              ),
              const SizedBox(height: 6),
              Text(
                method.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.2,
                  fontWeight: FontWeight.w800,
                  color: selected ? _saleFlowHeaderColor : AppTheme.navy,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaceholderPickerField extends StatelessWidget {
  const _PlaceholderPickerField({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _saleFlowBorderColor),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF98A2B3),
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 28,
                color: AppTheme.navy,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectedProductsCard extends StatelessWidget {
  const _SelectedProductsCard({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _saleFlowBorderColor),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFF6F8FB),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.shopping_bag_outlined,
                  color: _saleFlowHeaderColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Seleccionar productos',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.navy,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Al agregar productos se actualizará tu inventario automáticamente',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.25,
                        color: _saleFlowMutedText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: Color(0xFFDCEBFB),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: _saleFlowHeaderColor,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.chevron_right_rounded,
                size: 28,
                color: AppTheme.navy,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExpandableSectionCard extends StatelessWidget {
  const _ExpandableSectionCard({
    required this.title,
    required this.expanded,
    required this.onTap,
    required this.child,
  });

  final String title;
  final bool expanded;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.navy,
                    ),
                  ),
                ),
                Icon(
                  expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 28,
                  color: AppTheme.navy,
                ),
              ],
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: child,
            crossFadeState: expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 180),
          ),
        ],
      ),
    );
  }
}

class _PaymentDetailRow extends StatelessWidget {
  const _PaymentDetailRow({
    required this.index,
    required this.amount,
    required this.methods,
    required this.methodCode,
    required this.onChanged,
  });

  final int index;
  final double amount;
  final List<PaymentMethod> methods;
  final String methodCode;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _saleFlowBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _saleFlowBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Pago ${index + 1}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: AppTheme.navy,
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: methodCode,
            items: methods
                .map(
                  (method) => DropdownMenuItem(
                    value: method.code,
                    child: Text(method.name),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null && value.trim().isNotEmpty) {
                onChanged(value);
              }
            },
            decoration: _saleInputDecoration(labelText: 'Método'),
          ),
          const SizedBox(height: 8),
          Text(
            'Monto: \$${amount.toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 13,
              color: AppTheme.navy,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _StepperPill extends StatelessWidget {
  const _StepperPill({
    required this.value,
    required this.onMinus,
    required this.onPlus,
    this.compact = false,
  });

  final String value;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final horizontalPadding = compact ? 6.0 : 10.0;
    final verticalPadding = compact ? 4.0 : 8.0;
    final borderRadius = compact ? 16.0 : 22.0;
    final valueWidth = compact ? 38.0 : 54.0;
    final fontSize = compact ? 14.0 : 18.0;
    final buttonSize = compact ? 30.0 : 42.0;
    final iconSize = compact ? 20.0 : 26.0;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: verticalPadding,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: _saleFlowBorderColor, width: 1.4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepperIconButton(
            icon: Icons.remove_rounded,
            enabled: onMinus != null,
            onTap: onMinus,
            size: buttonSize,
            iconSize: iconSize,
          ),
          SizedBox(
            width: valueWidth,
            child: Text(
              value,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w900,
                color: AppTheme.navy,
              ),
            ),
          ),
          _StepperIconButton(
            icon: Icons.add_rounded,
            enabled: onPlus != null,
            onTap: onPlus,
            size: buttonSize,
            iconSize: iconSize,
          ),
        ],
      ),
    );
  }
}

class _StepperIconButton extends StatelessWidget {
  const _StepperIconButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
    required this.size,
    required this.iconSize,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: enabled ? AppTheme.navy : _saleFlowBorderColor,
              width: 1.4,
            ),
          ),
          child: Icon(
            icon,
            size: iconSize,
            color: enabled ? AppTheme.navy : const Color(0xFF98A2B3),
          ),
        ),
      ),
    );
  }
}

class _SaleBottomButton extends StatelessWidget {
  const _SaleBottomButton({
    required this.count,
    required this.amountUsd,
    required this.label,
    required this.enabled,
    required this.loading,
    required this.onTap,
  });

  final int count;
  final double amountUsd;
  final String label;
  final bool enabled;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = enabled ? AppTheme.navy : const Color(0xFFD5DDE7);
    final fg = enabled ? Colors.white : const Color(0xFF9AA3AE);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled && !loading ? onTap : null,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: enabled
                      ? const Color(0xFF334A6B)
                      : Colors.white.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: fg,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: loading
                    ? const SizedBox(
                        height: 20,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.6,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      )
                    : Text(
                        label,
                        style: TextStyle(
                          color: fg,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
              ),
              const SizedBox(width: 8),
              Text(
                '\$${amountUsd.toStringAsFixed(0)}',
                style: TextStyle(
                  color: fg,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded, color: fg, size: 26),
            ],
          ),
        ),
      ),
    );
  }
}

class _SaleProductThumb extends StatelessWidget {
  const _SaleProductThumb({required this.product, required this.size});

  final Product product;
  final double size;

  @override
  Widget build(BuildContext context) {
    final resolved = context.read<AppState>().resolveApiUrl(product.imageUrl);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFFF2E0FA),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _saleFlowBorderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: (resolved ?? '').trim().isEmpty
          ? Container(
              color: const Color(0xFFF2E0FA),
              alignment: Alignment.center,
              child: const Icon(
                Icons.inventory_2_outlined,
                color: Color(0xFFD2B3E8),
                size: 38,
              ),
            )
          : Image.network(
              resolved!,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                color: const Color(0xFFF2E0FA),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.inventory_2_outlined,
                  color: Color(0xFFD2B3E8),
                  size: 38,
                ),
              ),
            ),
    );
  }
}
