import 'package:dio/dio.dart';

import 'api_client.dart';

class UsersApi {
  final ApiClient client;
  UsersApi(this.client);

  Future<List<Map<String, dynamic>>> listUsers() async {
    final res = await client.dio.get('/users');
    final data = res.data;
    if (data is List) {
      return data.map((e) => (e as Map).cast<String, dynamic>()).toList();
    }
    return [];
  }

  Future<Map<String, dynamic>> createUser(Map<String, dynamic> payload) async {
    final res = await client.dio.post(
      '/users',
      data: payload,
      options: Options(headers: {'Content-Type': 'application/json'}),
    );
    return (res.data as Map).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> updateUser({required String userId, required Map<String, dynamic> payload}) async {
    final res = await client.dio.patch(
      '/users/$userId',
      data: payload,
      options: Options(headers: {'Content-Type': 'application/json'}),
    );
    return (res.data as Map).cast<String, dynamic>();
  }

  Future<void> setRoles({required String userId, required List<String> roleCodes}) async {
    await client.dio.put(
      '/users/$userId/roles',
      data: {'roleCodes': roleCodes},
      options: Options(headers: {'Content-Type': 'application/json'}),
    );
  }

  Future<Map<String, dynamic>> setPermisos({required String userId, required List<String> permissions}) async {
    final res = await client.dio.put(
      '/users/$userId/permisos',
      data: {'permissions': permissions},
      options: Options(headers: {'Content-Type': 'application/json'}),
    );
    return (res.data as Map).cast<String, dynamic>();
  }
}
