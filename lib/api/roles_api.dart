import 'api_client.dart';

class RolesApi {
  final ApiClient client;
  RolesApi(this.client);

  Future<List<Map<String, dynamic>>> listRoles() async {
    final res = await client.dio.get('/roles');
    final data = res.data;
    if (data is List) {
      return data.map((e) => (e as Map).cast<String, dynamic>()).toList();
    }
    return [];
  }
}
