import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/solar_history_repository.dart';
import '../domain/solar_history_models.dart';
import 'solar_history_state.dart';

class SolarHistoryCubit extends Cubit<SolarHistoryState> {
  SolarHistoryCubit({SolarHistoryRepository? repository})
      : _repo = repository ?? SolarHistoryRepository(),
        super(const SolarHistoryLoading());

  final SolarHistoryRepository _repo;

  Future<void> load({String assetId = 'SolarPanel_01', bool silent = false}) async {
    SolarHistoryPoint? prevIvPv;
    if (state is SolarHistoryLoaded) {
      prevIvPv = (state as SolarHistoryLoaded).ivPvPoint;
    }
    final showLoadingSpinner = !silent || state is! SolarHistoryLoaded;

    try {
      if (isClosed) return;
      if (showLoadingSpinner) {
        emit(const SolarHistoryLoading());
      }

      final results = await Future.wait<Object?>([
        _repo.fetchSolarHistory(assetId: assetId),
        _repo.fetchLatestIvPvPoint(),
      ]);
      if (isClosed) return;

      final points = results[0]! as List<SolarHistoryPoint>;
      final snap = results[1] as SolarHistoryPoint?;

      emit(
        SolarHistoryLoaded(
          assetId: assetId,
          points: points,
          lastUpdated: DateTime.now(),
          ivPvPoint: snap ?? prevIvPv,
        ),
      );
    } catch (e) {
      if (isClosed) return;
      emit(SolarHistoryError(e.toString()));
    }
  }
}
