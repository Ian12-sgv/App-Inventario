import 'package:dio/dio.dart';

import 'api_client.dart';

class BalanceApi {
  final ApiClient client;
  BalanceApi(this.client);

  Future<List<Map<String, dynamic>>> listPaymentMethods() async {
    final res = await client.dio.get('/balance/metodos-pago');
    final data = res.data;
    if (data is List) {
      return data.map((e) => (e as Map).cast<String, dynamic>()).toList();
    }
    return [];
  }

  Future<List<dynamic>> listExpenseCategories() async {
    final res = await client.dio.get('/balance/categorias-gastos');
    final data = res.data;
    return data is List ? data : [];
  }

  Future<List<Map<String, dynamic>>> listTransacciones({
    required String from,
    required String to,
    bool groupByDay = false,
    String? userId,
  }) async {
    final res = await client.dio.get(
      '/balance/transacciones',
      queryParameters: {
        'from': from,
        'to': to,
        if (groupByDay) 'groupByDay': true,
        if (userId != null && userId.trim().isNotEmpty) 'userId': userId.trim(),
      },
    );
    final data = res.data;
    if (data is List) {
      return data.map((e) => (e as Map).cast<String, dynamic>()).toList();
    }
    return [];
  }

  Future<Map<String, dynamic>> ver({required String from, required String to, String? userId}) async {
    final res = await client.dio.get('/balance/ver', queryParameters: {
      'from': from,
      'to': to,
      if (userId != null && userId.trim().isNotEmpty) 'userId': userId.trim(),
    });
    return (res.data as Map).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> crearVenta(Map<String, dynamic> payload) async {
    final res = await client.dio.post(
      '/balance/ventas',
      data: payload,
      options: Options(headers: {'Content-Type': 'application/json'}),
    );
    return (res.data as Map).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> crearGasto(Map<String, dynamic> payload) async {
    final res = await client.dio.post(
      '/balance/gastos',
      data: payload,
      options: Options(headers: {'Content-Type': 'application/json'}),
    );
    return (res.data as Map).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> crearAbono({required String gastoId, required Map<String, dynamic> payload}) async {
    final res = await client.dio.post(
      '/balance/gastos/$gastoId/abonos',
      data: payload,
      options: Options(headers: {'Content-Type': 'application/json'}),
    );
    return (res.data as Map).cast<String, dynamic>();
  }

  Future<void> eliminarVenta({required String saleId}) async {
    await client.dio.delete('/balance/ventas/$saleId');
  }

  Future<Map<String, dynamic>> editarVenta({required String saleId, required Map<String, dynamic> payload}) async {
    final res = await client.dio.patch(
      '/balance/ventas/$saleId',
      data: payload,
      options: Options(headers: {'Content-Type': 'application/json'}),
    );
    return (res.data as Map).cast<String, dynamic>();
  }

  Future<void> eliminarGasto({required String expenseId}) async {
    await client.dio.delete('/balance/gastos/$expenseId');
  }
}
