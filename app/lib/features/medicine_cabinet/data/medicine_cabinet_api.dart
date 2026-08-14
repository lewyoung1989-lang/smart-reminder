import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/inventory_batch.dart';
import '../domain/medicine_description_draft.dart';

typedef InventoryBatchLoader = Future<InventoryBatchPage> Function({
  String query,
  Uri? pageUrl,
});

abstract interface class MedicineCabinetDataSource {
  Future<InventoryBatchPage> listBatches({
    String query = '',
    Uri? pageUrl,
    MedicineCabinetScope scope = MedicineCabinetScope.personal,
  });

  Future<InventoryBatch> createBatch({
    required String medicineName,
    String specification = '',
    String manufacturer = '',
    List<int>? photoBytes,
    String batchNumber = '',
    DateTime? productionDate,
    DateTime? expiryDate,
    int quantity = 1,
    String packageUnit = '',
    double? unitsPerPackage,
    String unitName = '',
    double looseUnits = 0,
    MedicineCabinetScope scope = MedicineCabinetScope.personal,
  });

  Future<void> deleteBatch(String batchId);

  Future<InventoryBatch> correctExpiryDate(
    String batchId, {
    required DateTime expiryDate,
  });
}

class MedicineCabinetApi implements MedicineCabinetDataSource {
  MedicineCabinetApi({
    required String baseUrl,
    http.Client? client,
  })  : _baseUri = Uri.parse(baseUrl),
        _client = client ?? http.Client(),
        _ownsClient = client == null;

  final Uri _baseUri;
  final http.Client _client;
  final bool _ownsClient;

  Future<MedicineDescriptionDraft> parseDescription(String text) async {
    final response = await _client.post(
      _baseUri.resolve('/api/v1/inventory-batches/parse-description'),
      headers: {
        ..._headers,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'text': text.trim()}),
    );
    if (response.statusCode != 200) {
      throw MedicineCabinetApiException(response.statusCode, response.body);
    }
    return MedicineDescriptionDraft.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  @override
  Future<InventoryBatchPage> listBatches({
    String query = '',
    Uri? pageUrl,
    MedicineCabinetScope scope = MedicineCabinetScope.personal,
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
          queryParameters: {
            'scope': scope.apiValue,
            if (trimmedQuery.isNotEmpty) 'q': trimmedQuery,
          },
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

  @override
  Future<InventoryBatch> createBatch({
    required String medicineName,
    String specification = '',
    String manufacturer = '',
    List<int>? photoBytes,
    String batchNumber = '',
    DateTime? productionDate,
    DateTime? expiryDate,
    int quantity = 1,
    String packageUnit = '',
    double? unitsPerPackage,
    String unitName = '',
    double looseUnits = 0,
    MedicineCabinetScope scope = MedicineCabinetScope.personal,
  }) async {
    final photoObjectKey =
        photoBytes == null ? null : await _uploadMedicinePhoto(photoBytes);
    final response = await _client.post(
      _baseUri.resolve('/api/v1/inventory-batches'),
      headers: {
        ..._headers,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'scope': scope.apiValue,
        'medicine_name': medicineName.trim(),
        'specification': specification.trim(),
        'manufacturer': manufacturer.trim(),
        if (photoObjectKey != null) 'photo_object_key': photoObjectKey,
        'batch_number': batchNumber.trim(),
        'production_date':
            productionDate == null ? null : _formatDate(productionDate),
        'expiry_date': expiryDate == null ? null : _formatDate(expiryDate),
        'quantity': quantity,
        if (unitsPerPackage != null) ...{
          'package_unit': packageUnit.trim(),
          'units_per_package': unitsPerPackage,
          'unit_name': unitName.trim(),
          'loose_units': looseUnits,
        },
      }),
    );
    if (response.statusCode != 201) {
      throw MedicineCabinetApiException(response.statusCode, response.body);
    }
    return InventoryBatch.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<String> _uploadMedicinePhoto(List<int> bytes) async {
    final grantResponse = await _client.post(
      _baseUri.resolve('/api/v1/medicine-photos/uploads'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({
        'content_type': 'image/jpeg',
        'byte_length': bytes.length,
      }),
    );
    if (grantResponse.statusCode != 201) {
      throw MedicineCabinetApiException(
        grantResponse.statusCode,
        grantResponse.body,
      );
    }
    final grant = jsonDecode(grantResponse.body) as Map<String, dynamic>;
    final response = await _client.put(
      Uri.parse(grant['upload_url'] as String),
      headers: Map<String, String>.from(grant['headers'] as Map),
      body: bytes,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw MedicineCabinetApiException(response.statusCode, response.body);
    }
    return grant['object_key'] as String;
  }

  @override
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

  @override
  Future<InventoryBatch> correctExpiryDate(
    String batchId, {
    required DateTime expiryDate,
    int? version,
  }) async {
    final encodedBatchId = Uri.encodeComponent(batchId);
    final uri = Uri.parse(
      '${_baseUri.origin}/api/v1/inventory-batches/$encodedBatchId/expiry-dates',
    );
    final response = await _client.patch(
      uri,
      headers: {
        ..._headers,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'expiry_date': _formatDate(expiryDate),
        if (version != null) 'version': version,
      }),
    );
    if (response.statusCode != 200) {
      throw MedicineCabinetApiException(response.statusCode, response.body);
    }
    return InventoryBatch.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Map<String, String> get _headers => {
        'Accept': 'application/json',
      };

  static bool _hasSameOrigin(Uri candidate, Uri base) =>
      candidate.scheme == base.scheme &&
      candidate.host == base.host &&
      candidate.port == base.port;

  static String _formatDate(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

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
