import 'package:dio/dio.dart';

import 'api_client.dart';

bool _hasUnsupportedLineFields(Map<String, dynamic> payload) {
  return payload.containsKey('line') || payload.containsKey('subLine');
}

bool _inventoryLineHasPricingFields(Map<String, dynamic> line) {
  return line.containsKey('unitCost') ||
      line.containsKey('unitCostUsd') ||
      line.containsKey('unitPrice') ||
      line.containsKey('unitPriceUsd') ||
      line.containsKey('lineTotalUsd');
}

Map<String, dynamic> _withoutUnsupportedLineFields(
  Map<String, dynamic> payload,
) {
  final sanitized = Map<String, dynamic>.from(payload);
  sanitized.remove('line');
  sanitized.remove('subLine');
  return sanitized;
}

List<Map<String, dynamic>> _withoutInventoryLinePricing(
  List<Map<String, dynamic>> lines,
) {
  return lines.map((line) {
    final sanitized = Map<String, dynamic>.from(line);
    sanitized.remove('unitCost');
    sanitized.remove('unitCostUsd');
    sanitized.remove('unitPrice');
    sanitized.remove('unitPriceUsd');
    sanitized.remove('lineTotalUsd');
    return sanitized;
  }).toList();
}

bool _shouldRetryWithoutLineFields(DioException error) {
  final data = error.response?.data;
  final messages = <String>[];

  if (data is Map) {
    final message = data['message'];
    if (message is List) {
      messages.addAll(message.map((e) => e.toString()));
    } else if (message != null) {
      messages.add(message.toString());
    }
    final rawError = data['error'];
    if (rawError != null) {
      messages.add(rawError.toString());
    }
  } else if (data != null) {
    messages.add(data.toString());
  }

  final joined = messages.join(' ').toLowerCase();
  return joined.contains('property line should not exist') ||
      joined.contains('property subline should not exist');
}

bool _shouldRetryWithoutInventoryLinePricing(DioException error) {
  final data = error.response?.data;
  final messages = <String>[];

  if (data is Map) {
    final message = data['message'];
    if (message is List) {
      messages.addAll(message.map((e) => e.toString()));
    } else if (message != null) {
      messages.add(message.toString());
    }
    final rawError = data['error'];
    if (rawError != null) {
      messages.add(rawError.toString());
    }
  } else if (data != null) {
    messages.add(data.toString());
  }

  final joined = messages.join(' ').toLowerCase();
  return joined.contains('property unitcost should not exist') ||
      joined.contains('property unitcostusd should not exist') ||
      joined.contains('property unitprice should not exist') ||
      joined.contains('property unitpriceusd should not exist') ||
      joined.contains('property linetotalusd should not exist');
}

class InventoryApi {
  final ApiClient client;
  InventoryApi(this.client);

  Future<List<Map<String, dynamic>>> listWarehouses() async {
    final res = await client.dio.get('/warehouses');
    final data = res.data;
    if (data is List) {
      return data.map((e) => (e as Map).cast<String, dynamic>()).toList();
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> listProducts() async {
    final res = await client.dio.get('/products');
    final data = res.data;
    if (data is List) {
      return data.map((e) => (e as Map).cast<String, dynamic>()).toList();
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> getStock({
    required String warehouseId,
  }) async {
    final res = await client.dio.get(
      '/stock',
      queryParameters: {'warehouseId': warehouseId},
    );
    final data = res.data;
    if (data is List) {
      return data.map((e) => (e as Map).cast<String, dynamic>()).toList();
    }
    return [];
  }

  Future<Map<String, dynamic>> createProduct(
    Map<String, dynamic> payload,
  ) async {
    try {
      final res = await client.dio.post(
        '/products',
        data: payload,
        options: Options(headers: {'Content-Type': 'application/json'}),
      );
      return (res.data as Map).cast<String, dynamic>();
    } on DioException catch (e) {
      if (!_hasUnsupportedLineFields(payload) ||
          !_shouldRetryWithoutLineFields(e)) {
        rethrow;
      }

      final res = await client.dio.post(
        '/products',
        data: _withoutUnsupportedLineFields(payload),
        options: Options(headers: {'Content-Type': 'application/json'}),
      );
      return (res.data as Map).cast<String, dynamic>();
    }
  }

  Future<Map<String, dynamic>> uploadProductImage({
    required String productId,
    required String filePath,
  }) async {
    final fileName = filePath.split(RegExp(r'[\/]')).last;
    final form = FormData.fromMap({
      'image': await MultipartFile.fromFile(filePath, filename: fileName),
    });
    final res = await client.dio.post(
      '/products/$productId/image',
      data: form,
      options: Options(headers: {'Content-Type': 'multipart/form-data'}),
    );
    return (res.data as Map).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> removeProductImage({
    required String productId,
  }) async {
    final res = await client.dio.delete('/products/$productId/image');
    return (res.data as Map).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> updateProduct({
    required String productId,
    required Map<String, dynamic> payload,
  }) async {
    try {
      final res = await client.dio.patch(
        '/products/$productId',
        data: payload,
        options: Options(headers: {'Content-Type': 'application/json'}),
      );
      return (res.data as Map).cast<String, dynamic>();
    } on DioException catch (e) {
      if (!_hasUnsupportedLineFields(payload) ||
          !_shouldRetryWithoutLineFields(e)) {
        rethrow;
      }

      final res = await client.dio.patch(
        '/products/$productId',
        data: _withoutUnsupportedLineFields(payload),
        options: Options(headers: {'Content-Type': 'application/json'}),
      );
      return (res.data as Map).cast<String, dynamic>();
    }
  }

  Future<void> deleteProduct({required String productId}) async {
    await client.dio.delete(
      '/products/$productId',
      options: Options(headers: {'Content-Type': 'application/json'}),
    );
  }

  Future<Map<String, dynamic>> createInventoryDoc(
    Map<String, dynamic> payload,
  ) async {
    final res = await client.dio.post(
      '/inventory-docs',
      data: payload,
      options: Options(headers: {'Content-Type': 'application/json'}),
    );
    return (res.data as Map).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> replaceInventoryDocLines({
    required String docId,
    required List<Map<String, dynamic>> lines,
  }) async {
    try {
      final res = await client.dio.put(
        '/inventory-docs/$docId/lines',
        data: {'lines': lines},
        options: Options(headers: {'Content-Type': 'application/json'}),
      );
      return (res.data as Map).cast<String, dynamic>();
    } on DioException catch (e) {
      final hasPricingFields = lines.any(_inventoryLineHasPricingFields);
      if (!hasPricingFields || !_shouldRetryWithoutInventoryLinePricing(e)) {
        rethrow;
      }

      final res = await client.dio.put(
        '/inventory-docs/$docId/lines',
        data: {'lines': _withoutInventoryLinePricing(lines)},
        options: Options(headers: {'Content-Type': 'application/json'}),
      );
      return (res.data as Map).cast<String, dynamic>();
    }
  }

  Future<Map<String, dynamic>> postInventoryDoc({required String docId}) async {
    final res = await client.dio.post(
      '/inventory-docs/$docId/post',
      options: Options(headers: {'Content-Type': 'application/json'}),
    );
    return (res.data as Map).cast<String, dynamic>();
  }

  Future<List<Map<String, dynamic>>> getInventoryDocLines({
    required String docId,
  }) async {
    final res = await client.dio.get('/inventory-docs/$docId/lines');
    final data = res.data;
    if (data is List) {
      return data.map((e) => (e as Map).cast<String, dynamic>()).toList();
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> listInventoryDocs({
    String? status,
    String? docType,
    String? warehouseId,
    String? from,
    String? to,
    String? createdByUserId,
  }) async {
    final res = await client.dio.get(
      '/inventory-docs',
      queryParameters: {
        if (status != null && status.trim().isNotEmpty) 'status': status.trim(),
        if (docType != null && docType.trim().isNotEmpty)
          'docType': docType.trim(),
        if (warehouseId != null && warehouseId.trim().isNotEmpty)
          'warehouseId': warehouseId.trim(),
        if (from != null && from.trim().isNotEmpty) 'from': from.trim(),
        if (to != null && to.trim().isNotEmpty) 'to': to.trim(),
        if (createdByUserId != null && createdByUserId.trim().isNotEmpty)
          'createdByUserId': createdByUserId.trim(),
      },
    );
    final data = res.data;
    if (data is List) {
      return data.map((e) => (e as Map).cast<String, dynamic>()).toList();
    }
    return [];
  }
}
