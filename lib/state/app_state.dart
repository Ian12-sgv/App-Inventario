import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/api_client.dart';
import '../api/api_config.dart';
import '../api/auth_api.dart';
import '../api/inventory_api.dart';
import '../api/balance_api.dart';
import '../api/users_api.dart';
import '../api/roles_api.dart';
import '../api/realtime_socket.dart';
import '../models/product.dart';
import '../models/txn.dart';

class PaymentMethod {
  final String code;
  final String name;
  final bool isActive;
  final int sortOrder;

  const PaymentMethod({
    required this.code,
    required this.name,
    required this.isActive,
    required this.sortOrder,
  });

  factory PaymentMethod.fromApi(Map<String, dynamic> m) => PaymentMethod(
    code: (m['code'] ?? m['codigo'] ?? '').toString(),
    name: (m['name'] ?? m['nombre'] ?? '').toString(),
    isActive: (m['isActive'] ?? m['activo'] ?? true) == true,
    sortOrder: (m['sortOrder'] ?? m['orden'] ?? 0) is num
        ? (m['sortOrder'] ?? m['orden'] ?? 0).toInt()
        : 0,
  );
}

class BalanceView {
  final double incomeUsd;
  final double expenseUsd;
  final double balanceUsd;

  final double salesUsd;
  final double cogsUsd;
  final double profitUsd;

  final Map<String, Map<String, double>>
  byPaymentMethod; // methodName -> {ventas, abonos, gastos, balance}

  const BalanceView({
    required this.incomeUsd,
    required this.expenseUsd,
    required this.balanceUsd,
    required this.salesUsd,
    required this.cogsUsd,
    required this.profitUsd,
    required this.byPaymentMethod,
  });

  static double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  factory BalanceView.fromApi(Map<String, dynamic> m) {
    final summary = ((m['summary'] ?? m['resumen']) is Map)
        ? ((m['summary'] ?? m['resumen']) as Map).cast<String, dynamic>()
        : <String, dynamic>{};
    final profit = ((m['profit'] ?? m['ganancias']) is Map)
        ? ((m['profit'] ?? m['ganancias']) as Map).cast<String, dynamic>()
        : <String, dynamic>{};
    final methods = <String, Map<String, double>>{};

    final list = m['paymentMethods'] ?? m['metodosPago'];
    if (list is List) {
      for (final it in list) {
        if (it is! Map) continue;
        final mm = it.cast<String, dynamic>();
        final name = (mm['name'] ?? mm['method'] ?? mm['metodo'] ?? '')
            .toString();
        if (name.isEmpty) continue;
        methods[name] = {
          'ventas': _toDouble(
            mm['salesUsd'] ?? mm['ventasUsd'] ?? mm['ventas'],
          ),
          'abonos': _toDouble(mm['abonosUsd'] ?? mm['abonos']),
          'gastos': _toDouble(
            mm['expensesUsd'] ?? mm['gastosUsd'] ?? mm['gastos'],
          ),
          'balance': _toDouble(
            mm['balanceUsd'] ?? mm['balance'] ?? mm['total'],
          ),
        };
      }
    }

    final income = _toDouble(
      summary['incomeUsd'] ?? summary['ingresosUsd'] ?? m['incomeUsd'],
    );
    final expense = _toDouble(
      summary['expenseUsd'] ?? summary['egresosUsd'] ?? m['expenseUsd'],
    );

    return BalanceView(
      incomeUsd: income,
      expenseUsd: expense,
      balanceUsd: _toDouble(
        summary['balanceUsd'] ?? m['balanceUsd'] ?? (income - expense),
      ),
      salesUsd: _toDouble(
        profit['salesUsd'] ?? profit['ventasUsd'] ?? m['salesUsd'] ?? income,
      ),
      cogsUsd: _toDouble(
        profit['cogsUsd'] ?? profit['costoVendidoUsd'] ?? m['cogsUsd'] ?? 0,
      ),
      profitUsd: _toDouble(
        profit['profitUsd'] ??
            profit['gananciaUsd'] ??
            m['profitUsd'] ??
            (income - 0),
      ),
      byPaymentMethod: methods,
    );
  }
}

class AppState extends ChangeNotifier {
  AppState() {
    _client = ApiClient();
    _authApi = AuthApi(_client);
    _inventoryApi = InventoryApi(_client);
    _balanceApi = BalanceApi(_client);
    _usersApi = UsersApi(_client);
    _rolesApi = RolesApi(_client);
    _client.onUnauthorized = () async {
      if (_isImpersonating) {
        await stopImpersonation();
        setError('La vista de usuario terminó. Volviste a tu sesión.');
        return;
      }
      await logout();
      setError('Tu sesión expiró. Inicia sesión nuevamente.');
    };
  }

  late final ApiClient _client;
  late final AuthApi _authApi;
  late final InventoryApi _inventoryApi;
  late final BalanceApi _balanceApi;
  late final UsersApi _usersApi;
  late final RolesApi _rolesApi;

  final _storage = const FlutterSecureStorage();

  String _apiBaseUrl = ApiConfig.defaultBaseUrl;

  bool _busy = false;
  String? _error;

  String? _token;
  bool _ready = false;

  String? _userId;

  String? _warehouseId;
  String? _warehouseName;
  String? _defaultWarehouseId;

  // Nombre visible del usuario autenticado (para pantallas de detalle).
  String? _userDisplayName;

  // Roles y permisos efectivos del usuario autenticado.
  List<String> _roles = const [];
  List<String> _permissions = const [];

  bool _authMeRefreshing = false;
  RealtimeSocket? _rt;

  bool _isImpersonating = false;
  String? _adminTokenBackup;
  int _adminRootTabBackup = 0;
  String? _adminDisplayNameBackup;
  String? _impersonatedUserName;

  List<Product> _products = [];
  List<String> _categories = [];

  DateTime _selectedDay = DateTime.now();
  List<Txn> _txnsForDay = [];
  BalanceView? _balanceView;

  List<PaymentMethod> _paymentMethods = [];
  List<String> _expenseCategories = [];

  int _rootTabIndex = 0; // 0=Balance, 1=Inventario
  int _balanceTabPreferred = 0; // 0=Ingresos, 1=Egresos
  int _balanceTabSignal = 0;
  int _newExpenseSheetSignal = 0;

  bool get ready => _ready;
  bool get busy => _busy;
  String? get error => _error;

  bool get isLoggedIn => (_token ?? '').isNotEmpty;
  bool get isImpersonating => _isImpersonating;
  String get impersonatedUserName =>
      (_impersonatedUserName ?? _userDisplayName ?? '').trim();
  String get adminDisplayName => (_adminDisplayNameBackup ?? '').trim();

  String? get userId => _userId;

  String get apiBaseUrl => _apiBaseUrl;

  String? resolveApiUrl(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return null;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    final base = _apiBaseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final path = value.startsWith('/') ? value : '/$value';
    return '$base$path';
  }

  String? get warehouseId => _warehouseId;
  String? get warehouseName => _warehouseName;

  String get userDisplayName => (_userDisplayName ?? '').trim().isNotEmpty
      ? _userDisplayName!.trim()
      : '—';

  List<String> get roles => _roles;
  List<String> get permissions => _permissions;

  bool hasRole(String code) =>
      _roles.map((r) => r.toUpperCase()).contains(code.toUpperCase());
  bool hasPerm(String code) =>
      _permissions.map((p) => p.toUpperCase()).contains(code.toUpperCase());

  bool get isAdmin => hasRole('ADMIN') || hasPerm('USUARIOS_ADMIN');

  bool get canCrearVenta => hasPerm('VENTAS_CREAR');
  bool get canEditarVenta => hasPerm('VENTAS_EDITAR');
  bool get canEliminarVenta => hasPerm('VENTAS_ELIMINAR');

  bool get canCrearInventario => hasPerm('INVENTARIO_CREAR');
  bool get canEditarInventario => hasPerm('INVENTARIO_EDITAR');
  bool get canEliminarInventario => hasPerm('INVENTARIO_ELIMINAR');

  List<Product> get products => _products;
  List<String> get categories => _categories;

  DateTime get selectedDay => _selectedDay;
  List<Txn> get txnsForDay => _txnsForDay;

  /// Utilidad para pantallas de detalle (ventas por inventario).
  Future<List<Map<String, dynamic>>> getInventoryDocLines(String docId) {
    return _inventoryApi.getInventoryDocLines(docId: docId);
  }

  BalanceView? get balanceView => _balanceView;

  List<PaymentMethod> get paymentMethods => _paymentMethods;
  List<String> get expenseCategories => _expenseCategories;

  int get rootTabIndex => _rootTabIndex;
  int get balanceTabPreferred => _balanceTabPreferred;
  int get balanceTabSignal => _balanceTabSignal;
  int get newExpenseSheetSignal => _newExpenseSheetSignal;

  double get dayIncome => _txnsForDay
      .where((t) => t.type == 'income')
      .fold(0.0, (a, b) => a + b.amount);
  double get dayExpense => _txnsForDay
      .where((t) => t.type == 'expense')
      .fold(0.0, (a, b) => a + b.amount);
  double get dayBalance => dayIncome - dayExpense;

  void setRootTabIndex(int index) {
    if (_rootTabIndex == index) return;
    _rootTabIndex = index;
    notifyListeners();
  }

  void _openBalanceIngresosAfterVenta() {
    _rootTabIndex = 0;
    _balanceTabPreferred = 0;
    _balanceTabSignal++;
    notifyListeners();
  }

  void _openBalanceEgresosAfterGasto() {
    _rootTabIndex = 0;
    _balanceTabPreferred = 1;
    _balanceTabSignal++;
    notifyListeners();
  }

  void openNewExpenseSheetFromInventory() {
    _rootTabIndex = 0;
    _balanceTabPreferred = 1;
    _balanceTabSignal++;
    _newExpenseSheetSignal++;
    notifyListeners();
  }

  void _applyAuthMe(Map<String, dynamic> me) {
    final id = (me['id'] ?? me['userId'] ?? me['sub'])?.toString();
    if (id != null && id.trim().isNotEmpty) {
      _userId = id.trim();
    }
    final defaultWarehouse =
        (me['defaultWarehouseId'] ?? me['default_warehouse_id'])?.toString();
    _defaultWarehouseId =
        (defaultWarehouse != null && defaultWarehouse.trim().isNotEmpty)
        ? defaultWarehouse.trim()
        : null;

    // Nombre/usuario para mostrar.
    final name =
        (me['name'] ??
                me['fullName'] ??
                me['displayName'] ??
                me['username'] ??
                me['email'])
            ?.toString();
    if (name != null && name.trim().isNotEmpty) {
      _userDisplayName = name.trim();
    }

    // Roles / permisos (vienen desde /auth/me)
    final rr = me['roles'];
    if (rr is List) {
      _roles = rr
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList();
    }
    final pp = me['permissions'] ?? me['permisos'];
    if (pp is List) {
      _permissions = pp
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList();
    }
  }

  String? _normalizeExpenseCategoryLabel(dynamic raw) {
    if (raw == null) return null;
    if (raw is String) {
      final t = raw.trim();
      return t.isEmpty ? null : t;
    }
    if (raw is Map) {
      final m = raw.cast<dynamic, dynamic>();
      final candidates = [
        m['label'],
        m['nombre'],
        m['name'],
        m['texto'],
        m['text'],
        m['descripcion'],
        m['description'],
        m['value'],
      ];
      for (final c in candidates) {
        if (c == null) continue;
        final t = c.toString().trim();
        if (t.isNotEmpty) return t;
      }
    }
    final t = raw.toString().trim();
    return t.isEmpty ? null : t;
  }

  Future<void> init() async {
    if (_ready) return;
    _setBusy(true);
    try {
      // En esta etapa el frontend usa un servidor fijo (sin selector en UI).
      // Limpiamos cualquier valor viejo guardado para evitar que dispositivos
      // queden apuntando a localhost u otras URLs.
      try {
        await _storage.delete(key: 'api_base_url');
      } catch (_) {}
      _apiBaseUrl = ApiConfig.defaultBaseUrl;
      _client.setBaseUrl(_apiBaseUrl);

      final token = await _storage.read(key: 'auth_token');
      if (token != null && token.isNotEmpty) {
        _setToken(token, notify: false);
        try {
          final me = await _authApi.me();
          _applyAuthMe(me);
          _connectRealtime();
        } catch (_) {
          await logout();
        }
      }
      if (isLoggedIn) {
        await _refreshDataBatch(includeReferenceData: true);
      }
      _ready = true;
    } finally {
      _setBusy(false);
    }
  }

  String _normalizeBaseUrl(String raw) {
    var v = raw.trim();
    if (v.isEmpty) return ApiConfig.defaultBaseUrl;

    // Algunos pegados/teclados añaden sufijos tipo "?#" o "#".
    // Todo lo que vaya después de ? o # NO debe formar parte del servidor base.
    if (v.contains('#')) v = v.split('#').first;
    if (v.contains('?')) v = v.split('?').first;
    v = v.trim();

    // Quitar barras finales (http://x:3000///)
    while (v.endsWith('/')) {
      v = v.substring(0, v.length - 1).trim();
    }

    // Permite que el usuario escriba solo la IP (ej: 192.168.1.50)
    if (!v.startsWith('http://') && !v.startsWith('https://')) {
      v = 'http://$v';
    }

    // Si no trae puerto, asumimos 3000
    Uri? uri;
    try {
      uri = Uri.parse(v);
    } catch (_) {
      return ApiConfig.defaultBaseUrl;
    }

    final hasPort = uri.hasPort && uri.port != 0;

    // Construimos un Uri limpio SIN query/fragment/path para evitar que Uri.toString
    // mantenga sufijos vacíos como "?#".
    final normalized = Uri(
      scheme: uri.scheme.isNotEmpty ? uri.scheme : 'http',
      host: uri.host,
      port: hasPort ? uri.port : 3000,
    );
    return normalized.toString();
  }

  Future<void> setApiBaseUrl(String raw) async {
    final url = _normalizeBaseUrl(raw);
    _apiBaseUrl = url;
    _client.setBaseUrl(url);
    await _storage.write(key: 'api_base_url', value: url);

    // Cambiar de servidor puede invalidar el token actual.
    await logout();
    setError('Servidor actualizado. Inicia sesión nuevamente.');
  }

  Future<void> login({
    required String username,
    required String password,
  }) async {
    _setBusy(true);
    try {
      final token = await _authApi.login(
        username: username,
        password: password,
      );
      _setToken(token, notify: false);
      await _storage.write(key: 'auth_token', value: token);
      try {
        final me = await _authApi.me();
        _applyAuthMe(me);
        _connectRealtime();
      } catch (_) {}
      await _refreshDataBatch(includeReferenceData: true);
    } finally {
      _setBusy(false);
    }
  }

  Future<void> startImpersonation({required String userId}) async {
    if ((_token ?? '').isEmpty) {
      throw Exception('No hay sesión activa');
    }

    if (_isImpersonating) {
      await stopImpersonation();
    }

    _setBusy(true);
    try {
      _adminTokenBackup = _token;
      _adminRootTabBackup = _rootTabIndex;
      _adminDisplayNameBackup = _userDisplayName;

      _disconnectRealtime();

      final tempToken = await _authApi.impersonate(userId: userId);
      _token = tempToken;
      _client.setToken(tempToken);

      final me = await _authApi.me();
      _applyAuthMe(me);
      _isImpersonating = true;
      _impersonatedUserName = _userDisplayName;
      _rootTabIndex = 0;

      _connectRealtime();
      await _refreshDataBatch(includeReferenceData: true);
    } catch (e) {
      final restore = _adminTokenBackup;
      _token = restore;
      _client.setToken(restore);
      _isImpersonating = false;
      _impersonatedUserName = null;
      if ((restore ?? '').isNotEmpty) {
        try {
          final me = await _authApi.me();
          _applyAuthMe(me);
          _connectRealtime();
        } catch (_) {}
      }
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> stopImpersonation() async {
    if (!_isImpersonating) return;

    final restoreToken = _adminTokenBackup;
    final restoreRootTab = _adminRootTabBackup;

    _setBusy(true);
    try {
      _disconnectRealtime();
      _token = restoreToken;
      _client.setToken(restoreToken);
      _isImpersonating = false;
      _impersonatedUserName = null;
      _rootTabIndex = restoreRootTab;

      if ((restoreToken ?? '').isNotEmpty) {
        final me = await _authApi.me();
        _applyAuthMe(me);
        _connectRealtime();
        await _refreshDataBatch(includeReferenceData: true);
      }
    } finally {
      _setBusy(false);
    }
  }

  Future<void> logout() async {
    _disconnectRealtime();
    _isImpersonating = false;
    _adminTokenBackup = null;
    _adminRootTabBackup = 0;
    _adminDisplayNameBackup = null;
    _impersonatedUserName = null;
    _setToken(null, notify: false);
    await _storage.delete(key: 'auth_token');
    _warehouseId = null;
    _warehouseName = null;
    _defaultWarehouseId = null;
    _userId = null;
    _userDisplayName = null;
    _roles = const [];
    _permissions = const [];
    _products = [];
    _categories = [];
    _txnsForDay = [];
    _balanceView = null;
    _rootTabIndex = 0;
    _balanceTabPreferred = 0;
    notifyListeners();
  }

  /// Refresca roles/permisos desde /auth/me para que cambios realizados por el
  /// administrador se reflejen sin tener que cerrar sesión.
  Future<void> refreshAuthMe({bool notify = true}) async {
    if (!isLoggedIn) return;
    if (_authMeRefreshing) return;
    _authMeRefreshing = true;
    try {
      final me = await _authApi.me();
      final prevRoles = List<String>.from(_roles);
      final prevPerms = List<String>.from(_permissions);
      final prevName = _userDisplayName;
      final prevDefaultWh = _defaultWarehouseId;
      final prevUserId = _userId;

      _applyAuthMe(me);

      final changed =
          !listEquals(prevRoles, _roles) ||
          !listEquals(prevPerms, _permissions) ||
          prevName != _userDisplayName ||
          prevDefaultWh != _defaultWarehouseId ||
          prevUserId != _userId;

      if (notify && changed) {
        notifyListeners();
      }
    } catch (_) {
      // Silencioso: si falla, se intentará en el siguiente ciclo.
    } finally {
      _authMeRefreshing = false;
    }
  }

  void _connectRealtime() {
    _disconnectRealtime();
    if (!isLoggedIn) return;
    final t = _token;
    if (t == null || t.isEmpty) return;

    _rt = RealtimeSocket(
      baseUrl: _apiBaseUrl,
      token: t,
      onAuthMe: (me) {
        final prevRoles = List<String>.from(_roles);
        final prevPerms = List<String>.from(_permissions);
        final prevName = _userDisplayName;
        final prevDefaultWh = _defaultWarehouseId;
        final prevUserId = _userId;

        _applyAuthMe(me);

        final changed =
            !listEquals(prevRoles, _roles) ||
            !listEquals(prevPerms, _permissions) ||
            prevName != _userDisplayName ||
            prevDefaultWh != _defaultWarehouseId ||
            prevUserId != _userId;

        if (changed) {
          notifyListeners();
        }
      },
      onDeactivated: () async {
        await logout();
        setError('Tu usuario fue desactivado.');
      },
    );

    _rt!.connect();
  }

  void _disconnectRealtime() {
    try {
      _rt?.disconnect();
    } catch (_) {}
    _rt = null;
  }

  // -------------------------
  // ADMIN - Usuarios
  // -------------------------

  Future<List<Map<String, dynamic>>> adminListUsers() async {
    return _usersApi.listUsers();
  }

  Future<List<Map<String, dynamic>>> adminListRoles() async {
    return _rolesApi.listRoles();
  }

  Future<Map<String, dynamic>> adminCreateUser({
    required String username,
    required String fullName,
    required String password,
    List<String> roleCodes = const [],
    List<String> permissions = const [],
    bool isActive = true,
  }) async {
    return _usersApi.createUser({
      'username': username.trim(),
      'fullName': fullName.trim(),
      'password': password,
      'roleCodes': roleCodes,
      'permissions': permissions,
      'isActive': isActive,
    });
  }

  Future<Map<String, dynamic>> adminSetPermisos({
    required String userId,
    required List<String> permissions,
  }) async {
    final res = await _usersApi.setPermisos(
      userId: userId,
      permissions: permissions,
    );
    // Si el admin se cambió permisos a sí mismo, refrescamos de inmediato.
    if ((_userId ?? '') == userId) {
      await refreshAuthMe(notify: true);
    }
    return res;
  }

  Future<void> adminSetRoles({
    required String userId,
    required List<String> roleCodes,
  }) async {
    await _usersApi.setRoles(userId: userId, roleCodes: roleCodes);
  }

  Future<List<Txn>> adminTransaccionesPorDia({
    required String userId,
    required DateTime day,
  }) async {
    final fromDt = DateTime(day.year, day.month, day.day);
    final toDt = fromDt.add(const Duration(days: 1));
    final from = fromDt.toUtc().toIso8601String();
    final to = toDt.toUtc().toIso8601String();

    final raw = await _balanceApi.listTransacciones(
      from: from,
      to: to,
      userId: userId,
    );
    final parsed = raw.map((m) => Txn.fromApi(m)).toList();

    // Filtra por día local (por seguridad ante husos horarios)
    return parsed
        .where(
          (t) =>
              t.when.year == day.year &&
              t.when.month == day.month &&
              t.when.day == day.day,
        )
        .toList()
      ..sort((a, b) => b.when.compareTo(a.when));
  }

  Future<List<Map<String, dynamic>>> adminDocsInventario({
    required String userId,
  }) async {
    final wid = (_warehouseId ?? '').trim();
    return _inventoryApi.listInventoryDocs(
      status: 'POSTED',
      warehouseId: wid.isEmpty ? null : wid,
      createdByUserId: userId,
    );
  }

  Future<void> _refreshDataBatch({
    bool includeReferenceData = false,
    bool includeInventory = true,
    bool includeBalance = true,
  }) async {
    if (!isLoggedIn) return;
    final tasks = <Future<void>>[];
    if (includeReferenceData) {
      tasks.add(_loadReferenceData(notify: false));
    }
    if (includeInventory) {
      tasks.add(refreshInventory(showBusy: false, notify: false));
    }
    if (includeBalance) {
      tasks.add(refreshBalance(showBusy: false, notify: false));
    }
    if (tasks.isEmpty) return;
    await Future.wait(tasks);
  }

  Future<void> _refreshDataBatchWithBusy({
    bool includeInventory = true,
    bool includeBalance = true,
  }) async {
    if (!isLoggedIn) return;
    _setBusy(true);
    try {
      await _refreshDataBatch(
        includeInventory: includeInventory,
        includeBalance: includeBalance,
      );
    } finally {
      _setBusy(false);
    }
  }

  Future<void> _loadReferenceData({bool notify = true}) async {
    if (!isLoggedIn) return;
    try {
      final methods = await _balanceApi.listPaymentMethods();
      _paymentMethods =
          methods
              .map(PaymentMethod.fromApi)
              .where((m) => m.code.isNotEmpty)
              .toList()
            ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    } catch (_) {
      _paymentMethods = const [];
    }

    try {
      final cats = await _balanceApi.listExpenseCategories();
      final seen = <String>{};
      final normalized = <String>[];
      for (final raw in cats) {
        final label = _normalizeExpenseCategoryLabel(raw);
        if (label == null) continue;
        final key = label.trim().toLowerCase();
        if (seen.add(key)) normalized.add(label.trim());
      }
      _expenseCategories = normalized;
    } catch (_) {
      _expenseCategories = const [];
    }

    if (notify) {
      notifyListeners();
    }
  }

  bool _isProductActiveForList(Map<String, dynamic> p) {
    final rawStatus = p['status'];
    if (rawStatus != null) {
      final s = rawStatus.toString().trim().toUpperCase();
      if (s == 'INACTIVE' || s == 'FALSE' || s == '0') return false;
      if (s == 'ACTIVE' || s == 'TRUE' || s == '1') return true;
    }
    final isActive = p['isActive'];
    if (isActive is bool) return isActive;
    if (isActive != null) {
      final v = isActive.toString().trim().toLowerCase();
      if (v == 'false' || v == '0') return false;
      if (v == 'true' || v == '1') return true;
    }
    return true;
  }

  Future<void> _adjustProductStockToTarget({
    required String productId,
    required double currentQty,
    required double targetQty,
  }) async {
    final wid = (_warehouseId ?? '').trim();
    if (wid.isEmpty) return;

    final delta = targetQty - currentQty;
    if (delta.abs() < 0.000001) return;

    final isPositive = delta > 0;
    final qty = delta.abs();

    final draft = await _inventoryApi.createInventoryDoc({
      'docType': 'ADJUSTMENT',
      if (isPositive) 'toWarehouseId': wid,
      if (!isPositive) 'fromWarehouseId': wid,
      'notes': isPositive
          ? 'Ajuste de inventario (+) desde edición de producto en app móvil'
          : 'Ajuste de inventario (-) desde edición de producto en app móvil',
    });

    final docId = (draft['id'] ?? '').toString();
    if (docId.isEmpty) return;

    await _inventoryApi.replaceInventoryDocLines(
      docId: docId,
      lines: [
        {'productId': productId, 'qty': qty},
      ],
    );
    await _inventoryApi.postInventoryDoc(docId: docId);
  }

  String _expenseInventoryToken(String expenseId) {
    final cleanId = expenseId.trim();
    return cleanId.isEmpty ? '' : '[EXPENSE:$cleanId]';
  }

  String? _extractCreatedExpenseId(Map<String, dynamic> created) {
    final raw =
        created['id'] ??
        created['expenseId'] ??
        (created['expense'] is Map ? created['expense']['id'] : null);
    final id = raw?.toString().trim();
    return (id == null || id.isEmpty) ? null : id;
  }

  DateTime _localDateTime(dynamic raw) {
    if (raw is DateTime) {
      return raw.isUtc ? raw.toLocal() : raw;
    }
    final parsed = raw == null ? null : DateTime.tryParse(raw.toString());
    if (parsed == null) return DateTime.now();
    return parsed.isUtc ? parsed.toLocal() : parsed;
  }

  bool _isInventoryExpenseCategory(dynamic raw) {
    final value = (raw ?? '')
        .toString()
        .trim()
        .toUpperCase()
        .replaceAll('Á', 'A')
        .replaceAll('É', 'E')
        .replaceAll('Í', 'I')
        .replaceAll('Ó', 'O')
        .replaceAll('Ú', 'U')
        .replaceAll('Ñ', 'N')
        .replaceAll(RegExp(r'[^A-Z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return value == 'COMPRA_PRODUCTOS_E_INSUMOS' ||
        value == 'COMPRA_DE_PRODUCTOS_E_INSUMOS';
  }

  double _expenseItemQty(Map<String, dynamic> row) {
    final raw = row['qty'] ?? row['quantity'] ?? row['cantidad'];
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw?.toString() ?? '') ?? 0;
  }

  double _expenseItemUnitCost(Map<String, dynamic> row) {
    final raw =
        row['unitCostUsd'] ??
        row['unitCost'] ??
        row['costUsd'] ??
        row['cost'] ??
        row['unitPriceUsd'] ??
        row['unitPrice'];
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw?.toString() ?? '') ?? 0;
  }

  List<Map<String, dynamic>> _normalizeExpenseInventoryItems(
    Iterable<Map<String, dynamic>> rows,
  ) {
    final byId = <String, Map<String, dynamic>>{};
    for (final row in rows) {
      final productId =
          (row['productId'] ?? row['product_id'] ?? row['id'] ?? '')
              .toString()
              .trim();
      final qty = _expenseItemQty(row);
      if (productId.isEmpty || qty <= 0) continue;
      final unitCost = _expenseItemUnitCost(row);
      final existing = byId.putIfAbsent(productId, () {
        return <String, dynamic>{
          'productId': productId,
          'qty': 0.0,
          'unitCost': 0.0,
          'unitCostUsd': 0.0,
        };
      });
      existing['qty'] = (existing['qty'] as double) + qty;
      if (unitCost > 0) {
        existing['unitCost'] = unitCost;
        existing['unitCostUsd'] = unitCost;
      }
    }
    return byId.values
        .where((row) => (row['qty'] as double) > 0)
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Future<void> _postExpenseInventoryAdjustment({
    required List<Map<String, dynamic>> lines,
    required bool incoming,
    required String notes,
  }) async {
    final wid = (_warehouseId ?? '').trim();
    if (wid.isEmpty) {
      throw StateError(
        'No hay bodega seleccionada. Actualiza inventario o inicia sesión nuevamente.',
      );
    }
    if (lines.isEmpty) return;

    final draft = await _inventoryApi.createInventoryDoc({
      'docType': 'ADJUSTMENT',
      if (incoming) 'toWarehouseId': wid,
      if (!incoming) 'fromWarehouseId': wid,
      'notes': notes,
    });

    final docId = (draft['id'] ?? '').toString().trim();
    if (docId.isEmpty) {
      throw StateError('No se pudo crear el documento de inventario.');
    }

    await _inventoryApi.replaceInventoryDocLines(docId: docId, lines: lines);
    await _inventoryApi.postInventoryDoc(docId: docId);
  }

  Future<void> _registerExpenseInventoryPurchase({
    required List<Map<String, dynamic>> items,
    String? description,
    String? expenseId,
  }) async {
    final lines = _normalizeExpenseInventoryItems(items);
    if (lines.isEmpty) return;

    final cleanDescription = (description ?? '').trim();
    final token = _expenseInventoryToken(expenseId ?? '');
    final notesBase = token.isEmpty
        ? 'Compra registrada desde gasto en app móvil'
        : 'Compra registrada desde gasto $token';
    final notes = cleanDescription.isEmpty
        ? notesBase
        : '$notesBase: $cleanDescription';

    await _postExpenseInventoryAdjustment(
      lines: lines,
      incoming: true,
      notes: notes,
    );
  }

  Future<void> _syncEditedExpenseInventoryPurchase({
    required String previousExpenseId,
    required String expenseId,
    required List<Map<String, dynamic>> previousItems,
    required List<Map<String, dynamic>> nextItems,
    String? description,
  }) async {
    final before = _normalizeExpenseInventoryItems(previousItems);
    final after = _normalizeExpenseInventoryItems(nextItems);
    if (before.isEmpty && after.isEmpty) return;

    final oldId = previousExpenseId.trim();
    final newId = expenseId.trim();
    final cleanDescription = (description ?? '').trim();

    if (oldId.isNotEmpty && newId.isNotEmpty && oldId != newId) {
      final oldToken = _expenseInventoryToken(oldId);
      if (before.isNotEmpty) {
        final notes = cleanDescription.isEmpty
            ? 'Ajuste por edición de gasto $oldToken (salida)'
            : 'Ajuste por edición de gasto $oldToken (salida): $cleanDescription';
        await _postExpenseInventoryAdjustment(
          lines: before,
          incoming: false,
          notes: notes,
        );
      }
      if (after.isNotEmpty) {
        await _registerExpenseInventoryPurchase(
          items: after,
          description: cleanDescription,
          expenseId: newId,
        );
      }
      return;
    }

    final beforeById = <String, Map<String, dynamic>>{
      for (final row in before) row['productId'].toString(): row,
    };
    final afterById = <String, Map<String, dynamic>>{
      for (final row in after) row['productId'].toString(): row,
    };
    final productIds = {...beforeById.keys, ...afterById.keys};
    final additions = <Map<String, dynamic>>[];
    final removals = <Map<String, dynamic>>[];

    for (final productId in productIds) {
      final beforeRow = beforeById[productId];
      final afterRow = afterById[productId];
      final beforeQty = beforeRow == null ? 0.0 : _expenseItemQty(beforeRow);
      final afterQty = afterRow == null ? 0.0 : _expenseItemQty(afterRow);
      final delta = afterQty - beforeQty;
      if (delta.abs() < 0.000001) continue;
      if (delta > 0) {
        final unitCost = afterRow == null
            ? 0.0
            : _expenseItemUnitCost(afterRow);
        additions.add({
          'productId': productId,
          'qty': delta,
          if (unitCost > 0) 'unitCost': unitCost,
          if (unitCost > 0) 'unitCostUsd': unitCost,
        });
      } else {
        final unitCost = beforeRow == null
            ? 0.0
            : _expenseItemUnitCost(beforeRow);
        removals.add({
          'productId': productId,
          'qty': delta.abs(),
          if (unitCost > 0) 'unitCost': unitCost,
          if (unitCost > 0) 'unitCostUsd': unitCost,
        });
      }
    }

    final token = _expenseInventoryToken(expenseId);
    if (removals.isNotEmpty) {
      final notes = cleanDescription.isEmpty
          ? 'Ajuste por edición de gasto $token (salida)'
          : 'Ajuste por edición de gasto $token (salida): $cleanDescription';
      await _postExpenseInventoryAdjustment(
        lines: removals,
        incoming: false,
        notes: notes,
      );
    }
    if (additions.isNotEmpty) {
      final notes = cleanDescription.isEmpty
          ? 'Compra registrada desde edición de gasto $token'
          : 'Compra registrada desde edición de gasto $token: $cleanDescription';
      await _postExpenseInventoryAdjustment(
        lines: additions,
        incoming: true,
        notes: notes,
      );
    }
  }

  Future<List<Map<String, dynamic>>> _inventoryDocsForExpense({
    required String expenseId,
    dynamic occurredAt,
  }) async {
    final cleanId = expenseId.trim();
    if (cleanId.isEmpty) return const [];

    final dt = _localDateTime(occurredAt);
    final from = DateTime(
      dt.year,
      dt.month,
      dt.day,
    ).subtract(const Duration(days: 1));
    final to = DateTime(
      dt.year,
      dt.month,
      dt.day,
      23,
      59,
      59,
      999,
    ).add(const Duration(days: 1));

    final docs = await _inventoryApi.listInventoryDocs(
      status: 'POSTED',
      docType: 'ADJUSTMENT',
      warehouseId: (_warehouseId ?? '').trim().isEmpty ? null : _warehouseId,
      from: from.toUtc().toIso8601String(),
      to: to.toUtc().toIso8601String(),
    );
    final token = _expenseInventoryToken(cleanId);
    final matches = docs.where((doc) {
      final notes = (doc['notes'] ?? '').toString();
      return notes.contains(token);
    }).toList();
    matches.sort((a, b) {
      final aWhen = _localDateTime(a['createdAt'] ?? a['created_at']);
      final bWhen = _localDateTime(b['createdAt'] ?? b['created_at']);
      return aWhen.compareTo(bWhen);
    });
    return matches;
  }

  Product? _productForExpenseLine(String productId) {
    final cleanId = productId.trim();
    if (cleanId.isEmpty) return null;
    return _products.cast<Product?>().firstWhere(
      (item) => item?.id == cleanId,
      orElse: () => null,
    );
  }

  Map<String, dynamic> _mergeExpenseLineProduct({
    required String productId,
    required Map<String, dynamic> product,
  }) {
    final match = _productForExpenseLine(productId);
    if (match == null) return product;

    final merged = <String, dynamic>{...product};
    merged['id'] = (merged['id'] ?? '').toString().trim().isEmpty
        ? match.id
        : merged['id'];
    merged['description'] =
        (merged['description'] ?? merged['name'] ?? merged['nombre'] ?? '')
            .toString()
            .trim()
            .isEmpty
        ? match.name
        : (merged['description'] ?? merged['name'] ?? merged['nombre']);
    merged['reference'] =
        (merged['reference'] ?? merged['referencia'] ?? '')
            .toString()
            .trim()
            .isEmpty
        ? match.reference
        : (merged['reference'] ?? merged['referencia']);
    merged['barcode'] = (merged['barcode'] ?? '').toString().trim().isEmpty
        ? match.barcode
        : merged['barcode'];
    merged['line'] =
        (merged['line'] ?? merged['linea'] ?? '').toString().trim().isEmpty
        ? match.line
        : (merged['line'] ?? merged['linea']);
    merged['subLine'] =
        (merged['subLine'] ??
                merged['sub_line'] ??
                merged['sublinea'] ??
                merged['sub_linea'] ??
                '')
            .toString()
            .trim()
            .isEmpty
        ? match.subLine
        : (merged['subLine'] ??
              merged['sub_line'] ??
              merged['sublinea'] ??
              merged['sub_linea']);
    merged['category'] =
        (merged['category'] ?? merged['categoria'] ?? '')
            .toString()
            .trim()
            .isEmpty
        ? match.category
        : (merged['category'] ?? merged['categoria']);
    merged['subCategory'] =
        (merged['subCategory'] ??
                merged['sub_category'] ??
                merged['subcategoria'] ??
                merged['sub_categoria'] ??
                '')
            .toString()
            .trim()
            .isEmpty
        ? match.subCategory
        : (merged['subCategory'] ??
              merged['sub_category'] ??
              merged['subcategoria'] ??
              merged['sub_categoria']);
    final hasImage =
        (merged['imageUrl'] ?? merged['image_url'] ?? merged['image'] ?? '')
            .toString()
            .trim()
            .isNotEmpty;
    if (!hasImage && (match.imageUrl ?? '').trim().isNotEmpty) {
      merged['imageUrl'] = match.imageUrl;
    }
    return merged;
  }

  Map<String, dynamic> enrichInventoryLine(Map<String, dynamic> row) {
    final product = (row['product'] is Map)
        ? (row['product'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final productId =
        (row['productId'] ?? row['product_id'] ?? product['id'] ?? '')
            .toString()
            .trim();
    if (productId.isEmpty) return row;

    final mergedProduct = _mergeExpenseLineProduct(
      productId: productId,
      product: product,
    );
    final enriched = <String, dynamic>{...row};
    if (mergedProduct.isNotEmpty) {
      enriched['product'] = mergedProduct;
    }
    return enriched;
  }

  Future<List<Map<String, dynamic>>> getEnrichedInventoryDocLines(
    String docId,
  ) async {
    final lines = await getInventoryDocLines(docId);
    return lines.map(enrichInventoryLine).toList();
  }

  Map<String, dynamic> _enrichExpenseLine(Map<String, dynamic> row) {
    final enriched = enrichInventoryLine(row);
    final mergedProduct = (enriched['product'] is Map)
        ? (enriched['product'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};

    final hasImage =
        (enriched['imageUrl'] ??
                enriched['image_url'] ??
                enriched['image'] ??
                '')
            .toString()
            .trim()
            .isNotEmpty;
    if (!hasImage) {
      final mergedImage =
          (mergedProduct['imageUrl'] ??
                  mergedProduct['image_url'] ??
                  mergedProduct['image'] ??
                  '')
              .toString()
              .trim();
      if (mergedImage.isNotEmpty) {
        enriched['imageUrl'] = mergedImage;
      }
    }
    return enriched;
  }

  Future<List<Map<String, dynamic>>> getExpensePurchaseLines({
    required Map<String, dynamic> expense,
    required String expenseId,
  }) async {
    Map<String, dynamic>? fallbackDirectLine() {
      final product = (expense['product'] is Map)
          ? (expense['product'] as Map).cast<String, dynamic>()
          : const <String, dynamic>{};
      final productId =
          (expense['productId'] ?? expense['product_id'] ?? product['id'] ?? '')
              .toString()
              .trim();
      if (productId.isEmpty) return null;

      final productMatch = _productForExpenseLine(productId);
      final qty = 1.0;
      final rawUnitCost =
          expense['unitCostUsd'] ??
          expense['unitCost'] ??
          expense['costUsd'] ??
          expense['cost'] ??
          expense['amountUsd'] ??
          expense['totalUsd'];
      var unitCost = rawUnitCost is num
          ? rawUnitCost.toDouble()
          : double.tryParse(rawUnitCost?.toString() ?? '') ?? 0.0;
      if (unitCost <= 0 && productMatch != null) {
        unitCost = productMatch.costUsd;
      }
      return <String, dynamic>{
        'productId': productId,
        'qty': qty,
        'unitCost': unitCost,
        'unitCostUsd': unitCost,
        'lineTotalUsd': unitCost > 0 ? qty * unitCost : 0.0,
        'product': <String, dynamic>{
          'id': productId,
          'description':
              product['description'] ??
              product['name'] ??
              productMatch?.name ??
              expense['description'] ??
              expense['concept'] ??
              'Producto',
          'reference': product['reference'] ?? productMatch?.reference,
          'barcode': product['barcode'] ?? productMatch?.barcode,
          'line': product['line'] ?? product['linea'] ?? productMatch?.line,
          'subLine':
              product['subLine'] ??
              product['sub_line'] ??
              product['sublinea'] ??
              productMatch?.subLine,
          'category':
              product['category'] ??
              product['categoria'] ??
              productMatch?.category,
          'subCategory':
              product['subCategory'] ??
              product['sub_category'] ??
              product['subcategoria'] ??
              productMatch?.subCategory,
          'imageUrl':
              product['imageUrl'] ??
              product['image_url'] ??
              expense['imageUrl'] ??
              expense['image_url'] ??
              productMatch?.imageUrl,
        },
      };
    }

    final directDocId =
        (expense['inventoryDocId'] ?? expense['inventory_doc_id'])
            ?.toString()
            .trim();
    if ((directDocId ?? '').isNotEmpty) {
      final lines = await getInventoryDocLines(directDocId!);
      return lines.map(_enrichExpenseLine).toList();
    }

    final category = expense['categoryLabel'] ?? expense['category'];
    if (!_isInventoryExpenseCategory(category)) {
      final fallback = fallbackDirectLine();
      return fallback == null ? const [] : [fallback];
    }

    final docs = await _inventoryDocsForExpense(
      expenseId: expenseId,
      occurredAt: expense['occurredAt'] ?? expense['occurred_at'],
    );
    if (docs.isEmpty) {
      final fallback = fallbackDirectLine();
      return fallback == null ? const [] : [fallback];
    }

    final aggregated = <String, Map<String, dynamic>>{};
    for (final doc in docs) {
      final docId = (doc['id'] ?? '').toString().trim();
      if (docId.isEmpty) continue;
      final lines = await getInventoryDocLines(docId);
      final movesOut =
          (doc['fromWarehouseId'] ?? doc['from_warehouse_id'] ?? '')
              .toString()
              .trim()
              .isNotEmpty;
      final sign = movesOut ? -1.0 : 1.0;
      final docAt = _localDateTime(
        doc['createdAt'] ?? doc['created_at'],
      ).millisecondsSinceEpoch;

      for (final row in lines) {
        final productId =
            (row['productId'] ??
                    row['product_id'] ??
                    (row['product'] is Map ? row['product']['id'] : null) ??
                    '')
                .toString()
                .trim();
        final qty = _expenseItemQty(row);
        if (productId.isEmpty || qty <= 0) continue;

        final entry = aggregated.putIfAbsent(productId, () {
          return <String, dynamic>{
            'productId': productId,
            'qty': 0.0,
            'unitCost': 0.0,
            'unitCostUsd': 0.0,
            '_updatedAt': 0,
          };
        });
        entry['qty'] = (entry['qty'] as double) + (qty * sign);

        if (row['product'] is Map) {
          entry['product'] = _mergeExpenseLineProduct(
            productId: productId,
            product: (row['product'] as Map).cast<String, dynamic>(),
          );
        } else if (entry['product'] == null) {
          final product = _productForExpenseLine(productId);
          if (product != null) {
            entry['product'] = <String, dynamic>{
              'id': product.id,
              'description': product.name,
              'reference': product.reference,
              'barcode': product.barcode,
              'imageUrl': product.imageUrl,
            };
          }
        }

        final unitCost = _expenseItemUnitCost(row);
        if (sign > 0 && unitCost > 0 && docAt >= (entry['_updatedAt'] as int)) {
          entry['unitCost'] = unitCost;
          entry['unitCostUsd'] = unitCost;
          entry['_updatedAt'] = docAt;
        }
      }
    }

    final rows = aggregated.values
        .where((row) => (row['qty'] as double) > 0.000001)
        .map((row) {
          final qty = row['qty'] as double;
          var unitCost = (row['unitCostUsd'] as double?) ?? 0.0;
          if (unitCost <= 0) {
            final productId = row['productId'].toString();
            final product = _productForExpenseLine(productId);
            if (product != null) {
              unitCost = product.costUsd;
            }
          }
          return _enrichExpenseLine(<String, dynamic>{
            'productId': row['productId'],
            'qty': qty,
            'unitCost': unitCost,
            'unitCostUsd': unitCost,
            'lineTotalUsd': unitCost > 0 ? qty * unitCost : 0.0,
            if (row['product'] is Map)
              'product': (row['product'] as Map).cast<String, dynamic>(),
          });
        })
        .toList();

    rows.sort((a, b) {
      final aProduct = (a['product'] is Map)
          ? (a['product'] as Map).cast<String, dynamic>()
          : const <String, dynamic>{};
      final bProduct = (b['product'] is Map)
          ? (b['product'] as Map).cast<String, dynamic>()
          : const <String, dynamic>{};
      final aName = (aProduct['description'] ?? aProduct['reference'] ?? '')
          .toString()
          .toLowerCase();
      final bName = (bProduct['description'] ?? bProduct['reference'] ?? '')
          .toString()
          .toLowerCase();
      return aName.compareTo(bName);
    });
    if (rows.isNotEmpty) return rows;
    final fallback = fallbackDirectLine();
    return fallback == null ? const [] : [fallback];
  }

  Future<void> refreshInventory({
    bool showBusy = true,
    bool notify = true,
  }) async {
    if (!isLoggedIn) return;
    if (showBusy) {
      _setBusy(true);
    }
    try {
      final warehouses = await _inventoryApi.listWarehouses();
      final active = warehouses
          .where((w) => (w['isActive'] ?? true) == true)
          .toList();
      Map<String, dynamic>? picked;
      final wantedId = (_defaultWarehouseId ?? '').trim();
      if (wantedId.isNotEmpty) {
        for (final w in [...active, ...warehouses]) {
          if ((w['id'] ?? '').toString().trim() == wantedId) {
            picked = w;
            break;
          }
        }
      }
      picked ??= active.firstWhere(
        (w) => (w['code'] ?? '').toString().toUpperCase() == 'WH-CENTRAL',
        orElse: () => <String, dynamic>{},
      );
      if ((picked['id'] ?? '').toString().isEmpty) {
        picked = active.isNotEmpty
            ? active.first
            : (warehouses.isNotEmpty ? warehouses.first : null);
      }
      _warehouseId = picked == null ? null : picked['id']?.toString();
      _warehouseName = picked == null ? null : (picked['name']?.toString());

      final productsApi = await _inventoryApi.listProducts();
      final stockRows = (_warehouseId == null)
          ? <Map<String, dynamic>>[]
          : await _inventoryApi.getStock(warehouseId: _warehouseId!);

      final stockByProduct = <String, double>{};
      for (final row in stockRows) {
        final pid =
            (row['productId'] ??
                    (row['product'] is Map ? row['product']['id'] : null))
                ?.toString();
        if (pid == null || pid.isEmpty) continue;
        final qty =
            row['qty'] ??
            row['quantity'] ??
            row['stock'] ??
            row['qtyOnHand'] ??
            row['qty_on_hand'] ??
            row['available'] ??
            0;
        final q = (qty is num)
            ? qty.toDouble()
            : double.tryParse(qty.toString()) ?? 0;
        stockByProduct[pid] = q;
      }

      _products = productsApi
          .where(_isProductActiveForList)
          .map(
            (p) => Product.fromApi(
              p,
              stock: stockByProduct[(p['id'] ?? '').toString()] ?? 0,
            ),
          )
          .toList();

      final cats =
          _products
              .map((p) => p.category.trim())
              .where((c) => c.isNotEmpty)
              .toSet()
              .toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      _categories = cats;

      if (notify) {
        notifyListeners();
      }
    } finally {
      if (showBusy) {
        _setBusy(false);
      }
    }
  }

  Future<void> setSelectedDay(DateTime d) async {
    final todayNow = DateTime.now();
    final today = DateTime(todayNow.year, todayNow.month, todayNow.day);
    final wanted = DateTime(d.year, d.month, d.day);
    _selectedDay = wanted.isAfter(today) ? today : wanted;
    await refreshBalance();
  }

  Future<void> refreshBalance({
    bool showBusy = true,
    bool notify = true,
  }) async {
    if (!isLoggedIn) return;
    if (showBusy) {
      _setBusy(true);
    }
    try {
      final startLocal = DateTime(
        _selectedDay.year,
        _selectedDay.month,
        _selectedDay.day,
        0,
        0,
        0,
        0,
        0,
      );
      final endLocal = DateTime(
        _selectedDay.year,
        _selectedDay.month,
        _selectedDay.day,
        23,
        59,
        59,
        999,
      );
      final from = startLocal.toUtc().toIso8601String();
      final to = endLocal.toUtc().toIso8601String();

      final txns = await _balanceApi.listTransacciones(from: from, to: to);
      // Protección extra: si por zona horaria o backend regresan items fuera del día,
      // filtramos por fecha local seleccionada para mostrar SOLO lo correspondiente.
      final parsed = txns.map(Txn.fromApi).toList();
      final y = _selectedDay.year;
      final m = _selectedDay.month;
      final d = _selectedDay.day;
      _txnsForDay =
          parsed
              .where(
                (t) => t.when.year == y && t.when.month == m && t.when.day == d,
              )
              .toList()
            ..sort((a, b) => b.when.compareTo(a.when));

      final view = await _balanceApi.ver(from: from, to: to);
      _balanceView = BalanceView.fromApi(view);

      if (notify) {
        notifyListeners();
      }
    } finally {
      if (showBusy) {
        _setBusy(false);
      }
    }
  }

  Future<void> crearVentaLibre({
    required double totalUsd,
    double? discountPercent,
    double? discountUsd,
    required String note,
    required String receiptNote,
    DateTime? occurredAt,
    List<Map<String, dynamic>>? payments,
  }) async {
    final payload = <String, dynamic>{
      'saleType': 'LIBRE',
      'totalUsd': totalUsd,
      'description': note,
      'receiptNote': receiptNote,
    };
    if (discountPercent != null) payload['discountPercent'] = discountPercent;
    if (discountUsd != null) payload['discountUsd'] = discountUsd;
    if (occurredAt != null) {
      payload['occurredAt'] = occurredAt.toUtc().toIso8601String();
    }
    if (payments != null && payments.isNotEmpty) payload['payments'] = payments;
    await _balanceApi.crearVenta(payload);
    final targetDay = occurredAt ?? DateTime.now();
    _selectedDay = DateTime(targetDay.year, targetDay.month, targetDay.day);
    await _refreshDataBatchWithBusy();
    _openBalanceIngresosAfterVenta();
  }

  Future<void> crearVentaInventario({
    required List<Map<String, dynamic>> items,
    double? discountPercent,
    double? discountUsd,
    required String note,
    required String receiptNote,
    DateTime? occurredAt,
    List<Map<String, dynamic>>? payments,
  }) async {
    final wid = (_warehouseId ?? '').trim();
    if (wid.isEmpty) {
      throw StateError(
        'No hay bodega seleccionada. Actualiza inventario o inicia sesión nuevamente.',
      );
    }
    final payload = <String, dynamic>{
      'saleType': 'INVENTARIO',
      'warehouseId': wid,
      'items': items,
      'description': note,
      'receiptNote': receiptNote,
    };
    if (discountPercent != null) payload['discountPercent'] = discountPercent;
    if (discountUsd != null) payload['discountUsd'] = discountUsd;
    if (occurredAt != null) {
      payload['occurredAt'] = occurredAt.toUtc().toIso8601String();
    }
    if (payments != null && payments.isNotEmpty) payload['payments'] = payments;
    await _balanceApi.crearVenta(payload);
    final targetDay = occurredAt ?? DateTime.now();
    _selectedDay = DateTime(targetDay.year, targetDay.month, targetDay.day);
    await _refreshDataBatchWithBusy();
    _openBalanceIngresosAfterVenta();
  }

  Future<void> crearGasto({
    required String status, // PAGADO o DEUDA
    required String category,
    required double amountUsd,
    required String description,
    required String receiptNote,
    String? productId,
    DateTime? occurredAt,
    List<Map<String, dynamic>>? payments,
    List<Map<String, dynamic>>? items,
  }) async {
    final payload = <String, dynamic>{
      'status': status,
      'category': category,
      'amountUsd': amountUsd,
      'description': description,
      'receiptNote': receiptNote,
    };
    if (productId != null && productId.trim().isNotEmpty) {
      payload['productId'] = productId.trim();
    }
    if (occurredAt != null) {
      payload['occurredAt'] = occurredAt.toUtc().toIso8601String();
    }
    if (payments != null) {
      payload['payments'] = payments;
    }
    final normalizedItems = (items ?? const <Map<String, dynamic>>[])
        .where((row) => row.isNotEmpty)
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    final created = await _balanceApi.crearGasto(payload);
    if (normalizedItems.isNotEmpty) {
      final createdExpenseId = _extractCreatedExpenseId(created);
      await _registerExpenseInventoryPurchase(
        items: normalizedItems,
        description: description,
        expenseId: createdExpenseId,
      );
    }

    final targetDay = occurredAt ?? DateTime.now();
    _selectedDay = DateTime(targetDay.year, targetDay.month, targetDay.day);
    await _refreshDataBatchWithBusy(
      includeInventory:
          (productId ?? '').trim().isNotEmpty || normalizedItems.isNotEmpty,
    );
    _openBalanceEgresosAfterGasto();
  }

  Future<void> crearAbono({
    required String gastoId,
    required double amountUsd,
    required String paymentMethodCode,
    required String concept,
    required String receiptNote,
  }) async {
    final payload = {
      'amountUsd': amountUsd,
      'paymentMethodCode': paymentMethodCode,
      'concept': concept,
      'receiptNote': receiptNote,
    };
    await _balanceApi.crearAbono(gastoId: gastoId, payload: payload);
    await _refreshDataBatchWithBusy(includeInventory: false);
  }

  Future<void> eliminarVenta(String saleId) async {
    final id = saleId.trim();
    if (id.isEmpty) throw ArgumentError('saleId vacío');
    await _balanceApi.eliminarVenta(saleId: id);
    await _refreshDataBatchWithBusy();
  }

  Future<void> eliminarGasto(String expenseId) async {
    final id = expenseId.trim();
    if (id.isEmpty) throw ArgumentError('expenseId vacío');
    await _balanceApi.eliminarGasto(expenseId: id);
    await _refreshDataBatchWithBusy(includeInventory: false);
    _openBalanceEgresosAfterGasto();
  }

  Future<String> editarVentaRecrear({
    required String saleId,
    required Map<String, dynamic> payload,
  }) async {
    final id = saleId.trim();
    if (id.isEmpty) throw ArgumentError('saleId vacío');

    // ✅ Ahora editamos la venta por endpoint dedicado (mantiene el mismo id).
    final updated = await _balanceApi.editarVenta(saleId: id, payload: payload);

    // 3) Mantén el día seleccionado coherente con la fecha de la venta
    final raw = payload['occurredAt']?.toString() ?? '';
    final dt = DateTime.tryParse(raw);
    final targetDay = (dt == null)
        ? DateTime.now()
        : (dt.isUtc ? dt.toLocal() : dt);
    _selectedDay = DateTime(targetDay.year, targetDay.month, targetDay.day);

    await _refreshDataBatchWithBusy();
    _openBalanceIngresosAfterVenta();

    // Siempre mantiene el mismo id.
    final sameId = (updated['id'] ?? updated['saleId'] ?? id).toString().trim();
    return sameId.isEmpty ? id : sameId;
  }

  Future<String> editarGastoRecrear({
    required String expenseId,
    required Map<String, dynamic> payload,
    List<Map<String, dynamic>>? previousItems,
    List<Map<String, dynamic>>? items,
  }) async {
    final id = expenseId.trim();
    if (id.isEmpty) throw ArgumentError('expenseId vacío');

    // 1) Elimina el gasto anterior (cascade borra pagos/abonos)
    await _balanceApi.eliminarGasto(expenseId: id);

    // 2) Crea el gasto nuevo con los datos editados
    final created = await _balanceApi.crearGasto(payload);

    // 3) Mantén el día seleccionado coherente con la fecha del gasto
    final raw = payload['occurredAt']?.toString() ?? '';
    final dt = DateTime.tryParse(raw);
    final targetDay = (dt == null)
        ? DateTime.now()
        : (dt.isUtc ? dt.toLocal() : dt);
    _selectedDay = DateTime(targetDay.year, targetDay.month, targetDay.day);

    final newExpenseId = _extractCreatedExpenseId(created) ?? id;
    final normalizedPrevious = _normalizeExpenseInventoryItems(
      previousItems ?? const <Map<String, dynamic>>[],
    );
    final normalizedNext = _normalizeExpenseInventoryItems(
      items ?? const <Map<String, dynamic>>[],
    );
    if (normalizedPrevious.isNotEmpty || normalizedNext.isNotEmpty) {
      await _syncEditedExpenseInventoryPurchase(
        previousExpenseId: id,
        expenseId: newExpenseId,
        previousItems: normalizedPrevious,
        nextItems: normalizedNext,
        description: payload['description']?.toString(),
      );
    }

    final productId = payload['productId']?.toString().trim() ?? '';
    await _refreshDataBatchWithBusy(
      includeInventory:
          productId.isNotEmpty ||
          normalizedPrevious.isNotEmpty ||
          normalizedNext.isNotEmpty,
    );
    _openBalanceEgresosAfterGasto();

    return newExpenseId;
  }

  Future<void> editarProductoBasico({
    required String productId,
    required String barcode,
    required String description,
    required String category,
    required double costUsd,
    required double priceRetailUsd,
    double? priceWholesaleUsd,
    String? line,
    String? subLine,
    String? subCategory,
    String? imagePath,
    bool removeImage = false,
    double? targetQty,
    double? currentQty,
  }) async {
    final payload = <String, dynamic>{
      'barcode': barcode,
      'description': description,
      'cost': costUsd.toString(),
      'priceRetail': priceRetailUsd.toString(),
      'priceWholesale': (priceWholesaleUsd ?? priceRetailUsd).toString(),
      'status': 'ACTIVE',
    };

    final cleanLine = (line ?? '').trim();
    final cleanSubLine = (subLine ?? '').trim();
    final cleanCategory = category.trim();
    final cleanSubCategory = (subCategory ?? '').trim();

    payload['line'] = cleanLine.isEmpty ? null : cleanLine;
    payload['subLine'] = cleanSubLine.isEmpty ? null : cleanSubLine;
    payload['size'] = cleanCategory.isEmpty ? null : cleanCategory;
    payload['color'] = cleanSubCategory.isEmpty ? null : cleanSubCategory;

    await _inventoryApi.updateProduct(productId: productId, payload: payload);

    if (removeImage) {
      await _inventoryApi.removeProductImage(productId: productId);
    }
    if ((imagePath ?? '').trim().isNotEmpty) {
      await _inventoryApi.uploadProductImage(
        productId: productId,
        filePath: imagePath!.trim(),
      );
    }

    if (targetQty != null) {
      await _adjustProductStockToTarget(
        productId: productId,
        currentQty: currentQty ?? 0,
        targetQty: targetQty,
      );
    }

    await refreshInventory();
  }

  Future<void> eliminarProducto({required String productId}) async {
    await _inventoryApi.deleteProduct(productId: productId);
    await refreshInventory();
  }

  Future<void> crearProductoBasico({
    required String barcode,
    required String description,
    required String category,
    required double costUsd,
    required double priceRetailUsd,
    double? priceWholesaleUsd,
    String? line,
    String? subLine,
    String? subCategory,
    String? imagePath,
    double? initialQty,
  }) async {
    final payload = <String, dynamic>{
      'barcode': barcode,
      'description': description,
      'cost': costUsd.toString(),
      'priceRetail': priceRetailUsd.toString(),
      // Compatibilidad: si UI no pide precio mayor, usamos el mismo precio de venta.
      'priceWholesale': (priceWholesaleUsd ?? priceRetailUsd).toString(),
      'status': 'ACTIVE',
    };

    final cleanLine = (line ?? '').trim();
    final cleanSubLine = (subLine ?? '').trim();
    final cleanCategory = category.trim();
    final cleanSubCategory = (subCategory ?? '').trim();
    if (cleanLine.isNotEmpty) payload['line'] = cleanLine;
    if (cleanSubLine.isNotEmpty) payload['subLine'] = cleanSubLine;
    if (cleanCategory.isNotEmpty) payload['size'] = cleanCategory;
    if (cleanSubCategory.isNotEmpty) payload['color'] = cleanSubCategory;

    final created = await _inventoryApi.createProduct(payload);

    final createdId = (created['id'] ?? '').toString();
    if ((imagePath ?? '').trim().isNotEmpty && createdId.isNotEmpty) {
      await _inventoryApi.uploadProductImage(
        productId: createdId,
        filePath: imagePath!.trim(),
      );
    }

    final qty = (initialQty ?? 0);
    if (qty > 0 && createdId.isNotEmpty && (_warehouseId ?? '').isNotEmpty) {
      final draft = await _inventoryApi.createInventoryDoc({
        'docType': 'INITIAL_LOAD',
        'toWarehouseId': _warehouseId,
        'notes': 'Carga inicial desde app móvil',
      });
      final docId = (draft['id'] ?? '').toString();
      if (docId.isNotEmpty) {
        await _inventoryApi.replaceInventoryDocLines(
          docId: docId,
          lines: [
            {
              'productId': createdId,
              'qty': qty,
              // Compatibilidad multiempresa:
              // algunas empresas no permiten capturar unitCost en inventoryLine.
              // El backend ya puede derivarlo desde el costo del producto/variante.
            },
          ],
        );
        await _inventoryApi.postInventoryDoc(docId: docId);
      }
    }

    await refreshInventory();
  }

  void _setToken(String? token, {bool notify = true}) {
    if (_token == token) {
      _client.setToken(token);
      return;
    }
    _token = token;
    _client.setToken(token);
    if (notify) {
      notifyListeners();
    }
  }

  void _setBusy(bool v) {
    final shouldClearError = v && _error != null;
    if (_busy == v && !shouldClearError) return;
    _busy = v;
    if (shouldClearError) {
      _error = null;
    }
    notifyListeners();
  }

  void setError(String? msg) {
    if (_error == msg) return;
    _error = msg;
    notifyListeners();
  }
}
