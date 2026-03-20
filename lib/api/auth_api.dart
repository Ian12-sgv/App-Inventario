import 'package:dio/dio.dart';

import 'api_client.dart';

class AuthApi {
  final ApiClient client;
  AuthApi(this.client);

  Future<String> login({required String username, required String password}) async {
    final res = await client.dio.post(
      '/auth/login',
      data: {'username': username, 'password': password},
      options: Options(headers: {'Content-Type': 'application/json'}),
    );
    final token = (res.data is Map ? res.data['access_token'] : null)?.toString() ?? '';
    if (token.isEmpty) throw Exception('No se recibió token de acceso');
    return token;
  }

  Future<Map<String, dynamic>> me() async {
    final res = await client.dio.get('/auth/me');
    return (res.data as Map).cast<String, dynamic>();
  }

  Future<String> impersonate({required String userId}) async {
    final res = await client.dio.post('/auth/impersonate/$userId');
    final token = (res.data is Map ? res.data['access_token'] : null)?.toString() ?? '';
    if (token.isEmpty) throw Exception('No se recibió token temporal');
    return token;
  }
}

