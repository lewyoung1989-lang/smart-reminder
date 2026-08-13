class OcrCandidate {
  const OcrCandidate({
    required this.medicineName,
    required this.specification,
    this.manufacturer = '',
    required this.batchNumber,
    this.productionDate,
    this.expiryDate,
  });

  final String medicineName;
  final String specification;
  final String manufacturer;
  final String batchNumber;
  final DateTime? productionDate;
  final DateTime? expiryDate;

  factory OcrCandidate.fromJson(Map<String, dynamic> json) => OcrCandidate(
        medicineName: json['medicine_name'] as String? ?? '',
        specification: json['specification'] as String? ?? '',
        manufacturer: json['manufacturer'] as String? ?? '',
        batchNumber: json['batch_number'] as String? ?? '',
        productionDate: json['production_date'] == null
            ? null
            : DateTime.parse(json['production_date'] as String),
        expiryDate: json['expiry_date'] == null
            ? null
            : DateTime.parse(json['expiry_date'] as String),
      );
}

class OcrJob {
  const OcrJob({
    required this.id,
    required this.status,
    this.candidate,
    this.errorCode,
  });

  final String id;
  final String status;
  final OcrCandidate? candidate;
  final String? errorCode;

  bool get isTerminal =>
      status == 'succeeded' || status == 'failed' || status == 'confirmed';

  factory OcrJob.fromJson(Map<String, dynamic> json) => OcrJob(
        id: json['id'] as String,
        status: json['status'] as String,
        candidate: json['candidate'] == null
            ? null
            : OcrCandidate.fromJson(
                json['candidate'] as Map<String, dynamic>,
              ),
        errorCode: json['error_code'] as String?,
      );
}
