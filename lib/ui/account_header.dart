import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'app_theme.dart';
import 'logout.dart';

class AccountHeader extends StatelessWidget implements PreferredSizeWidget {
  const AccountHeader({
    super.key,
    required this.contextLabel,
    this.onSearch,
    this.onFilter,
    this.bottom,
  });

  final String contextLabel;
  final VoidCallback? onSearch;
  final VoidCallback? onFilter;
  final PreferredSizeWidget? bottom;

  @override
  Size get preferredSize =>
      Size.fromHeight(84 + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final headerData = context
        .select<AppState, ({String title, String subtitle})>(
          (state) => (
            title: state.isImpersonating
                ? state.impersonatedUserName
                : state.userDisplayName,
            subtitle: _roleLabel(state),
          ),
        );

    return AppBar(
      backgroundColor: AppTheme.bannerBlue,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      systemOverlayStyle: AppTheme.bannerOverlay,
      surfaceTintColor: Colors.transparent,
      toolbarHeight: 84,
      leadingWidth: 74,
      automaticallyImplyLeading: false,
      flexibleSpace: const DecoratedBox(
        decoration: BoxDecoration(color: AppTheme.bannerBlue),
      ),
      leading: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: Center(
          child: Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.person_outline_rounded,
              color: AppTheme.navy,
              size: 27,
            ),
          ),
        ),
      ),
      titleSpacing: 0,
      title: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () =>
            _showAccountsSheet(context, context.read<AppState>(), contextLabel),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            headerData.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              height: 1.0,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      headerData.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.94),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (onSearch != null)
          IconButton(
            onPressed: onSearch,
            icon: const Icon(
              Icons.search_rounded,
              color: Colors.white,
              size: 30,
            ),
            tooltip: 'Buscar',
          ),
        if (onFilter != null)
          IconButton(
            onPressed: onFilter,
            icon: const Icon(Icons.tune_rounded, color: Colors.white, size: 26),
            tooltip: 'Filtros',
          ),
        const SizedBox(width: 6),
      ],
      bottom: bottom,
    );
  }

  static String _roleLabel(AppState state) {
    final roles = state.roles.map((e) => e.toUpperCase()).toSet();
    if (state.isImpersonating) return 'Viendo la app como usuario';
    if (roles.contains('ADMIN')) return 'Propietario';
    if (roles.contains('SUPERVISOR')) return 'Supervisor';
    if (roles.contains('SUCURSAL')) return 'Sucursal';
    if (roles.contains('BODEGA')) return 'Bodega';
    return 'Usuario';
  }
}

Future<void> _showAccountsSheet(
  BuildContext context,
  AppState state,
  String contextLabel,
) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheetContext) {
      final name = state.isImpersonating
          ? state.impersonatedUserName
          : state.userDisplayName;
      final adminName = state.adminDisplayName;
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Cuentas',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.navy,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    icon: const Icon(Icons.close),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFFF2F4F7),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7FAFC),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE4EAF2)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.person_outline,
                        color: AppTheme.navy,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 17,
                              color: AppTheme.navy,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            state.isImpersonating
                                ? 'Vista temporal en $contextLabel'
                                : AccountHeader._roleLabel(state),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Colors.black54,
                            ),
                          ),
                          if (state.isImpersonating &&
                              adminName.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Administrador: $adminName',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Colors.black54,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (state.isImpersonating)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.pop(sheetContext);
                      await state.stopImpersonation();
                      if (context.mounted && Navigator.of(context).canPop()) {
                        Navigator.of(context).pop();
                      }
                    },
                    icon: const Icon(Icons.undo_rounded),
                    label: const Text('Volver a mi sesión'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.navy,
                      side: const BorderSide(color: Color(0xFFD8E0EA)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              if (state.isImpersonating) const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () async {
                    Navigator.pop(sheetContext);
                    await confirmLogout(context);
                  },
                  icon: Icon(
                    state.isImpersonating
                        ? Icons.logout_rounded
                        : Icons.power_settings_new_rounded,
                  ),
                  label: Text(
                    state.isImpersonating
                        ? 'Salir de vista de usuario'
                        : 'Cerrar sesión',
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: state.isImpersonating
                        ? AppTheme.navy
                        : const Color(0xFFB42318),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
