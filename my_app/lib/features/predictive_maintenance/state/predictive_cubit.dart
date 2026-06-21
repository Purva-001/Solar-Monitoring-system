import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/predictive_repository.dart';
import 'predictive_state.dart';

class PredictiveMaintenanceCubit extends Cubit<PredictiveMaintenanceState> {
  PredictiveMaintenanceCubit({PredictiveMaintenanceRepository? repository})
      : _repo = repository ?? PredictiveMaintenanceRepository(),
        super(const PredictiveMaintenanceLoading());

  final PredictiveMaintenanceRepository _repo;

  Future<void> load({String panelId = 'PL01-B02-INV03-STR05-P01'}) async {
    try {
      if (isClosed) return;
      emit(const PredictiveMaintenanceLoading());
      final data = await _repo.fetch(panelId: panelId);
      if (isClosed) return;
      emit(PredictiveMaintenanceLoaded(data));
    } catch (e) {
      if (isClosed) return;
      emit(PredictiveMaintenanceError(e.toString()));
    }
  }
}
