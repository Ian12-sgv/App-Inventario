import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/product.dart';
import '../../state/app_state.dart';
import '../../ui/app_theme.dart';
import '../../ui/input_formatters.dart';
import '../inventory/product_sheets.dart';

const Color _expenseFlowHeaderColor = AppTheme.bannerBlue;
const Color _expenseFlowBackground = Color(0xFFF3F4F6);
const Color _expenseFlowBorderColor = Color(0xFFD5DDE7);
const Color _expenseFlowMutedText = Color(0xFF667085);
const double _expenseLowStockThreshold = 3;

const SystemUiOverlayStyle _expenseFlowOverlay = AppTheme.bannerOverlay;

const String _expenseInventoryCategoryCode = 'COMPRA_PRODUCTOS_E_INSUMOS';
const Set<String> _expenseInventoryCategoryAliases = {
  _expenseInventoryCategoryCode,
  'COMPRA_DE_PRODUCTOS_E_INSUMOS',
};

const List<String> _expenseCategoryFallbacks = [
  'Servicios públicos',
  'Compra de productos e insumos',
  'Arriendo',
  'Nómina',
  'Gastos administrativos',
  'Mercadeo y publicidad',
  'Transporte, domicilios y logística',
  'Mantenimiento y reparaciones',
  'Muebles, equipos o maquinaria',
  'Otros',
];

Future<void> showExpenseFlow(BuildContext context) async {
  await Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const ExpenseFlowScreen()));
}

Future<String?> showEditExpenseFlow(
  BuildContext context, {
  required Map<String, dynamic> expense,
  required String expenseId,
  List<Map<String, dynamic>> prefillPayments = const [],
  List<Map<String, dynamic>> lineRows = const [],
}) async {
  return Navigator.of(context).push<String>(
    MaterialPageRoute(
      builder: (_) => ExpenseFlowScreen(
        isEdit: true,
        existingExpense: expense,
        expenseId: expenseId,
        prefillPayments: prefillPayments,
        initialLineRows: lineRows,
      ),
    ),
  );
}

String _expenseText(dynamic value) => (value ?? '').toString().trim();

double _expenseToDouble(dynamic value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}

String _expenseNormalizeKey(String value) {
  var normalized = value.trim().toUpperCase();
  const replacements = {
    'Á': 'A',
    'É': 'E',
    'Í': 'I',
    'Ó': 'O',
    'Ú': 'U',
    'Ñ': 'N',
  };
  replacements.forEach((from, to) {
    normalized = normalized.replaceAll(from, to);
  });
  return normalized
      .replaceAll(RegExp(r'[^A-Z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
}

bool _expenseIsInventoryCategory(String? category) {
  return _expenseInventoryCategoryAliases.contains(
    _expenseNormalizeKey(category ?? ''),
  );
}

String _expenseCategoryPayloadValue(String? category) {
  final raw = _expenseText(category);
  if (raw.isEmpty) return raw;
  return _expenseIsInventoryCategory(raw) ? _expenseInventoryCategoryCode : raw;
}

String _expenseHumanizeError(Object e) {
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

InputDecoration _expenseInputDecoration({
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
      borderSide: const BorderSide(color: _expenseFlowBorderColor),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: _expenseFlowBorderColor),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: AppTheme.bannerBlue, width: 1.4),
    ),
  );
}

enum _ExpenseStep { form, catalog, confirm }

enum _ExpenseStatus { paid, debt }

class _ExpensePurchaseLine {
  _ExpensePurchaseLine({
    required this.product,
    required this.qty,
    required this.unitCostUsd,
  });

  Product product;
  int qty;
  double unitCostUsd;

  double get subtotal => qty * unitCostUsd;
}

class ExpenseFlowScreen extends StatefulWidget {
  const ExpenseFlowScreen({
    super.key,
    this.isEdit = false,
    this.existingExpense,
    this.expenseId,
    this.prefillPayments = const [],
    this.initialLineRows = const [],
  });

  final bool isEdit;
  final Map<String, dynamic>? existingExpense;
  final String? expenseId;
  final List<Map<String, dynamic>> prefillPayments;
  final List<Map<String, dynamic>> initialLineRows;

  @override
  State<ExpenseFlowScreen> createState() => _ExpenseFlowScreenState();
}

class _ExpenseFlowScreenState extends State<ExpenseFlowScreen> {
  final _searchCtl = TextEditingController();
  final _conceptCtl = TextEditingController();

  final Map<String, _ExpensePurchaseLine> _linesById = {};

  _ExpenseStep _step = _ExpenseStep.form;
  _ExpenseStatus _status = _ExpenseStatus.paid;
  DateTime _expenseDate = DateTime.now();
  String? _category;
  String? _selectedMethodCode;
  bool _showAmountPad = false;
  bool _showSearch = false;
  bool _lowStockOnly = false;
  bool _selectedOnly = false;
  bool _sortByStock = false;
  bool _submitting = false;
  double _amountUsd = 0;
  String _amountExpression = '';
  String _initialSignature = '';

  String get _expenseId => (widget.expenseId ?? '').trim();

  bool get _isDirty => !widget.isEdit || _buildSignature() != _initialSignature;

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
    _conceptCtl.dispose();
    super.dispose();
  }

  List<_ExpensePurchaseLine> get _lines => _linesById.values.toList();

  int get _selectedLineCount => _lines.length;

  bool get _isInventoryPurchase => _expenseIsInventoryCategory(_category);

  bool get _canPopRoute => switch (_step) {
    _ExpenseStep.form => !_showAmountPad,
    _ExpenseStep.catalog => false,
    _ExpenseStep.confirm => false,
  };

  double get _purchaseSubtotal =>
      _lines.fold<double>(0, (sum, line) => sum + line.subtotal);

  double get _subtotal => _isInventoryPurchase && _lines.isNotEmpty
      ? _purchaseSubtotal
      : _amountUsd;

  String get _displayAmount {
    if (_showAmountPad) {
      return _amountExpression.isEmpty ? '0' : _amountExpression;
    }
    return _formatEditableAmount(_amountUsd);
  }

  String _formatEditableAmount(double value) {
    final text = value.toStringAsFixed(value % 1 == 0 ? 0 : 2);
    return text.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  String _money(double value) =>
      '\$${value.toStringAsFixed(value % 1 == 0 ? 0 : 2)}';

  DateTime _parseExpenseDate(dynamic raw) {
    if (raw is DateTime) {
      return raw.isUtc ? raw.toLocal() : raw;
    }
    final parsed = raw == null ? null : DateTime.tryParse(raw.toString());
    if (parsed == null) return DateTime.now();
    return parsed.isUtc ? parsed.toLocal() : parsed;
  }

  String _resolveMethodCode(
    List<PaymentMethod> methods,
    String label, {
    String fallback = 'CASH',
  }) {
    final raw = label.trim();
    if (raw.isEmpty) return fallback;
    final wanted = _expenseNormalizeKey(raw);
    for (final method in methods) {
      if (_expenseNormalizeKey(method.code) == wanted) return method.code;
      if (_expenseNormalizeKey(method.name) == wanted) return method.code;
    }
    return fallback;
  }

  bool _isDebtExpense(Map<String, dynamic> expense) {
    final status = _expenseText(expense['status']);
    final statusLabel = _expenseText(expense['statusLabel']);
    final normalized = _expenseNormalizeKey('$status $statusLabel');
    return normalized.contains('DEUDA') || normalized.contains('DEBT');
  }

  Product? _productFromLineRow(Map<String, dynamic> row, AppState state) {
    final productMap = (row['product'] is Map)
        ? (row['product'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};
    final productId = _expenseText(
      row['productId'] ?? row['product_id'] ?? productMap['id'],
    );
    if (productId.isEmpty) return null;

    for (final product in state.products) {
      if (product.id == productId) return product;
    }

    final stock = _expenseToDouble(
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
      'cost':
          row['unitCostUsd'] ??
          row['unitCost'] ??
          row['costUsd'] ??
          row['cost'] ??
          productMap['cost'] ??
          productMap['costUsd'],
    };
    return Product.fromApi(merged, stock: stock);
  }

  _ExpensePurchaseLine? _lineFromRow(Map<String, dynamic> row, AppState state) {
    final product = _productFromLineRow(row, state);
    if (product == null) return null;
    final qty = _expenseToDouble(row['qty']);
    final explicitUnit = _expenseToDouble(
      row['unitCostUsd'] ??
          row['unitCost'] ??
          row['costUsd'] ??
          row['cost'] ??
          row['unitPriceUsd'] ??
          row['unitPrice'],
    );
    final explicitTotal = _expenseToDouble(
      row['lineTotalUsd'] ??
          row['totalUsd'] ??
          row['subtotalUsd'] ??
          row['amountUsd'],
    );
    final derivedUnit = explicitUnit > 0
        ? explicitUnit
        : (qty > 0 && explicitTotal > 0 ? explicitTotal / qty : 0.0);
    return _ExpensePurchaseLine(
      product: product,
      qty: math.max(1, qty.round()),
      unitCostUsd: derivedUnit > 0
          ? derivedUnit
          : (product.costUsd > 0 ? product.costUsd : 0.0),
    );
  }

  List<Map<String, dynamic>> _paymentRowsForExpense(
    AppState state,
    List<PaymentMethod> methods,
  ) {
    final expense = widget.existingExpense;
    if (expense == null || _expenseId.isEmpty) {
      return widget.prefillPayments;
    }

    final isDebt = _isDebtExpense(expense);
    if (isDebt) return const [];

    if (widget.prefillPayments.isNotEmpty) {
      return widget.prefillPayments;
    }

    final related =
        state.txnsForDay
            .where((txn) => (txn.expenseId ?? '') == _expenseId)
            .toList()
          ..sort((a, b) => a.when.compareTo(b.when));
    final wantedKind = isDebt ? 'ABONO' : 'GASTO';
    final rows = related
        .where((txn) => (txn.kind ?? '').toUpperCase() == wantedKind)
        .toList();
    if (rows.isNotEmpty) {
      return rows
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

    final expenseMethod = _expenseText(
      expense['paymentMethodCode'] ??
          expense['paymentMethodName'] ??
          expense['paymentMethod'] ??
          expense['metodoPago'],
    );
    if (expenseMethod.isEmpty || isDebt) return const [];
    return [
      {
        'paymentMethodCode': _resolveMethodCode(
          methods,
          expenseMethod,
          fallback: methods.first.code,
        ),
        'amountUsd': _expenseToDouble(
          expense['totalUsd'] ?? expense['amountUsd'] ?? expense['montoUsd'],
        ),
      },
    ];
  }

  List<Map<String, dynamic>> _buildItemsPayloadFromLines(
    List<_ExpensePurchaseLine> lines,
  ) {
    return lines
        .map(
          (line) => {
            'productId': line.product.id,
            'qty': line.qty,
            'unitCost': line.unitCostUsd,
            'unitCostUsd': line.unitCostUsd,
          },
        )
        .toList();
  }

  String _categoryForSignature() {
    final raw = _expenseText(_category);
    return _expenseIsInventoryCategory(raw)
        ? 'Compra de productos e insumos'
        : raw;
  }

  String _buildSignature() {
    final linesKey = _lines.toList()
      ..sort((a, b) => a.product.id.compareTo(b.product.id));
    final lineKey = linesKey
        .map(
          (line) =>
              '${line.product.id}:${line.qty}:${line.unitCostUsd.toStringAsFixed(2)}',
        )
        .join('|');
    return [
      _status.name,
      _expenseDate.toIso8601String(),
      _categoryForSignature(),
      (_selectedMethodCode ?? '').trim(),
      _amountUsd.toStringAsFixed(2),
      _conceptCtl.text.trim(),
      lineKey,
    ].join('||');
  }

  void _prefillEditState() {
    final expense = widget.existingExpense;
    if (expense == null) {
      _initialSignature = _buildSignature();
      return;
    }

    final state = context.read<AppState>();
    final methods = _activeMethods(state);

    _step = _ExpenseStep.form;
    _expenseDate = _parseExpenseDate(
      expense['occurredAt'] ?? expense['occurred_at'],
    );

    final rawCategory = _expenseText(
      expense['categoryLabel'] ?? expense['category'],
    );
    _category = _expenseIsInventoryCategory(rawCategory)
        ? 'Compra de productos e insumos'
        : rawCategory;

    _amountUsd = _expenseToDouble(
      expense['totalUsd'] ?? expense['amountUsd'] ?? expense['montoUsd'],
    );
    _amountExpression = _formatEditableAmount(_amountUsd);
    _conceptCtl.text = _expenseText(
      expense['description'] ?? expense['concept'],
    );

    _linesById.clear();
    for (final row in widget.initialLineRows) {
      final line = _lineFromRow(row, state);
      if (line == null) continue;
      _linesById[line.product.id] = line;
    }
    if (_isInventoryPurchase && _lines.isNotEmpty) {
      _amountUsd = 0;
      if (_conceptCtl.text.trim().isEmpty) {
        _conceptCtl.text = _defaultConceptFromLines(_lines);
      }
    }

    final paymentRows = _paymentRowsForExpense(state, methods);
    if (paymentRows.isNotEmpty) {
      _status = _ExpenseStatus.paid;
      _selectedMethodCode =
          _expenseText(paymentRows.first['paymentMethodCode']).isEmpty
          ? methods.first.code
          : _expenseText(paymentRows.first['paymentMethodCode']);
    } else {
      _status = _isDebtExpense(expense)
          ? _ExpenseStatus.debt
          : _ExpenseStatus.paid;
      _ensureSelectedMethod(methods);
    }

    _initialSignature = _buildSignature();
  }

  bool _isOperator(String token) {
    return token == '+' || token == '-' || token == 'x' || token == '/';
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

  List<String> _categoriesFor(AppState state) {
    final raw = state.expenseCategories.isNotEmpty
        ? state.expenseCategories
        : _expenseCategoryFallbacks;
    final categories = <String>[];
    final seen = <String>{};
    for (final item in raw) {
      final label = _expenseText(item);
      if (label.isEmpty) continue;
      final key = label.toLowerCase();
      if (seen.add(key)) categories.add(label);
    }
    if (!categories.any(_expenseIsInventoryCategory)) {
      categories.insert(
        1.clamp(0, categories.length),
        'Compra de productos e insumos',
      );
    }
    return categories;
  }

  Product? _selectedProduct(Product product) {
    return _linesById[product.id]?.product;
  }

  int _selectedQtyFor(Product product) => _linesById[product.id]?.qty ?? 0;

  List<Product> _visibleProducts(List<Product> products) {
    final query = _searchCtl.text.trim().toLowerCase();
    var visible = products.where((product) {
      if (_lowStockOnly && product.stock >= _expenseLowStockThreshold) {
        return false;
      }
      if (_selectedOnly && !_linesById.containsKey(product.id)) {
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
      ].join(' | ').toLowerCase();
      return haystack.contains(query);
    }).toList();

    if (_sortByStock) {
      visible.sort((a, b) => a.stock.compareTo(b.stock));
    } else {
      visible.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
    }
    return visible;
  }

  void _ensureSelectedMethod(List<PaymentMethod> methods) {
    if (methods.isEmpty) return;
    final current = (_selectedMethodCode ?? '').trim();
    if (current.isNotEmpty && methods.any((method) => method.code == current)) {
      return;
    }
    _selectedMethodCode = methods.first.code;
  }

  String _defaultConceptFromLines(List<_ExpensePurchaseLine> lines) {
    if (lines.isEmpty) return 'Gasto';
    if (lines.length == 1) {
      final line = lines.first;
      return '${line.qty} ${line.product.name}'.trim();
    }
    final totalQty = lines.fold<int>(0, (sum, line) => sum + line.qty);
    return '$totalQty productos';
  }

  double? _evaluateExpression(String expression) {
    final cleaned = expression.replaceAll(' ', '');
    if (cleaned.isEmpty) return 0;
    final tokens = <String>[];
    var current = '';

    for (final rune in cleaned.runes) {
      final char = String.fromCharCode(rune);
      final isDigit = RegExp(r'[0-9]').hasMatch(char);
      if (isDigit || char == '.') {
        current += char;
        continue;
      }
      if (char == '%') {
        if (current.isEmpty || current.endsWith('%')) return null;
        current += char;
        continue;
      }
      if (_isOperator(char)) {
        final canStartNegative =
            char == '-' &&
            current.isEmpty &&
            (tokens.isEmpty || _isOperator(tokens.last));
        if (canStartNegative) {
          current = '-';
          continue;
        }
        if (current.isEmpty) return null;
        tokens.add(current);
        current = '';
        tokens.add(char);
        continue;
      }
      return null;
    }

    if (current.isNotEmpty) {
      tokens.add(current);
    }
    if (tokens.isEmpty || _isOperator(tokens.last)) return null;

    final values = <double>[];
    final ops = <String>[];
    for (final token in tokens) {
      if (_isOperator(token)) {
        ops.add(token);
        continue;
      }
      final isPercent = token.endsWith('%');
      final raw = isPercent ? token.substring(0, token.length - 1) : token;
      final value = double.tryParse(raw);
      if (value == null) return null;
      values.add(isPercent ? value / 100 : value);
    }
    if (values.length != ops.length + 1) return null;

    final collapsedValues = <double>[values.first];
    final collapsedOps = <String>[];
    for (var i = 0; i < ops.length; i++) {
      final op = ops[i];
      final next = values[i + 1];
      if (op == 'x' || op == '/') {
        final left = collapsedValues.removeLast();
        if (op == '/' && next.abs() < 0.0000001) return null;
        collapsedValues.add(op == 'x' ? left * next : left / next);
        continue;
      }
      collapsedOps.add(op);
      collapsedValues.add(next);
    }

    var result = collapsedValues.first;
    for (var i = 0; i < collapsedOps.length; i++) {
      final op = collapsedOps[i];
      final next = collapsedValues[i + 1];
      result = op == '+' ? result + next : result - next;
    }
    return double.parse(result.toStringAsFixed(2));
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _openAmountPad() {
    setState(() {
      _showAmountPad = true;
      if (_amountExpression.isEmpty && _amountUsd > 0) {
        _amountExpression = _formatEditableAmount(_amountUsd);
      }
    });
  }

  void _appendAmountToken(String token) {
    setState(() {
      if (_amountExpression == '0' && RegExp(r'^[0-9]+$').hasMatch(token)) {
        _amountExpression = token;
        return;
      }
      _amountExpression += token;
    });
  }

  void _appendOperator(String operator) {
    setState(() {
      if (_amountExpression.isEmpty) {
        if (operator == '-') {
          _amountExpression = '-';
        }
        return;
      }
      final last = _amountExpression[_amountExpression.length - 1];
      if (_isOperator(last)) {
        _amountExpression =
            _amountExpression.substring(0, _amountExpression.length - 1) +
            operator;
        return;
      }
      if (last == '.') return;
      _amountExpression += operator;
    });
  }

  void _appendPercent() {
    setState(() {
      if (_amountExpression.isEmpty) return;
      final last = _amountExpression[_amountExpression.length - 1];
      if (_isOperator(last) || last == '.' || last == '%') return;
      _amountExpression += '%';
    });
  }

  void _appendDecimal() {
    setState(() {
      final parts = _amountExpression.split(RegExp(r'[+\-x/]'));
      final current = parts.isEmpty ? '' : parts.last;
      if (current.contains('.') || current.endsWith('%')) return;
      if (current.isEmpty || current == '-') {
        _amountExpression += '0.';
        return;
      }
      _amountExpression += '.';
    });
  }

  void _backspaceAmount() {
    setState(() {
      if (_amountExpression.isEmpty) return;
      _amountExpression = _amountExpression.substring(
        0,
        _amountExpression.length - 1,
      );
    });
  }

  void _clearAmount() {
    setState(() {
      _amountExpression = '';
      _amountUsd = 0;
    });
  }

  void _commitAmount() {
    final result = _evaluateExpression(_amountExpression);
    if (result == null || result < 0) {
      _showSnack('La operación ingresada no es válida.');
      return;
    }
    setState(() {
      _amountUsd = result;
      _amountExpression = _formatEditableAmount(result);
      _showAmountPad = false;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: _expenseDate,
      locale: const Locale('es'),
    );
    if (picked == null) return;
    setState(() {
      _expenseDate = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _expenseDate.hour,
        _expenseDate.minute,
        _expenseDate.second,
        _expenseDate.millisecond,
        _expenseDate.microsecond,
      );
    });
  }

  Future<void> _pickCategory(AppState state) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _ExpenseCategorySheet(
        categories: _categoriesFor(state),
        selected: _category,
      ),
    );
    if (!mounted || selected == null || selected.trim().isEmpty) return;
    final wasInventoryPurchase = _isInventoryPurchase;
    final currentLinesTotal = _purchaseSubtotal;
    setState(() {
      _category = selected;
      if (wasInventoryPurchase && !_isInventoryPurchase) {
        if (_lines.isNotEmpty) {
          _amountUsd = currentLinesTotal;
        }
        _linesById.clear();
      }
    });
  }

  void _incrementProduct(Product product) {
    setState(() {
      final existing = _linesById[product.id];
      if (existing == null) {
        _linesById[product.id] = _ExpensePurchaseLine(
          product: product,
          qty: 1,
          unitCostUsd: math.max(0, product.costUsd),
        );
        return;
      }
      existing.qty += 1;
    });
  }

  void _decrementProduct(Product product) {
    final existing = _linesById[product.id];
    if (existing == null) return;
    setState(() {
      existing.qty -= 1;
      if (existing.qty <= 0) {
        _linesById.remove(product.id);
      }
    });
  }

  void _removeLine(_ExpensePurchaseLine line) {
    setState(() {
      _linesById.remove(line.product.id);
    });
  }

  void _updateLineQty(_ExpensePurchaseLine line, int qty) {
    setState(() {
      line.qty = math.max(1, qty);
    });
  }

  void _updateLineCost(_ExpensePurchaseLine line, double cost) {
    setState(() {
      line.unitCostUsd = cost.clamp(0, double.infinity);
    });
  }

  void _goToConfirm() {
    if (_lines.isEmpty) {
      _showSnack('Selecciona al menos un producto.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _showSearch = false;
      _step = _ExpenseStep.confirm;
    });
  }

  void _goToFormFromConfirm() {
    if (_lines.isEmpty) {
      _showSnack('Selecciona al menos un producto.');
      return;
    }
    for (final line in _lines) {
      if (line.qty <= 0) {
        _showSnack('La cantidad debe ser mayor a 0.');
        return;
      }
      if (line.unitCostUsd < 0) {
        _showSnack('El costo unitario no puede ser negativo.');
        return;
      }
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _step = _ExpenseStep.form;
      _amountUsd = 0;
      if (_conceptCtl.text.trim().isEmpty) {
        _conceptCtl.text = _defaultConceptFromLines(_lines);
      }
    });
  }

  void _handleBack() {
    if (_showAmountPad) {
      setState(() => _showAmountPad = false);
      return;
    }
    switch (_step) {
      case _ExpenseStep.form:
        Navigator.of(context).pop();
        break;
      case _ExpenseStep.catalog:
        setState(() => _step = _ExpenseStep.form);
        break;
      case _ExpenseStep.confirm:
        setState(() => _step = _ExpenseStep.catalog);
        break;
    }
  }

  Future<void> _submit(AppState state) async {
    if (_submitting) return;
    if (_showAmountPad) {
      final tentative = _evaluateExpression(_amountExpression);
      if (tentative == null || tentative < 0) {
        _showSnack('La operación ingresada no es válida.');
        return;
      }
      setState(() => _amountUsd = tentative);
    }

    final category = _expenseText(_category);
    if (category.isEmpty) {
      _showSnack('Selecciona una categoría de gasto.');
      return;
    }

    final total = _subtotal;
    if (total <= 0) {
      _showSnack('El valor del gasto debe ser mayor a 0.');
      return;
    }

    final methods = _activeMethods(state);
    _ensureSelectedMethod(methods);
    final methodCode = (_selectedMethodCode ?? '').trim();
    if (_status == _ExpenseStatus.paid && methodCode.isEmpty) {
      _showSnack('Selecciona un método de pago.');
      return;
    }

    final itemsPayload = _isInventoryPurchase && _lines.isNotEmpty
        ? _buildItemsPayloadFromLines(_lines)
        : null;

    if ((itemsPayload ?? const []).isNotEmpty &&
        (state.warehouseId ?? '').trim().isEmpty) {
      _showSnack(
        'No hay bodega seleccionada. Actualiza inventario o inicia sesión nuevamente.',
      );
      return;
    }

    final concept = _conceptCtl.text.trim().isEmpty
        ? (_lines.isNotEmpty ? _defaultConceptFromLines(_lines) : 'Gasto')
        : _conceptCtl.text.trim();

    final paymentsPayload = _status == _ExpenseStatus.debt
        ? <Map<String, dynamic>>[]
        : [
            {
              'paymentMethodCode': methodCode,
              'amountUsd': total,
              'concept': concept,
              'receiptNote': '',
            },
          ];

    setState(() => _submitting = true);
    try {
      if (widget.isEdit) {
        if (_expenseId.isEmpty) {
          throw StateError('No se pudo editar: expenseId vacío');
        }

        final payload = <String, dynamic>{
          'status': _status == _ExpenseStatus.paid ? 'PAGADO' : 'DEUDA',
          'category': _expenseCategoryPayloadValue(category),
          'amountUsd': total,
          'description': concept,
          'receiptNote': '',
          'occurredAt': _expenseDate.toUtc().toIso8601String(),
          if (_status == _ExpenseStatus.paid) 'payments': paymentsPayload,
        };

        final updatedExpenseId = await state.editarGastoRecrear(
          expenseId: _expenseId,
          payload: payload,
          previousItems: widget.initialLineRows,
          items: itemsPayload,
        );
        if (!mounted) return;
        Navigator.of(context).pop(updatedExpenseId);
      } else {
        await state.crearGasto(
          status: _status == _ExpenseStatus.paid ? 'PAGADO' : 'DEUDA',
          category: _expenseCategoryPayloadValue(category),
          amountUsd: total,
          description: concept,
          receiptNote: '',
          occurredAt: _expenseDate,
          payments: _status == _ExpenseStatus.debt ? null : paymentsPayload,
          items: itemsPayload,
        );
        if (!mounted) return;
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;
      _showSnack(
        widget.isEdit
            ? 'No se pudo editar el gasto: ${_expenseHumanizeError(e)}'
            : 'No se pudo registrar el gasto: ${_expenseHumanizeError(e)}',
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  String _formattedExpenseDate() {
    final now = DateTime.now();
    final isToday =
        now.year == _expenseDate.year &&
        now.month == _expenseDate.month &&
        now.day == _expenseDate.day;
    final label = DateFormat('d MMMM', 'es').format(_expenseDate);
    return isToday ? 'Hoy, $label' : label;
  }

  Widget _buildAmountCard() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _openAmountPad,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _expenseFlowBorderColor),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text.rich(
                        TextSpan(
                          text: 'Valor',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.navy,
                          ),
                          children: [
                            TextSpan(
                              text: ' *',
                              style: TextStyle(color: AppTheme.red),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Text(
                      _displayAmount,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.navy,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: const BoxDecoration(
                  color: Color(0xFFE8EBF0),
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Valor total',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.navy,
                        ),
                      ),
                    ),
                    Text(
                      _money(_subtotal),
                      style: const TextStyle(
                        fontSize: 18,
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

  Widget _buildFormStep(AppState state, {required double bottomPadding}) {
    final methods = _activeMethods(state);
    _ensureSelectedMethod(methods);
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPadding),
      children: [
        _ExpenseStatusToggle(
          value: _status,
          onChanged: (value) => setState(() => _status = value),
        ),
        const SizedBox(height: 14),
        const Text.rich(
          TextSpan(
            text: 'Fecha del gasto',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppTheme.navy,
            ),
            children: [
              TextSpan(
                text: ' *',
                style: TextStyle(color: AppTheme.red),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _ExpensePickerField(
          label: _formattedExpenseDate(),
          icon: Icons.calendar_month_outlined,
          onTap: _pickDate,
        ),
        const SizedBox(height: 14),
        const Text.rich(
          TextSpan(
            text: 'Categoría del gasto',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppTheme.navy,
            ),
            children: [
              TextSpan(
                text: ' *',
                style: TextStyle(color: AppTheme.red),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _ExpensePickerField(
          label: _expenseText(_category).isEmpty
              ? 'Selecciona una opción'
              : _expenseText(_category),
          icon: Icons.keyboard_arrow_down_rounded,
          placeholder: _expenseText(_category).isEmpty,
          onTap: () => _pickCategory(state),
        ),
        if (_isInventoryPurchase) ...[
          const SizedBox(height: 14),
          _ExpenseSelectedProductsCard(
            count: _selectedLineCount,
            onTap: () => setState(() => _step = _ExpenseStep.catalog),
          ),
        ],
        const SizedBox(height: 14),
        if (_isInventoryPurchase && _lines.isNotEmpty)
          _ExpenseTotalSummary(amountUsd: _subtotal)
        else
          _buildAmountCard(),
        const SizedBox(height: 14),
        const Text(
          'Proveedor',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppTheme.navy,
          ),
        ),
        const SizedBox(height: 8),
        _ExpensePickerField(
          label: 'Escoge tu proveedor',
          icon: Icons.keyboard_arrow_down_rounded,
          placeholder: true,
          onTap: () => _showSnack('Proveedores: próximamente'),
        ),
        const SizedBox(height: 14),
        if (_status == _ExpenseStatus.paid) ...[
          const Text.rich(
            TextSpan(
              text: 'Método de pago',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppTheme.navy,
              ),
              children: [
                TextSpan(
                  text: ' *',
                  style: TextStyle(color: AppTheme.red),
                ),
              ],
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
                  final selected = method.code == _selectedMethodCode;
                  return SizedBox(
                    width: width,
                    child: _ExpenseMethodTile(
                      method: method,
                      selected: selected,
                      onTap: () =>
                          setState(() => _selectedMethodCode = method.code),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _expenseFlowBorderColor),
            ),
            child: const Text(
              'El gasto se registrará sin pagos para manejarlo como deuda.',
              style: TextStyle(
                fontSize: 13,
                color: _expenseFlowMutedText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
        const SizedBox(height: 14),
        const Text(
          'Concepto',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppTheme.navy,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _conceptCtl,
          decoration: _expenseInputDecoration(
            hintText: 'Dale un nombre a tu gasto',
          ),
        ),
      ],
    );
  }

  Widget _buildCatalogStep(BuildContext context, AppState state) {
    final products = _visibleProducts(state.products);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      children: [
        SizedBox(
          height: 64,
          child: OutlinedButton.icon(
            onPressed: () => showCreateProductSheet(context),
            icon: const Icon(Icons.add_circle_outline_rounded, size: 28),
            label: const Text('Nuevo producto'),
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppTheme.navy,
              side: const BorderSide(color: AppTheme.navy, width: 1.8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
        if (_showSearch) ...[
          const SizedBox(height: 14),
          TextField(
            controller: _searchCtl,
            onChanged: (_) => setState(() {}),
            decoration: _expenseInputDecoration(
              hintText: 'Buscar producto',
              prefixText: null,
            ).copyWith(prefixIcon: const Icon(Icons.search_rounded, size: 22)),
          ),
        ],
        const SizedBox(height: 14),
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
                      selectedColor: _expenseFlowHeaderColor,
                      selectedTextColor: Colors.white,
                      onTap: () => setState(() => _lowStockOnly = false),
                    ),
                    const SizedBox(width: 10),
                    _CatalogScopeChip(
                      label: 'Stock bajo',
                      selected: _lowStockOnly,
                      selectedColor: const Color(0xFFDCEBFB),
                      selectedTextColor: AppTheme.navy,
                      leading: const Icon(
                        Icons.workspace_premium_rounded,
                        size: 18,
                        color: AppTheme.bannerBlue,
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
              border: Border.all(color: _expenseFlowBorderColor),
            ),
            child: const Text(
              'No hay productos para mostrar con esos filtros.',
              style: TextStyle(
                color: _expenseFlowMutedText,
                fontWeight: FontWeight.w700,
              ),
            ),
          )
        else
          ...products.map(
            (product) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _ExpenseCatalogProductCard(
                product: _selectedProduct(product) ?? product,
                selectedQty: _selectedQtyFor(product),
                onMinus: () => _decrementProduct(product),
                onPlus: () => _incrementProduct(product),
              ),
            ),
          ),
        const SizedBox(height: 10),
        const Text(
          'En el siguiente paso podrás confirmar costos',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _expenseFlowMutedText,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  Widget _buildConfirmStep() {
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
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                color: Color(0xFF1A78D7),
                size: 26,
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Agrega cantidades y costo por producto. Se calculará automáticamente el valor total del gasto.',
                  style: TextStyle(
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
            child: _ExpenseConfirmProductCard(
              line: line,
              onRemove: () => _removeLine(line),
              onQtyChanged: (qty) => _updateLineQty(line, qty),
              onCostChanged: (cost) => _updateLineCost(line, cost),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAmountPad() {
    return _ExpenseKeypad(
      onClear: _clearAmount,
      onBackspace: _backspaceAmount,
      onPercent: _appendPercent,
      onDivide: () => _appendOperator('/'),
      onMultiply: () => _appendOperator('x'),
      onMinus: () => _appendOperator('-'),
      onPlus: () => _appendOperator('+'),
      onEqual: _commitAmount,
      onDecimal: _appendDecimal,
      onDigit: _appendAmountToken,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final methods = _activeMethods(state);
    _ensureSelectedMethod(methods);
    final bottomPadding = _showAmountPad ? 24.0 : 120.0;

    final title = switch (_step) {
      _ExpenseStep.form => 'Nuevo gasto',
      _ExpenseStep.catalog => 'Seleccionar productos',
      _ExpenseStep.confirm => 'Confirma precios y cantidades',
    };

    return PopScope<void>(
      canPop: _canPopRoute,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _handleBack();
        }
      },
      child: Scaffold(
        backgroundColor: _expenseFlowBackground,
        appBar: AppBar(
          backgroundColor: _expenseFlowHeaderColor,
          foregroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          systemOverlayStyle: _expenseFlowOverlay,
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
          actions: _step == _ExpenseStep.catalog
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
        body: Stack(
          children: [
            SafeArea(
              top: false,
              child: switch (_step) {
                _ExpenseStep.form => _buildFormStep(
                  state,
                  bottomPadding: bottomPadding,
                ),
                _ExpenseStep.catalog => _buildCatalogStep(context, state),
                _ExpenseStep.confirm => _buildConfirmStep(),
              },
            ),
            if (_showAmountPad && _step == _ExpenseStep.form) ...[
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () => setState(() => _showAmountPad = false),
                  child: const SizedBox.expand(),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: SafeArea(top: false, child: _buildAmountPad()),
              ),
            ],
          ],
        ),
        bottomNavigationBar: _showAmountPad && _step == _ExpenseStep.form
            ? null
            : SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: _ExpenseBottomButton(
                    count: _step == _ExpenseStep.form
                        ? null
                        : _selectedLineCount,
                    amountUsd: _step == _ExpenseStep.form ? null : _subtotal,
                    label: switch (_step) {
                      _ExpenseStep.form =>
                        widget.isEdit ? 'Guardar cambios' : 'Crear gasto',
                      _ExpenseStep.catalog => 'Añadir productos',
                      _ExpenseStep.confirm => 'Confirmar',
                    },
                    enabled: switch (_step) {
                      _ExpenseStep.form =>
                        !_submitting &&
                            _expenseText(_category).isNotEmpty &&
                            _subtotal > 0 &&
                            (_status == _ExpenseStatus.debt ||
                                _expenseText(_selectedMethodCode).isNotEmpty) &&
                            (!widget.isEdit || _isDirty),
                      _ExpenseStep.catalog => _lines.isNotEmpty,
                      _ExpenseStep.confirm => _lines.isNotEmpty,
                    },
                    loading: _submitting,
                    onTap: () {
                      switch (_step) {
                        case _ExpenseStep.form:
                          _submit(state);
                          break;
                        case _ExpenseStep.catalog:
                          _goToConfirm();
                          break;
                        case _ExpenseStep.confirm:
                          _goToFormFromConfirm();
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

class _ExpenseStatusToggle extends StatelessWidget {
  const _ExpenseStatusToggle({required this.value, required this.onChanged});

  final _ExpenseStatus value;
  final ValueChanged<_ExpenseStatus> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget tab(String label, _ExpenseStatus status) {
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
        border: Border.all(color: _expenseFlowBorderColor),
      ),
      child: Row(
        children: [
          tab('Pagado', _ExpenseStatus.paid),
          const SizedBox(width: 4),
          tab('Deuda', _ExpenseStatus.debt),
        ],
      ),
    );
  }
}

class _ExpensePickerField extends StatelessWidget {
  const _ExpensePickerField({
    required this.label,
    required this.icon,
    required this.onTap,
    this.placeholder = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool placeholder;

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
            border: Border.all(color: _expenseFlowBorderColor),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: placeholder
                        ? const Color(0xFF98A2B3)
                        : AppTheme.navy,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              Icon(icon, size: 28, color: AppTheme.navy),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExpenseSelectedProductsCard extends StatelessWidget {
  const _ExpenseSelectedProductsCard({
    required this.count,
    required this.onTap,
  });

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
            border: Border.all(color: _expenseFlowBorderColor),
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
                  color: AppTheme.bannerBlue,
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
                        color: _expenseFlowMutedText,
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
                    color: AppTheme.bannerBlue,
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

class _ExpenseTotalSummary extends StatelessWidget {
  const _ExpenseTotalSummary({required this.amountUsd});

  final double amountUsd;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Valor total:',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: AppTheme.navy,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '\$${amountUsd.toStringAsFixed(amountUsd % 1 == 0 ? 0 : 2)}',
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w900,
              color: AppTheme.navy,
            ),
          ),
        ],
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
                color: filled ? AppTheme.navy : _expenseFlowBorderColor,
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
              color: selected ? selectedColor : _expenseFlowBorderColor,
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

class _ExpenseCatalogProductCard extends StatelessWidget {
  const _ExpenseCatalogProductCard({
    required this.product,
    required this.selectedQty,
    required this.onMinus,
    required this.onPlus,
  });

  final Product product;
  final int selectedQty;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    final selected = selectedQty > 0;
    final stock = product.stock;
    final low = stock <= 0 || stock < _expenseLowStockThreshold;
    final stockBg = stock <= 0
        ? const Color(0xFFFDE8E7)
        : (low ? const Color(0xFFFDE8E7) : const Color(0xFFDDF6EA));
    final stockFg = stock <= 0
        ? AppTheme.red
        : (low ? AppTheme.red : const Color(0xFF0F7B4F));
    final stockLabel = stock <= 0
        ? 'No disponible'
        : '${stock == stock.roundToDouble() ? stock.toStringAsFixed(0) : stock.toStringAsFixed(1)} disponibles';

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected ? AppTheme.green : _expenseFlowBorderColor,
          width: selected ? 2.0 : 1.3,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ExpenseProductThumb(product: product, size: 76),
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
                  '\$${product.costUsd.toStringAsFixed(product.costUsd % 1 == 0 ? 0 : 2)}',
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
                    onPlus: onPlus,
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

class _ExpenseConfirmProductCard extends StatefulWidget {
  const _ExpenseConfirmProductCard({
    required this.line,
    required this.onRemove,
    required this.onQtyChanged,
    required this.onCostChanged,
  });

  final _ExpensePurchaseLine line;
  final VoidCallback onRemove;
  final ValueChanged<int> onQtyChanged;
  final ValueChanged<double> onCostChanged;

  @override
  State<_ExpenseConfirmProductCard> createState() =>
      _ExpenseConfirmProductCardState();
}

class _ExpenseConfirmProductCardState
    extends State<_ExpenseConfirmProductCard> {
  late final TextEditingController _costCtl;

  @override
  void initState() {
    super.initState();
    _costCtl = TextEditingController(
      text: widget.line.unitCostUsd.toStringAsFixed(2),
    );
  }

  @override
  void didUpdateWidget(covariant _ExpenseConfirmProductCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.line.unitCostUsd.toStringAsFixed(2);
    if (_costCtl.text != next) {
      _costCtl.text = next;
    }
  }

  @override
  void dispose() {
    _costCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final line = widget.line;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _expenseFlowBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _ExpenseProductThumb(product: line.product, size: 40),
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
                      onPlus: () => widget.onQtyChanged(line.qty + 1),
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
                      'Costo unitario *',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.navy,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _costCtl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: AppInputFormatters.decimal(
                        maxDecimals: 2,
                      ),
                      decoration: _expenseInputDecoration(prefixText: '\$ '),
                      onChanged: (value) => widget.onCostChanged(
                        math.max(
                          0,
                          double.tryParse(value.replaceAll(',', '.')) ?? 0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Costo por 1 unidad: \$${line.unitCostUsd.toStringAsFixed(line.unitCostUsd % 1 == 0 ? 0 : 2)}',
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

class _ExpenseMethodTile extends StatelessWidget {
  const _ExpenseMethodTile({
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
              color: selected ? AppTheme.green : _expenseFlowBorderColor,
              width: selected ? 1.8 : 1.4,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _iconForMethod(),
                size: 24,
                color: selected ? AppTheme.green : AppTheme.navy,
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
                  color: selected ? AppTheme.green : AppTheme.navy,
                ),
              ),
            ],
          ),
        ),
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
        border: Border.all(color: _expenseFlowBorderColor, width: 1.4),
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
              color: enabled ? AppTheme.navy : _expenseFlowBorderColor,
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

class _ExpenseBottomButton extends StatelessWidget {
  const _ExpenseBottomButton({
    required this.count,
    required this.amountUsd,
    required this.label,
    required this.enabled,
    required this.loading,
    required this.onTap,
  });

  final int? count;
  final double? amountUsd;
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
              if (count != null) ...[
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: enabled
                        ? Colors.white.withValues(alpha: 0.10)
                        : Colors.white.withValues(alpha: 0.30),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      color: fg,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
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
                        textAlign: amountUsd == null
                            ? TextAlign.center
                            : TextAlign.left,
                        style: TextStyle(
                          color: fg,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
              ),
              if (amountUsd != null) ...[
                const SizedBox(width: 8),
                Text(
                  '\$${amountUsd!.toStringAsFixed(amountUsd! % 1 == 0 ? 0 : 2)}',
                  style: TextStyle(
                    color: fg,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.chevron_right_rounded, color: fg, size: 26),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ExpenseKeypad extends StatelessWidget {
  const _ExpenseKeypad({
    required this.onClear,
    required this.onBackspace,
    required this.onPercent,
    required this.onDivide,
    required this.onMultiply,
    required this.onMinus,
    required this.onPlus,
    required this.onEqual,
    required this.onDecimal,
    required this.onDigit,
  });

  final VoidCallback onClear;
  final VoidCallback onBackspace;
  final VoidCallback onPercent;
  final VoidCallback onDivide;
  final VoidCallback onMultiply;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final VoidCallback onEqual;
  final VoidCallback onDecimal;
  final ValueChanged<String> onDigit;

  @override
  Widget build(BuildContext context) {
    Widget numberButton(String label) {
      return _ExpensePadButton(label: label, onTap: () => onDigit(label));
    }

    Widget operatorButton(String label, VoidCallback onTap) {
      return _ExpensePadButton(label: label, onTap: onTap, filled: true);
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _ExpensePadButton(
                  label: 'C',
                  onTap: onClear,
                  textColor: const Color(0xFFD92D20),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ExpensePadButton.icon(
                  icon: Icons.backspace_outlined,
                  onTap: onBackspace,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: operatorButton('%', onPercent)),
              const SizedBox(width: 10),
              Expanded(child: operatorButton('/', onDivide)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: numberButton('7')),
              const SizedBox(width: 10),
              Expanded(child: numberButton('8')),
              const SizedBox(width: 10),
              Expanded(child: numberButton('9')),
              const SizedBox(width: 10),
              Expanded(child: operatorButton('x', onMultiply)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: numberButton('4')),
              const SizedBox(width: 10),
              Expanded(child: numberButton('5')),
              const SizedBox(width: 10),
              Expanded(child: numberButton('6')),
              const SizedBox(width: 10),
              Expanded(child: operatorButton('-', onMinus)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: numberButton('1')),
              const SizedBox(width: 10),
              Expanded(child: numberButton('2')),
              const SizedBox(width: 10),
              Expanded(child: numberButton('3')),
              const SizedBox(width: 10),
              Expanded(child: operatorButton('+', onPlus)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: numberButton('0')),
              const SizedBox(width: 10),
              Expanded(child: numberButton('000')),
              const SizedBox(width: 10),
              Expanded(
                child: _ExpensePadButton(label: '.', onTap: onDecimal),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ExpensePadButton(
                  label: '=',
                  onTap: onEqual,
                  filled: true,
                  backgroundColor: AppTheme.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ExpensePadButton extends StatelessWidget {
  const _ExpensePadButton({
    required this.label,
    required this.onTap,
    this.filled = false,
    this.textColor,
    this.backgroundColor,
    this.foregroundColor,
  }) : icon = null;

  const _ExpensePadButton.icon({required this.icon, required this.onTap})
    : label = null,
      filled = false,
      textColor = null,
      backgroundColor = null,
      foregroundColor = null;

  final String? label;
  final IconData? icon;
  final VoidCallback onTap;
  final bool filled;
  final Color? textColor;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final bg =
        backgroundColor ??
        (filled ? const Color(0xFFF8E9A7) : const Color(0xFFF1F3F6));
    final fg = foregroundColor ?? textColor ?? AppTheme.navy;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          height: 56,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Center(
            child: icon != null
                ? Icon(icon, color: fg, size: 22)
                : Text(
                    label ?? '',
                    style: TextStyle(
                      color: fg,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _ExpenseCategorySheet extends StatelessWidget {
  const _ExpenseCategorySheet({
    required this.categories,
    required this.selected,
  });

  final List<String> categories;
  final String? selected;

  IconData _iconForCategory(String value) {
    final key = _expenseNormalizeKey(value);
    if (key.contains('SERVICIO')) return Icons.water_drop_outlined;
    if (key.contains('COMPRA')) return Icons.inventory_2_outlined;
    if (key.contains('ARRIENDO')) return Icons.home_work_outlined;
    if (key.contains('NOMINA')) return Icons.groups_2_outlined;
    if (key.contains('ADMIN')) return Icons.balance_outlined;
    if (key.contains('MERCADEO') || key.contains('PUBLICIDAD')) {
      return Icons.campaign_outlined;
    }
    if (key.contains('TRANSPORTE') ||
        key.contains('DOMICILIO') ||
        key.contains('LOGISTICA')) {
      return Icons.local_shipping_outlined;
    }
    if (key.contains('MANTENIMIENTO') || key.contains('REPARACION')) {
      return Icons.settings_outlined;
    }
    if (key.contains('MUEBLE') ||
        key.contains('EQUIPO') ||
        key.contains('MAQUINARIA')) {
      return Icons.chair_outlined;
    }
    return Icons.grid_view_outlined;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Expanded(
                  child: Text(
                    'Escoge una categoría',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.navy,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 40,
                  height: 40,
                  child: IconButton.filledTonal(
                    onPressed: () => Navigator.of(context).pop(),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFFE8EEF6),
                      foregroundColor: const Color(0xFF6B7D93),
                      padding: EdgeInsets.zero,
                    ),
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: categories.length,
                separatorBuilder: (context, index) => const SizedBox(height: 4),
                itemBuilder: (context, index) {
                  final category = categories[index];
                  final isSelected = category == selected;
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => Navigator.of(context).pop(category),
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 2,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 44,
                              child: Icon(
                                _iconForCategory(category),
                                size: 28,
                                color: AppTheme.navy,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                category,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.navy,
                                ),
                              ),
                            ),
                            Icon(
                              isSelected
                                  ? Icons.radio_button_checked_rounded
                                  : Icons.radio_button_off_rounded,
                              size: 30,
                              color: isSelected
                                  ? AppTheme.bannerBlue
                                  : const Color(0xFF9FB0C3),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExpenseProductThumb extends StatelessWidget {
  const _ExpenseProductThumb({required this.product, required this.size});

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
        border: Border.all(color: _expenseFlowBorderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: (resolved ?? '').trim().isEmpty
          ? Container(
              color: const Color(0xFFF2E0FA),
              alignment: Alignment.center,
              child: Icon(
                Icons.inventory_2_outlined,
                color: const Color(0xFFD2B3E8),
                size: size * 0.44,
              ),
            )
          : Image.network(
              resolved!,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                color: const Color(0xFFF2E0FA),
                alignment: Alignment.center,
                child: Icon(
                  Icons.inventory_2_outlined,
                  color: const Color(0xFFD2B3E8),
                  size: size * 0.44,
                ),
              ),
            ),
    );
  }
}
