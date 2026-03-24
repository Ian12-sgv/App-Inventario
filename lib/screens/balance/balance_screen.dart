import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/txn.dart';
import '../../state/app_state.dart';
import '../../ui/app_theme.dart';
import '../../ui/account_header.dart';
import '../../utils/balance_report_exporter.dart';
import 'balance_date_strip.dart';
import 'balance_detail_screen.dart';
import 'transaction_sheet.dart';
import 'txn_detail_screen.dart';

class BalanceScreen extends StatefulWidget {
  const BalanceScreen({super.key});

  @override
  State<BalanceScreen> createState() => _BalanceScreenState();
}

class _BalanceScreenState extends State<BalanceScreen> {
  static const List<String> _fixedPaymentMethods = <String>[
    'Binance',
    'Efectivo',
    'Pago móvil',
    'Tarjeta',
    'Transferencia bancaria',
    'Zelle',
  ];

  int _tab = 0; // 0 ingresos, 1 egresos
  int _lastAppliedBalanceTabSignal = -1;
  int _lastAppliedNewExpenseSheetSignal = -1;
  bool _showSearch = false;
  final TextEditingController _searchCtl = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _incomeQuery = '';
  String _expenseQuery = '';
  String? _incomePaymentMethod;
  String? _expensePaymentMethod;

  @override
  void dispose() {
    _searchCtl.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  String get _currentQuery => _tab == 0 ? _incomeQuery : _expenseQuery;

  String? get _currentPaymentMethod =>
      _tab == 0 ? _incomePaymentMethod : _expensePaymentMethod;

  void _setCurrentQuery(String value) {
    final clean = value.trimLeft();
    setState(() {
      if (_tab == 0) {
        _incomeQuery = clean;
      } else {
        _expenseQuery = clean;
      }
    });
  }

  void _setCurrentPaymentMethod(String? value) {
    final clean = (value ?? '').trim();
    setState(() {
      if (_tab == 0) {
        _incomePaymentMethod = clean.isEmpty ? null : clean;
      } else {
        _expensePaymentMethod = clean.isEmpty ? null : clean;
      }
    });
  }

  void _syncSearchController() {
    final target = _currentQuery;
    if (_searchCtl.text == target) return;
    _searchCtl.value = TextEditingValue(
      text: target,
      selection: TextSelection.collapsed(offset: target.length),
    );
  }

  void _requestSearchFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _searchFocusNode.requestFocus();
    });
  }

  void _openSearch() {
    setState(() {
      _showSearch = true;
      _syncSearchController();
    });
    _requestSearchFocus();
  }

  void _closeSearch() {
    setState(() {
      if (_tab == 0) {
        _incomeQuery = '';
      } else {
        _expenseQuery = '';
      }
      _showSearch = false;
      _searchCtl.clear();
    });
    _searchFocusNode.unfocus();
  }

  void _changeTab(int index) {
    if (_tab == index) return;
    setState(() {
      _tab = index;
      _syncSearchController();
    });
    if (_showSearch) _requestSearchFocus();
  }

  String _normalizeText(String value) {
    return value
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('ñ', 'n');
  }

  String _normalizePaymentMethodKey(String value) {
    return _normalizeText(value)
        .replaceAll('_', ' ')
        .replaceAll(RegExp(r'[^a-z0-9 ]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _canonicalPaymentMethod(String value) {
    final normalized = _normalizePaymentMethodKey(value);
    if (normalized.isEmpty || normalized == '—') return '';
    if (normalized.contains('binance')) return 'Binance';
    if (normalized.contains('efectivo')) return 'Efectivo';
    if (normalized.contains('pago movil') || normalized.contains('pagomovil')) {
      return 'Pago móvil';
    }
    if (normalized.contains('tarjeta')) return 'Tarjeta';
    if (normalized.contains('transferencia')) return 'Transferencia bancaria';
    if (normalized.contains('zelle')) return 'Zelle';
    return value.trim();
  }

  String _txnSearchText(Txn txn) {
    final entity = txn.sale ?? txn.expense ?? const <String, dynamic>{};
    final contact =
        [
              entity['contactName'],
              entity['contact'],
              entity['clientName'],
              entity['cliente'],
              entity['client'],
              entity['supplierName'],
              entity['proveedor'],
              entity['provider'],
              entity['customerName'],
              entity['customer'],
            ]
            .map((value) => (value ?? '').toString().trim())
            .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    final parts = <String>[
      txn.note ?? '',
      txn.paymentMethod,
      txn.kind ?? '',
      txn.id,
      txn.amount.toStringAsFixed(0),
      txn.amount.toStringAsFixed(2),
      contact,
      (entity['description'] ?? entity['concept'] ?? '').toString(),
      (entity['categoryLabel'] ?? entity['category'] ?? '').toString(),
      (entity['statusLabel'] ?? entity['status'] ?? '').toString(),
    ];
    return _normalizeText(parts.join(' '));
  }

  List<Txn> _filteredTxns(List<Txn> txns) {
    final query = _normalizeText(_currentQuery.trim());
    final paymentMethod = _canonicalPaymentMethod(_currentPaymentMethod ?? '');
    return txns.where((txn) {
      if (paymentMethod.isNotEmpty &&
          _canonicalPaymentMethod(txn.paymentMethod) != paymentMethod) {
        return false;
      }
      if (query.isNotEmpty && !_txnSearchText(txn).contains(query)) {
        return false;
      }
      return true;
    }).toList();
  }

  Future<void> _openPaymentMethodFilterSheet() async {
    final selected = await showModalBottomSheet<String?>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => _PaymentMethodFilterSheet(
        title: _tab == 0 ? 'Filtrar ingresos' : 'Filtrar egresos',
        selectedMethod: _currentPaymentMethod,
        methods: _fixedPaymentMethods,
      ),
    );

    if (!mounted || selected == null) return;
    if (selected == _PaymentMethodFilterSheet.clearValue) {
      _setCurrentPaymentMethod(null);
      return;
    }
    _setCurrentPaymentMethod(selected);
  }

  Future<void> _openExportSheet(AppState model) async {
    final txns = model.txnsForDay;
    if (txns.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay movimientos en este dia para exportar.'),
        ),
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
      builder: (sheetContext) => _BalanceExportSheet(
        movementCount: txns.length,
        onPdf: () async {
          Navigator.pop(sheetContext);
          await _exportPdf(model);
        },
        onExcel: () async {
          Navigator.pop(sheetContext);
          await _exportExcel(model, shareOrigin: shareOrigin);
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

  Future<void> _exportPdf(AppState model) async {
    try {
      await BalanceReportExporter.shareDailyPdfReport(
        state: model,
        txns: model.txnsForDay,
        day: model.selectedDay,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo generar el PDF: $e')));
    }
  }

  Future<void> _exportExcel(AppState model, {Rect? shareOrigin}) async {
    try {
      await BalanceReportExporter.shareDailyExcelReport(
        state: model,
        txns: model.txnsForDay,
        day: model.selectedDay,
        sharePositionOrigin: shareOrigin,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo generar Excel: $e')));
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

    if (_lastAppliedBalanceTabSignal == -1) {
      // Ignora señales antiguas para que la vista siempre arranque en Ingresos.
      _lastAppliedBalanceTabSignal = model.balanceTabSignal;
    } else if (_lastAppliedBalanceTabSignal != model.balanceTabSignal) {
      _lastAppliedBalanceTabSignal = model.balanceTabSignal;
      final target = model.balanceTabPreferred.clamp(0, 1);
      if (_tab != target) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() => _tab = target);
        });
      }
    }

    if (_lastAppliedNewExpenseSheetSignal == -1) {
      _lastAppliedNewExpenseSheetSignal = model.newExpenseSheetSignal;
    } else if (_lastAppliedNewExpenseSheetSignal !=
        model.newExpenseSheetSignal) {
      _lastAppliedNewExpenseSheetSignal = model.newExpenseSheetSignal;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_tab != 1) {
          setState(() => _tab = 1);
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (!mounted) return;
            await showNuevoGastoSheet(context);
          });
          return;
        }
        showNuevoGastoSheet(context);
      });
    }

    final day = model.selectedDay;

    final dayFmt = DateFormat('d MMM', 'es');
    final txnFmt = DateFormat("dd 'de' MMM - hh:mm a", 'es');

    final allTxns = model.txnsForDay
        .where((t) => _tab == 0 ? t.type == 'income' : t.type == 'expense')
        .toList();
    final txns = _filteredTxns(allTxns);

    final balance = model.dayBalance;
    final income = model.dayIncome;
    final expense = model.dayExpense;

    if (_searchCtl.text != _currentQuery) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _syncSearchController();
      });
    }

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AccountHeader(
        contextLabel: 'Balance',
        onSearch: _openSearch,
        onFilter: _openPaymentMethodFilterSheet,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Container(
            padding: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: AppTheme.bannerBlue,
              border: Border(
                top: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
              ),
            ),
            child: BalanceDateStrip(
              selected: day,
              format: dayFmt,
              onPick: (d) => context.read<AppState>().setSelectedDay(d),
              onOpenCalendar: () async {
                final now = DateTime.now();
                final today = DateTime(now.year, now.month, now.day);
                final picked = await showDatePicker(
                  context: context,
                  firstDate: DateTime(2020),
                  lastDate: today,
                  initialDate: day.isAfter(today) ? today : day,
                  locale: const Locale('es'),
                );
                if (picked != null && context.mounted) {
                  await context.read<AppState>().setSelectedDay(picked);
                }
              },
              selectedBackgroundColor: Colors.white,
              selectedTextColor: AppTheme.navy,
              unselectedTextColor: Colors.white.withValues(alpha: 0.85),
              dividerColor: Colors.white.withValues(alpha: 0.18),
              calendarBorderColor: Colors.white.withValues(alpha: 0.28),
              calendarIconColor: Colors.white,
              isRefreshing: model.balanceRefreshing,
              futureDays: 0,
            ),
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            _BalanceCardCompact(
              balance: balance,
              income: income,
              expense: expense,
              onDownload: () => _openExportSheet(model),
              onViewBalance: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const BalanceDetailScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            _OrganizeCardCompact(
              progressText: '0/7',
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Organiza tu negocio: próximamente'),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            _UnderlineTabsCompact(
              left: 'Ingresos',
              right: 'Egresos',
              selectedIndex: _tab,
              onChanged: _changeTab,
            ),
            if (_showSearch) ...[
              const SizedBox(height: 10),
              _BalanceSearchBar(
                controller: _searchCtl,
                focusNode: _searchFocusNode,
                hintText: _tab == 0
                    ? 'Buscar ingresos del día'
                    : 'Buscar egresos del día',
                onChanged: _setCurrentQuery,
                onClose: _closeSearch,
              ),
            ],
            if (_currentQuery.trim().isNotEmpty ||
                (_currentPaymentMethod ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              _BalanceActiveFilters(
                query: _currentQuery.trim(),
                paymentMethod: _currentPaymentMethod,
                onClearQuery: _currentQuery.trim().isEmpty
                    ? null
                    : () {
                        _searchCtl.clear();
                        _setCurrentQuery('');
                      },
                onClearPaymentMethod:
                    (_currentPaymentMethod ?? '').trim().isEmpty
                    ? null
                    : () => _setCurrentPaymentMethod(null),
                onClearAll: () {
                  _searchCtl.clear();
                  setState(() {
                    if (_tab == 0) {
                      _incomeQuery = '';
                      _incomePaymentMethod = null;
                    } else {
                      _expenseQuery = '';
                      _expensePaymentMethod = null;
                    }
                  });
                },
              ),
            ],
            const SizedBox(height: 10),
            if (allTxns.isEmpty)
              const _EmptyStateCompact()
            else if (txns.isEmpty)
              const _NoResultsCompact()
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: txns.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 10),
                itemBuilder: (context, i) => _TxnTileCompact(
                  t: txns[i],
                  fmt: txnFmt,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => TxnDetailScreen(txn: txns[i]),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 12),
          ],
        ),
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
            children: [
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(26),
                      ),
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    onPressed: model.canCrearVenta
                        ? () => showNuevaVentaSheet(context)
                        : null,
                    // Si el usuario no tiene permiso, el backend igual lo bloqueará.
                    // Aquí lo deshabilitamos para evitar errores y mejorar UX.
                    icon: const Icon(Icons.add_circle_outline, size: 20),
                    label: const Text('Nueva venta'),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.red,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(26),
                      ),
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    onPressed: () => showNuevoGastoSheet(context),
                    icon: const Icon(Icons.remove_circle_outline, size: 20),
                    label: const Text('Nuevo gasto'),
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

/* -------------------- BALANCE CARD (COMPACTO) -------------------- */

class _BalanceCardCompact extends StatelessWidget {
  const _BalanceCardCompact({
    required this.balance,
    required this.income,
    required this.expense,
    required this.onDownload,
    required this.onViewBalance,
  });

  final double balance;
  final double income;
  final double expense;
  final VoidCallback onDownload;
  final VoidCallback onViewBalance;

  @override
  Widget build(BuildContext context) {
    final balColor = balance >= 0 ? AppTheme.green : AppTheme.red;

    Widget col({
      required IconData icon,
      required Color color,
      required String label,
      required String value,
    }) {
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: color, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.black54,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                value,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 22,
                  color: AppTheme.navy,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE6EBF2), width: 1.2),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Text(
                'Balance',
                style: TextStyle(
                  color: Colors.black54,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Text(
                '\$${balance.toStringAsFixed(0)}',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 22,
                  color: balColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              col(
                icon: Icons.trending_up,
                color: AppTheme.green,
                label: 'Ingresos',
                value: '\$${income.toStringAsFixed(0)}',
              ),
              Container(width: 1, height: 60, color: const Color(0xFFE6EBF2)),
              col(
                icon: Icons.trending_down,
                color: AppTheme.red,
                label: 'Egresos',
                value: '\$${expense.toStringAsFixed(0)}',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: onDownload,
                  child: const Text(
                    'Descargar Reportes',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      decoration: TextDecoration.underline,
                      color: AppTheme.navy,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              InkWell(
                onTap: onViewBalance,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Ver Balance',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: AppTheme.navy,
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(Icons.chevron_right_rounded, color: AppTheme.navy),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BalanceExportSheet extends StatelessWidget {
  const _BalanceExportSheet({
    required this.movementCount,
    required this.onPdf,
    required this.onExcel,
  });

  final int movementCount;
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
                    'Descargar reporte',
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
              'Exporta $movementCount movimiento(s) del dia seleccionado en el formato que prefieras.',
              style: const TextStyle(
                color: Colors.black54,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            _BalanceExportOption(
              icon: Icons.picture_as_pdf_rounded,
              accent: AppTheme.red,
              title: 'PDF',
              subtitle:
                  'Reporte visual del balance diario con resumen y movimientos.',
              onTap: onPdf,
            ),
            const SizedBox(height: 12),
            _BalanceExportOption(
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

class _BalanceExportOption extends StatelessWidget {
  const _BalanceExportOption({
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
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE4EAF2), width: 1.2),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: accent, size: 26),
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
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.25,
                        color: Colors.black54,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppTheme.navy,
                size: 28,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* -------------------- ORGANIZE CARD (COMPACTO) -------------------- */

class _OrganizeCardCompact extends StatelessWidget {
  const _OrganizeCardCompact({required this.progressText, required this.onTap});

  final String progressText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFE6EBF2), width: 1.2),
        ),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'Organiza tu negocio',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  color: AppTheme.navy,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFDFF7EC),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                progressText,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F5E3B),
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.keyboard_arrow_down_rounded, color: AppTheme.navy),
          ],
        ),
      ),
    );
  }
}

/* -------------------- TABS (COMPACTO) -------------------- */

class _UnderlineTabsCompact extends StatelessWidget {
  const _UnderlineTabsCompact({
    required this.left,
    required this.right,
    required this.selectedIndex,
    required this.onChanged,
  });

  final String left;
  final String right;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget tab(String label, int i) {
      final sel = selectedIndex == i;
      return Expanded(
        child: InkWell(
          onTap: () => onChanged(i),
          child: Column(
            children: [
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  color: sel
                      ? AppTheme.navy
                      : AppTheme.navy.withValues(alpha: 0.55),
                ),
              ),
              const SizedBox(height: 8),
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                height: 4,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: sel ? AppTheme.navy : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Row(children: [tab(left, 0), tab(right, 1)]);
  }
}

/* -------------------- TXN TILE (COMPACTO) -------------------- */

class _TxnTileCompact extends StatelessWidget {
  const _TxnTileCompact({
    required this.t,
    required this.fmt,
    required this.onTap,
  });
  final Txn t;
  final DateFormat fmt;
  final VoidCallback onTap;

  static double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  String _statusLabel() {
    final k = (t.kind ?? '').toUpperCase();
    if (k == 'DEUDA') return 'Deuda';
    if (k == 'ABONO') return 'Pagado';
    if (k == 'GASTO' && t.expense != null) {
      final s = (t.expense!['statusLabel'] ?? t.expense!['status'] ?? '')
          .toString()
          .toUpperCase();
      if (s.contains('DEUDA')) return 'Deuda';
    }
    return 'Pagado';
  }

  String _cleanTime(String s) {
    // intl en español suele devolver “a. m.” / “p. m.”; lo normalizamos a “am/pm”.
    return s
        .replaceAll('a.\u00A0m.', 'am')
        .replaceAll('p.\u00A0m.', 'pm')
        .replaceAll('a. m.', 'am')
        .replaceAll('p. m.', 'pm')
        .replaceAll('a.\u202Fm.', 'am')
        .replaceAll('p.\u202Fm.', 'pm');
  }

  @override
  Widget build(BuildContext context) {
    final sign = t.type == 'income' ? '+' : '-';
    final color = t.type == 'income' ? AppTheme.green : AppTheme.red;

    final status = _statusLabel();
    final statusColor = status == 'Deuda' ? AppTheme.red : AppTheme.green;

    // Título: concepto/nota. Si es pago parcial, prefija (xx%).
    var title = (t.note ?? '').trim();
    if (title.isEmpty) title = t.type == 'income' ? 'Ingreso' : 'Egreso';

    final sale = t.sale;
    final totalUsd = sale == null
        ? 0.0
        : _toDouble(sale['totalUsd'] ?? sale['total_usd'] ?? sale['total']);
    if ((t.kind ?? '').toUpperCase() == 'VENTA' && totalUsd > 0) {
      final pct = (t.amount / totalUsd) * 100.0;
      final pctInt = pct.isFinite ? pct.round() : 0;
      final looksPrefixed = title.contains('%');
      if (!looksPrefixed && pctInt > 0 && pctInt < 100) {
        title = '($pctInt%) $title';
      }
    }

    final whenText = _cleanTime(fmt.format(t.when));
    final subtitle = '${t.paymentMethod} • $whenText';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE6EBF2), width: 1.2),
          ),
          child: Row(
            children: [
              Container(
                height: 44,
                width: 44,
                decoration: BoxDecoration(
                  color: AppTheme.bg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE6EBF2)),
                ),
                child: Icon(
                  t.type == 'income' ? Icons.add : Icons.remove,
                  color: color,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: AppTheme.navy,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
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
                    '$sign\$${t.amount.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    status,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 12.5,
                      color: statusColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BalanceSearchBar extends StatelessWidget {
  const _BalanceSearchBar({
    required this.controller,
    required this.focusNode,
    required this.hintText,
    required this.onChanged,
    required this.onClose,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE6EBF2), width: 1.2),
            ),
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: const TextStyle(
                  color: Colors.black38,
                  fontWeight: FontWeight.w700,
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: AppTheme.navy,
                ),
                suffixIcon: controller.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          controller.clear();
                          onChanged('');
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        IconButton(
          onPressed: onClose,
          icon: const Icon(Icons.close_rounded),
          style: IconButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: AppTheme.navy,
            padding: const EdgeInsets.all(14),
            side: const BorderSide(color: Color(0xFFE6EBF2), width: 1.2),
          ),
        ),
      ],
    );
  }
}

class _BalanceActiveFilters extends StatelessWidget {
  const _BalanceActiveFilters({
    required this.query,
    required this.paymentMethod,
    required this.onClearQuery,
    required this.onClearPaymentMethod,
    required this.onClearAll,
  });

  final String query;
  final String? paymentMethod;
  final VoidCallback? onClearQuery;
  final VoidCallback? onClearPaymentMethod;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (query.isNotEmpty)
          _FilterPill(label: 'Buscar: $query', onClear: onClearQuery),
        if ((paymentMethod ?? '').trim().isNotEmpty)
          _FilterPill(
            label: 'Método: ${paymentMethod!.trim()}',
            onClear: onClearPaymentMethod,
          ),
        TextButton(
          onPressed: onClearAll,
          style: TextButton.styleFrom(
            foregroundColor: AppTheme.navy,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
            minimumSize: const Size(0, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text(
            'Limpiar todo',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({required this.label, this.onClear});

  final String label;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE6EBF2), width: 1.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.navy,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (onClear != null) ...[
            const SizedBox(width: 8),
            InkWell(
              onTap: onClear,
              borderRadius: BorderRadius.circular(999),
              child: const Icon(
                Icons.close_rounded,
                size: 18,
                color: AppTheme.navy,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PaymentMethodFilterSheet extends StatelessWidget {
  const _PaymentMethodFilterSheet({
    required this.title,
    required this.selectedMethod,
    required this.methods,
  });

  static const String clearValue = '__clear__';

  final String title;
  final String? selectedMethod;
  final List<String> methods;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.72;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
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
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFFF2F4F7),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Selecciona un método de pago para filtrar los movimientos del día actual.',
                style: TextStyle(
                  color: Colors.black54,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _PaymentMethodOption(
                        label: 'Todos los métodos',
                        selected: (selectedMethod ?? '').trim().isEmpty,
                        onTap: () => Navigator.pop(context, clearValue),
                      ),
                      const SizedBox(height: 10),
                      for (final method in methods) ...[
                        _PaymentMethodOption(
                          label: method,
                          selected: method == selectedMethod,
                          onTap: () => Navigator.pop(context, method),
                        ),
                        if (method != methods.last) const SizedBox(height: 10),
                      ],
                    ],
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

class _PaymentMethodOption extends StatelessWidget {
  const _PaymentMethodOption({
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
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? AppTheme.bannerBlue : const Color(0xFFE4EAF2),
              width: selected ? 1.6 : 1.2,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.navy,
                  ),
                ),
              ),
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: selected ? AppTheme.bannerBlue : Colors.black26,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* -------------------- EMPTY (COMPACTO) -------------------- */

class _EmptyStateCompact extends StatelessWidget {
  const _EmptyStateCompact();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFE6EBF2), width: 1.2),
              ),
              child: const Icon(
                Icons.hourglass_empty,
                size: 48,
                color: Colors.black26,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'No tienes registros creados en esta fecha.',
              style: TextStyle(
                fontSize: 16,
                color: Colors.black54,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _NoResultsCompact extends StatelessWidget {
  const _NoResultsCompact();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFE6EBF2), width: 1.2),
              ),
              child: const Icon(
                Icons.search_off_rounded,
                size: 48,
                color: Colors.black26,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'No hay resultados con esa búsqueda o filtro.',
              style: TextStyle(
                fontSize: 16,
                color: Colors.black54,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
