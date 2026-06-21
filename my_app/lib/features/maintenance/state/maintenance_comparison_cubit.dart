import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/maintenance_comparison_repository.dart';
import 'maintenance_comparison_state.dart';

class MaintenanceComparisonCubit extends Cubit<MaintenanceComparisonState> {
  MaintenanceComparisonCubit({MaintenanceComparisonRepository? repository})
      : _repo = repository ?? MaintenanceComparisonRepository(),
        super(const MaintenanceComparisonLoading());

  final MaintenanceComparisonRepository _repo;

  Future<void> load({String panelId = 'PL01-B02-INV03-STR05-P01'}) async {
    try {
      if (isClosed) return;
      emit(const MaintenanceComparisonLoading());
      final channelIdx = _repo.channelIndexForPanel(panelId);
      final liveW = await _repo.fetchLiveChannelPowerW(panelId: panelId, channelIdx: channelIdx);
      var before = await _repo.fetchBeforeRaw(panelId: panelId);
      final latest = await _repo.fetchLatestRaw(panelId: panelId);

      final beforeMissing = before.isEmpty || (before['image'] is! Map) || ((before['image'] as Map)['url'] == null);
      if (beforeMissing) {
        before = await _repo.captureBeforeRaw(panelId: panelId);
      }

      final payload = latest.isNotEmpty ? latest : <String, dynamic>{'panel_id': panelId, 'before': before};
      final data = _repo.mapFromPayload(payload: payload, panelId: panelId, channelIdx: channelIdx, liveChannelPowerW: liveW);
      if (isClosed) return;
      emit(MaintenanceComparisonLoaded(data));
    } catch (e) {
      if (isClosed) return;
      emit(MaintenanceComparisonError(e.toString()));
    }
  }

  Future<void> run({String panelId = 'PL01-B02-INV03-STR05-P01'}) async {
    try {
      if (isClosed) return;
      emit(const MaintenanceComparisonLoading());
      final channelIdx = _repo.channelIndexForPanel(panelId);
      final latest = await _repo.runComparisonRaw(panelId: panelId);
      final liveW = await _repo.fetchLiveChannelPowerW(panelId: panelId, channelIdx: channelIdx);
      final data = _repo.mapFromPayload(payload: latest, panelId: panelId, channelIdx: channelIdx, liveChannelPowerW: liveW);
      if (isClosed) return;
      emit(MaintenanceComparisonLoaded(data));
    } catch (e) {
      if (isClosed) return;
      emit(MaintenanceComparisonError(e.toString()));
    }
  }

  Future<void> runWithStabilization({
    String panelId = 'PL01-B02-INV03-STR05-P01',
    int seconds = 30,
  }) async {
    try {
      final channelIdx = _repo.channelIndexForPanel(panelId);
      final beforeRaw = await _repo.captureBeforeRaw(panelId: panelId);
      final liveW0 = await _repo.fetchLiveChannelPowerW(panelId: panelId, channelIdx: channelIdx);
      final beforeData = _repo.mapFromPayload(payload: {'panel_id': panelId, 'before': beforeRaw}, panelId: panelId, channelIdx: channelIdx, liveChannelPowerW: liveW0);
      if (isClosed) return;
      emit(MaintenanceComparisonRunning(data: beforeData, countdownSeconds: seconds));
      for (var s = seconds - 1; s >= 0; s -= 1) {
        await Future<void>.delayed(const Duration(seconds: 1));
        if (isClosed) return;
        emit(MaintenanceComparisonRunning(data: beforeData, countdownSeconds: s));
      }
      final latest = await _repo.runComparisonRaw(panelId: panelId);
      final liveW = await _repo.fetchLiveChannelPowerW(panelId: panelId, channelIdx: channelIdx);
      final data = _repo.mapFromPayload(payload: latest, panelId: panelId, channelIdx: channelIdx, liveChannelPowerW: liveW);
      if (isClosed) return;
      emit(MaintenanceComparisonLoaded(data));
    } catch (e) {
      if (isClosed) return;
      emit(MaintenanceComparisonError(e.toString()));
    }
  }
}
