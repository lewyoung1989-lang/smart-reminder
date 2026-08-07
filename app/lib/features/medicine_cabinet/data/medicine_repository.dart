import '../domain/medicine_models.dart';

abstract interface class MedicineRepository {
  Future<MedicineCollection> load();

  Future<MedicineDetail> getById(String id);
}
