import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/txn.dart';
import '../../state/app_state.dart';
import '../../ui/app_theme.dart';
import '../../ui/logout.dart';
import '../balance/txn_detail_screen.dart';

class UserActivityScreen extends StatefulWidget {
  final Map<String, dynamic> user;
  const UserActivityScreen({super.key, required this.user});

  @override
  State<UserActivityScreen> createState() => _UserActivityScreenState();
}

class _UserActivityScreenState extends State<UserActivityScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  DateTime _day = DateTime.now();
  bool _loading = true;
  String? _error;
  List<Txn> _txns = const [];
  List<Map<String, dynamic>> _docs = const [];

  String get _userId => (widget.user['id'] ?? '').toString();

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final model = context.read<AppState>();
      final txns = await model.adminTransaccionesPorDia(
        userId: _userId,
        day: _day,
      );
      final docs = await model.adminDocsInventario(userId: _userId);
      if (!mounted) return;
      setState(() {
        _txns = txns;
        _docs = docs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: _day,
      locale: const Locale('es'),
    );
    if (picked == null) return;
    setState(() => _day = DateTime(picked.year, picked.month, picked.day));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final fullName = (widget.user['fullName'] ?? '').toString();
    final username = (widget.user['username'] ?? '').toString();
    final dayFmt = DateFormat("EEEE d 'de' MMM", 'es');
    final txnFmt = DateFormat("dd 'de' MMM - hh:mm a", 'es');

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bannerBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              fullName.isEmpty ? 'Actividad del usuario' : fullName,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            if (username.isNotEmpty)
              Text(
                username,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withOpacity(0.9),
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _pickDay,
            icon: const Icon(Icons.calendar_month_outlined),
            tooltip: 'Cambiar día',
          ),
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
          ),
          IconButton(
            onPressed: () => confirmLogout(context),
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          indicatorColor: Colors.white,
          labelStyle: const TextStyle(fontWeight: FontWeight.w900),
          tabs: const [
            Tab(text: 'Balance'),
            Tab(text: 'Inventario'),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : (_error != null)
            ? Center(
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              )
            : TabBarView(
                controller: _tab,
                children: [
                  ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: const Color(0xFFE6EBF2),
                            width: 1.2,
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.event_note_outlined,
                              color: AppTheme.navy,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                dayFmt.format(_day),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            Text(
                              '${_txns.length} mov.',
                              style: TextStyle(
                                color: Colors.black.withOpacity(0.55),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_txns.isEmpty)
                        const Center(
                          child: Text('No hay transacciones en esta fecha'),
                        )
                      else
                        ..._txns.map(
                          (t) => _TxnRow(
                            t: t,
                            fmt: txnFmt,
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => TxnDetailScreen(txn: t),
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                  ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: const Color(0xFFE6EBF2),
                            width: 1.2,
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.inventory_2_outlined,
                              color: AppTheme.navy,
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'Documentos de inventario',
                                style: TextStyle(fontWeight: FontWeight.w900),
                              ),
                            ),
                            Text(
                              '${_docs.length}',
                              style: TextStyle(
                                color: Colors.black.withOpacity(0.55),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_docs.isEmpty)
                        const Center(
                          child: Text('No hay documentos registrados'),
                        )
                      else
                        ..._docs.map((d) => _DocTile(doc: d)).toList(),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}

class _TxnRow extends StatelessWidget {
  final Txn t;
  final DateFormat fmt;
  final VoidCallback onTap;
  const _TxnRow({required this.t, required this.fmt, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isIncome = t.type == 'income';
    final amount = t.amount.toStringAsFixed(2);
    final currency = String.fromCharCode(36);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE6EBF2), width: 1.2),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: isIncome
                    ? const Color(0xFFE7F7EE)
                    : const Color(0xFFFFE9E9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isIncome ? Icons.trending_up : Icons.trending_down,
                color: isIncome
                    ? const Color(0xFF177245)
                    : const Color(0xFFB00020),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.note ?? (t.kind ?? 'Transacción'),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${fmt.format(t.when)} • ${t.paymentMethod}',
                    style: TextStyle(color: Colors.black.withOpacity(0.55)),
                  ),
                ],
              ),
            ),
            Text(
              '${isIncome ? '+' : '-'}$currency$amount',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: isIncome
                    ? const Color(0xFF177245)
                    : const Color(0xFFB00020),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DocTile extends StatelessWidget {
  final Map<String, dynamic> doc;
  const _DocTile({required this.doc});

  @override
  Widget build(BuildContext context) {
    final docType = (doc['docType'] ?? doc['tipo'] ?? '').toString();
    final status = (doc['status'] ?? '').toString();
    final num = (doc['docNumber'] ?? doc['numero'] ?? '').toString();
    final notes = (doc['notes'] ?? '').toString();
    final createdAt = doc['createdAt'] ?? doc['created_at'];
    final dt = DateTime.tryParse(createdAt?.toString() ?? '');
    final when = dt == null
        ? ''
        : DateFormat(
            "dd 'de' MMM - hh:mm a",
            'es',
          ).format(dt.isUtc ? dt.toLocal() : dt);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE6EBF2), width: 1.2),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFF2F5FA),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.description_outlined, color: AppTheme.navy),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$docType ${num.isEmpty ? '' : '#$num'}',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 2),
                Text(
                  '${status.isEmpty ? '—' : status}${when.isEmpty ? '' : ' • $when'}',
                  style: TextStyle(color: Colors.black.withOpacity(0.55)),
                ),
                if (notes.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      notes,
                      style: TextStyle(color: Colors.black.withOpacity(0.7)),
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
