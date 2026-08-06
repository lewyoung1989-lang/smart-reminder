import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/inventory_batch.dart';

class MedicineCabinetApi {
  MedicineCabinetApi({
    required String baseUrl,
    http.Client? client,
  })  : _baseUri = Uri.parse(baseUrl),
        _client = client ?? http.Client(),
        _ownsClient = client == null;

  final Uri _baseUri;
  final http.Client _client;
  final bool _ownsClient;

  Future<InventoryBatchPage> listBatches({
    String query = '',
    Uri? pageUrl,
  }) async {
    if (pageUrl != null && !_hasSameOrigin(pageUrl, _baseUri)) {
      throw const MedicineCabinetApiException(
        0,
        'invalid_cursor_origin',
      );
    }

    final trimmedQuery = query.trim();
    final uri = pageUrl ??
        _baseUri.resolve('/api/v1/inventory-batches').replace(
              queryParameters:
                  trimmedQuery.isEmpty ? null : {'q': trimmedQuery},
            );
    final response = await _client.get(uri, headers: _headers);
    if (response.statusCode != 200) {
      throw MedicineCabinetApiException(response.statusCode, response.body);
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final results = payload['results'] as List<dynamic>;
    final next = payload['next'] as String?;
    return InventoryBatchPage(
      batches: results
          .map(
            (value) => InventoryBatch.fromJson(
              value as Map<String, dynamic>,
            ),
          )
          .toList(growable: false),
      nextPage: next == null ? null : Uri.parse(next),
    );
  }

  Future<void> deleteBatch(String batchId) async {
    final encodedBatchId = Uri.encodeComponent(batchId);
    final uri = Uri.parse(
      '${_baseUri.origin}/api/v1/inventory-batches/$encodedBatchId',
    );
    final response = await _client.delete(uri, headers: _headers);
    if (response.statusCode != 204) {
      throw MedicineCabinetApiException(response.statusCode, response.body);
    }
  }

  Map<String, String> get _headers => {
        'Accept': 'application/json',
      };

  static bool _hasSameOrigin(Uri candidate, Uri base) =>
      candidate.scheme == base.scheme &&
      candidate.host == base.host &&
      candidate.port == base.port;

  void close() {
    if (_ownsClient) _client.close();
  }
}

class MedicineCabinetApiException implements Exception {
  const MedicineCabinetApiException(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  String toString() => 'MedicineCabinetApiException($statusCode)';
}
