import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/admin/admin_screen.dart';
import '../screens/balance/balance_screen.dart';
import '../screens/inventory/inventory_screen.dart';
import '../state/app_state.dart';
import 'app_theme.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (state == AppLifecycleState.resumed) {
      context.read<AppState>().refreshAuthMe(notify: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.select<AppState, bool>((state) => state.isAdmin);
    final rootTabIndex = context.select<AppState, int>(
      (state) => state.rootTabIndex,
    );

    final pages = <Widget>[
      const BalanceScreen(),
      const InventoryScreen(),
      if (isAdmin) const AdminScreen(),
    ];

    final items = <_ShellDestination>[
      const _ShellDestination(
        icon: Icons.receipt_long_outlined,
        label: 'Balance',
      ),
      const _ShellDestination(
        icon: Icons.inventory_2_outlined,
        label: 'Inventario',
      ),
      if (isAdmin)
        const _ShellDestination(
          icon: Icons.admin_panel_settings_outlined,
          label: 'Admin',
        ),
    ];

    final i = rootTabIndex.clamp(0, pages.length - 1);
    return Scaffold(
      body: pages[i],
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 18,
                offset: Offset(0, -4),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
          child: Row(
            children: List.generate(items.length, (index) {
              final item = items[index];
              return Expanded(
                child: _ShellNavItem(
                  icon: item.icon,
                  label: item.label,
                  selected: i == index,
                  onTap: () => context.read<AppState>().setRootTabIndex(index),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _ShellDestination {
  final IconData icon;
  final String label;

  const _ShellDestination({required this.icon, required this.label});
}

class _ShellNavItem extends StatelessWidget {
  const _ShellNavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppTheme.navy : const Color(0xFF9AA3AE);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 25),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 10.5,
                  fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
