import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/txn.dart';
import '../../state/app_state.dart';
import '../../ui/app_theme.dart';
import 'balance_date_strip.dart';

class BalanceDetailScreen extends StatefulWidget {
  const BalanceDetailScreen({super.key});

  @override
  State<BalanceDetailScreen> createState() => _BalanceDetailScreenState();
}

class _BalanceDetailScreenState extends State<BalanceDetailScreen> {
  bool _profitExpanded = true;

  double _sum(Iterable<Txn> list) =>
      list.fold<double>(0, (a, t) => a + t.amount);

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
    final day = model.selectedDay;

    final dayFmt = DateFormat('d MMM', 'es');

    final all = model.txnsForDay;
    final incomes = all.where((t) => t.type == 'income').toList();
    final expenses = all.where((t) => t.type == 'expense').toList();

    final incomeTotal = _sum(incomes);
    final expenseTotal = _sum(expenses);
    final balance = model.dayBalance;

    // Ya viene calculado desde el backend (/balance/ver)
    final view = model.balanceView;
    final sales = view?.salesUsd ?? incomeTotal;
    final cogs = view?.cogsUsd ?? 0.0;
    final profit = view?.profitUsd ?? (sales - cogs);

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
          'Detalle del balance',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Container(
            padding: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: AppTheme.bannerBlue,
              border: Border(
                top: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
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
              unselectedTextColor: AppTheme.navy.withValues(alpha: 0.80),
              dividerColor: Colors.black.withValues(alpha: 0.12),
              calendarBorderColor: Colors.black.withValues(alpha: 0.18),
              calendarIconColor: AppTheme.navy,
              futureDays: 0,
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _TopTotalsCard(
            income: incomeTotal,
            expense: expenseTotal,
            balance: balance,
          ),
          const SizedBox(height: 12),

          _ExpandableCard(
            title: 'Ganancia',
            expanded: _profitExpanded,
            onChanged: (v) => setState(() => _profitExpanded = v),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Se calcula restando de tus ventas el costo que tienes registrado en los productos.',
                  style: TextStyle(
                    color: Colors.black54,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 14),
                _kvRow('Ventas', '\$${sales.toStringAsFixed(0)}'),
                const SizedBox(height: 10),
                _kvRow(
                  'Costo de productos que\nvendiste',
                  '\$-${cogs.toStringAsFixed(0)}',
                  valueColor: AppTheme.red,
                ),
                const SizedBox(height: 12),
                const Divider(color: Color(0xFFE6EBF2), height: 1),
                const SizedBox(height: 12),
                _kvRow(
                  'Ganancia estimada',
                  '\$${profit.toStringAsFixed(0)}',
                  bold: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Cards por método de pago (ventas/abonos/gastos/balance)
          for (final entry
              in (view?.byPaymentMethod.entries.toList() ?? const []).toList()
                ..sort(
                  (a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()),
                )) ...[
            _PaymentMethodCard(method: entry.key, data: entry.value),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  static Widget _kvRow(
    String left,
    String right, {
    bool bold = false,
    Color? valueColor,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            left,
            style: TextStyle(
              fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
              fontSize: bold ? 16 : 15,
              color: AppTheme.navy,
              height: 1.15,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          right,
          style: TextStyle(
            fontWeight: bold ? FontWeight.w900 : FontWeight.w800,
            fontSize: bold ? 16 : 15,
            color: valueColor ?? AppTheme.navy,
          ),
        ),
      ],
    );
  }
}

class _TopTotalsCard extends StatelessWidget {
  const _TopTotalsCard({
    required this.income,
    required this.expense,
    required this.balance,
  });

  final double income;
  final double expense;
  final double balance;

  @override
  Widget build(BuildContext context) {
    final balColor = balance >= 0 ? AppTheme.green : AppTheme.red;

    Widget col({
      required IconData icon,
      required Color iconColor,
      required String label,
      required String value,
    }) {
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: iconColor, size: 18),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.black54,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 20,
                color: AppTheme.navy,
              ),
            ),
          ],
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
              col(
                icon: Icons.trending_up,
                iconColor: AppTheme.green,
                label: 'Ingresos',
                value: '\$${income.toStringAsFixed(0)}',
              ),
              Container(width: 1, height: 64, color: const Color(0xFFE6EBF2)),
              col(
                icon: Icons.trending_down,
                iconColor: AppTheme.red,
                label: 'Egresos',
                value: '-\$${expense.toStringAsFixed(0)}',
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: Color(0xFFE6EBF2), height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Balance',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                    color: AppTheme.navy,
                  ),
                ),
              ),
              Text(
                '\$${balance.toStringAsFixed(0)}',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                  color: balColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PaymentMethodCard extends StatefulWidget {
  const _PaymentMethodCard({required this.method, required this.data});
  final String method;
  final Map<String, double> data;

  @override
  State<_PaymentMethodCard> createState() => _PaymentMethodCardState();
}

class _PaymentMethodCardState extends State<_PaymentMethodCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final sales = widget.data['ventas'] ?? 0.0;
    final abonos = widget.data['abonos'] ?? 0.0;
    final expenses = widget.data['gastos'] ?? 0.0;
    final total = widget.data['balance'] ?? (sales + abonos - expenses);

    Widget row(
      String left,
      String right, {
      Color? valueColor,
      bool bold = false,
    }) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                left,
                style: TextStyle(
                  fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
                  fontSize: 14,
                  color: AppTheme.navy,
                ),
              ),
            ),
            Text(
              right,
              style: TextStyle(
                fontWeight: bold ? FontWeight.w900 : FontWeight.w800,
                fontSize: 14,
                color: valueColor ?? AppTheme.navy,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE6EBF2), width: 1.2),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: _expanded,
          onExpansionChanged: (v) => setState(() => _expanded = v),
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),

          // ✅ Title solo el método (con ellipsis)
          title: Text(
            widget.method,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 18,
              color: AppTheme.navy,
            ),
          ),

          // ✅ Trailing: monto + flecha (como referencia) y sin overflow
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '\$${total.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  color: AppTheme.navy,
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                _expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                color: AppTheme.navy,
                size: 28,
              ),
            ],
          ),

          children: [
            row('Ventas', '\$${sales.toStringAsFixed(0)}'),
            row('Abonos', '\$${abonos.toStringAsFixed(0)}'),
            row(
              'Gastos',
              '\$${expenses.toStringAsFixed(0)}',
              valueColor: AppTheme.red,
            ),
            const Divider(color: Color(0xFFE6EBF2), height: 1),
            const SizedBox(height: 10),
            row(
              'Balance total registrado',
              '\$${total.toStringAsFixed(0)}',
              bold: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _ExpandableCard extends StatelessWidget {
  const _ExpandableCard({
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
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          title: Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 20,
              color: AppTheme.navy,
            ),
          ),
          trailing: Icon(
            expanded
                ? Icons.keyboard_arrow_up_rounded
                : Icons.keyboard_arrow_down_rounded,
            color: AppTheme.navy,
            size: 28,
          ),
          children: [child],
        ),
      ),
    );
  }
}
