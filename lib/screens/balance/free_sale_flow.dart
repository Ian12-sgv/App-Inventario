import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../ui/app_theme.dart';
import '../../ui/input_formatters.dart';

const Color _freeSaleHeaderColor = AppTheme.bannerBlue;
const Color _freeSaleBackground = Color(0xFFF3F4F6);
const Color _freeSaleBorderColor = Color(0xFFD5DDE7);
const Color _freeSaleMutedText = Color(0xFF667085);

Future<void> showFreeSaleFlow(BuildContext context) async {
  await Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const FreeSaleFlowScreen()));
}

Future<bool?> showEditFreeSaleFlow(
  BuildContext context, {
  required Map<String, dynamic> sale,
  required String saleId,
  List<Map<String, dynamic>> prefillPayments = const [],
}) async {
  return Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => FreeSaleFlowScreen(
        isEdit: true,
        existingSale: sale,
        saleId: saleId,
        prefillPayments: prefillPayments,
      ),
    ),
  );
}

double _freeSaleToDouble(dynamic value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}

String _freeSaleText(dynamic value) => (value ?? '').toString().trim();

String _freeSaleNormalizeKey(String value) {
  return value
      .trim()
      .toUpperCase()
      .replaceAll(RegExp(r'[^A-Z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
}

String _freeSaleHumanizeError(Object e) {
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

InputDecoration _freeSaleInputDecoration({
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
      borderSide: const BorderSide(color: _freeSaleBorderColor),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: _freeSaleBorderColor),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: _freeSaleHeaderColor, width: 1.4),
    ),
  );
}

enum _FreeSaleStatus { paid, debt }

class _FreeSalePaymentSlot {
  _FreeSalePaymentSlot({required this.methodCode});

  String methodCode;
}

class FreeSaleFlowScreen extends StatefulWidget {
  const FreeSaleFlowScreen({
    super.key,
    this.isEdit = false,
    this.existingSale,
    this.saleId,
    this.prefillPayments = const [],
  });

  final bool isEdit;
  final Map<String, dynamic>? existingSale;
  final String? saleId;
  final List<Map<String, dynamic>> prefillPayments;

  @override
  State<FreeSaleFlowScreen> createState() => _FreeSaleFlowScreenState();
}

class _FreeSaleFlowScreenState extends State<FreeSaleFlowScreen> {
  final _discountPctCtl = TextEditingController();
  final _discountUsdCtl = TextEditingController();
  final _conceptCtl = TextEditingController();
  final _receiptCtl = TextEditingController();

  final List<_FreeSalePaymentSlot> _paymentSlots = [];

  _FreeSaleStatus _status = _FreeSaleStatus.paid;
  DateTime _saleDate = DateTime.now();
  bool _showAmountPad = false;
  bool _moreOptionsExpanded = true;
  bool _paymentDetailExpanded = false;
  bool _submitting = false;
  int _paymentCount = 1;
  double _amountUsd = 0;
  String _amountExpression = '';
  String _initialSignature = '';

  String get _saleId => (widget.saleId ?? '').trim();

  bool get _canPopRoute => !_showAmountPad;

  bool get _isDirty => _buildSignature() != _initialSignature;

  double get _subtotal => _amountUsd;

  double get _discountUsd {
    final pct = _parseNum(_discountPctCtl.text);
    final usd = _parseNum(_discountUsdCtl.text);
    if (pct > 0) return (_subtotal * pct / 100).clamp(0, _subtotal);
    if (usd > 0) return usd.clamp(0, _subtotal);
    return 0;
  }

  double get _total => (_subtotal - _discountUsd).clamp(0, double.infinity);

  String get _displayAmount {
    if (_showAmountPad) {
      return _amountExpression.isEmpty ? '0' : _amountExpression;
    }
    return _formatEditableAmount(_amountUsd);
  }

  @override
  void initState() {
    super.initState();
    if (widget.isEdit) {
      _prefillEditState();
    }
  }

  @override
  void dispose() {
    _discountPctCtl.dispose();
    _discountUsdCtl.dispose();
    _conceptCtl.dispose();
    _receiptCtl.dispose();
    super.dispose();
  }

  double _parseNum(String raw) =>
      double.tryParse(raw.replaceAll(',', '.').trim()) ?? 0;

  DateTime _parseSaleDate(dynamic raw) {
    if (raw is DateTime) {
      return raw.isUtc ? raw.toLocal() : raw;
    }
    final parsed = raw == null ? null : DateTime.tryParse(raw.toString());
    if (parsed == null) return DateTime.now();
    return parsed.isUtc ? parsed.toLocal() : parsed;
  }

  bool _isDebtSale(Map<String, dynamic> sale) {
    final status = _freeSaleText(sale['status']);
    final statusLabel = _freeSaleText(sale['statusLabel']);
    final normalized = _freeSaleNormalizeKey('$status $statusLabel');
    return normalized.contains('DEUDA') || normalized.contains('DEBT');
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

  String _resolveMethodCode(
    List<PaymentMethod> methods,
    String label, {
    String fallback = 'CASH',
  }) {
    final raw = label.trim();
    if (raw.isEmpty) return fallback;
    final wanted = _freeSaleNormalizeKey(raw);
    for (final method in methods) {
      if (_freeSaleNormalizeKey(method.code) == wanted) return method.code;
      if (_freeSaleNormalizeKey(method.name) == wanted) return method.code;
    }
    return fallback;
  }

  void _ensurePaymentSlots(List<PaymentMethod> methods) {
    final fallbackCode = methods.first.code;
    while (_paymentSlots.length < _paymentCount) {
      _paymentSlots.add(_FreeSalePaymentSlot(methodCode: fallbackCode));
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

  String _formatEditableAmount(double value) {
    final text = value.toStringAsFixed(value % 1 == 0 ? 0 : 2);
    return text.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  String _money(double value) {
    return '\$${value.toStringAsFixed(value % 1 == 0 ? 0 : 2)}';
  }

  bool _isOperator(String token) {
    return token == '+' || token == '-' || token == 'x' || token == '/';
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

  String _buildSignature() {
    final paymentKey = _status == _FreeSaleStatus.debt
        ? ''
        : _paymentSlots.map((slot) => slot.methodCode).join('|');
    return [
      _status.name,
      _saleDate.toIso8601String(),
      _amountUsd.toStringAsFixed(2),
      _discountPctCtl.text.trim(),
      _discountUsdCtl.text.trim(),
      _conceptCtl.text.trim(),
      _receiptCtl.text.trim(),
      _paymentCount.toString(),
      paymentKey,
    ].join('||');
  }

  void _prefillEditState() {
    final sale = widget.existingSale;
    if (sale == null) {
      _initialSignature = _buildSignature();
      return;
    }
    final state = context.read<AppState>();
    final methods = _activeMethods(state);

    _saleDate = _parseSaleDate(sale['occurredAt'] ?? sale['occurred_at']);
    _amountUsd = _freeSaleToDouble(
      sale['totalUsd'] ?? sale['total_usd'] ?? sale['total'],
    );
    _amountExpression = _formatEditableAmount(_amountUsd);

    final discountPct = _freeSaleToDouble(
      sale['discountPercent'] ?? sale['discount_percent'],
    );
    final discountUsd = _freeSaleToDouble(
      sale['discountUsd'] ?? sale['discount_usd'],
    );
    if (discountPct > 0) {
      _discountPctCtl.text = _formatEditableAmount(discountPct);
    } else if (discountUsd > 0) {
      _discountUsdCtl.text = _formatEditableAmount(discountUsd);
    }

    _conceptCtl.text = _freeSaleText(sale['description'] ?? sale['concept']);
    _receiptCtl.text = _freeSaleText(sale['receiptNote']);

    final prefill = widget.prefillPayments;
    _paymentSlots.clear();
    if (prefill.isNotEmpty) {
      _status = _FreeSaleStatus.paid;
      _paymentCount = prefill.length;
      for (final row in prefill) {
        _paymentSlots.add(
          _FreeSalePaymentSlot(
            methodCode: _resolveMethodCode(
              methods,
              _freeSaleText(row['paymentMethodCode'] ?? row['methodCode']),
              fallback: methods.first.code,
            ),
          ),
        );
      }
    } else {
      _status = _isDebtSale(sale) ? _FreeSaleStatus.debt : _FreeSaleStatus.paid;
      _paymentCount = 1;
      _ensurePaymentSlots(methods);
    }

    _initialSignature = _buildSignature();
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

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _submit(AppState state, List<PaymentMethod> methods) async {
    if (_submitting) return;
    if (_showAmountPad) {
      final tentative = _evaluateExpression(_amountExpression);
      if (tentative != null) {
        setState(() => _amountUsd = tentative);
      }
    }
    if (_subtotal <= 0) {
      _showSnack('El valor de la venta debe ser mayor a 0.');
      return;
    }
    if (_total <= 0) {
      _showSnack('El total de la venta debe ser mayor a 0.');
      return;
    }

    _ensurePaymentSlots(methods);
    final discountPct = _parseNum(_discountPctCtl.text);
    final discountUsd = _parseNum(_discountUsdCtl.text);
    final concept = _conceptCtl.text.trim();
    final receiptNote = _receiptCtl.text.trim();
    final paymentAmounts = _splitAmounts(_total, _paymentSlots.length);
    final paymentsPayload = _status == _FreeSaleStatus.debt
        ? <Map<String, dynamic>>[]
        : List<Map<String, dynamic>>.generate(_paymentSlots.length, (index) {
            final slot = _paymentSlots[index];
            return {
              'paymentMethodCode': slot.methodCode,
              'amountUsd': paymentAmounts[index],
              'concept': concept.isEmpty ? 'Venta' : concept,
              'receiptNote': receiptNote,
            };
          });

    setState(() => _submitting = true);
    try {
      if (widget.isEdit) {
        if (_saleId.isEmpty) {
          throw StateError('No se pudo editar: saleId vacío');
        }
        await state.editarVentaRecrear(
          saleId: _saleId,
          payload: {
            'saleType': 'LIBRE',
            'totalUsd': _subtotal,
            if (discountPct > 0) 'discountPercent': discountPct,
            if (discountPct <= 0 && discountUsd > 0) 'discountUsd': discountUsd,
            'description': concept,
            'receiptNote': receiptNote,
            'occurredAt': _saleDate.toUtc().toIso8601String(),
            'payments': paymentsPayload,
          },
        );
      } else {
        await state.crearVentaLibre(
          totalUsd: _subtotal,
          discountPercent: discountPct > 0 ? discountPct : null,
          discountUsd: discountPct > 0
              ? null
              : (discountUsd > 0 ? discountUsd : null),
          note: concept,
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
            ? 'No se pudo editar la venta: ${_freeSaleHumanizeError(e)}'
            : 'No se pudo registrar la venta: ${_freeSaleHumanizeError(e)}',
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Widget _buildHintBubble() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF1778F2),
            borderRadius: BorderRadius.circular(22),
          ),
          child: const Text(
            'Ingresa el valor que te pagó tu cliente y el método de pago.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        Transform.rotate(
          angle: math.pi / 4,
          child: Container(
            width: 14,
            height: 14,
            color: const Color(0xFF1778F2),
          ),
        ),
      ],
    );
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
            border: Border.all(color: _freeSaleBorderColor),
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
                        'Valor Total',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.navy,
                        ),
                      ),
                    ),
                    Text(
                      _money(_total),
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

  Widget _buildAmountPad() {
    return _FreeSaleKeypad(
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

  Widget _buildBody(AppState state, {required double bottomPadding}) {
    final methods = _activeMethods(state);
    _ensurePaymentSlots(methods);
    final dateLabel = DateFormat('d MMMM', 'es').format(_saleDate);
    final paymentAmounts = _splitAmounts(_total, _paymentSlots.length);

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPadding),
      children: [
        _FreeSaleStatusToggle(
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
        const SizedBox(height: 10),
        if (_amountUsd <= 0 && !_showAmountPad) ...[
          _buildHintBubble(),
          const SizedBox(height: 10),
        ],
        _buildAmountCard(),
        const SizedBox(height: 14),
        if (_status == _FreeSaleStatus.paid) ...[
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
                return _FreeSaleCountChip(
                  label: '$count',
                  selected: count == _paymentCount,
                  onTap: () => _setPaymentCount(count, methods),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _paymentCount == 1
                ? 'Metodo de pago'
                : 'Metodo por defecto para los $_paymentCount pagos',
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
                    child: _FreeSaleMethodTile(
                      method: method,
                      selected: selected,
                      onTap: () => _applyMethodToAll(method.code),
                    ),
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: 14),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _freeSaleBorderColor),
            ),
            child: const Text(
              'La venta se registrara sin pagos para manejarla como deuda.',
              style: TextStyle(
                fontSize: 13,
                color: _freeSaleMutedText,
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
                decoration: _freeSaleInputDecoration(hintText: '0%'),
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
                decoration: _freeSaleInputDecoration(hintText: '\$ 0'),
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
        _FreeSalePlaceholderPicker(
          label: 'Selecciona un cliente',
          onTap: () => _showSnack('Clientes: proximamente'),
        ),
        const SizedBox(height: 14),
        _FreeSaleExpandableSection(
          title: 'Mas opciones',
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
                decoration: _freeSaleInputDecoration(
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
                decoration: _freeSaleInputDecoration(
                  hintText: 'Agregar nota...',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _FreeSaleExpandableSection(
          title: 'Detalle del pago',
          expanded: _paymentDetailExpanded,
          onTap: () =>
              setState(() => _paymentDetailExpanded = !_paymentDetailExpanded),
          child: _status == _FreeSaleStatus.debt
              ? const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'No hay pagos configurados para esta venta.',
                    style: TextStyle(
                      fontSize: 13,
                      color: _freeSaleMutedText,
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
                      padding: EdgeInsets.only(top: index == 0 ? 8 : 10),
                      child: _FreeSalePaymentDetailRow(
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
    final bottomPadding = _showAmountPad ? 24.0 : 120.0;

    return PopScope<void>(
      canPop: _canPopRoute,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _showAmountPad) {
          setState(() => _showAmountPad = false);
        }
      },
      child: Scaffold(
        backgroundColor: _freeSaleBackground,
        appBar: AppBar(
          backgroundColor: _freeSaleHeaderColor,
          foregroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          systemOverlayStyle: AppTheme.bannerOverlay,
          leading: IconButton(
            onPressed: () {
              if (_showAmountPad) {
                setState(() => _showAmountPad = false);
                return;
              }
              Navigator.of(context).pop();
            },
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: 'Volver',
          ),
          title: Text(
            widget.isEdit ? 'Editar venta' : 'Nueva venta',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 22,
            ),
          ),
        ),
        body: Stack(
          children: [
            SafeArea(
              top: false,
              child: _buildBody(state, bottomPadding: bottomPadding),
            ),
            if (_showAmountPad) ...[
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
        bottomNavigationBar: _showAmountPad
            ? null
            : SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: _FreeSaleBottomButton(
                    amountUsd: _total,
                    label: widget.isEdit ? 'Guardar venta' : 'Crear venta',
                    enabled:
                        !_submitting &&
                        _total > 0 &&
                        (!widget.isEdit || _isDirty),
                    loading: _submitting,
                    onTap: () => _submit(state, methods),
                  ),
                ),
              ),
      ),
    );
  }
}

class _FreeSaleStatusToggle extends StatelessWidget {
  const _FreeSaleStatusToggle({required this.value, required this.onChanged});

  final _FreeSaleStatus value;
  final ValueChanged<_FreeSaleStatus> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget tab(String label, _FreeSaleStatus status) {
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
        border: Border.all(color: _freeSaleBorderColor),
      ),
      child: Row(
        children: [
          tab('Pagado', _FreeSaleStatus.paid),
          const SizedBox(width: 4),
          tab('Deuda', _FreeSaleStatus.debt),
        ],
      ),
    );
  }
}

class _FreeSaleCountChip extends StatelessWidget {
  const _FreeSaleCountChip({
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
            color: selected ? const Color(0xFFF7D54D) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? const Color(0xFFF7D54D) : _freeSaleBorderColor,
              width: 1.4,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: AppTheme.navy,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FreeSaleMethodTile extends StatelessWidget {
  const _FreeSaleMethodTile({
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
              color: selected ? AppTheme.green : _freeSaleBorderColor,
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

class _FreeSalePlaceholderPicker extends StatelessWidget {
  const _FreeSalePlaceholderPicker({required this.label, required this.onTap});

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
            border: Border.all(color: _freeSaleBorderColor),
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

class _FreeSaleExpandableSection extends StatelessWidget {
  const _FreeSaleExpandableSection({
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

class _FreeSalePaymentDetailRow extends StatelessWidget {
  const _FreeSalePaymentDetailRow({
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
        color: _freeSaleBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _freeSaleBorderColor),
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
            decoration: _freeSaleInputDecoration(labelText: 'Metodo'),
          ),
          const SizedBox(height: 8),
          Text(
            'Monto: ${_moneyStatic(amount)}',
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

String _moneyStatic(double value) {
  return '\$${value.toStringAsFixed(value % 1 == 0 ? 0 : 2)}';
}

class _FreeSaleBottomButton extends StatelessWidget {
  const _FreeSaleBottomButton({
    required this.amountUsd,
    required this.label,
    required this.enabled,
    required this.loading,
    required this.onTap,
  });

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
                _moneyStatic(amountUsd),
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

class _FreeSaleKeypad extends StatelessWidget {
  const _FreeSaleKeypad({
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
      return _FreeSalePadButton(label: label, onTap: () => onDigit(label));
    }

    Widget operatorButton(String label, VoidCallback onTap) {
      return _FreeSalePadButton(label: label, onTap: onTap, filled: true);
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
                child: _FreeSalePadButton(
                  label: 'C',
                  onTap: onClear,
                  textColor: const Color(0xFFD92D20),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _FreeSalePadButton.icon(
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
                child: _FreeSalePadButton(label: '.', onTap: onDecimal),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _FreeSalePadButton(
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

class _FreeSalePadButton extends StatelessWidget {
  const _FreeSalePadButton({
    required this.label,
    required this.onTap,
    this.filled = false,
    this.textColor,
    this.backgroundColor,
    this.foregroundColor,
  }) : icon = null;

  const _FreeSalePadButton.icon({required this.icon, required this.onTap})
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
