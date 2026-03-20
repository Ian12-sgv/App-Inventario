import 'package:dio/dio.dart';

import 'api_config.dart';

class ApiClient {
  final Dio dio;

  String? _token;
  Future<void> Function()? onUnauthorized;
  bool _handlingUnauthorized = false;

  ApiClient({String? baseUrl})
      : dio = Dio(
          BaseOptions(
            baseUrl: baseUrl ?? ApiConfig.defaultBaseUrl,
            connectTimeout: const Duration(seconds: 12),
            receiveTimeout: const Duration(seconds: 20),
          ),
        ) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final token = _token;
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
        onError: (error, handler) async {
          final status = error.response?.statusCode;
          if (status == 401 && !_handlingUnauthorized) {
            _handlingUnauthorized = true;
            try {
              final cb = onUnauthorized;
              if (cb != null) {
                await cb();
              }
            } finally {
              _handlingUnauthorized = false;
            }
          }
          return handler.next(error);
        },
      ),
    );
  }

  void setToken(String? token) {
    _token = token;
  }

  String get baseUrl => dio.options.baseUrl;

  void setBaseUrl(String url) {
    dio.options.baseUrl = url;
  }
}
