import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/app_state.dart';
import '../../ui/app_theme.dart';
import '../../ui/logout.dart';
import 'user_app_view_screen.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _users = const [];
  List<Map<String, dynamic>> _roles = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final model = context.read<AppState>();
      final users = await model.adminListUsers();
      List<Map<String, dynamic>> roles = const [];
      try {
        roles = await model.adminListRoles();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _users = users;
        _roles = roles;
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

  Future<void> _openCreateUser() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _UserFormSheet(roles: _roles),
    );
    if (created == true) {
      await _load();
    }
  }

  Future<void> _openPermisos(Map<String, dynamic> u) async {
    final userId = (u['id'] ?? '').toString();
    if (userId.trim().isEmpty) return;

    final current = (u['permissions'] is List)
        ? (u['permissions'] as List).map((e) => e.toString()).toList()
        : <String>[];

    final updated = await showDialog<List<String>>(
      context: context,
      builder: (_) => _PermisosDialog(initial: current),
    );

    if (updated == null) return;

    try {
      await context.read<AppState>().adminSetPermisos(
        userId: userId,
        permissions: updated,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Permisos actualizados')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar permisos: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bannerBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Administración',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
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
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.navy,
        foregroundColor: Colors.white,
        onPressed: _openCreateUser,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Crear usuario'),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : (_error != null)
            ? Center(
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                itemCount: _users.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final u = _users[i];
                  final fullName = (u['fullName'] ?? u['name'] ?? '')
                      .toString();
                  final username = (u['username'] ?? u['user'] ?? '')
                      .toString();
                  final roles = (u['roles'] is List)
                      ? (u['roles'] as List)
                            .map((e) => e.toString())
                            .where((e) => e.trim().isNotEmpty)
                            .toList()
                      : <String>[];
                  final active = (u['isActive'] ?? u['activo'] ?? true) == true;

                  return Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: const Color(0xFFE6EBF2),
                        width: 1.2,
                      ),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    fullName.isEmpty ? '—' : fullName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    username,
                                    style: TextStyle(
                                      color: Colors.black.withOpacity(0.55),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: active
                                    ? const Color(0xFFE7F7EE)
                                    : const Color(0xFFFFE9E9),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                active ? 'Activo' : 'Inactivo',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: active
                                      ? const Color(0xFF177245)
                                      : const Color(0xFFB00020),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (roles.isNotEmpty)
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: roles
                                .map(
                                  (r) => Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF2F5FA),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      r,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _openPermisos(u),
                                icon: const Icon(Icons.lock_outline),
                                label: const Text('Permisos'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppTheme.navy,
                                ),
                                onPressed: () async {
                                  final model = context.read<AppState>();
                                  try {
                                    await model.startImpersonation(
                                      userId: (u['id'] ?? '').toString(),
                                    );
                                    if (!mounted) return;
                                    await Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const UserAppViewScreen(),
                                      ),
                                    );
                                  } catch (e) {
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'No se pudo abrir la app del usuario: $e',
                                        ),
                                      ),
                                    );
                                  }
                                },
                                icon: const Icon(Icons.visibility_outlined),
                                label: const Text('Abrir app'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _UserFormSheet extends StatefulWidget {
  final List<Map<String, dynamic>> roles;
  const _UserFormSheet({required this.roles});

  @override
  State<_UserFormSheet> createState() => _UserFormSheetState();
}

class _UserFormSheetState extends State<_UserFormSheet> {
  final _username = TextEditingController();
  final _fullName = TextEditingController();
  final _password = TextEditingController();

  String _roleCode = 'SUCURSAL';
  bool _active = true;
  List<String> _perms = <String>[];

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.roles.isNotEmpty) {
      final first = widget.roles.firstWhere(
        (r) => (r['code'] ?? '').toString().trim().isNotEmpty,
        orElse: () => widget.roles.first,
      );
      final c = (first['code'] ?? '').toString().trim();
      if (c.isNotEmpty) _roleCode = c;
    }
  }

  @override
  void dispose() {
    _username.dispose();
    _fullName.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _pickPerms() async {
    final updated = await showDialog<List<String>>(
      context: context,
      builder: (_) => _PermisosDialog(initial: _perms),
    );
    if (updated == null) return;
    setState(() => _perms = updated);
  }

  Future<void> _save() async {
    if (_saving) return;
    final u = _username.text.trim();
    final n = _fullName.text.trim();
    final p = _password.text;
    if (u.isEmpty || n.isEmpty || p.trim().length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Completa usuario, nombre y contraseña (mínimo 6 caracteres)',
          ),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await context.read<AppState>().adminCreateUser(
        username: u,
        fullName: n,
        password: p,
        roleCodes: [_roleCode],
        permissions: _perms,
        isActive: _active,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo crear usuario: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final padding = mq.viewInsets.bottom;

    final roleItems = (widget.roles.isNotEmpty)
        ? widget.roles
              .map((r) => (r['code'] ?? '').toString().trim())
              .where((c) => c.isNotEmpty)
              .toSet()
              .toList()
        : <String>['ADMIN', 'SUPERVISOR', 'SUCURSAL', 'BODEGA'];

    return Padding(
      padding: EdgeInsets.only(bottom: padding),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Crear usuario',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _username,
                decoration: const InputDecoration(
                  labelText: 'Usuario',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _fullName,
                decoration: const InputDecoration(
                  labelText: 'Nombre completo',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Contraseña',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _roleCode,
                items: roleItems
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: _saving
                    ? null
                    : (v) => setState(() => _roleCode = (v ?? 'SUCURSAL')),
                decoration: const InputDecoration(
                  labelText: 'Rol',
                  prefixIcon: Icon(Icons.shield_outlined),
                ),
              ),
              const SizedBox(height: 10),
              SwitchListTile.adaptive(
                value: _active,
                onChanged: _saving ? null : (v) => setState(() => _active = v),
                title: const Text('Usuario activo'),
              ),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: _saving ? null : _pickPerms,
                icon: const Icon(Icons.lock_open_outlined),
                label: Text(
                  _perms.isEmpty
                      ? 'Configurar permisos'
                      : 'Permisos (${_perms.length})',
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: AppTheme.navy),
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Crear usuario',
                          style: TextStyle(fontWeight: FontWeight.w900),
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

class _PermisosDialog extends StatefulWidget {
  final List<String> initial;
  const _PermisosDialog({required this.initial});

  @override
  State<_PermisosDialog> createState() => _PermisosDialogState();
}

class _PermisosDialogState extends State<_PermisosDialog> {
  late final Set<String> _selected;

  static const _all = <Map<String, String>>[
    {'code': 'VENTAS_CREAR', 'label': 'Crear ventas'},
    {'code': 'VENTAS_EDITAR', 'label': 'Editar ventas'},
    {'code': 'VENTAS_ELIMINAR', 'label': 'Eliminar ventas'},
    {'code': 'INVENTARIO_CREAR', 'label': 'Crear inventario'},
    {'code': 'INVENTARIO_EDITAR', 'label': 'Editar inventario'},
    {'code': 'INVENTARIO_ELIMINAR', 'label': 'Eliminar inventario'},
    {'code': 'VER_TODO', 'label': 'Ver información de otros usuarios'},
    {'code': 'USUARIOS_ADMIN', 'label': 'Administrar usuarios'},
  ];

  @override
  void initState() {
    super.initState();
    _selected = widget.initial
        .map((e) => e.toString().trim().toUpperCase())
        .where((e) => e.isNotEmpty)
        .toSet();
  }

  @override
  Widget build(BuildContext context) {
    final allCodes = _all.map((e) => e['code']!).toSet();
    final allSelected = _selected.containsAll(allCodes);

    return AlertDialog(
      title: const Text('Permisos'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            SwitchListTile.adaptive(
              value: allSelected,
              title: const Text('Conceder todos'),
              onChanged: (v) {
                setState(() {
                  if (v) {
                    _selected.addAll(allCodes);
                  } else {
                    _selected.clear();
                  }
                });
              },
            ),
            const Divider(height: 1),
            const SizedBox(height: 6),
            ..._all.map((p) {
              final code = p['code']!;
              final label = p['label']!;
              final checked = _selected.contains(code);
              return CheckboxListTile(
                value: checked,
                onChanged: (v) {
                  setState(() {
                    if (v == true) {
                      _selected.add(code);
                    } else {
                      _selected.remove(code);
                    }
                  });
                },
                title: Text(label),
              );
            }),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppTheme.navy),
          onPressed: () =>
              Navigator.of(context).pop(_selected.toList()..sort()),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
