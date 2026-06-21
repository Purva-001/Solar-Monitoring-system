import 'package:flutter_bloc/flutter_bloc.dart';

import '../../solar_history/data/solar_history_repository.dart';
import 'historical_state.dart';

class HistoricalAnalysisCubit extends Cubit<HistoricalAnalysisState> {
  HistoricalAnalysisCubit({SolarHistoryRepository? repository})
      : _repo = repository ?? SolarHistoryRepository(),
        super(const HistoricalAnalysisLoading());

  final SolarHistoryRepository _repo;

  Future<void> load({String assetId = 'SolarPanel_01'}) async {
    try {
      if (isClosed) return;
      emit(const HistoricalAnalysisLoading());
      final points = await _repo.fetchSolarHistory(assetId: assetId);
      if (isClosed) return;
      if (points.isEmpty) {
        emit(HistoricalAnalysisError('No data returned from API for assetId=$assetId'));
        return;
      }
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final cutoffMs = nowMs - (24 * 60 * 60 * 1000);
      final recent = points.where((p) => p.tsMs >= cutoffMs).toList(growable: false);
      emit(HistoricalAnalysisLoaded(assetId: assetId, points: recent.isEmpty ? points : recent, lastUpdated: DateTime.now()));
    } catch (e) {
      if (isClosed) return;
      emit(HistoricalAnalysisError(e.toString()));
    }
  }
}
