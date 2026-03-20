class Txn {
  final String id;
  final String type; // income | expense
  final double amount;
  final String paymentMethod;
  final String? note;
  final DateTime when;

  /// Datos extra para pantallas de detalle (sin romper compatibilidad).
  ///
  /// Ejemplo backend (/balance/transacciones):
  /// {
  ///   kind: 'VENTA'|'GASTO'|'ABONO'|'DEUDA',
  ///   direction: 'INGRESO'|'EGRESO',
  ///   occurredAt, amountUsd,
  ///   paymentMethod, sale?, expense?
  /// }
  final String? kind;
  final Map<String, dynamic>? sale;
  final Map<String, dynamic>? expense;
  final String? saleId;
  final String? expenseId;

  const Txn({
    required this.id,
    required this.type,
    required this.amount,
    required this.paymentMethod,
    required this.note,
    required this.when,

    this.kind,
    this.sale,
    this.expense,
    this.saleId,
    this.expenseId,
  });

  static double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  static DateTime _toDate(dynamic v) {
    if (v == null) return DateTime.now();
    if (v is DateTime) return v.isUtc ? v.toLocal() : v;
    final s = v.toString();
    final dt = DateTime.tryParse(s);
    if (dt == null) return DateTime.now();
    return dt.isUtc ? dt.toLocal() : dt;
  }

  /// Mapeo flexible desde el backend.
  /// Espera algo como:
  /// {
  ///   id, direction: 'INGRESO'|'EGRESO', amountUsd,
  ///   paymentMethod: { name } | paymentMethodName,
  ///   note/description/title,
  ///   date/createdAt
  /// }
  factory Txn.fromApi(Map<String, dynamic> m) {
    final direction = (m['direction'] ?? m['tipo'] ?? '').toString().toUpperCase();
    final isIncome = direction.contains('INGRESO') || direction.contains('VENTA') || direction.contains('IN');

    final pm = (m['paymentMethod'] is Map)
        ? ((m['paymentMethod']['name'] ?? m['paymentMethod']['code'])?.toString() ?? '')
        : (m['paymentMethodName'] ?? m['paymentMethodCode'] ?? m['metodoPago'] ?? '').toString();

    final noteRaw = (
        m['note'] ??
        m['description'] ??
        m['title'] ??
        m['concept'] ??
        (m['sale'] is Map ? (m['sale']['description'] ?? m['sale']['concept']) : null) ??
        (m['expense'] is Map ? (m['expense']['description'] ?? m['expense']['concept']) : null) ??
        m['kind']);
    final note = (noteRaw == null)
        ? null
        : (noteRaw.toString().trim().isEmpty ? null : noteRaw.toString().trim());

    final kind = (m['kind'] ?? '').toString().trim();
    final sale = (m['sale'] is Map) ? (m['sale'] as Map).cast<String, dynamic>() : null;
    final expense = (m['expense'] is Map) ? (m['expense'] as Map).cast<String, dynamic>() : null;
    final saleId = (
      (sale == null ? null : (sale['id']?.toString())) ??
      m['saleId']?.toString() ??
      m['ventaId']?.toString() ??
      m['sale_id']?.toString()
    );
    final expenseId = (
      (expense == null ? null : (expense['id']?.toString())) ??
      m['expenseId']?.toString() ??
      m['gastoId']?.toString() ??
      m['expense_id']?.toString()
    );

    final inferredId = (
      m['id'] ??
      (m['sale'] is Map ? m['sale']['id'] : null) ??
      (m['expense'] is Map ? m['expense']['id'] : null) ??
      '${m['kind'] ?? 'TX'}-${m['occurredAt'] ?? m['createdAt'] ?? m['date'] ?? ''}'
    ).toString();

    return Txn(
      id: inferredId,
      type: isIncome ? 'income' : 'expense',
      amount: _toDouble(m['amountUsd'] ?? m['amount'] ?? m['montoUsd'] ?? m['monto']),
      paymentMethod: pm.isEmpty ? '—' : pm,
      note: note,
      when: _toDate(m['occurredAt'] ?? m['date'] ?? m['createdAt'] ?? m['when']),

      kind: kind.isEmpty ? null : kind,
      sale: sale,
      expense: expense,
      saleId: saleId == null || saleId.trim().isEmpty ? null : saleId.trim(),
      expenseId: expenseId == null || expenseId.trim().isEmpty ? null : expenseId.trim(),
    );
  }
}
