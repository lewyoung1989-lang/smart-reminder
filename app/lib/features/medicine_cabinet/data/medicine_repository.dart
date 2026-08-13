import '../domain/medicine_models.dart';
import '../domain/inventory_batch.dart';

abstract interface class MedicineRepository {
  Future<MedicineCollection> load({
    MedicineCabinetScope scope = MedicineCabinetScope.personal,
  });

  Future<MedicineDetail> getById(String id);
}
